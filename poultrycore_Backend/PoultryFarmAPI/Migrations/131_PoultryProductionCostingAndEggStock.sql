-- =============================================================================
-- Migration 131: Production Records feed/medication costing + egg inventory
-- =============================================================================
-- Doc section 4. Additive columns on ProductionRecords + extend the existing
-- spEggProduction_Insert/Update/Delete to (a) store feed/medication costing and
-- (b) increase the default egg finished-product stock via a PoultryStockTransaction.
-- All new SP params are optional so existing callers keep working unchanged.
-- Idempotent (guarded ALTER + CREATE OR ALTER). Preserves existing behaviour.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF COL_LENGTH('dbo.ProductionRecords','SpecificFeedUsedId') IS NULL       ALTER TABLE dbo.ProductionRecords ADD SpecificFeedUsedId INT NULL;
GO
IF COL_LENGTH('dbo.ProductionRecords','SpecificFeedUsedName') IS NULL     ALTER TABLE dbo.ProductionRecords ADD SpecificFeedUsedName NVARCHAR(150) NULL;
GO
IF COL_LENGTH('dbo.ProductionRecords','FeedUnitCost') IS NULL             ALTER TABLE dbo.ProductionRecords ADD FeedUnitCost DECIMAL(14,4) NULL;
GO
IF COL_LENGTH('dbo.ProductionRecords','TotalFeedConsumed') IS NULL        ALTER TABLE dbo.ProductionRecords ADD TotalFeedConsumed DECIMAL(14,3) NULL;
GO
IF COL_LENGTH('dbo.ProductionRecords','TotalFeedCost') IS NULL            ALTER TABLE dbo.ProductionRecords ADD TotalFeedCost DECIMAL(14,2) NULL;
GO
IF COL_LENGTH('dbo.ProductionRecords','SpecificMedicationUsedId') IS NULL ALTER TABLE dbo.ProductionRecords ADD SpecificMedicationUsedId INT NULL;
GO
IF COL_LENGTH('dbo.ProductionRecords','SpecificMedicationUsedName') IS NULL ALTER TABLE dbo.ProductionRecords ADD SpecificMedicationUsedName NVARCHAR(150) NULL;
GO
IF COL_LENGTH('dbo.ProductionRecords','MedicationUnitCost') IS NULL       ALTER TABLE dbo.ProductionRecords ADD MedicationUnitCost DECIMAL(14,4) NULL;
GO
IF COL_LENGTH('dbo.ProductionRecords','TotalMedicationConsumed') IS NULL  ALTER TABLE dbo.ProductionRecords ADD TotalMedicationConsumed DECIMAL(14,3) NULL;
GO
IF COL_LENGTH('dbo.ProductionRecords','TotalMedicationCost') IS NULL      ALTER TABLE dbo.ProductionRecords ADD TotalMedicationCost DECIMAL(14,2) NULL;
GO
IF COL_LENGTH('dbo.ProductionRecords','TotalCostOfProduction') IS NULL    ALTER TABLE dbo.ProductionRecords ADD TotalCostOfProduction DECIMAL(14,2) NULL;
GO

-- Helper: ensure default egg product + post/replace the production stock txn.
CREATE OR ALTER PROCEDURE dbo.spPoultryEggStock_SyncForProduction
    @FarmId NVARCHAR(450), @ProductionId INT, @GoodEggs INT, @UnitCost DECIMAL(14,4) = NULL, @CreatedBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    -- remove any prior production-linked egg stock txn for this record (idempotent update)
    DELETE FROM dbo.PoultryStockTransactions WHERE FarmId = @FarmId AND TxnType = 'Production' AND RelatedId = @ProductionId;
    IF (ISNULL(@GoodEggs,0) <= 0) RETURN;

    DECLARE @egg INT;
    SELECT TOP 1 @egg = PoultryProductId FROM dbo.PoultryProducts
    WHERE  FarmId = @FarmId AND (IsRawEggProduct = 1 OR Name IN (N'Eggs', N'Chicken Eggs'))
    ORDER  BY IsRawEggProduct DESC, PoultryProductId;
    IF @egg IS NULL
    BEGIN
        INSERT INTO dbo.PoultryProducts (FarmId, Name, Unit, UnitPrice, ProductType, IsRawEggProduct, RequiresRecipeSetup)
        VALUES (@FarmId, N'Eggs', N'Crate', 0, 'FinishedGood', 1, 0);
        SET @egg = CAST(SCOPE_IDENTITY() AS INT);
    END

    INSERT INTO dbo.PoultryStockTransactions (FarmId, PoultryProductId, TxnType, Quantity, UnitCost, RelatedId, Note, CreatedBy)
    VALUES (@FarmId, @egg, 'Production', @GoodEggs, @UnitCost, @ProductionId, N'Egg production', @CreatedBy);
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spEggProduction_Insert]
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
    @EggGrade NVARCHAR(50) = NULL,
    @SpecificFeedUsedId INT = NULL, @SpecificFeedUsedName NVARCHAR(150) = NULL,
    @FeedUnitCost DECIMAL(14,4) = NULL, @TotalFeedConsumed DECIMAL(14,3) = NULL, @TotalFeedCost DECIMAL(14,2) = NULL,
    @SpecificMedicationUsedId INT = NULL, @SpecificMedicationUsedName NVARCHAR(150) = NULL,
    @MedicationUnitCost DECIMAL(14,4) = NULL, @TotalMedicationConsumed DECIMAL(14,3) = NULL, @TotalMedicationCost DECIMAL(14,2) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @TotalProduction INT = @Production9AM + @Production12PM + @Production4PM;
    IF @TotalProduction = 0 AND @EggCount > 0 BEGIN SET @Production9AM = @EggCount; SET @TotalProduction = @EggCount; END
    DECLARE @TotalCostOfProduction DECIMAL(14,2) = ISNULL(@TotalFeedCost,0) + ISNULL(@TotalMedicationCost,0);

    BEGIN TRANSACTION;
    INSERT INTO [dbo].[ProductionRecords] (
        FarmId, CreatedBy, UserId, AgeInWeeks, AgeInDays, [Date],
        NoOfBirds, Mortality, NoOfBirdsLeft, FeedKg, Medication,
        Production9AM, Production12PM, Production4PM, TotalProduction,
        FlockId, BrokenEggs, Notes, EggCount, EggGrade, CreatedAt,
        SpecificFeedUsedId, SpecificFeedUsedName, FeedUnitCost, TotalFeedConsumed, TotalFeedCost,
        SpecificMedicationUsedId, SpecificMedicationUsedName, MedicationUnitCost, TotalMedicationConsumed, TotalMedicationCost, TotalCostOfProduction)
    VALUES (
        @FarmId, @UserId, @UserId, 0, 0, @ProductionDate,
        0, 0, 0, ISNULL(@TotalFeedConsumed,0), @SpecificMedicationUsedName,
        @Production9AM, @Production12PM, @Production4PM, @TotalProduction,
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

CREATE OR ALTER PROCEDURE [dbo].[spEggProduction_Update]
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
    @EggGrade NVARCHAR(50) = NULL,
    @SpecificFeedUsedId INT = NULL, @SpecificFeedUsedName NVARCHAR(150) = NULL,
    @FeedUnitCost DECIMAL(14,4) = NULL, @TotalFeedConsumed DECIMAL(14,3) = NULL, @TotalFeedCost DECIMAL(14,2) = NULL,
    @SpecificMedicationUsedId INT = NULL, @SpecificMedicationUsedName NVARCHAR(150) = NULL,
    @MedicationUnitCost DECIMAL(14,4) = NULL, @TotalMedicationConsumed DECIMAL(14,3) = NULL, @TotalMedicationCost DECIMAL(14,2) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @TotalProduction INT = @Production9AM + @Production12PM + @Production4PM;
    IF @TotalProduction = 0 AND @EggCount > 0 BEGIN SET @Production9AM = @EggCount; SET @TotalProduction = @EggCount; END
    DECLARE @TotalCostOfProduction DECIMAL(14,2) = ISNULL(@TotalFeedCost,0) + ISNULL(@TotalMedicationCost,0);

    BEGIN TRANSACTION;
    UPDATE [dbo].[ProductionRecords]
    SET FlockId=@FlockId, [Date]=@ProductionDate, EggCount=@EggCount,
        Production9AM=@Production9AM, Production12PM=@Production12PM, Production4PM=@Production4PM,
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

CREATE OR ALTER PROCEDURE [dbo].[spEggProduction_Delete]
    @ProductionId INT, @FarmId NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRANSACTION;
    DELETE FROM dbo.PoultryStockTransactions WHERE FarmId = @FarmId AND TxnType = 'Production' AND RelatedId = @ProductionId;
    DELETE FROM [dbo].[ProductionRecords] WHERE Id = @ProductionId AND FarmId = @FarmId;
    COMMIT TRANSACTION;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spPoultryEggStock_SyncForProduction TO [Techretainer];
    GRANT EXECUTE ON dbo.spEggProduction_Insert TO [Techretainer];
    GRANT EXECUTE ON dbo.spEggProduction_Update TO [Techretainer];
    GRANT EXECUTE ON dbo.spEggProduction_Delete TO [Techretainer];
    PRINT '131: granted EXECUTE to Techretainer.';
END
GO

PRINT '131_PoultryProductionCostingAndEggStock.sql complete.';
GO
