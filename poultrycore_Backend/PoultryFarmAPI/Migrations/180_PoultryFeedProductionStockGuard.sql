-- =============================================================================
-- Migration 180: Feed Production — stock guard on posting
-- =============================================================================
-- Posting a feed production batch draws each ingredient's inventory portion out
-- of stock (spPoultryFeedProductionBatch_Post, migration 178). Nothing checked
-- that the stock was actually there: a batch needing 250kg of maize against
-- 180kg on hand posted silently and left PoultryRawMaterialItems.CurrentQuantity
-- at -70. Every downstream cost and availability figure inherits that.
--
-- This migration adds the missing guard. It is the LAST word on the draw, so it
-- protects every caller — the web form, mobile, integrations, direct SQL —
-- not just the client that happens to check first.
--
--   • Shortfall is computed PER INGREDIENT ITEM, not per line. Two lines drawing
--     the same ingredient must not each pass against the same stock.
--   • Only the INVENTORY portion counts (InventoryQuantityUsed — exactly what
--     the posting loop draws). Bought-during-production quantities arrive with
--     their own purchase lot, so they can never be short.
--   • @AllowNegativeStock = 1 is a deliberate, recorded override: the farmer
--     confirms in the UI, and the batch Notes are stamped so the decision stays
--     visible on the record afterwards. Default 0 = reject.
--
-- Repost of a reversed batch draws stock again, so the guard covers it too.
--
-- Supersedes the Post SP from 178 (178's Reverse SP is unchanged and still
-- stands). The only behavioural change is the new guard + parameter; the
-- posting body is otherwise identical to 178.
-- Idempotent (CREATE OR ALTER). Safe to re-run.
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- =============================================================================
-- POST — cycle-stamped; accepts Draft OR Reversed (repost); stock-guarded.
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.spPoultryFeedProductionBatch_Post
    @FarmId NVARCHAR(450),
    @PoultryFeedProductionBatchId INT,
    @PostedBy NVARCHAR(450) = NULL,
    @AllowNegativeStock BIT = 0      -- 1 = farmer confirmed an insufficient-stock post
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Status NVARCHAR(20), @FinishedFeedItemId INT, @QtyProduced DECIMAL(14,3),
            @BatchNumber NVARCHAR(60), @ProductionDate DATETIME2, @OutputUnit NVARCHAR(30);
    SELECT @Status = Status, @FinishedFeedItemId = FinishedFeedItemId, @QtyProduced = QuantityProduced,
           @BatchNumber = BatchNumber, @ProductionDate = ProductionDate, @OutputUnit = OutputUnit
    FROM   dbo.PoultryFeedProductionBatches
    WHERE  PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId AND FarmId = @FarmId;

    IF @Status IS NULL      THROW 51100, 'Feed production batch not found.', 1;
    IF @Status = 'Posted'   THROW 51101, 'Batch is already posted.', 1;
    -- A Reversed batch MAY be reposted: each cycle is scoped by CreatedAt/PostedAt.
    IF ISNULL(@QtyProduced,0) <= 0 THROW 51103, 'Quantity produced must be greater than zero.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.PoultryFeedProductionBatchLines WHERE PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId)
        THROW 51104, 'Add at least one ingredient line before posting.', 1;

    IF EXISTS (SELECT 1 FROM dbo.PoultryFeedProductionBatchLines
               WHERE PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId AND ISNULL(AmountPaid,0) > 0 AND PaidFromCashAccountId IS NULL)
        THROW 51105, 'Select a cash account for paid ingredient purchases.', 1;
    IF EXISTS (SELECT 1 FROM dbo.PoultryFeedProductionAdditionalCosts
               WHERE PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId AND ISNULL(AmountPaid,0) > 0 AND PaidFromCashAccountId IS NULL)
        THROW 51106, 'Select a cash account for paid production costs.', 1;

    -- -------------------------------------------------------------------------
    -- Stock guard. Per ITEM (lines summed), inventory portion only. Built even
    -- when overridden, so the override can be recorded against the batch.
    -- The 0.0005 tolerance matches the reversal guard: DECIMAL(14,3) quantities
    -- shouldn't trip on their own last digit.
    -- -------------------------------------------------------------------------
    DECLARE @Short NVARCHAR(MAX) = NULL;

    ;WITH Need AS (
        SELECT   l.IngredientItemId AS ItemId, SUM(ISNULL(l.InventoryQuantityUsed,0)) AS Qty
        FROM     dbo.PoultryFeedProductionBatchLines l
        WHERE    l.PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId
        GROUP BY l.IngredientItemId
        HAVING   SUM(ISNULL(l.InventoryQuantityUsed,0)) > 0
    )
    SELECT @Short = STUFF((
        SELECT N'; ' + it.ItemName
             + N' (need '  + CONVERT(NVARCHAR(30), CAST(n.Qty AS DECIMAL(14,3)))
             + N', have '  + CONVERT(NVARCHAR(30), CAST(ISNULL(it.CurrentQuantity,0) AS DECIMAL(14,3)))
             + N', short ' + CONVERT(NVARCHAR(30), CAST(n.Qty - ISNULL(it.CurrentQuantity,0) AS DECIMAL(14,3)))
             + ISNULL(N' ' + NULLIF(it.UnitOfMeasure, N''), N'') + N')'
        FROM   Need n
        JOIN   dbo.PoultryRawMaterialItems it
               ON it.PoultryRawMaterialItemId = n.ItemId AND it.FarmId = @FarmId
        WHERE  n.Qty > ISNULL(it.CurrentQuantity,0) + 0.0005
        ORDER  BY it.ItemName
        FOR XML PATH(N''), TYPE).value(N'.', N'NVARCHAR(MAX)'), 1, 2, N'');

    IF @Short IS NOT NULL AND ISNULL(@AllowNegativeStock,0) = 0
    BEGIN
        -- THROW's message is capped at NVARCHAR(2048); a long shortage list is
        -- truncated rather than losing the error.
        DECLARE @Msg NVARCHAR(2048) = LEFT(
            N'Not enough stock to post this batch: ' + @Short
          + N'. Reduce the quantity produced, or record the shortfall as bought during production.', 2048);
        THROW 51107, @Msg, 1;
    END

    -- One timestamp for the whole cycle: stamped on every row + stored as PostedAt,
    -- so reversal can select exactly this cycle's rows with CreatedAt >= PostedAt.
    DECLARE @CycleStart DATETIME2 = SYSUTCDATETIME();

    BEGIN TRANSACTION;

    DECLARE @LineId INT, @ItemId INT, @Qty DECIMAL(14,3),
            @InvQty DECIMAL(14,3), @PurQty DECIMAL(14,3), @PurUnit DECIMAL(18,4),
            @Unit NVARCHAR(30), @SupplierId INT, @SupplierName NVARCHAR(200), @PaymentMethod NVARCHAR(30),
            @InvCost DECIMAL(14,4), @InvPortion DECIMAL(14,2), @PurPortion DECIMAL(14,2), @UsageId INT,
            @PurLotId INT, @PurUsageId INT;

    DECLARE line_cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT PoultryFeedProductionBatchLineId, IngredientItemId, QuantityUsed,
               ISNULL(InventoryQuantityUsed,0), ISNULL(PurchasedQuantityUsed,0), ISNULL(PurchasedUnitCost,0),
               UnitOfMeasure, SupplierId, SupplierName, PaymentMethod
        FROM   dbo.PoultryFeedProductionBatchLines
        WHERE  PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId
        ORDER  BY SortOrder, PoultryFeedProductionBatchLineId;
    OPEN line_cur;
    FETCH NEXT FROM line_cur INTO @LineId, @ItemId, @Qty, @InvQty, @PurQty, @PurUnit, @Unit, @SupplierId, @SupplierName, @PaymentMethod;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @InvCost = 0; SET @InvPortion = 0; SET @PurPortion = 0; SET @UsageId = NULL;

        -- Inventory portion: consume from real stock lots (authoritative cost).
        IF @InvQty > 0
        BEGIN
            INSERT INTO dbo.PoultryRawMaterialUsage (FarmId, PoultryRawMaterialItemId, PoultryFeedProductionBatchId, QuantityUsed, Notes, CreatedBy, CreatedAt)
            VALUES (@FarmId, @ItemId, @PoultryFeedProductionBatchId, @InvQty, CONCAT(N'Feed production ', @BatchNumber), @PostedBy, @CycleStart);
            SET @UsageId = CAST(SCOPE_IDENTITY() AS INT);

            EXEC dbo.spPoultryRawMaterialItem_ConsumeBatches @FarmId, @ItemId, @UsageId, @InvQty, @InvCost OUTPUT;

            UPDATE dbo.PoultryRawMaterialItems
            SET    CurrentQuantity = CurrentQuantity - @InvQty, UpdatedAt = SYSUTCDATETIME()
            WHERE  PoultryRawMaterialItemId = @ItemId AND FarmId = @FarmId;

            UPDATE dbo.PoultryRawMaterialUsage SET UnitCost = @InvCost WHERE PoultryRawMaterialUsageId = @UsageId;
            SET @InvPortion = CAST(ISNULL(@InvCost,0) * @InvQty AS DECIMAL(14,2));
        END

        -- Purchased portion: a bought-and-consumed lot (net-zero stock) for audit.
        IF @PurQty > 0
        BEGIN
            INSERT INTO dbo.PoultryRawMaterialPurchases
                (FarmId, PoultryRawMaterialItemId, SupplierName, SupplierId, PurchaseDate, Quantity, UnitCost, TotalCost,
                 ProductionUnit, ProductionUnitsPerPurchaseUnit, RemainingQuantity, PaymentMethod, AmountPaid,
                 SourceFeedProductionBatchId, Notes, CreatedBy, CreatedAt)
            VALUES (@FarmId, @ItemId, @SupplierName, @SupplierId, @ProductionDate, @PurQty, @PurUnit, CAST(@PurQty * @PurUnit AS DECIMAL(14,2)),
                 @Unit, 1, @PurQty, @PaymentMethod, CAST(@PurQty * @PurUnit AS DECIMAL(14,2)),
                 @PoultryFeedProductionBatchId, CONCAT(N'Bought for feed production ', @BatchNumber), @PostedBy, @CycleStart);
            SET @PurLotId = CAST(SCOPE_IDENTITY() AS INT);

            INSERT INTO dbo.PoultryRawMaterialUsage (FarmId, PoultryRawMaterialItemId, PoultryFeedProductionBatchId, QuantityUsed, UnitCost, Notes, CreatedBy, CreatedAt)
            VALUES (@FarmId, @ItemId, @PoultryFeedProductionBatchId, @PurQty, @PurUnit, CONCAT(N'Bought & consumed for feed production ', @BatchNumber), @PostedBy, @CycleStart);
            SET @PurUsageId = CAST(SCOPE_IDENTITY() AS INT);

            INSERT INTO dbo.PoultryRawMaterialUsageBatch (PoultryRawMaterialUsageId, PoultryRawMaterialPurchaseId, QuantityDrawn, UnitCostAtDraw)
            VALUES (@PurUsageId, @PurLotId, @PurQty, @PurUnit);

            UPDATE dbo.PoultryRawMaterialPurchases SET RemainingQuantity = 0, UpdatedAt = SYSUTCDATETIME()
            WHERE  PoultryRawMaterialPurchaseId = @PurLotId;

            SET @PurPortion = CAST(@PurQty * @PurUnit AS DECIMAL(14,2));
        END

        UPDATE dbo.PoultryFeedProductionBatchLines
        SET    InventoryUnitCost = @InvCost,
               TotalCost = @InvPortion + @PurPortion,
               UnitCost  = CAST((@InvPortion + @PurPortion) / NULLIF(@Qty,0) AS DECIMAL(18,4))
        WHERE  PoultryFeedProductionBatchLineId = @LineId;

        FETCH NEXT FROM line_cur INTO @LineId, @ItemId, @Qty, @InvQty, @PurQty, @PurUnit, @Unit, @SupplierId, @SupplierName, @PaymentMethod;
    END
    CLOSE line_cur; DEALLOCATE line_cur;

    -- Roll up the finalised costs.
    DECLARE @IngCost DECIMAL(14,2) = ISNULL((SELECT SUM(TotalCost) FROM dbo.PoultryFeedProductionBatchLines WHERE PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId), 0);
    DECLARE @AddCost DECIMAL(14,2) = ISNULL((SELECT SUM(Amount)    FROM dbo.PoultryFeedProductionAdditionalCosts WHERE PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId), 0);
    DECLARE @TotCost DECIMAL(14,2) = @IngCost + @AddCost;
    DECLARE @CPU DECIMAL(18,4) = CAST(@TotCost / NULLIF(@QtyProduced,0) AS DECIMAL(18,4));

    -- Produced finished-feed stock lot (consumable by flocks at cost/unit).
    INSERT INTO dbo.PoultryRawMaterialPurchases
        (FarmId, PoultryRawMaterialItemId, SupplierName, PurchaseDate, Quantity, UnitCost, TotalCost,
         ProductionUnit, ProductionUnitsPerPurchaseUnit, RemainingQuantity, PaymentMethod, AmountPaid,
         SourceFeedProductionBatchId, Notes, CreatedBy, CreatedAt)
    VALUES (@FarmId, @FinishedFeedItemId, N'Feed Production', @ProductionDate, @QtyProduced, @CPU, @TotCost,
         @OutputUnit, 1, @QtyProduced, N'Production', @TotCost,
         @PoultryFeedProductionBatchId, CONCAT(N'Produced feed ', @BatchNumber), @PostedBy, @CycleStart);

    UPDATE dbo.PoultryRawMaterialItems
    SET    CurrentQuantity = CurrentQuantity + @QtyProduced, UpdatedAt = SYSUTCDATETIME()
    WHERE  PoultryRawMaterialItemId = @FinishedFeedItemId AND FarmId = @FarmId;

    -- Cash out — one posting per account (paid ingredient purchases + paid costs).
    ;WITH Pay AS (
        SELECT PaidFromCashAccountId AS AcctId, SUM(ISNULL(AmountPaid,0)) AS Paid
        FROM   dbo.PoultryFeedProductionBatchLines
        WHERE  PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId AND PaidFromCashAccountId IS NOT NULL AND ISNULL(AmountPaid,0) > 0
        GROUP  BY PaidFromCashAccountId
        UNION ALL
        SELECT PaidFromCashAccountId, SUM(ISNULL(AmountPaid,0))
        FROM   dbo.PoultryFeedProductionAdditionalCosts
        WHERE  PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId AND PaidFromCashAccountId IS NOT NULL AND ISNULL(AmountPaid,0) > 0
        GROUP  BY PaidFromCashAccountId
    )
    SELECT AcctId, SUM(Paid) AS Paid INTO #Pay FROM Pay GROUP BY AcctId HAVING SUM(Paid) > 0;

    DECLARE @AcctId INT, @Paid DECIMAL(14,2), @NewBal DECIMAL(14,2);
    DECLARE pay_cur CURSOR LOCAL FAST_FORWARD FOR SELECT AcctId, Paid FROM #Pay;
    OPEN pay_cur; FETCH NEXT FROM pay_cur INTO @AcctId, @Paid;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        UPDATE dbo.PoultryCashAccounts SET CurrentBalance = CurrentBalance - @Paid, UpdatedAt = SYSUTCDATETIME()
        WHERE  PoultryCashAccountId = @AcctId AND FarmId = @FarmId;
        SET @NewBal = (SELECT CurrentBalance FROM dbo.PoultryCashAccounts WHERE PoultryCashAccountId = @AcctId AND FarmId = @FarmId);
        INSERT INTO dbo.PoultryCashTransactions
            (FarmId, PoultryCashAccountId, TransactionDate, TransactionType, SourceType, SourceId, Amount, BalanceAfterTransaction, Description, CreatedBy, CreatedAt)
        VALUES (@FarmId, @AcctId, @ProductionDate, 'CashOut', 'FeedProduction', @PoultryFeedProductionBatchId, -@Paid, @NewBal, CONCAT(N'Feed production ', @BatchNumber), @PostedBy, @CycleStart);
        FETCH NEXT FROM pay_cur INTO @AcctId, @Paid;
    END
    CLOSE pay_cur; DEALLOCATE pay_cur;
    DROP TABLE #Pay;

    -- -> Posted. PostedAt = the cycle start (so reversal can scope this cycle).
    -- Clear any reversal stamp left from a prior reverse (repost case).
    UPDATE dbo.PoultryFeedProductionBatches
    SET    TotalIngredientCost = @IngCost, TotalAdditionalCost = @AddCost, TotalProductionCost = @TotCost,
           CostPerOutputUnit = @CPU, Status = 'Posted', PostedBy = @PostedBy, PostedAt = @CycleStart,
           ReversedBy = NULL, ReversedAt = NULL, ReversalReason = NULL, UpdatedAt = SYSUTCDATETIME()
    WHERE  PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId AND FarmId = @FarmId;

    -- An overridden post is recorded on the batch itself, so the decision is
    -- still visible to whoever reads the record later. Notes is NVARCHAR(500).
    IF @Short IS NOT NULL
        UPDATE dbo.PoultryFeedProductionBatches
        SET    Notes = LEFT(ISNULL(NULLIF(Notes, N'') + NCHAR(13) + NCHAR(10), N'')
                     + N'[Posted with insufficient stock - override] ' + @Short, 500)
        WHERE  PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId AND FarmId = @FarmId;

    COMMIT TRANSACTION;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spPoultryFeedProductionBatch_Post TO [Techretainer];
    PRINT '180: granted EXECUTE on feed production post to Techretainer.';
END
GO

PRINT '180_PoultryFeedProductionStockGuard.sql complete.';
GO
