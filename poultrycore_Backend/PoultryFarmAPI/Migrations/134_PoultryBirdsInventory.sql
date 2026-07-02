-- =============================================================================
-- Migration 134: Live Birds inventory (doc 2)
-- =============================================================================
-- Default Birds product + bird stock movements hooked into existing modules:
--   * flock batch purchase  -> +birds (spMainFlockBatch_Insert/_Delete)
--   * production mortality   -> -birds (spProductionRecord_Insert/Update/Delete)
--   * bird sale              -> -birds (spSale_Insert/_Delete; detected by product)
-- All via PoultryStockTransactions (Bird Batch Purchase / Mortality / Bird Sale),
-- keyed by (TxnType, RelatedId) so update/delete reverse cleanly.
-- Existing SP bodies preserved; only the bird-stock sync is added. Idempotent.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF COL_LENGTH('dbo.PoultryProducts', 'IsBirdProduct') IS NULL
    ALTER TABLE dbo.PoultryProducts ADD IsBirdProduct BIT NOT NULL CONSTRAINT DF_PoultryProducts_Bird DEFAULT (0);
GO

-- Ensure the default live-Birds product for a farm.
CREATE OR ALTER PROCEDURE dbo.spPoultryProduct_EnsureDefaultBirds
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Id INT;
    SELECT TOP 1 @Id = PoultryProductId FROM dbo.PoultryProducts
    WHERE FarmId = @FarmId AND (IsBirdProduct = 1 OR Name = N'Birds')
    ORDER BY IsBirdProduct DESC, PoultryProductId;
    IF @Id IS NULL
    BEGIN
        INSERT INTO dbo.PoultryProducts (FarmId, Name, Unit, UnitPrice, ProductType, IsRawEggProduct, RequiresRecipeSetup, IsBirdProduct)
        VALUES (@FarmId, N'Birds', N'Bird', 0, 'FinishedGood', 0, 0, 1);
        SET @Id = CAST(SCOPE_IDENTITY() AS INT);
    END
    SELECT @Id AS PoultryProductId;
END
GO

-- Post/replace a bird-stock movement (find/create Birds product first).
CREATE OR ALTER PROCEDURE dbo.spPoultryBirdStock_Sync
    @FarmId NVARCHAR(450), @TxnType NVARCHAR(30), @Quantity DECIMAL(14,3), @RelatedId INT,
    @Note NVARCHAR(500) = NULL, @CreatedBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @bird INT;
    SELECT TOP 1 @bird = PoultryProductId FROM dbo.PoultryProducts
    WHERE FarmId = @FarmId AND (IsBirdProduct = 1 OR Name = N'Birds') ORDER BY IsBirdProduct DESC, PoultryProductId;
    IF @bird IS NULL
    BEGIN
        INSERT INTO dbo.PoultryProducts (FarmId, Name, Unit, UnitPrice, ProductType, IsRawEggProduct, RequiresRecipeSetup, IsBirdProduct)
        VALUES (@FarmId, N'Birds', N'Bird', 0, 'FinishedGood', 0, 0, 1);
        SET @bird = CAST(SCOPE_IDENTITY() AS INT);
    END
    DELETE FROM dbo.PoultryStockTransactions WHERE FarmId = @FarmId AND TxnType = @TxnType AND RelatedId = @RelatedId;
    IF (ISNULL(@Quantity,0) <> 0)
        INSERT INTO dbo.PoultryStockTransactions (FarmId, PoultryProductId, TxnType, Quantity, RelatedId, Note, CreatedBy)
        VALUES (@FarmId, @bird, @TxnType, @Quantity, @RelatedId, @Note, @CreatedBy);
END
GO

-- ---- Flock batch purchase -> +birds -----------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[spMainFlockBatch_Insert]
    @UserId NVARCHAR(450), @FarmId NVARCHAR(450), @BatchCode NVARCHAR(25), @BatchName NVARCHAR(100),
    @Breed NVARCHAR(50), @NumberOfBirds INT, @StartDate DATETIME2, @Status NVARCHAR(20) = N'active',
    @CostPerChick DECIMAL(18,2) = 0, @TotalCost DECIMAL(18,2) = 0, @SupplierType NVARCHAR(20) = NULL,
    @SupplierId INT = NULL, @AmountPaid DECIMAL(18,2) = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF (@TotalCost IS NULL OR @TotalCost = 0) AND @CostPerChick > 0 SET @TotalCost = @CostPerChick * @NumberOfBirds;
    BEGIN TRANSACTION;
    INSERT INTO [dbo].[MainFlockBatch] (UserId, FarmId, BatchCode, BatchName, Breed, NumberOfBirds, StartDate, Status, CostPerChick, TotalCost, AmountPaid, SupplierType, SupplierId, CreatedDate)
    VALUES (@UserId, @FarmId, @BatchCode, @BatchName, @Breed, @NumberOfBirds, @StartDate, ISNULL(@Status, N'active'), ISNULL(@CostPerChick,0), ISNULL(@TotalCost,0), ISNULL(@AmountPaid,0), @SupplierType, @SupplierId, SYSUTCDATETIME());
    DECLARE @NewId INT = CAST(SCOPE_IDENTITY() AS INT);
    IF (ISNULL(@NumberOfBirds,0) > 0)
        EXEC dbo.spPoultryBirdStock_Sync @FarmId, N'Bird Batch Purchase', @NumberOfBirds, @NewId, N'Flock batch purchase', @UserId;
    COMMIT TRANSACTION;
    SELECT @NewId;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spMainFlockBatch_Delete]
    @BatchId INT, @UserId NVARCHAR(450), @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRANSACTION;
    EXEC dbo.spPoultryBirdStock_Sync @FarmId, N'Bird Batch Purchase', 0, @BatchId, NULL, @UserId;
    DELETE FROM [dbo].[MainFlockBatch] WHERE [BatchId] = @BatchId AND [FarmId] = @FarmId;
    COMMIT TRANSACTION;
END
GO

-- ---- Production mortality -> -birds ------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[spProductionRecord_Insert]
    @FarmId NVARCHAR(100), @CreatedBy NVARCHAR(100), @UserId NVARCHAR(100), @AgeInWeeks INT, @AgeInDays INT,
    @Date DATE, @NoOfBirds INT, @Mortality INT, @NoOfBirdsLeft INT, @FeedKg DECIMAL(18,2), @Medication NVARCHAR(500) = NULL,
    @Production9AM INT, @Production12PM INT, @Production4PM INT, @TotalProduction INT, @FlockId INT = NULL,
    @BrokenEggs INT = NULL, @Notes NVARCHAR(MAX) = NULL, @EggCount INT = NULL, @EggGrade NVARCHAR(50) = NULL,
    @MeatyEggs INT = NULL, @SoftEggs INT = NULL, @LostEggs INT = NULL, @NewId INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @EggCount = ISNULL(@EggCount, @TotalProduction);
    BEGIN TRANSACTION;
    INSERT INTO [dbo].[ProductionRecords] (FarmId, CreatedBy, UserId, AgeInWeeks, AgeInDays, [Date], NoOfBirds, Mortality, NoOfBirdsLeft, FeedKg, Medication, Production9AM, Production12PM, Production4PM, TotalProduction, FlockId, BrokenEggs, Notes, EggCount, EggGrade, MeatyEggs, SoftEggs, LostEggs, CreatedAt)
    VALUES (@FarmId, @CreatedBy, @UserId, @AgeInWeeks, @AgeInDays, @Date, @NoOfBirds, @Mortality, @NoOfBirdsLeft, @FeedKg, @Medication, @Production9AM, @Production12PM, @Production4PM, @TotalProduction, @FlockId, @BrokenEggs, @Notes, @EggCount, @EggGrade, @MeatyEggs, @SoftEggs, @LostEggs, GETUTCDATE());
    SET @NewId = SCOPE_IDENTITY();
    DECLARE @mq DECIMAL(14,3) = -CAST(ISNULL(@Mortality,0) AS DECIMAL(14,3));
    IF (@mq <> 0)
        EXEC dbo.spPoultryBirdStock_Sync @FarmId, N'Mortality', @mq, @NewId, N'Production mortality', @UserId;
    COMMIT TRANSACTION;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spProductionRecord_Update]
    @RecordId INT, @UpdatedBy NVARCHAR(100), @AgeInWeeks INT, @AgeInDays INT, @Date DATE, @NoOfBirds INT, @Mortality INT,
    @NoOfBirdsLeft INT, @FeedKg DECIMAL(18,2), @Medication NVARCHAR(500) = NULL, @Production9AM INT, @Production12PM INT,
    @Production4PM INT, @TotalProduction INT, @FlockId INT = NULL, @BrokenEggs INT = NULL, @Notes NVARCHAR(MAX) = NULL,
    @EggCount INT = NULL, @EggGrade NVARCHAR(50) = NULL, @MeatyEggs INT = NULL, @SoftEggs INT = NULL, @LostEggs INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @EggCount = ISNULL(@EggCount, @TotalProduction);
    DECLARE @FarmId NVARCHAR(100);
    SELECT @FarmId = FarmId FROM dbo.ProductionRecords WHERE Id = @RecordId;
    BEGIN TRANSACTION;
    UPDATE [dbo].[ProductionRecords]
    SET UpdatedBy=@UpdatedBy, AgeInWeeks=@AgeInWeeks, AgeInDays=@AgeInDays, [Date]=@Date, NoOfBirds=@NoOfBirds, Mortality=@Mortality,
        NoOfBirdsLeft=@NoOfBirdsLeft, FeedKg=@FeedKg, Medication=@Medication, Production9AM=@Production9AM, Production12PM=@Production12PM,
        Production4PM=@Production4PM, TotalProduction=@TotalProduction, FlockId=@FlockId, BrokenEggs=@BrokenEggs, Notes=@Notes,
        EggCount=@EggCount, EggGrade=@EggGrade, MeatyEggs=@MeatyEggs, SoftEggs=@SoftEggs, LostEggs=@LostEggs, UpdatedAt=GETUTCDATE()
    WHERE Id = @RecordId;
    DECLARE @mq2 DECIMAL(14,3) = -CAST(ISNULL(@Mortality,0) AS DECIMAL(14,3));
    IF (@FarmId IS NOT NULL)
        EXEC dbo.spPoultryBirdStock_Sync @FarmId, N'Mortality', @mq2, @RecordId, N'Production mortality', @UpdatedBy;
    COMMIT TRANSACTION;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spProductionRecord_Delete]
    @RecordId INT, @UserId NVARCHAR(100), @FarmId NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRANSACTION;
    EXEC dbo.spPoultryBirdStock_Sync @FarmId, N'Mortality', 0, @RecordId, NULL, @UserId;
    DELETE FROM [dbo].[ProductionRecords] WHERE Id = @RecordId AND FarmId = @FarmId;
    COMMIT TRANSACTION;
END
GO

-- ---- Bird sale -> -birds (detected by product name) -------------------------
CREATE OR ALTER PROCEDURE [dbo].[spSale_Insert]
    @UserId NVARCHAR(100), @FarmId NVARCHAR(100), @SaleDate DATETIME2, @Product NVARCHAR(200), @Quantity DECIMAL(18,2),
    @UnitPrice DECIMAL(18,2), @TotalAmount DECIMAL(18,2), @PaymentMethod NVARCHAR(100) = NULL, @CustomerName NVARCHAR(200) = NULL,
    @FlockId INT = NULL, @SaleDescription NVARCHAR(MAX) = NULL, @Paid BIT = 1, @Size NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRANSACTION;
    INSERT INTO [dbo].[Sale] (UserId, FarmId, SaleDate, Product, Quantity, UnitPrice, TotalAmount, PaymentMethod, CustomerName, FlockId, SaleDescription, Paid, Size, CreatedDate)
    VALUES (@UserId, @FarmId, @SaleDate, @Product, @Quantity, @UnitPrice, @TotalAmount, @PaymentMethod, @CustomerName, @FlockId, @SaleDescription, ISNULL(@Paid,1), @Size, SYSUTCDATETIME());
    DECLARE @NewId INT = CAST(SCOPE_IDENTITY() AS INT);
    -- Bird sale detection: product equals the Birds product name or looks bird-like (not eggs).
    DECLARE @p NVARCHAR(200) = LOWER(ISNULL(@Product, N''));
    IF (@p = N'birds' OR @p LIKE N'%bird%' OR @p LIKE N'%chick%' OR @p LIKE N'%cockerel%') AND @p NOT LIKE N'%egg%' AND ISNULL(@Quantity,0) > 0
    BEGIN
        DECLARE @bq DECIMAL(14,3) = -CAST(@Quantity AS DECIMAL(14,3));
        EXEC dbo.spPoultryBirdStock_Sync @FarmId, N'Bird Sale', @bq, @NewId, N'Bird sale', @UserId;
    END
    COMMIT TRANSACTION;
    SELECT @NewId AS NewId;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spSale_Delete]
    @FarmId VARCHAR(450), @UserId VARCHAR(450), @SaleId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRANSACTION;
    EXEC dbo.spPoultryBirdStock_Sync @FarmId, N'Bird Sale', 0, @SaleId, NULL, @UserId;
    DELETE FROM [dbo].[Sale] WHERE SaleId = @SaleId AND FarmId = @FarmId;
    COMMIT TRANSACTION;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spPoultryProduct_EnsureDefaultBirds TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryBirdStock_Sync TO [Techretainer];
    GRANT EXECUTE ON dbo.spMainFlockBatch_Insert TO [Techretainer];
    GRANT EXECUTE ON dbo.spMainFlockBatch_Delete TO [Techretainer];
    GRANT EXECUTE ON dbo.spProductionRecord_Insert TO [Techretainer];
    GRANT EXECUTE ON dbo.spProductionRecord_Update TO [Techretainer];
    GRANT EXECUTE ON dbo.spProductionRecord_Delete TO [Techretainer];
    GRANT EXECUTE ON dbo.spSale_Insert TO [Techretainer];
    GRANT EXECUTE ON dbo.spSale_Delete TO [Techretainer];
    PRINT '134: granted EXECUTE to Techretainer.';
END
GO

PRINT '134_PoultryBirdsInventory.sql complete.';
GO
