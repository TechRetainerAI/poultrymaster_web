-- =============================================================================
-- Migration 179: Append-only stock ledgers for production reversal
-- =============================================================================
-- Reversing a Batch Production record deletes the generated flock ProductionRecords
-- (spProductionRecord_Delete), which unwinds their side-effects through three shared
-- flock-level syncs. Two of those syncs PHYSICALLY DELETE stock-ledger rows, so the
-- reversal leaves no audit trail:
--   * spPoultryBirdStock_Sync / spPoultryEggStock_SyncForProduction — delete the
--     PoultryStockTransactions row for (TxnType, RelatedId) then re-insert.
--   * spPoultryProductionRawMaterialSync — restore stock then DELETE the
--     PoultryRawMaterialUsage rows.
--
-- These syncs are shared by EVERY flock production record (manual + batch), so the
-- fix is made here, at the sync level, and applies to both.
--
-- Stock movements must be append-only. This migration changes the reversal effect
-- from deletion to opposite/offsetting entries, leaving the originals in place:
--
--   1. PoultryStockTransactions (birds, eggs) — signed Quantity ledger whose stock
--      is SUM(Quantity). Replace "delete + re-insert" with "post the DELTA needed to
--      reach the target". A reversal (target 0) posts the exact opposite row; an edit
--      posts the difference. SUM stays correct; every original row is preserved.
--      No schema change.
--   2. PoultryRawMaterialUsage (feed / medication) — mark the consumed rows
--      IsReversed = 1 (KEEP them) instead of deleting, restore the drawn lots +
--      CurrentQuantity as before (scoped to the still-live rows so repeated edits
--      never double-restore), and post a compensating IN adjustment per item into
--      PoultryRawMaterialAdjustments (the append-only signed adjustments ledger) so
--      the recalc stays consistent and the reversal is visible on the Stock
--      Movements page.
--
-- The flock-level bird/egg/raw-material RE-APPLY logic is unchanged; only the
-- reversal effect changes. Idempotent (col guard + CREATE OR ALTER). Safe to re-run.
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- 0. Marker so a reversed feed/medication usage row is kept (audit) but excluded
--    from future restore aggregates. Additive + nullable-with-default.
-- -----------------------------------------------------------------------------
IF COL_LENGTH('dbo.PoultryRawMaterialUsage', 'IsReversed') IS NULL
    ALTER TABLE dbo.PoultryRawMaterialUsage ADD IsReversed BIT NOT NULL CONSTRAINT DF_PoultryRMUsage_IsReversed DEFAULT (0);
GO
IF COL_LENGTH('dbo.PoultryRawMaterialUsage', 'ReversedAt') IS NULL
    ALTER TABLE dbo.PoultryRawMaterialUsage ADD ReversedAt DATETIME2 NULL;
GO

-- =============================================================================
-- 1. Bird stock sync — append the delta instead of delete + re-insert.
--    Same net stock (SUM(Quantity)); every prior row is preserved.
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.spPoultryBirdStock_Sync
    @FarmId NVARCHAR(450), @TxnType NVARCHAR(30), @Quantity DECIMAL(14,3), @RelatedId INT,
    @Note NVARCHAR(500) = NULL, @CreatedBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @bird INT;
    SELECT TOP 1 @bird = PoultryProductId FROM dbo.PoultryProducts
    WHERE FarmId = @FarmId AND (IsBirdProduct = 1 OR Name = N'Birds') ORDER BY IsBirdProduct DESC, PoultryProductId;
    IF @bird IS NULL
    BEGIN
        INSERT INTO dbo.PoultryProducts (FarmId, Name, Unit, UnitPrice, ProductType, IsRawEggProduct, RequiresRecipeSetup, IsBirdProduct)
        VALUES (@FarmId, N'Birds', N'Bird', 0, 'FinishedGood', 0, 0, 1);
        SET @bird = CAST(SCOPE_IDENTITY() AS INT);
    END

    -- Append-only: post the delta to reach @Quantity for this (TxnType, RelatedId).
    -- Reversal (@Quantity = 0) posts the exact opposite of the prior net; never deletes.
    DECLARE @Net DECIMAL(14,3) = ISNULL((SELECT SUM(Quantity) FROM dbo.PoultryStockTransactions
        WHERE FarmId = @FarmId AND TxnType = @TxnType AND RelatedId = @RelatedId), 0);
    DECLARE @Delta DECIMAL(14,3) = ISNULL(@Quantity, 0) - @Net;

    IF (@Delta <> 0)
        INSERT INTO dbo.PoultryStockTransactions (FarmId, PoultryProductId, TxnType, Quantity, RelatedId, Note, CreatedBy)
        VALUES (@FarmId, @bird, @TxnType, @Delta, @RelatedId,
                CASE WHEN ISNULL(@Quantity,0) = 0 THEN CONCAT(N'Reversal of ', @TxnType) ELSE @Note END, @CreatedBy);
END
GO

-- =============================================================================
-- 2. Egg stock sync — append the delta instead of delete + re-insert.
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.spPoultryEggStock_SyncForProduction
    @FarmId NVARCHAR(450), @ProductionId INT, @GoodEggs INT, @UnitCost DECIMAL(14,4) = NULL, @CreatedBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Net DECIMAL(14,3) = ISNULL((SELECT SUM(Quantity) FROM dbo.PoultryStockTransactions
        WHERE FarmId = @FarmId AND TxnType = 'Production' AND RelatedId = @ProductionId), 0);
    DECLARE @Delta DECIMAL(14,3) = ISNULL(@GoodEggs, 0) - @Net;
    IF (@Delta = 0) RETURN;

    DECLARE @egg INT;
    SELECT TOP 1 @egg = PoultryProductId FROM dbo.PoultryProducts
    WHERE  FarmId = @FarmId AND (IsRawEggProduct = 1 OR Name IN (N'Eggs', N'Chicken Eggs'))
    ORDER  BY IsRawEggProduct DESC, PoultryProductId;
    IF @egg IS NULL
    BEGIN
        INSERT INTO dbo.PoultryProducts (FarmId, Name, Unit, UnitPrice, ProductType, IsRawEggProduct, RequiresRecipeSetup)
        VALUES (@FarmId, N'Eggs', N'Crate', 0, 'FinishedGood', 1, 0);
        SET @egg = CAST(SCOPE_IDENTITY() AS INT);
    END

    INSERT INTO dbo.PoultryStockTransactions (FarmId, PoultryProductId, TxnType, Quantity, UnitCost, RelatedId, Note, CreatedBy)
    VALUES (@FarmId, @egg, 'Production', @Delta, @UnitCost, @ProductionId,
            CASE WHEN ISNULL(@GoodEggs,0) = 0 THEN N'Reversal of egg production' ELSE N'Egg production' END, @CreatedBy);
END
GO

-- =============================================================================
-- 3. Raw-material (feed/medication) sync — append-only reversal.
--    Body identical to migration 158 EXCEPT the reversal section (step 1): the
--    consumed usage rows are marked IsReversed instead of deleted, restores are
--    scoped to still-live rows, and a compensating IN adjustment is posted.
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.spPoultryProductionRawMaterialSync
    @FarmId NVARCHAR(450), @ProductionId INT,
    @FeedItemId INT = NULL, @FeedQty DECIMAL(14,3) = NULL,
    @MedItemId  INT = NULL, @MedQty  DECIMAL(14,3) = NULL,
    @CreatedBy NVARCHAR(450) = NULL,
    @ComputedFeedUnitCost DECIMAL(14,4) = NULL OUTPUT,
    @ComputedTotalFeedCost DECIMAL(14,2) = NULL OUTPUT,
    @ComputedMedicationUnitCost DECIMAL(14,4) = NULL OUTPUT,
    @ComputedTotalMedicationCost DECIMAL(14,2) = NULL OUTPUT,
    @MedicationsJson NVARCHAR(MAX) = NULL,
    @FeedsJson NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @ComputedFeedUnitCost = NULL; SET @ComputedTotalFeedCost = NULL;
    SET @ComputedMedicationUnitCost = NULL; SET @ComputedTotalMedicationCost = NULL;

    -- Build the feed / medication lines to (re)apply up-front so we can tell a PURE
    -- REVERSAL (nothing to re-apply — the delete path) from a re-apply (insert/edit).
    DECLARE @FeedLines TABLE (Seq INT IDENTITY(1,1), ItemId INT, Qty DECIMAL(14,3));
    IF (@FeedsJson IS NOT NULL AND LEN(@FeedsJson) > 0)
    BEGIN
        INSERT INTO @FeedLines (ItemId, Qty)
        SELECT j.ItemId, j.Qty
        FROM   OPENJSON(@FeedsJson) WITH (ItemId INT '$.itemId', Qty DECIMAL(14,3) '$.qty') j
        WHERE  j.ItemId IS NOT NULL AND ISNULL(j.Qty, 0) > 0;
    END
    ELSE IF (@FeedItemId IS NOT NULL AND ISNULL(@FeedQty,0) > 0)
    BEGIN
        INSERT INTO @FeedLines (ItemId, Qty) VALUES (@FeedItemId, @FeedQty);
    END

    DECLARE @MedLines TABLE (Seq INT IDENTITY(1,1), ItemId INT, Qty DECIMAL(14,3));
    IF (@MedicationsJson IS NOT NULL AND LEN(@MedicationsJson) > 0)
    BEGIN
        INSERT INTO @MedLines (ItemId, Qty)
        SELECT j.ItemId, j.Qty
        FROM   OPENJSON(@MedicationsJson) WITH (ItemId INT '$.itemId', Qty DECIMAL(14,3) '$.qty') j
        WHERE  j.ItemId IS NOT NULL AND ISNULL(j.Qty, 0) > 0;
    END
    ELSE IF (@MedItemId IS NOT NULL AND ISNULL(@MedQty,0) > 0)
    BEGIN
        INSERT INTO @MedLines (ItemId, Qty) VALUES (@MedItemId, @MedQty);
    END

    DECLARE @IsPureReversal BIT =
        CASE WHEN NOT EXISTS (SELECT 1 FROM @FeedLines) AND NOT EXISTS (SELECT 1 FROM @MedLines) THEN 1 ELSE 0 END;

    -- 1. Reverse this record's still-live consumption. Restore the drawn lots +
    --    CurrentQuantity (scoped to non-reversed rows so a later edit never
    --    double-restores). Then:
    --      * PURE REVERSAL (delete path): APPEND-ONLY — mark the usage rows
    --        IsReversed (KEEP them for audit) and post a compensating IN adjustment.
    --      * RE-APPLY (insert/edit): keep the original behaviour — delete the live
    --        usage rows so the re-apply below rewrites current state (no ledger noise
    --        on routine edits; the reversal fix targets true reversals).
    DECLARE @Restore TABLE (ItemId INT, Qty DECIMAL(14,3));
    INSERT INTO @Restore (ItemId, Qty)
    SELECT PoultryRawMaterialItemId, SUM(QuantityUsed)
    FROM   dbo.PoultryRawMaterialUsage
    WHERE  FarmId = @FarmId AND ProductionRecordId = @ProductionId AND IsReversed = 0
    GROUP  BY PoultryRawMaterialItemId;

    ;WITH BatchBack AS (
        SELECT b.PoultryRawMaterialPurchaseId AS PurchaseId, SUM(b.QuantityDrawn) AS Qty
        FROM   dbo.PoultryRawMaterialUsageBatch b
        JOIN   dbo.PoultryRawMaterialUsage u ON u.PoultryRawMaterialUsageId = b.PoultryRawMaterialUsageId
        WHERE  u.FarmId = @FarmId AND u.ProductionRecordId = @ProductionId AND u.IsReversed = 0
        GROUP  BY b.PoultryRawMaterialPurchaseId
    )
    UPDATE p
    SET    p.RemainingQuantity = p.RemainingQuantity + bb.Qty, p.UpdatedAt = SYSUTCDATETIME()
    FROM   dbo.PoultryRawMaterialPurchases p
    JOIN   BatchBack bb ON bb.PurchaseId = p.PoultryRawMaterialPurchaseId;

    UPDATE it
    SET    it.CurrentQuantity = it.CurrentQuantity + r.Qty, it.UpdatedAt = SYSUTCDATETIME()
    FROM   dbo.PoultryRawMaterialItems it
    JOIN   @Restore r ON r.ItemId = it.PoultryRawMaterialItemId
    WHERE  it.FarmId = @FarmId;

    IF (@IsPureReversal = 1)
    BEGIN
        -- KEEP the original usage rows (append-only ledger); flag them reversed so
        -- they drop out of the next restore aggregate.
        UPDATE dbo.PoultryRawMaterialUsage
        SET    IsReversed = 1, ReversedAt = SYSUTCDATETIME()
        WHERE  FarmId = @FarmId AND ProductionRecordId = @ProductionId AND IsReversed = 0;

        -- Compensating IN adjustment per item — the visible opposite entry, and it
        -- keeps recalc (purchases - usage + adjustments) consistent with the restore.
        INSERT INTO dbo.PoultryRawMaterialAdjustments (FarmId, PoultryRawMaterialItemId, AdjustedDate, Quantity, MovementType, Note, CreatedBy)
        SELECT @FarmId, r.ItemId, SYSUTCDATETIME(), r.Qty, 'ProductionReversal',
               CONCAT(N'Reversal of production consumption (record #', CAST(@ProductionId AS NVARCHAR(20)), N')'), @CreatedBy
        FROM   @Restore r WHERE r.Qty <> 0;
    END
    ELSE
    BEGIN
        -- Re-apply (insert/edit): physically remove the current live usage rows;
        -- the loops below rewrite them. Reversed rows (if any) are left untouched.
        DELETE FROM dbo.PoultryRawMaterialUsage
        WHERE  FarmId = @FarmId AND ProductionRecordId = @ProductionId AND IsReversed = 0;
    END

    -- Costing detail is current-state (not a stock ledger) — keep replacing it.
    DELETE FROM dbo.ProductionRecordFeeds
    WHERE  FarmId = @FarmId AND ProductionRecordId = @ProductionId;

    DELETE FROM dbo.ProductionRecordMedications
    WHERE  FarmId = @FarmId AND ProductionRecordId = @ProductionId;

    -- 2. Apply feed consumption from the lines built above.
    DECLARE @FeedTotalCost DECIMAL(14,2) = 0, @FeedTotalQty DECIMAL(14,3) = 0, @AppliedAnyFeed BIT = 0;
    DECLARE @fi INT = 1, @fn INT = (SELECT ISNULL(MAX(Seq), 0) FROM @FeedLines);
    DECLARE @fLineItemId INT, @fLineQty DECIMAL(14,3), @FeedUsageId INT,
            @fLineUnitCost DECIMAL(14,4), @fLineTotal DECIMAL(14,2), @fLineName NVARCHAR(150);

    WHILE @fi <= @fn
    BEGIN
        SELECT @fLineItemId = ItemId, @fLineQty = Qty FROM @FeedLines WHERE Seq = @fi;

        IF (@fLineItemId IS NOT NULL AND @fLineQty > 0)
        BEGIN
            SET @fLineUnitCost = NULL;
            INSERT INTO dbo.PoultryRawMaterialUsage (FarmId, PoultryRawMaterialItemId, ProductionRecordId, QuantityUsed, Notes, CreatedBy)
            VALUES (@FarmId, @fLineItemId, @ProductionId, @fLineQty, N'Feed used in production', @CreatedBy);
            SET @FeedUsageId = CAST(SCOPE_IDENTITY() AS INT);

            EXEC dbo.spPoultryRawMaterialItem_ConsumeBatches @FarmId, @fLineItemId, @FeedUsageId, @fLineQty, @fLineUnitCost OUTPUT;

            UPDATE dbo.PoultryRawMaterialItems
            SET    CurrentQuantity = CurrentQuantity - @fLineQty, UpdatedAt = SYSUTCDATETIME()
            WHERE  PoultryRawMaterialItemId = @fLineItemId AND FarmId = @FarmId;

            SET @fLineName = (SELECT ItemName FROM dbo.PoultryRawMaterialItems WHERE PoultryRawMaterialItemId = @fLineItemId AND FarmId = @FarmId);
            SET @fLineTotal = CAST(ISNULL(@fLineUnitCost, 0) * @fLineQty AS DECIMAL(14,2));

            INSERT INTO dbo.ProductionRecordFeeds (FarmId, ProductionRecordId, PoultryRawMaterialItemId, ItemName, QuantityConsumed, UnitCost, TotalCost)
            VALUES (@FarmId, @ProductionId, @fLineItemId, @fLineName, @fLineQty, ISNULL(@fLineUnitCost, 0), @fLineTotal);

            SET @FeedTotalCost += @fLineTotal;
            SET @FeedTotalQty  += @fLineQty;
            SET @AppliedAnyFeed = 1;
        END
        SET @fi += 1;
    END

    IF (@AppliedAnyFeed = 1)
    BEGIN
        SET @ComputedFeedUnitCost = CASE WHEN @FeedTotalQty > 0 THEN @FeedTotalCost / @FeedTotalQty ELSE NULL END;
        SET @ComputedTotalFeedCost = @FeedTotalCost;
    END

    -- 3. Apply medication consumption from the lines built above.
    DECLARE @MedTotalCost DECIMAL(14,2) = 0, @MedTotalQty DECIMAL(14,3) = 0, @AppliedAnyMed BIT = 0;
    DECLARE @i INT = 1, @n INT = (SELECT ISNULL(MAX(Seq), 0) FROM @MedLines);
    DECLARE @lineItemId INT, @lineQty DECIMAL(14,3), @MedUsageId INT,
            @lineUnitCost DECIMAL(14,4), @lineTotal DECIMAL(14,2), @lineName NVARCHAR(150);

    WHILE @i <= @n
    BEGIN
        SELECT @lineItemId = ItemId, @lineQty = Qty FROM @MedLines WHERE Seq = @i;

        IF (@lineItemId IS NOT NULL AND @lineQty > 0)
        BEGIN
            SET @lineUnitCost = NULL;
            INSERT INTO dbo.PoultryRawMaterialUsage (FarmId, PoultryRawMaterialItemId, ProductionRecordId, QuantityUsed, Notes, CreatedBy)
            VALUES (@FarmId, @lineItemId, @ProductionId, @lineQty, N'Medication used in production', @CreatedBy);
            SET @MedUsageId = CAST(SCOPE_IDENTITY() AS INT);

            EXEC dbo.spPoultryRawMaterialItem_ConsumeBatches @FarmId, @lineItemId, @MedUsageId, @lineQty, @lineUnitCost OUTPUT;

            UPDATE dbo.PoultryRawMaterialItems
            SET    CurrentQuantity = CurrentQuantity - @lineQty, UpdatedAt = SYSUTCDATETIME()
            WHERE  PoultryRawMaterialItemId = @lineItemId AND FarmId = @FarmId;

            SET @lineName = (SELECT ItemName FROM dbo.PoultryRawMaterialItems WHERE PoultryRawMaterialItemId = @lineItemId AND FarmId = @FarmId);
            SET @lineTotal = CAST(ISNULL(@lineUnitCost, 0) * @lineQty AS DECIMAL(14,2));

            INSERT INTO dbo.ProductionRecordMedications (FarmId, ProductionRecordId, PoultryRawMaterialItemId, ItemName, QuantityConsumed, UnitCost, TotalCost)
            VALUES (@FarmId, @ProductionId, @lineItemId, @lineName, @lineQty, ISNULL(@lineUnitCost, 0), @lineTotal);

            SET @MedTotalCost += @lineTotal;
            SET @MedTotalQty  += @lineQty;
            SET @AppliedAnyMed = 1;
        END
        SET @i += 1;
    END

    IF (@AppliedAnyMed = 1)
    BEGIN
        SET @ComputedMedicationUnitCost = CASE WHEN @MedTotalQty > 0 THEN @MedTotalCost / @MedTotalQty ELSE NULL END;
        SET @ComputedTotalMedicationCost = @MedTotalCost;
    END
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spPoultryBirdStock_Sync                TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryEggStock_SyncForProduction   TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryProductionRawMaterialSync     TO [Techretainer];
    PRINT '179: granted EXECUTE on append-only production stock syncs to Techretainer.';
END
GO

PRINT '179_AppendOnlyProductionStockReversal.sql complete.';
GO
