-- =============================================================================
-- 010_EggGradeOnEggProductionProcedures.sql
-- =============================================================================
-- Wires EggGrade through spEggProduction_* (ProductionRecords.EggGrade from 003).
-- Run AFTER: 003_AddEggGradeToProductionRecords.sql
--
-- *** MUST RUN IN YOUR APPLICATION DATABASE — NOT [master] ***
--
-- If you see:
--   "CREATE PROCEDURE permission denied in database 'master'"
-- then SSMS (or your tool) is connected to [master]. Fix it using ONE of:
--
--   A) SSMS: open the "database" dropdown in the toolbar and pick your poultry /
--      farm database (same one as in your API connection string "Initial Catalog="
--      or "Database="), then execute this script again.
--
--   B) Uncomment the two lines below, put YOUR real database name in USE [...],
--      save, and run from the top (first batch must be USE ...; GO).
--
--      USE [YourDatabaseNameHere];
--      GO
--
-- Do not grant yourself rights in [master]; use the correct database context.
-- =============================================================================

-- Uncomment and set your database name if the toolbar is not switched easily:
-- USE [YourDatabaseNameHere];
-- GO

IF DB_NAME() = N'master'
BEGIN
    RAISERROR(
        N'010_EggGrade: Connected to [master]. Switch to your application database (SSMS database dropdown, or USE [YourDb]; GO at top of this file), then run again.',
        16,
        1
    );
    SET NOEXEC ON;
END
GO

IF OBJECT_ID('spEggProduction_Insert', 'P') IS NOT NULL
    DROP PROCEDURE spEggProduction_Insert;
GO

CREATE PROCEDURE [dbo].[spEggProduction_Insert]
    @FlockId INT,
    @ProductionDate DATE,
    @EggCount INT,
    @Production9AM INT = 0,
    @Production12PM INT = 0,
    @Production4PM INT = 0,
    @BrokenEggs INT = NULL,
    @Notes NVARCHAR(MAX) = NULL,
    @UserId NVARCHAR(100) = NULL,
    @FarmId NVARCHAR(100) = NULL,
    @EggGrade NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TotalProduction INT = @Production9AM + @Production12PM + @Production4PM;

    IF @TotalProduction = 0 AND @EggCount > 0
    BEGIN
        SET @Production9AM = @EggCount;
        SET @TotalProduction = @EggCount;
    END

    INSERT INTO [dbo].[ProductionRecords] (
        FarmId, CreatedBy, UserId,
        AgeInWeeks, AgeInDays, [Date],
        NoOfBirds, Mortality, NoOfBirdsLeft, FeedKg, Medication,
        Production9AM, Production12PM, Production4PM, TotalProduction,
        FlockId, BrokenEggs, Notes, EggCount, EggGrade, CreatedAt
    )
    VALUES (
        @FarmId, @UserId, @UserId,
        0, 0, @ProductionDate,
        0, 0, 0, 0, NULL,
        @Production9AM, @Production12PM, @Production4PM, @TotalProduction,
        @FlockId, @BrokenEggs, @Notes, @EggCount, @EggGrade, GETUTCDATE()
    );

    SELECT SCOPE_IDENTITY();
END
GO

IF OBJECT_ID('spEggProduction_Update', 'P') IS NOT NULL
    DROP PROCEDURE spEggProduction_Update;
GO

CREATE PROCEDURE [dbo].[spEggProduction_Update]
    @ProductionId INT,
    @FlockId INT,
    @ProductionDate DATE,
    @EggCount INT,
    @Production9AM INT = 0,
    @Production12PM INT = 0,
    @Production4PM INT = 0,
    @BrokenEggs INT = NULL,
    @Notes NVARCHAR(MAX) = NULL,
    @UserId NVARCHAR(100) = NULL,
    @FarmId NVARCHAR(100) = NULL,
    @EggGrade NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TotalProduction INT = @Production9AM + @Production12PM + @Production4PM;

    IF @TotalProduction = 0 AND @EggCount > 0
    BEGIN
        SET @Production9AM = @EggCount;
        SET @TotalProduction = @EggCount;
    END

    UPDATE [dbo].[ProductionRecords]
    SET
        FlockId = @FlockId,
        [Date] = @ProductionDate,
        EggCount = @EggCount,
        Production9AM = @Production9AM,
        Production12PM = @Production12PM,
        Production4PM = @Production4PM,
        TotalProduction = @TotalProduction,
        BrokenEggs = @BrokenEggs,
        Notes = @Notes,
        EggGrade = @EggGrade,
        UpdatedBy = @UserId,
        UpdatedAt = GETUTCDATE()
    WHERE Id = @ProductionId AND FarmId = @FarmId;
END
GO

IF OBJECT_ID('spEggProduction_GetById', 'P') IS NOT NULL
    DROP PROCEDURE spEggProduction_GetById;
GO

CREATE PROCEDURE [dbo].[spEggProduction_GetById]
    @ProductionId INT,
    @UserId NVARCHAR(100),
    @FarmId NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        Id AS ProductionId,
        ISNULL(FlockId, 0) AS FlockId,
        [Date] AS ProductionDate,
        ISNULL(EggCount, TotalProduction) AS EggCount,
        Production9AM,
        Production12PM,
        Production4PM,
        BrokenEggs,
        Notes,
        EggGrade,
        ISNULL(UserId, CreatedBy) AS UserId,
        FarmId
    FROM [dbo].[ProductionRecords]
    WHERE Id = @ProductionId AND FarmId = @FarmId;
END
GO

IF OBJECT_ID('spEggProduction_GetAll', 'P') IS NOT NULL
    DROP PROCEDURE spEggProduction_GetAll;
GO

CREATE PROCEDURE [dbo].[spEggProduction_GetAll]
    @FarmId NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        Id AS ProductionId,
        ISNULL(FlockId, 0) AS FlockId,
        [Date] AS ProductionDate,
        ISNULL(EggCount, TotalProduction) AS EggCount,
        Production9AM,
        Production12PM,
        Production4PM,
        ISNULL(Production9AM, 0) + ISNULL(Production12PM, 0) + ISNULL(Production4PM, 0) AS TotalProduction,
        BrokenEggs,
        Notes,
        EggGrade,
        ISNULL(UserId, CreatedBy) AS UserId,
        FarmId
    FROM [dbo].[ProductionRecords]
    WHERE FarmId = @FarmId
    ORDER BY [Date] DESC, CreatedAt DESC;
END
GO

IF OBJECT_ID('spEggProduction_GetByFlock', 'P') IS NOT NULL
    DROP PROCEDURE spEggProduction_GetByFlock;
GO

CREATE PROCEDURE [dbo].[spEggProduction_GetByFlock]
    @FlockId INT,
    @FarmId NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        Id AS ProductionId,
        ISNULL(FlockId, 0) AS FlockId,
        [Date] AS ProductionDate,
        ISNULL(EggCount, TotalProduction) AS EggCount,
        Production9AM,
        Production12PM,
        Production4PM,
        ISNULL(Production9AM, 0) + ISNULL(Production12PM, 0) + ISNULL(Production4PM, 0) AS TotalProduction,
        BrokenEggs,
        Notes,
        EggGrade,
        FarmId
    FROM [dbo].[ProductionRecords]
    WHERE FarmId = @FarmId AND FlockId = @FlockId
    ORDER BY [Date] DESC, CreatedAt DESC;
END
GO

PRINT '010_EggGradeOnEggProductionProcedures: spEggProduction_* updated with EggGrade.';
GO

SET NOEXEC OFF;
GO
