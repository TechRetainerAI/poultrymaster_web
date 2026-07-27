-- =============================================================================
-- Migration 178: Feed Production — cycle-safe repost of a reversed batch
-- =============================================================================
-- Migration 174 allowed a reversed batch to be reposted, on the premise that
-- reversal had DELETED the batch's rows (so a repost started clean). Migration 177
-- made reversal APPEND-ONLY (rows are kept, offsets are added). Reposting is still
-- wanted, but now a batch can accumulate MULTIPLE posting cycles' worth of rows,
-- all tagged with the same batch id. A naive reversal that keys only off the batch
-- id would offset EVERY cycle's rows at once (over-restoring stock, and the
-- produced-feed guard would misread an already-reversed lot as "consumed").
--
-- Fix: scope each posting cycle by time.
--   • POST captures @CycleStart once, stamps CreatedAt = @CycleStart on every row
--     it writes (usage, purchase lots, cash), and sets the batch PostedAt =
--     @CycleStart. Reposting a Reversed batch is allowed again (the 177 guard is
--     removed) and clears the reversal stamp.
--   • REVERSE offsets only rows of the CURRENT cycle: those created at/after the
--     batch's PostedAt. For a batch that was never reposted (a single produced
--     lot) the time filter is skipped so legacy batches — whose PostedAt predates
--     this scheme — still reverse in full.
--
-- Supersedes the Post + Reverse SPs from 177 (177's traceability SP is unchanged).
-- Idempotent (CREATE OR ALTER). Safe to re-run.
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- =============================================================================
-- POST — cycle-stamped; accepts Draft OR Reversed (repost).
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

-- =============================================================================
-- REVERSE — append-only, scoped to the current posting cycle.
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.spPoultryFeedProductionBatch_Reverse
    @FarmId NVARCHAR(450),
    @PoultryFeedProductionBatchId INT,
    @ReversedBy NVARCHAR(450) = NULL,
    @ReversalReason NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Status NVARCHAR(20), @FinishedFeedItemId INT, @BatchNumber NVARCHAR(60),
            @ProductionDate DATETIME2, @PostedAt DATETIME2;
    SELECT @Status = Status, @FinishedFeedItemId = FinishedFeedItemId, @BatchNumber = BatchNumber,
           @ProductionDate = ProductionDate, @PostedAt = PostedAt
    FROM   dbo.PoultryFeedProductionBatches
    WHERE  PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId AND FarmId = @FarmId;

    IF @Status IS NULL      THROW 51200, 'Feed production batch not found.', 1;
    IF @Status = 'Draft'    THROW 51201, 'Draft batches are edited or deleted, not reversed.', 1;
    IF @Status = 'Reversed' THROW 51202, 'This batch has already been reversed.', 1;

    -- Cycle boundary: only offset rows created since this cycle's PostedAt. Skipped
    -- (NULL) for a batch that was never reposted (a single produced lot) so legacy
    -- batches — whose PostedAt predates the cycle-stamp scheme — reverse in full.
    DECLARE @ProducedLotCount INT = (SELECT COUNT(*) FROM dbo.PoultryRawMaterialPurchases
        WHERE SourceFeedProductionBatchId = @PoultryFeedProductionBatchId AND PoultryRawMaterialItemId = @FinishedFeedItemId AND FarmId = @FarmId);
    DECLARE @Boundary DATETIME2 = CASE WHEN @ProducedLotCount > 1 THEN @PostedAt ELSE NULL END;

    -- Guard: block if the CURRENT cycle's produced feed has been used (lot not intact).
    DECLARE @Produced  DECIMAL(18,3) = ISNULL((SELECT SUM(Quantity)          FROM dbo.PoultryRawMaterialPurchases
        WHERE SourceFeedProductionBatchId = @PoultryFeedProductionBatchId AND PoultryRawMaterialItemId = @FinishedFeedItemId AND FarmId = @FarmId
          AND (@Boundary IS NULL OR CreatedAt >= @Boundary)), 0);
    DECLARE @Remaining DECIMAL(18,3) = ISNULL((SELECT SUM(RemainingQuantity) FROM dbo.PoultryRawMaterialPurchases
        WHERE SourceFeedProductionBatchId = @PoultryFeedProductionBatchId AND PoultryRawMaterialItemId = @FinishedFeedItemId AND FarmId = @FarmId
          AND (@Boundary IS NULL OR CreatedAt >= @Boundary)), 0);
    IF (@Remaining + 0.0005 < @Produced)
        THROW 51203, 'This batch cannot be reversed because some of the produced feed has already been used. Reverse the related feed usage first.', 1;

    BEGIN TRANSACTION;

    -- 1. Reverse the current cycle's INVENTORY-portion ingredient draws (drew from
    --    normal lots — SourceFeedProductionBatchId IS NULL).
    -- 1a. Return the ingredient to the exact lots it was drawn from.
    UPDATE p
    SET    p.RemainingQuantity = p.RemainingQuantity + ub.QuantityDrawn, p.UpdatedAt = SYSUTCDATETIME()
    FROM   dbo.PoultryRawMaterialPurchases p
    JOIN   dbo.PoultryRawMaterialUsageBatch ub ON ub.PoultryRawMaterialPurchaseId = p.PoultryRawMaterialPurchaseId
    JOIN   dbo.PoultryRawMaterialUsage u ON u.PoultryRawMaterialUsageId = ub.PoultryRawMaterialUsageId
    WHERE  u.PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId AND u.FarmId = @FarmId
      AND  p.SourceFeedProductionBatchId IS NULL
      AND  (@Boundary IS NULL OR u.CreatedAt >= @Boundary);

    -- 1b. Compensating IN adjustment per ingredient + bump CurrentQuantity. Usage rows KEPT.
    ;WITH InvUse AS (
        SELECT u.PoultryRawMaterialItemId AS ItemId, SUM(ub.QuantityDrawn) AS Qty
        FROM   dbo.PoultryRawMaterialUsage u
        JOIN   dbo.PoultryRawMaterialUsageBatch ub ON ub.PoultryRawMaterialUsageId = u.PoultryRawMaterialUsageId
        JOIN   dbo.PoultryRawMaterialPurchases p ON p.PoultryRawMaterialPurchaseId = ub.PoultryRawMaterialPurchaseId
        WHERE  u.PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId AND u.FarmId = @FarmId
          AND  p.SourceFeedProductionBatchId IS NULL
          AND  (@Boundary IS NULL OR u.CreatedAt >= @Boundary)
        GROUP  BY u.PoultryRawMaterialItemId
    )
    INSERT INTO dbo.PoultryRawMaterialAdjustments (FarmId, PoultryRawMaterialItemId, AdjustedDate, Quantity, MovementType, Note, CreatedBy)
    SELECT @FarmId, ItemId, SYSUTCDATETIME(), Qty, 'FeedProductionReversal',
           CONCAT(N'Reversal of feed production ', @BatchNumber), @ReversedBy
    FROM   InvUse WHERE Qty > 0;

    UPDATE it
    SET    it.CurrentQuantity = it.CurrentQuantity + iv.Qty, it.UpdatedAt = SYSUTCDATETIME()
    FROM   dbo.PoultryRawMaterialItems it
    JOIN  (SELECT u.PoultryRawMaterialItemId AS ItemId, SUM(ub.QuantityDrawn) AS Qty
           FROM   dbo.PoultryRawMaterialUsage u
           JOIN   dbo.PoultryRawMaterialUsageBatch ub ON ub.PoultryRawMaterialUsageId = u.PoultryRawMaterialUsageId
           JOIN   dbo.PoultryRawMaterialPurchases p ON p.PoultryRawMaterialPurchaseId = ub.PoultryRawMaterialPurchaseId
           WHERE  u.PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId AND u.FarmId = @FarmId
             AND  p.SourceFeedProductionBatchId IS NULL
             AND  (@Boundary IS NULL OR u.CreatedAt >= @Boundary)
           GROUP  BY u.PoultryRawMaterialItemId) iv ON iv.ItemId = it.PoultryRawMaterialItemId
    WHERE  it.FarmId = @FarmId;

    -- 2. Remove the current cycle's PRODUCED finished feed via an append-only draw
    --    against its produced lot(s), zeroing them. Lot rows KEPT.
    DECLARE @ProdLotId INT, @ProdQty DECIMAL(14,3), @ProdUnitCost DECIMAL(14,2), @RevUsageId INT;
    DECLARE prod_cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT PoultryRawMaterialPurchaseId, RemainingQuantity, UnitCost
        FROM   dbo.PoultryRawMaterialPurchases
        WHERE  SourceFeedProductionBatchId = @PoultryFeedProductionBatchId
          AND  PoultryRawMaterialItemId = @FinishedFeedItemId AND FarmId = @FarmId AND RemainingQuantity > 0
          AND  (@Boundary IS NULL OR CreatedAt >= @Boundary);
    OPEN prod_cur; FETCH NEXT FROM prod_cur INTO @ProdLotId, @ProdQty, @ProdUnitCost;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        INSERT INTO dbo.PoultryRawMaterialUsage (FarmId, PoultryRawMaterialItemId, QuantityUsed, UnitCost, Notes, CreatedBy)
        VALUES (@FarmId, @FinishedFeedItemId, @ProdQty, @ProdUnitCost, CONCAT(N'Reversal of produced feed ', @BatchNumber), @ReversedBy);
        SET @RevUsageId = CAST(SCOPE_IDENTITY() AS INT);

        INSERT INTO dbo.PoultryRawMaterialUsageBatch (PoultryRawMaterialUsageId, PoultryRawMaterialPurchaseId, QuantityDrawn, UnitCostAtDraw)
        VALUES (@RevUsageId, @ProdLotId, @ProdQty, @ProdUnitCost);

        UPDATE dbo.PoultryRawMaterialPurchases SET RemainingQuantity = 0, UpdatedAt = SYSUTCDATETIME()
        WHERE  PoultryRawMaterialPurchaseId = @ProdLotId;

        FETCH NEXT FROM prod_cur INTO @ProdLotId, @ProdQty, @ProdUnitCost;
    END
    CLOSE prod_cur; DEALLOCATE prod_cur;

    UPDATE dbo.PoultryRawMaterialItems
    SET    CurrentQuantity = CASE WHEN CurrentQuantity - @Produced < 0 THEN 0 ELSE CurrentQuantity - @Produced END,
           UpdatedAt = SYSUTCDATETIME()
    WHERE  PoultryRawMaterialItemId = @FinishedFeedItemId AND FarmId = @FarmId;

    -- 3. Bought-during-production ingredient lots are net-zero; rows KEPT, no offset.

    -- 4. Reverse the current cycle's cash — append an opposite CashIn per account.
    DECLARE @AcctId INT, @OutAmt DECIMAL(14,2), @NewBal DECIMAL(14,2);
    DECLARE rev_cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT PoultryCashAccountId, SUM(Amount)   -- Amount is negative (cash out)
        FROM   dbo.PoultryCashTransactions
        WHERE  SourceType = 'FeedProduction' AND SourceId = @PoultryFeedProductionBatchId AND FarmId = @FarmId
          AND  (@Boundary IS NULL OR CreatedAt >= @Boundary)
        GROUP  BY PoultryCashAccountId;
    OPEN rev_cur; FETCH NEXT FROM rev_cur INTO @AcctId, @OutAmt;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        UPDATE dbo.PoultryCashAccounts SET CurrentBalance = CurrentBalance - @OutAmt, UpdatedAt = SYSUTCDATETIME()
        WHERE  PoultryCashAccountId = @AcctId AND FarmId = @FarmId;
        SET @NewBal = (SELECT CurrentBalance FROM dbo.PoultryCashAccounts WHERE PoultryCashAccountId = @AcctId AND FarmId = @FarmId);
        INSERT INTO dbo.PoultryCashTransactions
            (FarmId, PoultryCashAccountId, TransactionDate, TransactionType, SourceType, SourceId, Amount, BalanceAfterTransaction, Description, CreatedBy)
        VALUES (@FarmId, @AcctId, @ProductionDate, 'CashIn', 'FeedProductionReversal', @PoultryFeedProductionBatchId, -@OutAmt, @NewBal, CONCAT(N'Reversal of feed production ', @BatchNumber), @ReversedBy);
        FETCH NEXT FROM rev_cur INTO @AcctId, @OutAmt;
    END
    CLOSE rev_cur; DEALLOCATE rev_cur;

    -- 5. Mark reversed (keep line/cost + all ledger history for the record).
    UPDATE dbo.PoultryFeedProductionBatches
    SET    Status = 'Reversed', ReversedBy = @ReversedBy, ReversedAt = SYSUTCDATETIME(),
           ReversalReason = @ReversalReason, UpdatedAt = SYSUTCDATETIME()
    WHERE  PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId AND FarmId = @FarmId;

    COMMIT TRANSACTION;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spPoultryFeedProductionBatch_Post     TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryFeedProductionBatch_Reverse TO [Techretainer];
    PRINT '178: granted EXECUTE on feed production post/reverse to Techretainer.';
END
GO

PRINT '178_PoultryFeedProductionRepostCycleSafe.sql complete.';
GO
