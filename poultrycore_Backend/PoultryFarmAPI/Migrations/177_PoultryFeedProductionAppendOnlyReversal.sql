-- =============================================================================
-- Migration 177: Feed Production — append-only reversal (+ posting consistency)
-- =============================================================================
-- Fixes the reversal engine so it NEVER physically deletes stock/usage/cash rows.
-- The prior reversal (172) hard-deleted the ingredient usage rows, the batch-owned
-- purchase lots (produced feed + bought-for-production), and the cash-out rows,
-- destroying the audit trail. Stock movements must be an append-only ledger: a
-- reversal is done by writing OFFSETTING entries, not by deletion.
--
-- CurrentQuantity is derived (migration 175) as:
--     SUM(purchase.Quantity) - SUM(usage.QuantityUsed) + SUM(adjustment.Quantity)
-- so every offset below is chosen to keep BOTH the live balances and that recalc
-- correct while leaving all original rows in place.
--
-- This migration has three parts:
--   1. POST — for the BoughtDuringProduction / purchased portion, also write an
--      explicit stock-out usage row (drawn against its own lot). Previously the
--      purchase lot was inserted with RemainingQuantity 0 and NO usage row, so the
--      recalc over-counted it by the purchased quantity. Now purchase (+q) and
--      usage (-q) net to zero in both the live balance and the recalc.
--   2. REVERSE — append-only:
--        • Inventory-portion draws: restore the exact lots' RemainingQuantity and
--          write a compensating IN adjustment per ingredient (+ bump CurrentQuantity).
--          Original usage rows are KEPT.
--        • Produced finished feed: write a usage row that draws the produced lot's
--          remaining quantity (explicit draw against that lot only), zeroing it, and
--          reduce CurrentQuantity. The produced purchase lot row is KEPT.
--        • Bought-during-production lots: net-zero already; rows KEPT, no offset.
--        • Cash: append an opposite CashIn per account. Original CashOut rows KEPT.
--   3. Traceability report — exclude the produced-feed reversal draw (it has no
--      ProductionRecordId) so it never shows up as a flock consuming the feed.
--
-- NOTE: batches POSTED before this migration have no purchased-portion usage row,
-- so recalc still over-counts their bought-during-production quantity (a pre-existing
-- condition). Reversing such a batch still restores live balances correctly; only the
-- recalc button remains inflated for them. Not backfilled here (data-migration risk).
--
-- Idempotent (CREATE OR ALTER). Safe to re-run.
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- =============================================================================
-- 1. POST engine — same as 171, plus an explicit stock-out for purchased portions.
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
    IF @Status = 'Reversed' THROW 51102, 'A reversed batch cannot be posted again.', 1;
    IF ISNULL(@QtyProduced,0) <= 0 THROW 51103, 'Quantity produced must be greater than zero.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.PoultryFeedProductionBatchLines WHERE PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId)
        THROW 51104, 'Add at least one ingredient line before posting.', 1;

    IF EXISTS (SELECT 1 FROM dbo.PoultryFeedProductionBatchLines
               WHERE PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId AND ISNULL(AmountPaid,0) > 0 AND PaidFromCashAccountId IS NULL)
        THROW 51105, 'Select a cash account for paid ingredient purchases.', 1;
    IF EXISTS (SELECT 1 FROM dbo.PoultryFeedProductionAdditionalCosts
               WHERE PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId AND ISNULL(AmountPaid,0) > 0 AND PaidFromCashAccountId IS NULL)
        THROW 51106, 'Select a cash account for paid production costs.', 1;

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
            INSERT INTO dbo.PoultryRawMaterialUsage (FarmId, PoultryRawMaterialItemId, PoultryFeedProductionBatchId, QuantityUsed, Notes, CreatedBy)
            VALUES (@FarmId, @ItemId, @PoultryFeedProductionBatchId, @InvQty, CONCAT(N'Feed production ', @BatchNumber), @PostedBy);
            SET @UsageId = CAST(SCOPE_IDENTITY() AS INT);

            EXEC dbo.spPoultryRawMaterialItem_ConsumeBatches @FarmId, @ItemId, @UsageId, @InvQty, @InvCost OUTPUT;

            UPDATE dbo.PoultryRawMaterialItems
            SET    CurrentQuantity = CurrentQuantity - @InvQty, UpdatedAt = SYSUTCDATETIME()
            WHERE  PoultryRawMaterialItemId = @ItemId AND FarmId = @FarmId;

            UPDATE dbo.PoultryRawMaterialUsage SET UnitCost = @InvCost WHERE PoultryRawMaterialUsageId = @UsageId;
            SET @InvPortion = CAST(ISNULL(@InvCost,0) * @InvQty AS DECIMAL(14,2));
        END

        -- Purchased portion: a bought-and-consumed lot (net-zero stock) for audit.
        -- The lot is the stock-in; an explicit usage row (drawn against that lot)
        -- is the stock-out, so both the live balance and the recalc net to zero.
        IF @PurQty > 0
        BEGIN
            INSERT INTO dbo.PoultryRawMaterialPurchases
                (FarmId, PoultryRawMaterialItemId, SupplierName, SupplierId, PurchaseDate, Quantity, UnitCost, TotalCost,
                 ProductionUnit, ProductionUnitsPerPurchaseUnit, RemainingQuantity, PaymentMethod, AmountPaid,
                 SourceFeedProductionBatchId, Notes, CreatedBy)
            VALUES (@FarmId, @ItemId, @SupplierName, @SupplierId, @ProductionDate, @PurQty, @PurUnit, CAST(@PurQty * @PurUnit AS DECIMAL(14,2)),
                 @Unit, 1, @PurQty, @PaymentMethod, CAST(@PurQty * @PurUnit AS DECIMAL(14,2)),
                 @PoultryFeedProductionBatchId, CONCAT(N'Bought for feed production ', @BatchNumber), @PostedBy);
            SET @PurLotId = CAST(SCOPE_IDENTITY() AS INT);

            INSERT INTO dbo.PoultryRawMaterialUsage (FarmId, PoultryRawMaterialItemId, PoultryFeedProductionBatchId, QuantityUsed, UnitCost, Notes, CreatedBy)
            VALUES (@FarmId, @ItemId, @PoultryFeedProductionBatchId, @PurQty, @PurUnit, CONCAT(N'Bought & consumed for feed production ', @BatchNumber), @PostedBy);
            SET @PurUsageId = CAST(SCOPE_IDENTITY() AS INT);

            INSERT INTO dbo.PoultryRawMaterialUsageBatch (PoultryRawMaterialUsageId, PoultryRawMaterialPurchaseId, QuantityDrawn, UnitCostAtDraw)
            VALUES (@PurUsageId, @PurLotId, @PurQty, @PurUnit);

            -- Bought and immediately consumed -> lot ends fully drawn (net-zero stock).
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
         SourceFeedProductionBatchId, Notes, CreatedBy)
    VALUES (@FarmId, @FinishedFeedItemId, N'Feed Production', @ProductionDate, @QtyProduced, @CPU, @TotCost,
         @OutputUnit, 1, @QtyProduced, N'Production', @TotCost,
         @PoultryFeedProductionBatchId, CONCAT(N'Produced feed ', @BatchNumber), @PostedBy);

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
            (FarmId, PoultryCashAccountId, TransactionDate, TransactionType, SourceType, SourceId, Amount, BalanceAfterTransaction, Description, CreatedBy)
        VALUES (@FarmId, @AcctId, @ProductionDate, 'CashOut', 'FeedProduction', @PoultryFeedProductionBatchId, -@Paid, @NewBal, CONCAT(N'Feed production ', @BatchNumber), @PostedBy);
        FETCH NEXT FROM pay_cur INTO @AcctId, @Paid;
    END
    CLOSE pay_cur; DEALLOCATE pay_cur;
    DROP TABLE #Pay;

    UPDATE dbo.PoultryFeedProductionBatches
    SET    TotalIngredientCost = @IngCost, TotalAdditionalCost = @AddCost, TotalProductionCost = @TotCost,
           CostPerOutputUnit = @CPU, Status = 'Posted', PostedBy = @PostedBy, PostedAt = SYSUTCDATETIME(), UpdatedAt = SYSUTCDATETIME()
    WHERE  PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId AND FarmId = @FarmId;

    COMMIT TRANSACTION;
END
GO

-- =============================================================================
-- 2. REVERSE engine — append-only. Never deletes; writes offsetting entries.
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

    DECLARE @Status NVARCHAR(20), @FinishedFeedItemId INT, @BatchNumber NVARCHAR(60), @ProductionDate DATETIME2;
    SELECT @Status = Status, @FinishedFeedItemId = FinishedFeedItemId, @BatchNumber = BatchNumber, @ProductionDate = ProductionDate
    FROM   dbo.PoultryFeedProductionBatches
    WHERE  PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId AND FarmId = @FarmId;

    IF @Status IS NULL      THROW 51200, 'Feed production batch not found.', 1;
    IF @Status = 'Draft'    THROW 51201, 'Draft batches are edited or deleted, not reversed.', 1;
    IF @Status = 'Reversed' THROW 51202, 'This batch has already been reversed.', 1;

    -- Guard: block if any produced feed has been used (its stock lot isn't intact).
    DECLARE @Produced  DECIMAL(18,3) = ISNULL((SELECT SUM(Quantity)          FROM dbo.PoultryRawMaterialPurchases
        WHERE SourceFeedProductionBatchId = @PoultryFeedProductionBatchId AND PoultryRawMaterialItemId = @FinishedFeedItemId AND FarmId = @FarmId), 0);
    DECLARE @Remaining DECIMAL(18,3) = ISNULL((SELECT SUM(RemainingQuantity) FROM dbo.PoultryRawMaterialPurchases
        WHERE SourceFeedProductionBatchId = @PoultryFeedProductionBatchId AND PoultryRawMaterialItemId = @FinishedFeedItemId AND FarmId = @FarmId), 0);
    IF (@Remaining + 0.0005 < @Produced)
        THROW 51203, 'This batch cannot be reversed because some of the produced feed has already been used. Reverse the related feed usage first.', 1;

    BEGIN TRANSACTION;

    -- -------------------------------------------------------------------------
    -- 1. Reverse the INVENTORY-portion ingredient draws (drew from normal lots,
    --    i.e. lots NOT owned by a feed production batch). The bought-during-
    --    production draws (their lot has SourceFeedProductionBatchId set) are
    --    excluded here — they are net-zero and handled by keeping their rows.
    -- -------------------------------------------------------------------------
    -- 1a. Physically return the ingredient to the exact lots it was drawn from.
    UPDATE p
    SET    p.RemainingQuantity = p.RemainingQuantity + ub.QuantityDrawn, p.UpdatedAt = SYSUTCDATETIME()
    FROM   dbo.PoultryRawMaterialPurchases p
    JOIN   dbo.PoultryRawMaterialUsageBatch ub ON ub.PoultryRawMaterialPurchaseId = p.PoultryRawMaterialPurchaseId
    JOIN   dbo.PoultryRawMaterialUsage u ON u.PoultryRawMaterialUsageId = ub.PoultryRawMaterialUsageId
    WHERE  u.PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId AND u.FarmId = @FarmId
      AND  p.SourceFeedProductionBatchId IS NULL;

    -- 1b. Append a compensating IN adjustment per ingredient (the offset that
    --     keeps CurrentQuantity/recalc correct without deleting the usage rows),
    --     then bump CurrentQuantity to match. Original usage rows are KEPT.
    ;WITH InvUse AS (
        SELECT u.PoultryRawMaterialItemId AS ItemId, SUM(ub.QuantityDrawn) AS Qty
        FROM   dbo.PoultryRawMaterialUsage u
        JOIN   dbo.PoultryRawMaterialUsageBatch ub ON ub.PoultryRawMaterialUsageId = u.PoultryRawMaterialUsageId
        JOIN   dbo.PoultryRawMaterialPurchases p ON p.PoultryRawMaterialPurchaseId = ub.PoultryRawMaterialPurchaseId
        WHERE  u.PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId AND u.FarmId = @FarmId
          AND  p.SourceFeedProductionBatchId IS NULL
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
           GROUP  BY u.PoultryRawMaterialItemId) iv ON iv.ItemId = it.PoultryRawMaterialItemId
    WHERE  it.FarmId = @FarmId;

    -- -------------------------------------------------------------------------
    -- 2. Remove the PRODUCED finished feed with an append-only draw: a usage row
    --    that consumes each produced lot's remaining quantity (explicit draw
    --    against that lot so other lots' FIFO is untouched), zeroing the lot. The
    --    produced purchase lot row itself is KEPT.
    -- -------------------------------------------------------------------------
    DECLARE @ProdLotId INT, @ProdQty DECIMAL(14,3), @ProdUnitCost DECIMAL(14,2), @RevUsageId INT;
    DECLARE prod_cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT PoultryRawMaterialPurchaseId, RemainingQuantity, UnitCost
        FROM   dbo.PoultryRawMaterialPurchases
        WHERE  SourceFeedProductionBatchId = @PoultryFeedProductionBatchId
          AND  PoultryRawMaterialItemId = @FinishedFeedItemId AND FarmId = @FarmId AND RemainingQuantity > 0;
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

    -- -------------------------------------------------------------------------
    -- 3. Bought-during-production ingredient lots are net-zero (bought and
    --    immediately consumed). Their purchase + usage rows are KEPT as-is;
    --    no stock offset is required.
    -- -------------------------------------------------------------------------

    -- -------------------------------------------------------------------------
    -- 4. Reverse the cash — append an opposite CashIn per account. The original
    --    CashOut rows are KEPT (append-only cash ledger).
    -- -------------------------------------------------------------------------
    DECLARE @AcctId INT, @OutAmt DECIMAL(14,2), @NewBal DECIMAL(14,2);
    DECLARE rev_cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT PoultryCashAccountId, SUM(Amount)   -- Amount is negative (cash out)
        FROM   dbo.PoultryCashTransactions
        WHERE  SourceType = 'FeedProduction' AND SourceId = @PoultryFeedProductionBatchId AND FarmId = @FarmId
        GROUP  BY PoultryCashAccountId;
    OPEN rev_cur; FETCH NEXT FROM rev_cur INTO @AcctId, @OutAmt;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- @OutAmt < 0; subtracting it returns the money.
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

-- =============================================================================
-- 3. Traceability — exclude the produced-feed reversal draw (no ProductionRecordId)
--    so a reversed batch never appears as a flock consuming the feed.
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.spPoultryFeedProductionReport_Traceability
    @FarmId NVARCHAR(450), @PoultryFeedProductionBatchId INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT b.PoultryFeedProductionBatchId, b.BatchNumber, b.FinishedFeedItemId,
           fi.ItemName AS FinishedFeedName,
           u.PoultryRawMaterialUsageId,
           u.ProductionRecordId,
           u.QuantityUsed,
           ub.QuantityDrawn,
           ub.UnitCostAtDraw,
           u.UsedDate
    FROM   dbo.PoultryFeedProductionBatches b
    INNER  JOIN dbo.PoultryRawMaterialItems fi ON fi.PoultryRawMaterialItemId = b.FinishedFeedItemId
    INNER  JOIN dbo.PoultryRawMaterialPurchases p ON p.SourceFeedProductionBatchId = b.PoultryFeedProductionBatchId AND p.PoultryRawMaterialItemId = b.FinishedFeedItemId
    INNER  JOIN dbo.PoultryRawMaterialUsageBatch ub ON ub.PoultryRawMaterialPurchaseId = p.PoultryRawMaterialPurchaseId
    INNER  JOIN dbo.PoultryRawMaterialUsage u ON u.PoultryRawMaterialUsageId = ub.PoultryRawMaterialUsageId
    WHERE  b.FarmId = @FarmId AND b.PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId
      AND  u.ProductionRecordId IS NOT NULL     -- flock consumption only (skip reversal draws)
    ORDER  BY u.UsedDate DESC;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spPoultryFeedProductionBatch_Post              TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryFeedProductionBatch_Reverse          TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryFeedProductionReport_Traceability    TO [Techretainer];
    PRINT '177: granted EXECUTE on feed production post/reverse/traceability to Techretainer.';
END
GO

PRINT '177_PoultryFeedProductionAppendOnlyReversal.sql complete.';
GO
