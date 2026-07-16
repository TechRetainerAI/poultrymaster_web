-- =============================================================================
-- Migration 155: Egg Production ("Egg sorting") module — 4th pick
-- =============================================================================
-- The Egg Production module writes to the unified dbo.ProductionRecords table via
-- its own spEggProduction_* procs (separate from spProductionRecord_*). Its
-- insert/update compute the total AND run egg-stock sync, so the 4th pick has to
-- be added inside these procs (not patched after) or the egg stock would be short
-- by the 4th-pick amount.
--
-- Insert/Update reproduced from migration 131; Get procs from migration 010 —
-- each with @Production4thPick / the Production4thPick column added and totals
-- widened to include it. Idempotent (CREATE OR ALTER).
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

-- ---------------------------------------------------------------------------
-- Insert (from 131) + @Production4thPick.
-- ---------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[spEggProduction_Insert]
    @FlockId INT,
    @ProductionDate DATE,
    @EggCount INT,
    @Production9AM INT = 0,
    @Production12PM INT = 0,
    @Production4PM INT = 0,
    @Production4thPick INT = 0,
    @BrokenEggs INT = NULL,
    @Notes NVARCHAR(MAX) = NULL,
    @UserId NVARCHAR(100) = NULL,
    @FarmId NVARCHAR(100) = NULL,
    @EggGrade NVARCHAR(50) = NULL,
    @SpecificFeedUsedId INT = NULL, @SpecificFeedUsedName NVARCHAR(150) = NULL,
    @FeedUnitCost DECIMAL(14,4) = NULL, @TotalFeedConsumed DECIMAL(14,3) = NULL, @TotalFeedCost DECIMAL(14,2) = NULL,
    @SpecificMedicationUsedId INT = NULL, @SpecificMedicationUsedName NVARCHAR(150) = NULL,
    @MedicationUnitCost DECIMAL(14,4) = NULL, @TotalMedicationConsumed DECIMAL(14,3) = NULL, @TotalMedicationCost DECIMAL(14,2) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @TotalProduction INT = @Production9AM + @Production12PM + @Production4PM + ISNULL(@Production4thPick,0);
    IF @TotalProduction = 0 AND @EggCount > 0 BEGIN SET @Production9AM = @EggCount; SET @TotalProduction = @EggCount; END
    DECLARE @TotalCostOfProduction DECIMAL(14,2) = ISNULL(@TotalFeedCost,0) + ISNULL(@TotalMedicationCost,0);

    BEGIN TRANSACTION;
    INSERT INTO [dbo].[ProductionRecords] (
        FarmId, CreatedBy, UserId, AgeInWeeks, AgeInDays, [Date],
        NoOfBirds, Mortality, NoOfBirdsLeft, FeedKg, Medication,
        Production9AM, Production12PM, Production4PM, Production4thPick, TotalProduction,
        FlockId, BrokenEggs, Notes, EggCount, EggGrade, CreatedAt,
        SpecificFeedUsedId, SpecificFeedUsedName, FeedUnitCost, TotalFeedConsumed, TotalFeedCost,
        SpecificMedicationUsedId, SpecificMedicationUsedName, MedicationUnitCost, TotalMedicationConsumed, TotalMedicationCost, TotalCostOfProduction)
    VALUES (
        @FarmId, @UserId, @UserId, 0, 0, @ProductionDate,
        0, 0, 0, ISNULL(@TotalFeedConsumed,0), @SpecificMedicationUsedName,
        @Production9AM, @Production12PM, @Production4PM, ISNULL(@Production4thPick,0), @TotalProduction,
        @FlockId, @BrokenEggs, @Notes, @EggCount, @EggGrade, GETUTCDATE(),
        @SpecificFeedUsedId, @SpecificFeedUsedName, @FeedUnitCost, @TotalFeedConsumed, @TotalFeedCost,
        @SpecificMedicationUsedId, @SpecificMedicationUsedName, @MedicationUnitCost, @TotalMedicationConsumed, @TotalMedicationCost, @TotalCostOfProduction);

    DECLARE @Pid INT = CAST(SCOPE_IDENTITY() AS INT);
    DECLARE @Good INT = @TotalProduction - ISNULL(@BrokenEggs,0);
    DECLARE @CPU DECIMAL(14,4) = CASE WHEN @Good > 0 AND @TotalCostOfProduction > 0 THEN @TotalCostOfProduction / @Good ELSE NULL END;
    IF @FarmId IS NOT NULL EXEC dbo.spPoultryEggStock_SyncForProduction @FarmId, @Pid, @Good, @CPU, @UserId;
    COMMIT TRANSACTION;
    SELECT @Pid;
END
GO

-- ---------------------------------------------------------------------------
-- Update (from 131) + @Production4thPick.
-- ---------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[spEggProduction_Update]
    @ProductionId INT,
    @FlockId INT,
    @ProductionDate DATE,
    @EggCount INT,
    @Production9AM INT = 0,
    @Production12PM INT = 0,
    @Production4PM INT = 0,
    @Production4thPick INT = 0,
    @BrokenEggs INT = NULL,
    @Notes NVARCHAR(MAX) = NULL,
    @UserId NVARCHAR(100) = NULL,
    @FarmId NVARCHAR(100) = NULL,
    @EggGrade NVARCHAR(50) = NULL,
    @SpecificFeedUsedId INT = NULL, @SpecificFeedUsedName NVARCHAR(150) = NULL,
    @FeedUnitCost DECIMAL(14,4) = NULL, @TotalFeedConsumed DECIMAL(14,3) = NULL, @TotalFeedCost DECIMAL(14,2) = NULL,
    @SpecificMedicationUsedId INT = NULL, @SpecificMedicationUsedName NVARCHAR(150) = NULL,
    @MedicationUnitCost DECIMAL(14,4) = NULL, @TotalMedicationConsumed DECIMAL(14,3) = NULL, @TotalMedicationCost DECIMAL(14,2) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @TotalProduction INT = @Production9AM + @Production12PM + @Production4PM + ISNULL(@Production4thPick,0);
    IF @TotalProduction = 0 AND @EggCount > 0 BEGIN SET @Production9AM = @EggCount; SET @TotalProduction = @EggCount; END
    DECLARE @TotalCostOfProduction DECIMAL(14,2) = ISNULL(@TotalFeedCost,0) + ISNULL(@TotalMedicationCost,0);

    BEGIN TRANSACTION;
    UPDATE [dbo].[ProductionRecords]
    SET FlockId=@FlockId, [Date]=@ProductionDate, EggCount=@EggCount,
        Production9AM=@Production9AM, Production12PM=@Production12PM, Production4PM=@Production4PM, Production4thPick=ISNULL(@Production4thPick,0),
        TotalProduction=@TotalProduction, BrokenEggs=@BrokenEggs, Notes=@Notes, EggGrade=@EggGrade,
        FeedKg=ISNULL(@TotalFeedConsumed, FeedKg),
        SpecificFeedUsedId=@SpecificFeedUsedId, SpecificFeedUsedName=@SpecificFeedUsedName, FeedUnitCost=@FeedUnitCost,
        TotalFeedConsumed=@TotalFeedConsumed, TotalFeedCost=@TotalFeedCost,
        SpecificMedicationUsedId=@SpecificMedicationUsedId, SpecificMedicationUsedName=@SpecificMedicationUsedName,
        MedicationUnitCost=@MedicationUnitCost, TotalMedicationConsumed=@TotalMedicationConsumed, TotalMedicationCost=@TotalMedicationCost,
        TotalCostOfProduction=@TotalCostOfProduction, UpdatedBy=@UserId, UpdatedAt=GETUTCDATE()
    WHERE Id=@ProductionId AND FarmId=@FarmId;

    DECLARE @Good INT = @TotalProduction - ISNULL(@BrokenEggs,0);
    DECLARE @CPU DECIMAL(14,4) = CASE WHEN @Good > 0 AND @TotalCostOfProduction > 0 THEN @TotalCostOfProduction / @Good ELSE NULL END;
    IF @FarmId IS NOT NULL EXEC dbo.spPoultryEggStock_SyncForProduction @FarmId, @ProductionId, @Good, @CPU, @UserId;
    COMMIT TRANSACTION;
END
GO

-- ---------------------------------------------------------------------------
-- Get procs (from 010) + Production4thPick; totals widened to include it.
-- ---------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[spEggProduction_GetById]
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
        ISNULL(Production4thPick, 0) AS Production4thPick,
        BrokenEggs,
        Notes,
        EggGrade,
        ISNULL(UserId, CreatedBy) AS UserId,
        FarmId
    FROM [dbo].[ProductionRecords]
    WHERE Id = @ProductionId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spEggProduction_GetAll]
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
        ISNULL(Production4thPick, 0) AS Production4thPick,
        ISNULL(Production9AM, 0) + ISNULL(Production12PM, 0) + ISNULL(Production4PM, 0) + ISNULL(Production4thPick, 0) AS TotalProduction,
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

CREATE OR ALTER PROCEDURE [dbo].[spEggProduction_GetByFlock]
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
        ISNULL(Production4thPick, 0) AS Production4thPick,
        ISNULL(Production9AM, 0) + ISNULL(Production12PM, 0) + ISNULL(Production4PM, 0) + ISNULL(Production4thPick, 0) AS TotalProduction,
        BrokenEggs,
        Notes,
        EggGrade,
        FarmId
    FROM [dbo].[ProductionRecords]
    WHERE FarmId = @FarmId AND FlockId = @FlockId
    ORDER BY [Date] DESC, CreatedAt DESC;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spEggProduction_Insert    TO [Techretainer];
    GRANT EXECUTE ON dbo.spEggProduction_Update    TO [Techretainer];
    GRANT EXECUTE ON dbo.spEggProduction_GetById   TO [Techretainer];
    GRANT EXECUTE ON dbo.spEggProduction_GetAll    TO [Techretainer];
    GRANT EXECUTE ON dbo.spEggProduction_GetByFlock TO [Techretainer];
    PRINT N'155: granted EXECUTE on egg-production 4th-pick procs to Techretainer.';
END
GO

PRINT N'155_EggProductionFourthPick.sql complete.';
GO
