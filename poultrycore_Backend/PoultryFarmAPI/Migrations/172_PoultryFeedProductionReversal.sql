-- =============================================================================
-- Migration 172: Feed Production — REVERSE engine (transactional)
-- =============================================================================
-- Reverses a posted batch, only when safe. Blocked if any of the produced feed
-- has been consumed (this batch's produced stock lot is no longer fully intact).
-- When allowed, in one atomic transaction it:
--   1. Restores the raw-material lots drawn for the inventory portions
--      (RemainingQuantity) + the items' CurrentQuantity, and deletes the usage rows.
--   2. Removes the produced finished-feed stock lot (CurrentQuantity down).
--   3. Deletes ALL batch-owned purchase lots (produced feed + bought-for-production
--      ingredient lots — the latter never bumped stock, so no restore needed).
--   4. Reverses the posted CashOut(s), restoring account balances, and deletes them.
--   5. Marks the batch Reversed (+ ReversedBy/At/Reason). Line/cost history is kept.
--
-- Draft batches are edited/deleted, not reversed. A reversed batch can't be
-- posted again. Idempotent (CREATE OR ALTER). Safe to re-run.
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryFeedProductionBatch_Reverse
    @FarmId NVARCHAR(450),
    @PoultryFeedProductionBatchId INT,
    @ReversedBy NVARCHAR(450) = NULL,
    @ReversalReason NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Status NVARCHAR(20), @FinishedFeedItemId INT;
    SELECT @Status = Status, @FinishedFeedItemId = FinishedFeedItemId
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

    -- 1a. Restore raw-material lots drawn for inventory portions.
    UPDATE p
    SET    p.RemainingQuantity = p.RemainingQuantity + ub.QuantityDrawn, p.UpdatedAt = SYSUTCDATETIME()
    FROM   dbo.PoultryRawMaterialPurchases p
    JOIN   dbo.PoultryRawMaterialUsageBatch ub ON ub.PoultryRawMaterialPurchaseId = p.PoultryRawMaterialPurchaseId
    JOIN   dbo.PoultryRawMaterialUsage u ON u.PoultryRawMaterialUsageId = ub.PoultryRawMaterialUsageId
    WHERE  u.PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId AND u.FarmId = @FarmId;

    -- 1b. Restore consumed items' CurrentQuantity.
    UPDATE it
    SET    it.CurrentQuantity = it.CurrentQuantity + u.QuantityUsed, it.UpdatedAt = SYSUTCDATETIME()
    FROM   dbo.PoultryRawMaterialItems it
    JOIN   dbo.PoultryRawMaterialUsage u ON u.PoultryRawMaterialItemId = it.PoultryRawMaterialItemId AND u.FarmId = it.FarmId
    WHERE  u.PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId AND u.FarmId = @FarmId;

    -- 1c. Delete usage rows (usage-batch cascades).
    DELETE FROM dbo.PoultryRawMaterialUsage WHERE PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId AND FarmId = @FarmId;

    -- 2. Remove produced finished-feed from stock (its lot is intact per the guard).
    UPDATE it
    SET    it.CurrentQuantity = it.CurrentQuantity - pr.Qty, it.UpdatedAt = SYSUTCDATETIME()
    FROM   dbo.PoultryRawMaterialItems it
    JOIN  (SELECT PoultryRawMaterialItemId, SUM(RemainingQuantity) AS Qty
           FROM   dbo.PoultryRawMaterialPurchases
           WHERE  SourceFeedProductionBatchId = @PoultryFeedProductionBatchId AND PoultryRawMaterialItemId = @FinishedFeedItemId AND FarmId = @FarmId
           GROUP  BY PoultryRawMaterialItemId) pr ON pr.PoultryRawMaterialItemId = it.PoultryRawMaterialItemId
    WHERE  it.FarmId = @FarmId;

    -- 3. Delete all batch-owned purchase lots (produced + bought-for-production).
    DELETE FROM dbo.PoultryRawMaterialPurchases WHERE SourceFeedProductionBatchId = @PoultryFeedProductionBatchId AND FarmId = @FarmId;

    -- 4. Reverse cash-out postings, restoring balances.
    DECLARE @AcctId INT, @Amt DECIMAL(14,2);
    DECLARE rev_cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT PoultryCashAccountId, SUM(Amount)
        FROM   dbo.PoultryCashTransactions
        WHERE  SourceType = 'FeedProduction' AND SourceId = @PoultryFeedProductionBatchId AND FarmId = @FarmId
        GROUP  BY PoultryCashAccountId;
    OPEN rev_cur; FETCH NEXT FROM rev_cur INTO @AcctId, @Amt;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- @Amt is negative (cash out); subtracting it adds the money back.
        UPDATE dbo.PoultryCashAccounts SET CurrentBalance = CurrentBalance - @Amt, UpdatedAt = SYSUTCDATETIME()
        WHERE  PoultryCashAccountId = @AcctId AND FarmId = @FarmId;
        FETCH NEXT FROM rev_cur INTO @AcctId, @Amt;
    END
    CLOSE rev_cur; DEALLOCATE rev_cur;
    DELETE FROM dbo.PoultryCashTransactions WHERE SourceType = 'FeedProduction' AND SourceId = @PoultryFeedProductionBatchId AND FarmId = @FarmId;

    -- 5. Mark reversed (keep line/cost history for the record).
    UPDATE dbo.PoultryFeedProductionBatches
    SET    Status = 'Reversed', ReversedBy = @ReversedBy, ReversedAt = SYSUTCDATETIME(),
           ReversalReason = @ReversalReason, UpdatedAt = SYSUTCDATETIME()
    WHERE  PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId AND FarmId = @FarmId;

    COMMIT TRANSACTION;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spPoultryFeedProductionBatch_Reverse TO [Techretainer];
    PRINT '172: granted EXECUTE on spPoultryFeedProductionBatch_Reverse to Techretainer.';
END
GO

PRINT '172_PoultryFeedProductionReversal.sql complete.';
GO
