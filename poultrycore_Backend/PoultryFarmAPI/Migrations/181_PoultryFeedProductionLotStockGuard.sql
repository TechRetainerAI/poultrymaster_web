-- =============================================================================
-- Migration 181: Feed Production — guard on TRACKED LOT stock, not CurrentQuantity
-- =============================================================================
-- Migration 180 added a stock guard, but checked the wrong number. Posting does
-- not draw against PoultryRawMaterialItems.CurrentQuantity — it calls
-- spPoultryRawMaterialItem_ConsumeBatches (migration 159), which draws from
-- PoultryRawMaterialPurchases lots and rejects with
--   'Not enough tracked batch stock for "maize": need 1000.000, only 100.0000
--    available across purchase batches.'
-- when the lots can't cover it.
--
-- The two figures legitimately diverge. CurrentQuantity is
--   SUM(purchases) - SUM(usage) + SUM(adjustments)
-- but an ADJUSTMENT creates no purchase lot, so stock added by adjustment raises
-- CurrentQuantity while contributing nothing to the drawable lot pool. A farm
-- that adjusts stock in rather than recording purchases can therefore show
-- plenty "in stock" and still fail to post. That is exactly what happened: 180's
-- guard passed, then ConsumeBatches threw a raw 500 at the user.
--
-- This migration:
--   1. Guards on the LOT POOL — SUM(RemainingQuantity * ProductionUnitsPerPurchaseUnit)
--      over lots with RemainingQuantity > 0, the same expression ConsumeBatches
--      uses (159:38) — so the batch is stopped by a clear message before any row
--      is written, instead of failing mid-post on a shared low-level SP.
--   2. Drops @AllowNegativeStock. There is no honest override: ConsumeBatches is
--      shared by feed usage and production sync and enforces the lot pool
--      regardless, so a "post anyway" could never have worked. Rejecting is the
--      only real behaviour.
--   3. Adds AvailableFromLots to the batch-form item picker, so the form warns on
--      the number that actually gates posting rather than on CurrentQuantity.
--
-- Supersedes the Post SP from 180 and the item picker from 170. 178's Reverse SP
-- is unchanged. Idempotent (CREATE OR ALTER). Safe to re-run.
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- =============================================================================
-- Batch-form item picker — now also reports drawable lot stock.
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.spPoultryFeedProduction_GetBatchItems
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT i.PoultryRawMaterialItemId,
           i.ItemName,
           i.Category,
           i.UnitOfMeasure,
           i.CurrentQuantity,
           i.IsActive,
           CAST(ISNULL((
               SELECT TOP 1 CASE WHEN ISNULL(p.ProductionUnitsPerPurchaseUnit,0) > 0
                                 THEN p.TotalCost / NULLIF(p.Quantity * p.ProductionUnitsPerPurchaseUnit,0)
                                 ELSE p.UnitCost END
               FROM dbo.PoultryRawMaterialPurchases p
               WHERE p.PoultryRawMaterialItemId = i.PoultryRawMaterialItemId AND p.FarmId = @FarmId
               ORDER BY p.PurchaseDate DESC, p.PoultryRawMaterialPurchaseId DESC
           ), 0) AS DECIMAL(18,4)) AS LatestUnitCost,
           -- What posting can actually draw, in PRODUCTION units. Mirrors
           -- spPoultryRawMaterialItem_ConsumeBatches (159). May be LESS than
           -- CurrentQuantity when stock was added by adjustment rather than by
           -- a purchase — adjustments create no lot to draw from.
           CAST(ISNULL((
               SELECT SUM(p2.RemainingQuantity * ISNULL(NULLIF(p2.ProductionUnitsPerPurchaseUnit, 0), 1))
               FROM   dbo.PoultryRawMaterialPurchases p2
               WHERE  p2.PoultryRawMaterialItemId = i.PoultryRawMaterialItemId
                 AND  p2.FarmId = @FarmId AND p2.RemainingQuantity > 0
           ), 0) AS DECIMAL(18,4)) AS AvailableFromLots
    FROM   dbo.PoultryRawMaterialItems i
    WHERE  i.FarmId = @FarmId
      AND  i.IsActive = 1
      AND  i.Category LIKE '%Feed%'   -- FinishedFeed + FeedIngredient
    ORDER  BY i.Category, i.ItemName;
END
GO

-- =============================================================================
-- POST — cycle-stamped; accepts Draft OR Reversed (repost); lot-stock guarded.
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.spPoultryFeedProductionBatch_Post
    @FarmId NVARCHAR(450),
    @PoultryFeedProductionBatchId INT,
    @PostedBy NVARCHAR(450) = NULL
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
    -- Stock guard. Checked against the DRAWABLE LOT POOL, because that is what
    -- spPoultryRawMaterialItem_ConsumeBatches actually consumes. Aggregated per
    -- ITEM (lines summed) so two lines drawing the same ingredient can't each
    -- pass against the same stock. Inventory portion only — bought-during-
    -- production quantities arrive with their own lot and are never short.
    -- Tolerance 0.0005 matches ConsumeBatches (159:58) and the reversal guard.
    -- -------------------------------------------------------------------------
    DECLARE @Short NVARCHAR(MAX) = NULL;

    ;WITH Need AS (
        SELECT   l.IngredientItemId AS ItemId, SUM(ISNULL(l.InventoryQuantityUsed,0)) AS Qty
        FROM     dbo.PoultryFeedProductionBatchLines l
        WHERE    l.PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId
        GROUP BY l.IngredientItemId
        HAVING   SUM(ISNULL(l.InventoryQuantityUsed,0)) > 0
    ),
    Avail AS (
        SELECT n.ItemId, n.Qty,
               ItemName = it.ItemName,
               Unit     = ISNULL(NULLIF(it.UnitOfMeasure, N''), N''),
               Pool     = ISNULL((
                   SELECT SUM(p.RemainingQuantity * ISNULL(NULLIF(p.ProductionUnitsPerPurchaseUnit, 0), 1))
                   FROM   dbo.PoultryRawMaterialPurchases p
                   WHERE  p.PoultryRawMaterialItemId = n.ItemId AND p.FarmId = @FarmId
                     AND  p.RemainingQuantity > 0), 0)
        FROM   Need n
        JOIN   dbo.PoultryRawMaterialItems it
               ON it.PoultryRawMaterialItemId = n.ItemId AND it.FarmId = @FarmId
    )
    SELECT @Short = STUFF((
        SELECT N' ' + a.ItemName
             + N' needs '     + CONVERT(NVARCHAR(30), CAST(a.Qty  AS DECIMAL(14,3)))
             + N' but only '  + CONVERT(NVARCHAR(30), CAST(a.Pool AS DECIMAL(14,3)))
             + CASE WHEN a.Unit = N'' THEN N'' ELSE N' ' + a.Unit END
             + N' is available.'
        FROM   Avail a
        WHERE  a.Qty > a.Pool + 0.0005
        ORDER  BY a.ItemName
        FOR XML PATH(N''), TYPE).value(N'.', N'NVARCHAR(MAX)'), 1, 1, N'');

    IF @Short IS NOT NULL
    BEGIN
        -- THROW's message is capped at NVARCHAR(2048); a long list truncates
        -- rather than losing the error.
        DECLARE @Msg NVARCHAR(2048) = LEFT(
            N'This batch needs more ingredient stock than is available. ' + @Short
          + N' Reduce the quantity produced, or set the short ingredients to "Bought During Production" so they are purchased with the batch.'
          + N' (Stock added by adjustment rather than by a recorded purchase cannot be drawn - record a purchase for it first.)', 2048);
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

    COMMIT TRANSACTION;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spPoultryFeedProductionBatch_Post   TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryFeedProduction_GetBatchItems TO [Techretainer];
    PRINT '181: granted EXECUTE on feed production post + item picker to Techretainer.';
END
GO

PRINT '181_PoultryFeedProductionLotStockGuard.sql complete.';
GO
