
-- Add EggGrade to ProductionRecords and refresh spProductionRecord_* procedures.
-- Run after 001_UnifyProductionTables.sql (and 002 if you use feed sync).

IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[ProductionRecords]') AND type in (N'U'))
BEGIN
    IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[ProductionRecords]') AND name = 'EggGrade')
    BEGIN
        ALTER TABLE [dbo].[ProductionRecords] ADD [EggGrade] NVARCHAR(50) NULL;
        PRINT 'Added EggGrade column to ProductionRecords';
    END
    ELSE
        PRINT 'EggGrade column already exists';
END
GO

IF OBJECT_ID('spProductionRecord_Insert', 'P') IS NOT NULL
    DROP PROCEDURE spProductionRecord_Insert;
GO

CREATE PROCEDURE [dbo].[spProductionRecord_Insert]
    @FarmId NVARCHAR(100),
    @CreatedBy NVARCHAR(100),
    @UserId NVARCHAR(100),
    @AgeInWeeks INT,
    @AgeInDays INT,
    @Date DATE,
    @NoOfBirds INT,
    @Mortality INT,
    @NoOfBirdsLeft INT,
    @FeedKg DECIMAL(18,2),
    @Medication NVARCHAR(500) = NULL,
    @Production9AM INT,
    @Production12PM INT,
    @Production4PM INT,
    @TotalProduction INT,
    @FlockId INT = NULL,
    @BrokenEggs INT = NULL,
    @Notes NVARCHAR(MAX) = NULL,
    @EggCount INT = NULL,
    @EggGrade NVARCHAR(50) = NULL,
    @NewId INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @EggCount = ISNULL(@EggCount, @TotalProduction);

    INSERT INTO [dbo].[ProductionRecords] (
        FarmId, CreatedBy, UserId, AgeInWeeks, AgeInDays, [Date],
        NoOfBirds, Mortality, NoOfBirdsLeft, FeedKg, Medication,
        Production9AM, Production12PM, Production4PM, TotalProduction,
        FlockId, BrokenEggs, Notes, EggCount, EggGrade, CreatedAt
    )
    VALUES (
        @FarmId, @CreatedBy, @UserId, @AgeInWeeks, @AgeInDays, @Date,
        @NoOfBirds, @Mortality, @NoOfBirdsLeft, @FeedKg, @Medication,
        @Production9AM, @Production12PM, @Production4PM, @TotalProduction,
        @FlockId, @BrokenEggs, @Notes, @EggCount, @EggGrade, GETUTCDATE()
    );

    SET @NewId = SCOPE_IDENTITY();
END
GO

IF OBJECT_ID('spProductionRecord_Update', 'P') IS NOT NULL
    DROP PROCEDURE spProductionRecord_Update;
GO

CREATE PROCEDURE [dbo].[spProductionRecord_Update]
    @RecordId INT,
    @UpdatedBy NVARCHAR(100),
    @AgeInWeeks INT,
    @AgeInDays INT,
    @Date DATE,
    @NoOfBirds INT,
    @Mortality INT,
    @NoOfBirdsLeft INT,
    @FeedKg DECIMAL(18,2),
    @Medication NVARCHAR(500) = NULL,
    @Production9AM INT,
    @Production12PM INT,
    @Production4PM INT,
    @TotalProduction INT,
    @FlockId INT = NULL,
    @BrokenEggs INT = NULL,
    @Notes NVARCHAR(MAX) = NULL,
    @EggCount INT = NULL,
    @EggGrade NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @EggCount = ISNULL(@EggCount, @TotalProduction);

    UPDATE [dbo].[ProductionRecords]
    SET
        UpdatedBy = @UpdatedBy,
        AgeInWeeks = @AgeInWeeks,
        AgeInDays = @AgeInDays,
        [Date] = @Date,
        NoOfBirds = @NoOfBirds,
        Mortality = @Mortality,
        NoOfBirdsLeft = @NoOfBirdsLeft,
        FeedKg = @FeedKg,
        Medication = @Medication,
        Production9AM = @Production9AM,
        Production12PM = @Production12PM,
        Production4PM = @Production4PM,
        TotalProduction = @TotalProduction,
        FlockId = @FlockId,
        BrokenEggs = @BrokenEggs,
        Notes = @Notes,
        EggCount = @EggCount,
        EggGrade = @EggGrade,
        UpdatedAt = GETUTCDATE()
    WHERE Id = @RecordId;
END
GO

IF OBJECT_ID('spProductionRecord_GetById', 'P') IS NOT NULL
    DROP PROCEDURE spProductionRecord_GetById;
GO

CREATE PROCEDURE [dbo].[spProductionRecord_GetById]
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

IF OBJECT_ID('spProductionRecord_GetAll', 'P') IS NOT NULL
    DROP PROCEDURE spProductionRecord_GetAll;
GO

CREATE PROCEDURE [dbo].[spProductionRecord_GetAll]
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

PRINT '003_AddEggGradeToProductionRecords: procedures updated.';
GO
