-- =============================================================================
-- Migration 160: Dollar Conversion Rate on flock batch purchases (James)
-- =============================================================================
-- Add an optional DollarConversionRate to MainFlockBatch (e.g. for foreign
-- supplier purchases priced in USD). Additive column + SP params; Get SPs return
-- it. Nothing else changes.
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF COL_LENGTH('dbo.MainFlockBatch','DollarConversionRate') IS NULL
    ALTER TABLE dbo.MainFlockBatch ADD DollarConversionRate DECIMAL(18,4) NULL;
GO

CREATE OR ALTER PROCEDURE [dbo].[spMainFlockBatch_Insert]
    @UserId NVARCHAR(450), @FarmId NVARCHAR(450), @BatchCode NVARCHAR(25), @BatchName NVARCHAR(100),
    @Breed NVARCHAR(50), @NumberOfBirds INT, @StartDate DATETIME2, @Status NVARCHAR(20) = N'active',
    @CostPerChick DECIMAL(18,2) = 0, @TotalCost DECIMAL(18,2) = 0, @SupplierType NVARCHAR(20) = NULL,
    @SupplierId INT = NULL, @AmountPaid DECIMAL(18,2) = 0, @Notes NVARCHAR(MAX) = NULL,
    @DollarConversionRate DECIMAL(18,4) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF (@TotalCost IS NULL OR @TotalCost = 0) AND @CostPerChick > 0 SET @TotalCost = @CostPerChick * @NumberOfBirds;
    BEGIN TRANSACTION;
    INSERT INTO [dbo].[MainFlockBatch] (UserId, FarmId, BatchCode, BatchName, Breed, NumberOfBirds, StartDate, Status, CostPerChick, TotalCost, AmountPaid, SupplierType, SupplierId, Notes, DollarConversionRate, CreatedDate)
    VALUES (@UserId, @FarmId, @BatchCode, @BatchName, @Breed, @NumberOfBirds, @StartDate, ISNULL(@Status, N'active'), ISNULL(@CostPerChick,0), ISNULL(@TotalCost,0), ISNULL(@AmountPaid,0), @SupplierType, @SupplierId, @Notes, @DollarConversionRate, SYSUTCDATETIME());
    DECLARE @NewId INT = CAST(SCOPE_IDENTITY() AS INT);
    IF (ISNULL(@NumberOfBirds,0) > 0)
        EXEC dbo.spPoultryBirdStock_Sync @FarmId, N'Bird Batch Purchase', @NumberOfBirds, @NewId, N'Flock batch purchase', @UserId;
    EXEC dbo.spFlockBatchExpense_Sync @FarmId, @NewId, @TotalCost, @StartDate, @BatchName, @NumberOfBirds, @UserId;
    COMMIT TRANSACTION;
    SELECT @NewId;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spMainFlockBatch_Update]
    @BatchId INT, @UserId NVARCHAR(450), @FarmId NVARCHAR(450), @BatchCode NVARCHAR(25), @BatchName NVARCHAR(100),
    @Breed NVARCHAR(50), @NumberOfBirds INT, @StartDate DATETIME2, @Status NVARCHAR(20) = N'active',
    @CostPerChick DECIMAL(18,2) = 0, @TotalCost DECIMAL(18,2) = 0, @SupplierType NVARCHAR(20) = NULL,
    @SupplierId INT = NULL, @AmountPaid DECIMAL(18,2) = 0, @Notes NVARCHAR(MAX) = NULL,
    @DollarConversionRate DECIMAL(18,4) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF (@TotalCost IS NULL OR @TotalCost = 0) AND @CostPerChick > 0 SET @TotalCost = @CostPerChick * @NumberOfBirds;
    BEGIN TRANSACTION;
    UPDATE [dbo].[MainFlockBatch]
    SET [BatchCode]=@BatchCode, [BatchName]=@BatchName, [Breed]=@Breed, [NumberOfBirds]=@NumberOfBirds,
        [StartDate]=@StartDate, [Status]=ISNULL(@Status,[Status]), [CostPerChick]=ISNULL(@CostPerChick,0),
        [TotalCost]=ISNULL(@TotalCost,0), [AmountPaid]=ISNULL(@AmountPaid,0), [SupplierType]=@SupplierType,
        [SupplierId]=@SupplierId, [Notes]=@Notes, [DollarConversionRate]=@DollarConversionRate
    WHERE [BatchId]=@BatchId AND [FarmId]=@FarmId;
    EXEC dbo.spPoultryBirdStock_Sync @FarmId, N'Bird Batch Purchase', @NumberOfBirds, @BatchId, N'Flock batch purchase', @UserId;
    EXEC dbo.spFlockBatchExpense_Sync @FarmId, @BatchId, @TotalCost, @StartDate, @BatchName, @NumberOfBirds, @UserId;
    COMMIT TRANSACTION;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spMainFlockBatch_GetAll]
    @UserId NVARCHAR(450), @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        b.[BatchId], b.[UserId], b.[FarmId], b.[BatchCode], b.[BatchName],
        b.[Breed], b.[NumberOfBirds], b.[StartDate], b.[CreatedDate],
        b.[Status], b.[CostPerChick], b.[TotalCost], b.[AmountPaid],
        b.[SupplierType], b.[SupplierId], b.[Notes], b.[DollarConversionRate],
        ISNULL(s.[Name], N'') AS [SupplierName]
    FROM [dbo].[MainFlockBatch] b
    LEFT JOIN [dbo].[Supplier] s ON s.[SupplierId] = b.[SupplierId] AND s.[FarmId] = b.[FarmId]
    WHERE b.[FarmId] = @FarmId
    ORDER BY b.[CreatedDate] DESC, b.[BatchId] DESC;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spMainFlockBatch_GetById]
    @BatchId INT, @UserId NVARCHAR(450), @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        b.[BatchId], b.[UserId], b.[FarmId], b.[BatchCode], b.[BatchName],
        b.[Breed], b.[NumberOfBirds], b.[StartDate], b.[CreatedDate],
        b.[Status], b.[CostPerChick], b.[TotalCost], b.[AmountPaid],
        b.[SupplierType], b.[SupplierId], b.[Notes], b.[DollarConversionRate],
        ISNULL(s.[Name], N'') AS [SupplierName]
    FROM [dbo].[MainFlockBatch] b
    LEFT JOIN [dbo].[Supplier] s ON s.[SupplierId] = b.[SupplierId] AND s.[FarmId] = b.[FarmId]
    WHERE b.[BatchId] = @BatchId AND b.[FarmId] = @FarmId;
END
GO

PRINT '160_FlockBatchDollarConversionRate.sql complete.';
GO
