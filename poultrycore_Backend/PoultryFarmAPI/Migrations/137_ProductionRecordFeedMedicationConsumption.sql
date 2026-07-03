-- =============================================================================
-- Migration 137: Production Records consume Feed + Medication inventory + costing
-- =============================================================================
-- Doc 1 sections 4a-4c. A production entry now records the specific feed and
-- medication used (from the raw-materials inventory), stores the unit-cost-based
-- costing on the record, and DECREMENTS the feed/medication raw-material stock
-- (PoultryRawMaterialItems.CurrentQuantity) with a usage ledger row. Combined
-- with migration 136 (eggs +) and 134/136 (birds - by mortality), a single
-- production record now drives ALL its inventory side effects.
--
-- Fully idempotent: the raw-material sync reverses every prior production-linked
-- usage row for the record (restoring CurrentQuantity) before re-applying, so
-- edits re-sync and deletes reverse — even if the selected feed/medication item
-- changes between edits.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- Link raw-material usage rows back to the production record that caused them.
IF COL_LENGTH('dbo.PoultryRawMaterialUsage','ProductionRecordId') IS NULL
    ALTER TABLE dbo.PoultryRawMaterialUsage ADD ProductionRecordId INT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_PoultryRMUsage_ProdRec' AND object_id = OBJECT_ID('dbo.PoultryRawMaterialUsage'))
    CREATE INDEX IX_PoultryRMUsage_ProdRec ON dbo.PoultryRawMaterialUsage (FarmId, ProductionRecordId);
GO

-- Helper: idempotently sync a production record's feed + medication consumption.
-- Reverses all prior production-linked usage (restores stock), then applies the
-- current feed/medication selections. Passing NULL/0 for both just reverses.
CREATE OR ALTER PROCEDURE dbo.spPoultryProductionRawMaterialSync
    @FarmId NVARCHAR(450), @ProductionId INT,
    @FeedItemId INT = NULL, @FeedQty DECIMAL(14,3) = NULL,
    @MedItemId  INT = NULL, @MedQty  DECIMAL(14,3) = NULL,
    @CreatedBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. Reverse every prior production-linked usage row: give the quantity back
    --    to its item, then delete the row.
    UPDATE it
    SET    it.CurrentQuantity = it.CurrentQuantity + u.QuantityUsed, it.UpdatedAt = SYSUTCDATETIME()
    FROM   dbo.PoultryRawMaterialItems it
    JOIN   dbo.PoultryRawMaterialUsage u
      ON   u.PoultryRawMaterialItemId = it.PoultryRawMaterialItemId
    WHERE  u.FarmId = @FarmId AND u.ProductionRecordId = @ProductionId;

    DELETE FROM dbo.PoultryRawMaterialUsage
    WHERE  FarmId = @FarmId AND ProductionRecordId = @ProductionId;

    -- 2. Apply feed consumption.
    IF (@FeedItemId IS NOT NULL AND ISNULL(@FeedQty,0) > 0)
    BEGIN
        INSERT INTO dbo.PoultryRawMaterialUsage (FarmId, PoultryRawMaterialItemId, ProductionRecordId, QuantityUsed, Notes, CreatedBy)
        VALUES (@FarmId, @FeedItemId, @ProductionId, @FeedQty, N'Feed used in production', @CreatedBy);
        UPDATE dbo.PoultryRawMaterialItems
        SET    CurrentQuantity = CurrentQuantity - @FeedQty, UpdatedAt = SYSUTCDATETIME()
        WHERE  PoultryRawMaterialItemId = @FeedItemId AND FarmId = @FarmId;
    END

    -- 3. Apply medication consumption.
    IF (@MedItemId IS NOT NULL AND ISNULL(@MedQty,0) > 0)
    BEGIN
        INSERT INTO dbo.PoultryRawMaterialUsage (FarmId, PoultryRawMaterialItemId, ProductionRecordId, QuantityUsed, Notes, CreatedBy)
        VALUES (@FarmId, @MedItemId, @ProductionId, @MedQty, N'Medication used in production', @CreatedBy);
        UPDATE dbo.PoultryRawMaterialItems
        SET    CurrentQuantity = CurrentQuantity - @MedQty, UpdatedAt = SYSUTCDATETIME()
        WHERE  PoultryRawMaterialItemId = @MedItemId AND FarmId = @FarmId;
    END
END
GO
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'Techretainer')
    GRANT EXECUTE ON dbo.spPoultryProductionRawMaterialSync TO [Techretainer];
GO

-- ---------------------------------------------------------------------------
-- spProductionRecord_Insert — persist costing + drive all side effects.
-- ---------------------------------------------------------------------------
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
    @NewId INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @EggCount = ISNULL(@EggCount, @TotalProduction);
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

    -- Feed + medication -> -raw-material inventory
    EXEC dbo.spPoultryProductionRawMaterialSync @FarmId, @NewId, @SpecificFeedUsedId, @TotalFeedConsumed, @SpecificMedicationUsedId, @TotalMedicationConsumed, @UserId;

    COMMIT TRANSACTION;
END
GO

-- ---------------------------------------------------------------------------
-- spProductionRecord_Update — same side effects, re-synced idempotently.
-- ---------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[spProductionRecord_Update]
    @RecordId INT, @UpdatedBy NVARCHAR(100), @AgeInWeeks INT, @AgeInDays INT, @Date DATE, @NoOfBirds INT, @Mortality INT,
    @NoOfBirdsLeft INT, @FeedKg DECIMAL(18,2), @Medication NVARCHAR(500) = NULL, @Production9AM INT, @Production12PM INT,
    @Production4PM INT, @TotalProduction INT, @FlockId INT = NULL, @BrokenEggs INT = NULL, @Notes NVARCHAR(MAX) = NULL,
    @EggCount INT = NULL, @EggGrade NVARCHAR(50) = NULL, @MeatyEggs INT = NULL, @SoftEggs INT = NULL, @LostEggs INT = NULL,
    @SpecificFeedUsedId INT = NULL, @SpecificFeedUsedName NVARCHAR(150) = NULL, @FeedUnitCost DECIMAL(14,4) = NULL,
    @TotalFeedConsumed DECIMAL(14,3) = NULL, @TotalFeedCost DECIMAL(14,2) = NULL,
    @SpecificMedicationUsedId INT = NULL, @SpecificMedicationUsedName NVARCHAR(150) = NULL, @MedicationUnitCost DECIMAL(14,4) = NULL,
    @TotalMedicationConsumed DECIMAL(14,3) = NULL, @TotalMedicationCost DECIMAL(14,2) = NULL,
    @TotalCostOfProduction DECIMAL(14,2) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @EggCount = ISNULL(@EggCount, @TotalProduction);
    IF (@TotalCostOfProduction IS NULL)
        SET @TotalCostOfProduction = ISNULL(@TotalFeedCost,0) + ISNULL(@TotalMedicationCost,0);
    DECLARE @FarmId NVARCHAR(100);
    SELECT @FarmId = FarmId FROM dbo.ProductionRecords WHERE Id = @RecordId;
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

        EXEC dbo.spPoultryProductionRawMaterialSync @FarmId, @RecordId, @SpecificFeedUsedId, @TotalFeedConsumed, @SpecificMedicationUsedId, @TotalMedicationConsumed, @UpdatedBy;
    END
    COMMIT TRANSACTION;
END
GO

-- ---------------------------------------------------------------------------
-- spProductionRecord_Delete — reverse every side effect.
-- ---------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[spProductionRecord_Delete]
    @RecordId INT, @UserId NVARCHAR(100), @FarmId NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRANSACTION;
    EXEC dbo.spPoultryBirdStock_Sync @FarmId, N'Mortality', 0, @RecordId, NULL, @UserId;
    EXEC dbo.spPoultryEggStock_SyncForProduction @FarmId, @RecordId, 0, NULL, @UserId;
    EXEC dbo.spPoultryProductionRawMaterialSync @FarmId, @RecordId, NULL, NULL, NULL, NULL, @UserId;
    DELETE FROM [dbo].[ProductionRecords] WHERE Id = @RecordId AND FarmId = @FarmId;
    COMMIT TRANSACTION;
END
GO

PRINT 'Migration 137 applied: production records now consume feed + medication inventory and store costing.';
GO
