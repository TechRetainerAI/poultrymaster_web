-- =============================================================================
-- Migration 163: reconcile ProductionRecord 4th-pick after the Enock↔dev merge
-- =============================================================================
-- Enock's 152_ProductionRecordFourthPick added a Production4thPick column and
-- rewrote spProductionRecord_GetById/_GetAll to return it. But dev's higher-
-- numbered 154 (multi-medication) and 155 (multi-feed) also CREATE OR ALTER
-- those two Get SPs and — having been authored without the 4th pick — dropped
-- the Production4thPick column from their SELECT. Because 154/155 run after 152,
-- the net result is: the 4th pick is STORED (spProductionRecord_SetFourthPick
-- still runs) but never READ BACK, so the UI can't show it.
--
-- 155's Get SP bodies are byte-for-byte identical to 152's except for the single
-- missing "ISNULL(Production4thPick,0) AS Production4thPick" column, so this
-- migration simply re-applies 152's Get SP definitions as the final word. The
-- Insert/Update SPs are untouched (Enock deliberately kept the 4th pick in a
-- separate SetFourthPick SP, so those never clobbered). Idempotent; additive.
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- Safety: column exists (no-op if 152 already added it).
IF COL_LENGTH(N'dbo.ProductionRecords', N'Production4thPick') IS NULL
    ALTER TABLE [dbo].[ProductionRecords] ADD [Production4thPick] INT NULL;
GO

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
        Production9AM, Production12PM, Production4PM, ISNULL(Production4thPick, 0) AS Production4thPick, TotalProduction,
        FlockId, BrokenEggs, Notes, ISNULL(EggCount, TotalProduction) AS EggCount,
        EggGrade,
        MeatyEggs, SoftEggs, LostEggs,
        SpecificFeedUsedId, SpecificFeedUsedName, FeedUnitCost, TotalFeedConsumed, TotalFeedCost,
        SpecificMedicationUsedId, SpecificMedicationUsedName, MedicationUnitCost, TotalMedicationConsumed, TotalMedicationCost,
        TotalCostOfProduction,
        (SELECT f.PoultryRawMaterialItemId AS specificFeedUsedId,
                f.ItemName                 AS specificFeedUsedName,
                f.QuantityConsumed         AS totalFeedConsumed,
                f.UnitCost                 AS feedUnitCost,
                f.TotalCost                AS totalFeedCost
         FROM dbo.ProductionRecordFeeds f
         WHERE f.ProductionRecordId = pr.Id
         ORDER BY f.ProductionRecordFeedId
         FOR JSON PATH) AS FeedsJson,
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
        Production9AM, Production12PM, Production4PM, ISNULL(Production4thPick, 0) AS Production4thPick, TotalProduction,
        FlockId, BrokenEggs, Notes, ISNULL(EggCount, TotalProduction) AS EggCount,
        EggGrade,
        MeatyEggs, SoftEggs, LostEggs,
        SpecificFeedUsedId, SpecificFeedUsedName, FeedUnitCost, TotalFeedConsumed, TotalFeedCost,
        SpecificMedicationUsedId, SpecificMedicationUsedName, MedicationUnitCost, TotalMedicationConsumed, TotalMedicationCost,
        TotalCostOfProduction,
        (SELECT f.PoultryRawMaterialItemId AS specificFeedUsedId,
                f.ItemName                 AS specificFeedUsedName,
                f.QuantityConsumed         AS totalFeedConsumed,
                f.UnitCost                 AS feedUnitCost,
                f.TotalCost                AS totalFeedCost
         FROM dbo.ProductionRecordFeeds f
         WHERE f.ProductionRecordId = pr.Id
         ORDER BY f.ProductionRecordFeedId
         FOR JSON PATH) AS FeedsJson,
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

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spProductionRecord_GetById TO [Techretainer];
    GRANT EXECUTE ON dbo.spProductionRecord_GetAll  TO [Techretainer];
END
GO

PRINT N'163_ReconcileProductionRecordFourthPick.sql complete.';
GO
