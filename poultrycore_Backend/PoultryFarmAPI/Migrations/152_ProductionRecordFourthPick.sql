-- =============================================================================
-- Migration 152: Production record — 4th egg pick
-- =============================================================================
-- Egg collection is being standardised around generic pick labels (1st/2nd/3rd/
-- 4th Pick) with a configurable time per farm. The 1st/2nd/3rd picks reuse the
-- existing Production9AM/Production12PM/Production4PM columns (pure relabel, no
-- data change); this migration adds the NEW 4th pick.
--
-- To avoid rewriting the large, side-effectful Insert/Update procs (bird/egg
-- stock sync + FIFO costing), the 4th pick is stored by a small dedicated proc
-- (spProductionRecord_SetFourthPick) that the service calls right after the
-- insert/update. It also recomputes TotalProduction to include the 4th pick with
-- nulls treated as zero, so historical rows (4th pick = 0) keep their totals.
--
-- The read procs (GetById/GetAll) are re-created verbatim from migration 148 with
-- Production4thPick added to the projection. Insert/Update are left untouched.
-- Idempotent (COL_LENGTH guard on the ALTER; CREATE OR ALTER on the procs).
-- =============================================================================
IF DB_NAME() IN (N'master', N'model', N'msdb', N'tempdb')
BEGIN
    THROW 50000, N'Select your application database (not master). Aborting.', 1;
END
GO

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[ProductionRecords]') AND type = N'U')
BEGIN
    RAISERROR(N'152: dbo.ProductionRecords not found. Run earlier migrations first.', 16, 1);
END
GO

IF COL_LENGTH(N'dbo.ProductionRecords', N'Production4thPick') IS NULL
BEGIN
    ALTER TABLE [dbo].[ProductionRecords] ADD [Production4thPick] INT NULL;
    PRINT N'152: Added ProductionRecords.Production4thPick';
END
GO

-- ---------------------------------------------------------------------------
-- Setter — persist the 4th pick + recompute the total (nulls -> 0).
-- ---------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[spProductionRecord_SetFourthPick]
    @RecordId        INT,
    @FarmId          NVARCHAR(100) = NULL,
    @Production4thPick INT = 0
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE [dbo].[ProductionRecords]
    SET    [Production4thPick] = @Production4thPick,
           [TotalProduction]   = ISNULL([Production9AM],0) + ISNULL([Production12PM],0)
                               + ISNULL([Production4PM],0) + ISNULL(@Production4thPick,0)
    WHERE  [Id] = @RecordId
      AND (@FarmId IS NULL OR [FarmId] = @FarmId);
END
GO

-- ---------------------------------------------------------------------------
-- GetById / GetAll — copied from migration 148 with Production4thPick added.
-- ---------------------------------------------------------------------------
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
    GRANT EXECUTE ON dbo.spProductionRecord_SetFourthPick TO [Techretainer];
    GRANT EXECUTE ON dbo.spProductionRecord_GetById       TO [Techretainer];
    GRANT EXECUTE ON dbo.spProductionRecord_GetAll        TO [Techretainer];
    PRINT N'152: granted EXECUTE on 4th-pick objects to Techretainer.';
END
GO

PRINT N'152_ProductionRecordFourthPick.sql complete.';
GO
