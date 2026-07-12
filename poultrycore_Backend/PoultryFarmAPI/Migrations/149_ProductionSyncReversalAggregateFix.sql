-- =============================================================================
-- Migration 149: fix production raw-material reversal (multi-line drift bug)
-- =============================================================================
-- BUG: spPoultryProductionRawMaterialSync reverses a record's prior consumption
-- with `UPDATE p ... FROM p JOIN usage/batch ...`. In SQL Server, when several
-- joined rows match one target row, the SET applies only ONE arbitrary matched
-- value (it does NOT sum them). Before the multi-line feature (147/148) a record
-- had at most one usage row per item and one draw per purchase, so this never
-- collided. Now a record can:
--   * consume the SAME item on two lines  -> two PoultryRawMaterialUsage rows for
--     that item  -> the item-level CurrentQuantity restore adds back only ONE
--     line's quantity;
--   * draw the SAME purchase lot from two lines -> two PoultryRawMaterialUsageBatch
--     rows for that purchase -> the lot-level RemainingQuantity restore adds back
--     only ONE draw.
-- The re-apply step (loop) still subtracts EVERY line, so each edit leaves stock
-- lower than it should be. Over repeated edits the item's on-hand and its purchase
-- lots drift apart — exactly the "25000 in stock but only 550 available across
-- recorded purchases" symptom.
--
-- FIX: aggregate (GROUP BY / SUM) the amounts to restore BEFORE the UPDATE, so a
-- single target row is credited the full total once. Only the two reversal
-- statements change; the rest of the proc is identical to migration 148.
--
-- This does NOT retro-correct already-drifted items — that is a separate one-time
-- data reconciliation (handled separately once the true on-hand is confirmed).
--
-- Idempotent (CREATE OR ALTER). Grants EXECUTE to the app login.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

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

    -- 1. Reverse every prior production-linked usage row. AGGREGATE first so a
    --    purchase drawn by several lines, or an item used on several lines, is
    --    credited its FULL total exactly once (see migration header).
    ;WITH BatchBack AS (
        SELECT b.PoultryRawMaterialPurchaseId AS PurchaseId, SUM(b.QuantityDrawn) AS Qty
        FROM   dbo.PoultryRawMaterialUsageBatch b
        JOIN   dbo.PoultryRawMaterialUsage u ON u.PoultryRawMaterialUsageId = b.PoultryRawMaterialUsageId
        WHERE  u.FarmId = @FarmId AND u.ProductionRecordId = @ProductionId
        GROUP  BY b.PoultryRawMaterialPurchaseId
    )
    UPDATE p
    SET    p.RemainingQuantity = p.RemainingQuantity + bb.Qty, p.UpdatedAt = SYSUTCDATETIME()
    FROM   dbo.PoultryRawMaterialPurchases p
    JOIN   BatchBack bb ON bb.PurchaseId = p.PoultryRawMaterialPurchaseId;

    ;WITH ItemBack AS (
        SELECT PoultryRawMaterialItemId AS ItemId, SUM(QuantityUsed) AS Qty
        FROM   dbo.PoultryRawMaterialUsage
        WHERE  FarmId = @FarmId AND ProductionRecordId = @ProductionId
        GROUP  BY PoultryRawMaterialItemId
    )
    UPDATE it
    SET    it.CurrentQuantity = it.CurrentQuantity + ib.Qty, it.UpdatedAt = SYSUTCDATETIME()
    FROM   dbo.PoultryRawMaterialItems it
    JOIN   ItemBack ib ON ib.ItemId = it.PoultryRawMaterialItemId;

    DELETE FROM dbo.PoultryRawMaterialUsage
    WHERE  FarmId = @FarmId AND ProductionRecordId = @ProductionId;

    DELETE FROM dbo.ProductionRecordFeeds
    WHERE  FarmId = @FarmId AND ProductionRecordId = @ProductionId;

    DELETE FROM dbo.ProductionRecordMedications
    WHERE  FarmId = @FarmId AND ProductionRecordId = @ProductionId;

    -- 2. Apply feed consumption — one line per JSON entry, else the legacy single
    --    @FeedItemId/@FeedQty pair.
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

    -- 3. Apply medication consumption — one line per JSON entry, else the legacy
    --    single @MedItemId/@MedQty pair.
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
    GRANT EXECUTE ON dbo.spPoultryProductionRawMaterialSync TO [Techretainer];
GO

PRINT '149_ProductionSyncReversalAggregateFix.sql complete.';
GO
