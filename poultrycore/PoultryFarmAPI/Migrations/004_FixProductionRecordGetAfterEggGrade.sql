-- If production records disappeared from the app after adding EggGrade, common causes:
--   1) spProductionRecord_GetAll filters WHERE UserId = @UserId AND FarmId = @FarmId
--      (legacy rows or login id mismatch → zero rows; app shows empty list).
--   2) SELECT list omitted UserId / UpdatedAt / etc. → API threw while mapping → 500 / empty.
--
-- This script restores GetById / GetAll to match 003_AddEggGradeToProductionRecords.sql:
--   - GetAll: WHERE FarmId = @FarmId only (same as 001 / 003).
--   - Full column list including UserId and EggGrade.
--
-- Run as a user with ALTER on these procedures. Safe to run repeatedly.

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
        CreatedAt, UpdatedAt
    FROM [dbo].[ProductionRecords]
    WHERE FarmId = @FarmId
    ORDER BY [Date] DESC, CreatedAt DESC;
END
GO

PRINT '004_FixProductionRecordGetAfterEggGrade: GetById + GetAll restored.';
GO
