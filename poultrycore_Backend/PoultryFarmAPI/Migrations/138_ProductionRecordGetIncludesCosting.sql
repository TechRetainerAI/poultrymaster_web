-- =============================================================================
-- Migration 138: return feed/medication costing from ProductionRecord Get procs
-- =============================================================================
-- spProductionRecord_GetById/_GetAll use explicit column lists, so the costing
-- columns added in migration 131/137 were not returned — the edit form could not
-- prefill them and the list could not display cost. Add the columns to both.
-- Idempotent (CREATE OR ALTER).
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
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
        Production9AM, Production12PM, Production4PM, TotalProduction,
        FlockId, BrokenEggs, Notes, ISNULL(EggCount, TotalProduction) AS EggCount,
        EggGrade,
        MeatyEggs, SoftEggs, LostEggs,
        SpecificFeedUsedId, SpecificFeedUsedName, FeedUnitCost, TotalFeedConsumed, TotalFeedCost,
        SpecificMedicationUsedId, SpecificMedicationUsedName, MedicationUnitCost, TotalMedicationConsumed, TotalMedicationCost,
        TotalCostOfProduction,
        CreatedAt, UpdatedAt
    FROM [dbo].[ProductionRecords]
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
        CreatedAt, UpdatedAt
    FROM [dbo].[ProductionRecords]
    WHERE FarmId = @FarmId
    ORDER BY [Date] DESC, CreatedAt DESC;
END
GO

PRINT 'Migration 138 applied: ProductionRecord Get procs now return feed/medication costing.';
GO
