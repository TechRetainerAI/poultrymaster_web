-- =============================================================================
-- Migration 147: Production records support MULTIPLE medication lines
-- =============================================================================
-- Previously a production record carried a single medication (one
-- SpecificMedicationUsedId / TotalMedicationConsumed / cost on ProductionRecords).
-- The user wants the water-sales "Add line" experience on the poultry production
-- form: N medication lines, each drawn from the raw-material inventory with its
-- own FIFO/LIFO/HIFO batch cost.
--
-- Design:
--   * New child table dbo.ProductionRecordMedications holds one snapshot row per
--     line (item, quantity consumed, server-computed unit cost, total cost).
--   * spPoultryProductionRawMaterialSync now accepts @MedicationsJson
--     ([{ "itemId": <int>, "qty": <decimal> }, ...]) and applies EACH line
--     through the existing batch-walk (spPoultryRawMaterialItem_ConsumeBatches),
--     writing a snapshot row per line. When @MedicationsJson is NULL it falls
--     back to the legacy single @MedItemId/@MedQty pair, so older callers and the
--     reverse-only Delete path keep working unchanged.
--   * The aggregate medication columns on ProductionRecords are still populated
--     (sum of quantities, weighted-average unit cost, sum of cost, first line's
--     item id/name) so existing reports/closing that read TotalMedicationCost
--     keep working — the new UI reads the ProductionRecordMedications lines.
--
-- Idempotent (object/column guards + CREATE OR ALTER). Grants EXECUTE to the app.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- 1. Child table: one row per medication line on a production record.
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.ProductionRecordMedications', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.ProductionRecordMedications (
        ProductionRecordMedicationId INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                       NVARCHAR(450) NOT NULL,
        ProductionRecordId           INT           NOT NULL,
        PoultryRawMaterialItemId     INT           NOT NULL,
        ItemName                     NVARCHAR(150) NULL,
        QuantityConsumed             DECIMAL(14,3) NOT NULL,
        UnitCost                     DECIMAL(14,4) NOT NULL CONSTRAINT DF_ProdRecMed_UnitCost DEFAULT (0),
        TotalCost                    DECIMAL(14,2) NOT NULL CONSTRAINT DF_ProdRecMed_TotalCost DEFAULT (0),
        CreatedAt                    DATETIME2     NOT NULL CONSTRAINT DF_ProdRecMed_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FK_ProdRecMed_ProductionRecord FOREIGN KEY (ProductionRecordId)
            REFERENCES dbo.ProductionRecords (Id) ON DELETE CASCADE
    );
    CREATE INDEX IX_ProdRecMed_Record ON dbo.ProductionRecordMedications (FarmId, ProductionRecordId);
END
GO

-- -----------------------------------------------------------------------------
-- 2. Batch-aware production sync — now medication-multi-line via @MedicationsJson.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spPoultryProductionRawMaterialSync
    @FarmId NVARCHAR(450), @ProductionId INT,
    @FeedItemId INT = NULL, @FeedQty DECIMAL(14,3) = NULL,
    @MedItemId  INT = NULL, @MedQty  DECIMAL(14,3) = NULL,
    @CreatedBy NVARCHAR(450) = NULL,
    @ComputedFeedUnitCost DECIMAL(14,4) = NULL OUTPUT,
    @ComputedTotalFeedCost DECIMAL(14,2) = NULL OUTPUT,
    @ComputedMedicationUnitCost DECIMAL(14,4) = NULL OUTPUT,
    @ComputedTotalMedicationCost DECIMAL(14,2) = NULL OUTPUT,
    @MedicationsJson NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @ComputedFeedUnitCost = NULL; SET @ComputedTotalFeedCost = NULL;
    SET @ComputedMedicationUnitCost = NULL; SET @ComputedTotalMedicationCost = NULL;

    -- 1. Reverse every prior production-linked usage row: restore the exact
    --    batch(es) it drew from, restore the item aggregate, then delete the
    --    usage rows (cascades to remove their batch-draw children). Also clear
    --    the medication snapshot lines so they can be re-derived.
    UPDATE p
    SET    p.RemainingQuantity = p.RemainingQuantity + b.QuantityDrawn, p.UpdatedAt = SYSUTCDATETIME()
    FROM   dbo.PoultryRawMaterialPurchases p
    JOIN   dbo.PoultryRawMaterialUsageBatch b ON b.PoultryRawMaterialPurchaseId = p.PoultryRawMaterialPurchaseId
    JOIN   dbo.PoultryRawMaterialUsage u ON u.PoultryRawMaterialUsageId = b.PoultryRawMaterialUsageId
    WHERE  u.FarmId = @FarmId AND u.ProductionRecordId = @ProductionId;

    UPDATE it
    SET    it.CurrentQuantity = it.CurrentQuantity + u.QuantityUsed, it.UpdatedAt = SYSUTCDATETIME()
    FROM   dbo.PoultryRawMaterialItems it
    JOIN   dbo.PoultryRawMaterialUsage u
      ON   u.PoultryRawMaterialItemId = it.PoultryRawMaterialItemId
    WHERE  u.FarmId = @FarmId AND u.ProductionRecordId = @ProductionId;

    DELETE FROM dbo.PoultryRawMaterialUsage
    WHERE  FarmId = @FarmId AND ProductionRecordId = @ProductionId;

    DELETE FROM dbo.ProductionRecordMedications
    WHERE  FarmId = @FarmId AND ProductionRecordId = @ProductionId;

    -- 2. Apply feed consumption (batch-walk per the item's FIFO/LIFO/HIFO policy).
    IF (@FeedItemId IS NOT NULL AND ISNULL(@FeedQty,0) > 0)
    BEGIN
        DECLARE @FeedUsageId INT;
        INSERT INTO dbo.PoultryRawMaterialUsage (FarmId, PoultryRawMaterialItemId, ProductionRecordId, QuantityUsed, Notes, CreatedBy)
        VALUES (@FarmId, @FeedItemId, @ProductionId, @FeedQty, N'Feed used in production', @CreatedBy);
        SET @FeedUsageId = CAST(SCOPE_IDENTITY() AS INT);

        EXEC dbo.spPoultryRawMaterialItem_ConsumeBatches @FarmId, @FeedItemId, @FeedUsageId, @FeedQty, @ComputedFeedUnitCost OUTPUT;

        UPDATE dbo.PoultryRawMaterialItems
        SET    CurrentQuantity = CurrentQuantity - @FeedQty, UpdatedAt = SYSUTCDATETIME()
        WHERE  PoultryRawMaterialItemId = @FeedItemId AND FarmId = @FarmId;

        SET @ComputedTotalFeedCost = CAST(ISNULL(@ComputedFeedUnitCost, 0) * @FeedQty AS DECIMAL(14,2));
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

-- -----------------------------------------------------------------------------
-- 3. Insert — accept @MedicationsJson, derive aggregate medication columns.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[spProductionRecord_Insert]
    @FarmId NVARCHAR(100), @CreatedBy NVARCHAR(100), @UserId NVARCHAR(100), @AgeInWeeks INT, @AgeInDays INT,
    @Date DATE, @NoOfBirds INT, @Mortality INT, @NoOfBirdsLeft INT, @FeedKg DECIMAL(18,2), @Medication NVARCHAR(500) = NULL,
    @Production9AM INT, @Production12PM INT, @Production4PM INT, @TotalProduction INT, @FlockId INT = NULL,
    @BrokenEggs INT = NULL, @Notes NVARCHAR(MAX) = NULL, @EggCount INT = NULL, @EggGrade NVARCHAR(50) = NULL,
    @MeatyEggs INT = NULL, @SoftEggs INT = NULL, @LostEggs INT = NULL,
    @SpecificFeedUsedId INT = NULL, @SpecificFeedUsedName NVARCHAR(150) = NULL, @FeedUnitCost DECIMAL(14,4) = NULL,
    @TotalFeedConsumed DECIMAL(14,3) = NULL, @TotalFeedCost DECIMAL(14,2) = NULL,
    @SpecificMedicationUsedId INT = NULL, @SpecificMedicationUsedName NVARCHAR(150) = NULL, @MedicationUnitCost DECIMAL(14,4) = NULL,
    @TotalMedicationConsumed DECIMAL(14,3) = NULL, @TotalMedicationCost DECIMAL(14,2) = NULL,
    @TotalCostOfProduction DECIMAL(14,2) = NULL,
    @MedicationsJson NVARCHAR(MAX) = NULL,
    @NewId INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @EggCount = ISNULL(@EggCount, @TotalProduction);

    -- Derive the aggregate medication columns from the multi-line JSON when given.
    DECLARE @MedAgg TABLE (Seq INT IDENTITY(1,1), ItemId INT, Qty DECIMAL(14,3));
    IF (@MedicationsJson IS NOT NULL AND LEN(@MedicationsJson) > 0)
        INSERT INTO @MedAgg (ItemId, Qty)
        SELECT ItemId, Qty FROM OPENJSON(@MedicationsJson) WITH (ItemId INT '$.itemId', Qty DECIMAL(14,3) '$.qty')
        WHERE ItemId IS NOT NULL AND ISNULL(Qty, 0) > 0;

    IF (@MedicationsJson IS NOT NULL)
    BEGIN
        IF EXISTS (SELECT 1 FROM @MedAgg)
        BEGIN
            SET @TotalMedicationConsumed = (SELECT SUM(Qty) FROM @MedAgg);
            SELECT TOP 1 @SpecificMedicationUsedId = ItemId FROM @MedAgg ORDER BY Seq;
            SET @SpecificMedicationUsedName = (SELECT ItemName FROM dbo.PoultryRawMaterialItems WHERE PoultryRawMaterialItemId = @SpecificMedicationUsedId AND FarmId = @FarmId);
        END
        ELSE
        BEGIN
            SET @SpecificMedicationUsedId = NULL; SET @SpecificMedicationUsedName = NULL; SET @TotalMedicationConsumed = NULL;
        END
    END

    IF (@TotalCostOfProduction IS NULL)
        SET @TotalCostOfProduction = ISNULL(@TotalFeedCost,0) + ISNULL(@TotalMedicationCost,0);
    BEGIN TRANSACTION;
    INSERT INTO [dbo].[ProductionRecords] (FarmId, CreatedBy, UserId, AgeInWeeks, AgeInDays, [Date], NoOfBirds, Mortality, NoOfBirdsLeft, FeedKg, Medication, Production9AM, Production12PM, Production4PM, TotalProduction, FlockId, BrokenEggs, Notes, EggCount, EggGrade, MeatyEggs, SoftEggs, LostEggs,
        SpecificFeedUsedId, SpecificFeedUsedName, FeedUnitCost, TotalFeedConsumed, TotalFeedCost,
        SpecificMedicationUsedId, SpecificMedicationUsedName, MedicationUnitCost, TotalMedicationConsumed, TotalMedicationCost,
        TotalCostOfProduction, CreatedAt)
    VALUES (@FarmId, @CreatedBy, @UserId, @AgeInWeeks, @AgeInDays, @Date, @NoOfBirds, @Mortality, @NoOfBirdsLeft, @FeedKg, @Medication, @Production9AM, @Production12PM, @Production4PM, @TotalProduction, @FlockId, @BrokenEggs, @Notes, @EggCount, @EggGrade, @MeatyEggs, @SoftEggs, @LostEggs,
        @SpecificFeedUsedId, @SpecificFeedUsedName, @FeedUnitCost, @TotalFeedConsumed, @TotalFeedCost,
        @SpecificMedicationUsedId, @SpecificMedicationUsedName, @MedicationUnitCost, @TotalMedicationConsumed, @TotalMedicationCost,
        @TotalCostOfProduction, GETUTCDATE());
    SET @NewId = SCOPE_IDENTITY();

    -- Bird mortality -> -birds
    DECLARE @mq DECIMAL(14,3) = -CAST(ISNULL(@Mortality,0) AS DECIMAL(14,3));
    IF (@mq <> 0)
        EXEC dbo.spPoultryBirdStock_Sync @FarmId, N'Mortality', @mq, @NewId, N'Production mortality', @UserId;

    -- Good eggs -> +egg finished-product stock + stock movement
    DECLARE @good INT = ISNULL(@TotalProduction,0) - ISNULL(@BrokenEggs,0) - ISNULL(@LostEggs,0);
    IF (@good < 0) SET @good = 0;
    EXEC dbo.spPoultryEggStock_SyncForProduction @FarmId, @NewId, @good, NULL, @UserId;

    -- Feed + medication -> -raw-material inventory, drawn per each item's FIFO/LIFO/HIFO policy.
    DECLARE @OutFeedUnitCost DECIMAL(14,4), @OutTotalFeedCost DECIMAL(14,2),
            @OutMedUnitCost DECIMAL(14,4), @OutTotalMedCost DECIMAL(14,2);
    EXEC dbo.spPoultryProductionRawMaterialSync
         @FarmId, @NewId, @SpecificFeedUsedId, @TotalFeedConsumed, @SpecificMedicationUsedId, @TotalMedicationConsumed, @UserId,
         @ComputedFeedUnitCost = @OutFeedUnitCost OUTPUT,
         @ComputedTotalFeedCost = @OutTotalFeedCost OUTPUT,
         @ComputedMedicationUnitCost = @OutMedUnitCost OUTPUT,
         @ComputedTotalMedicationCost = @OutTotalMedCost OUTPUT,
         @MedicationsJson = @MedicationsJson;

    UPDATE [dbo].[ProductionRecords]
    SET    FeedUnitCost = @OutFeedUnitCost,
           TotalFeedCost = @OutTotalFeedCost,
           MedicationUnitCost = @OutMedUnitCost,
           TotalMedicationCost = @OutTotalMedCost,
           TotalCostOfProduction = ISNULL(@OutTotalFeedCost,0) + ISNULL(@OutTotalMedCost,0)
    WHERE  Id = @NewId;

    COMMIT TRANSACTION;
END
GO

-- -----------------------------------------------------------------------------
-- 4. Update — same pattern, re-synced idempotently.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[spProductionRecord_Update]
    @RecordId INT, @UpdatedBy NVARCHAR(100), @AgeInWeeks INT, @AgeInDays INT, @Date DATE, @NoOfBirds INT, @Mortality INT,
    @NoOfBirdsLeft INT, @FeedKg DECIMAL(18,2), @Medication NVARCHAR(500) = NULL, @Production9AM INT, @Production12PM INT,
    @Production4PM INT, @TotalProduction INT, @FlockId INT = NULL, @BrokenEggs INT = NULL, @Notes NVARCHAR(MAX) = NULL,
    @EggCount INT = NULL, @EggGrade NVARCHAR(50) = NULL, @MeatyEggs INT = NULL, @SoftEggs INT = NULL, @LostEggs INT = NULL,
    @SpecificFeedUsedId INT = NULL, @SpecificFeedUsedName NVARCHAR(150) = NULL, @FeedUnitCost DECIMAL(14,4) = NULL,
    @TotalFeedConsumed DECIMAL(14,3) = NULL, @TotalFeedCost DECIMAL(14,2) = NULL,
    @SpecificMedicationUsedId INT = NULL, @SpecificMedicationUsedName NVARCHAR(150) = NULL, @MedicationUnitCost DECIMAL(14,4) = NULL,
    @TotalMedicationConsumed DECIMAL(14,3) = NULL, @TotalMedicationCost DECIMAL(14,2) = NULL,
    @TotalCostOfProduction DECIMAL(14,2) = NULL,
    @MedicationsJson NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @EggCount = ISNULL(@EggCount, @TotalProduction);

    DECLARE @FarmId NVARCHAR(100);
    SELECT @FarmId = FarmId FROM dbo.ProductionRecords WHERE Id = @RecordId;

    -- Derive the aggregate medication columns from the multi-line JSON when given.
    DECLARE @MedAgg TABLE (Seq INT IDENTITY(1,1), ItemId INT, Qty DECIMAL(14,3));
    IF (@MedicationsJson IS NOT NULL AND LEN(@MedicationsJson) > 0)
        INSERT INTO @MedAgg (ItemId, Qty)
        SELECT ItemId, Qty FROM OPENJSON(@MedicationsJson) WITH (ItemId INT '$.itemId', Qty DECIMAL(14,3) '$.qty')
        WHERE ItemId IS NOT NULL AND ISNULL(Qty, 0) > 0;

    IF (@MedicationsJson IS NOT NULL)
    BEGIN
        IF EXISTS (SELECT 1 FROM @MedAgg)
        BEGIN
            SET @TotalMedicationConsumed = (SELECT SUM(Qty) FROM @MedAgg);
            SELECT TOP 1 @SpecificMedicationUsedId = ItemId FROM @MedAgg ORDER BY Seq;
            SET @SpecificMedicationUsedName = (SELECT ItemName FROM dbo.PoultryRawMaterialItems WHERE PoultryRawMaterialItemId = @SpecificMedicationUsedId AND FarmId = @FarmId);
        END
        ELSE
        BEGIN
            SET @SpecificMedicationUsedId = NULL; SET @SpecificMedicationUsedName = NULL; SET @TotalMedicationConsumed = NULL;
        END
    END

    IF (@TotalCostOfProduction IS NULL)
        SET @TotalCostOfProduction = ISNULL(@TotalFeedCost,0) + ISNULL(@TotalMedicationCost,0);
    BEGIN TRANSACTION;
    UPDATE [dbo].[ProductionRecords]
    SET UpdatedBy=@UpdatedBy, AgeInWeeks=@AgeInWeeks, AgeInDays=@AgeInDays, [Date]=@Date, NoOfBirds=@NoOfBirds, Mortality=@Mortality,
        NoOfBirdsLeft=@NoOfBirdsLeft, FeedKg=@FeedKg, Medication=@Medication, Production9AM=@Production9AM, Production12PM=@Production12PM,
        Production4PM=@Production4PM, TotalProduction=@TotalProduction, FlockId=@FlockId, BrokenEggs=@BrokenEggs, Notes=@Notes,
        EggCount=@EggCount, EggGrade=@EggGrade, MeatyEggs=@MeatyEggs, SoftEggs=@SoftEggs, LostEggs=@LostEggs,
        SpecificFeedUsedId=@SpecificFeedUsedId, SpecificFeedUsedName=@SpecificFeedUsedName, FeedUnitCost=@FeedUnitCost,
        TotalFeedConsumed=@TotalFeedConsumed, TotalFeedCost=@TotalFeedCost,
        SpecificMedicationUsedId=@SpecificMedicationUsedId, SpecificMedicationUsedName=@SpecificMedicationUsedName, MedicationUnitCost=@MedicationUnitCost,
        TotalMedicationConsumed=@TotalMedicationConsumed, TotalMedicationCost=@TotalMedicationCost,
        TotalCostOfProduction=@TotalCostOfProduction, UpdatedAt=GETUTCDATE()
    WHERE Id = @RecordId;

    IF (@FarmId IS NOT NULL)
    BEGIN
        DECLARE @mq2 DECIMAL(14,3) = -CAST(ISNULL(@Mortality,0) AS DECIMAL(14,3));
        EXEC dbo.spPoultryBirdStock_Sync @FarmId, N'Mortality', @mq2, @RecordId, N'Production mortality', @UpdatedBy;

        DECLARE @good2 INT = ISNULL(@TotalProduction,0) - ISNULL(@BrokenEggs,0) - ISNULL(@LostEggs,0);
        IF (@good2 < 0) SET @good2 = 0;
        EXEC dbo.spPoultryEggStock_SyncForProduction @FarmId, @RecordId, @good2, NULL, @UpdatedBy;

        DECLARE @OutFeedUnitCost2 DECIMAL(14,4), @OutTotalFeedCost2 DECIMAL(14,2),
                @OutMedUnitCost2 DECIMAL(14,4), @OutTotalMedCost2 DECIMAL(14,2);
        EXEC dbo.spPoultryProductionRawMaterialSync
             @FarmId, @RecordId, @SpecificFeedUsedId, @TotalFeedConsumed, @SpecificMedicationUsedId, @TotalMedicationConsumed, @UpdatedBy,
             @ComputedFeedUnitCost = @OutFeedUnitCost2 OUTPUT,
             @ComputedTotalFeedCost = @OutTotalFeedCost2 OUTPUT,
             @ComputedMedicationUnitCost = @OutMedUnitCost2 OUTPUT,
             @ComputedTotalMedicationCost = @OutTotalMedCost2 OUTPUT,
             @MedicationsJson = @MedicationsJson;

        UPDATE [dbo].[ProductionRecords]
        SET    FeedUnitCost = @OutFeedUnitCost2,
               TotalFeedCost = @OutTotalFeedCost2,
               MedicationUnitCost = @OutMedUnitCost2,
               TotalMedicationCost = @OutTotalMedCost2,
               TotalCostOfProduction = ISNULL(@OutTotalFeedCost2,0) + ISNULL(@OutTotalMedCost2,0)
        WHERE  Id = @RecordId;
    END
    COMMIT TRANSACTION;
END
GO

-- -----------------------------------------------------------------------------
-- 5. Get procs — return the medication lines as a JSON array column.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[spProductionRecord_GetById]
    @RecordId INT,
    @UserId NVARCHAR(100),
    @FarmId NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        Id, FarmId, UserId, CreatedBy, UpdatedBy,
        AgeInWeeks, AgeInDays, [Date],
        NoOfBirds, Mortality, NoOfBirdsLeft, FeedKg, Medication,
        Production9AM, Production12PM, Production4PM, TotalProduction,
        FlockId, BrokenEggs, Notes, ISNULL(EggCount, TotalProduction) AS EggCount,
        EggGrade,
        MeatyEggs, SoftEggs, LostEggs,
        SpecificFeedUsedId, SpecificFeedUsedName, FeedUnitCost, TotalFeedConsumed, TotalFeedCost,
        SpecificMedicationUsedId, SpecificMedicationUsedName, MedicationUnitCost, TotalMedicationConsumed, TotalMedicationCost,
        TotalCostOfProduction,
        (SELECT m.PoultryRawMaterialItemId AS specificMedicationUsedId,
                m.ItemName                 AS specificMedicationUsedName,
                m.QuantityConsumed         AS totalMedicationConsumed,
                m.UnitCost                 AS medicationUnitCost,
                m.TotalCost                AS totalMedicationCost
         FROM dbo.ProductionRecordMedications m
         WHERE m.ProductionRecordId = pr.Id
         ORDER BY m.ProductionRecordMedicationId
         FOR JSON PATH) AS MedicationsJson,
        CreatedAt, UpdatedAt
    FROM [dbo].[ProductionRecords] pr
    WHERE Id = @RecordId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spProductionRecord_GetAll]
    @UserId NVARCHAR(100),
    @FarmId NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        Id, FarmId, UserId, CreatedBy, UpdatedBy,
        AgeInWeeks, AgeInDays, [Date],
        NoOfBirds, Mortality, NoOfBirdsLeft, FeedKg, Medication,
        Production9AM, Production12PM, Production4PM, TotalProduction,
        FlockId, BrokenEggs, Notes, ISNULL(EggCount, TotalProduction) AS EggCount,
        EggGrade,
        MeatyEggs, SoftEggs, LostEggs,
        SpecificFeedUsedId, SpecificFeedUsedName, FeedUnitCost, TotalFeedConsumed, TotalFeedCost,
        SpecificMedicationUsedId, SpecificMedicationUsedName, MedicationUnitCost, TotalMedicationConsumed, TotalMedicationCost,
        TotalCostOfProduction,
        (SELECT m.PoultryRawMaterialItemId AS specificMedicationUsedId,
                m.ItemName                 AS specificMedicationUsedName,
                m.QuantityConsumed         AS totalMedicationConsumed,
                m.UnitCost                 AS medicationUnitCost,
                m.TotalCost                AS totalMedicationCost
         FROM dbo.ProductionRecordMedications m
         WHERE m.ProductionRecordId = pr.Id
         ORDER BY m.ProductionRecordMedicationId
         FOR JSON PATH) AS MedicationsJson,
        CreatedAt, UpdatedAt
    FROM [dbo].[ProductionRecords] pr
    WHERE FarmId = @FarmId
    ORDER BY [Date] DESC, CreatedAt DESC;
END
GO

-- =============================================================================
-- Grants to the application login (matches ConnectionStrings__PoultryConn user)
-- =============================================================================
IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spPoultryProductionRawMaterialSync TO [Techretainer];
    GRANT EXECUTE ON dbo.spProductionRecord_Insert          TO [Techretainer];
    GRANT EXECUTE ON dbo.spProductionRecord_Update          TO [Techretainer];
    GRANT EXECUTE ON dbo.spProductionRecord_GetById         TO [Techretainer];
    GRANT EXECUTE ON dbo.spProductionRecord_GetAll          TO [Techretainer];
    GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.ProductionRecordMedications TO [Techretainer];
    PRINT '147: granted EXECUTE/table rights on multi-medication objects to Techretainer.';
END
GO

PRINT '147_ProductionRecordMultiMedication.sql complete.';
GO
