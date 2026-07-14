-- =============================================================================
-- Migration 150: Flock batch — order placement & estimated arrival dates
-- =============================================================================
-- The "Add New Flock Batch" dialog now captures procurement timing for a bird
-- purchase: when the order was placed and when the birds are expected to arrive.
-- Payment (TotalCost / AmountPaid, part payment supported since 023) is unchanged;
-- this migration only adds the two nullable date columns and threads them through
-- the Insert/Update/GetById/GetAll procedures.
--
-- Insert/Update bodies are copied from migration 142 (bird-stock sync + expense
-- sync preserved) with the two new parameters/columns added. GetById/GetAll are
-- copied from migration 024 with the two columns added to the projection.
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

IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[MainFlockBatch]') AND type = N'U')
BEGIN
    RAISERROR(N'150: dbo.MainFlockBatch not found. Run earlier migrations first.', 16, 1);
END
GO

IF COL_LENGTH(N'dbo.MainFlockBatch', N'OrderPlacementDate') IS NULL
BEGIN
    ALTER TABLE [dbo].[MainFlockBatch] ADD [OrderPlacementDate] DATE NULL;
    PRINT N'150: Added MainFlockBatch.OrderPlacementDate';
END
GO

IF COL_LENGTH(N'dbo.MainFlockBatch', N'EstimatedArrivalDate') IS NULL
BEGIN
    ALTER TABLE [dbo].[MainFlockBatch] ADD [EstimatedArrivalDate] DATE NULL;
    PRINT N'150: Added MainFlockBatch.EstimatedArrivalDate';
END
GO

-- ---------------------------------------------------------------------------
-- Insert — carries 142's bird + expense sync, plus the two new dates.
-- ---------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[spMainFlockBatch_Insert]
    @UserId NVARCHAR(450), @FarmId NVARCHAR(450), @BatchCode NVARCHAR(25), @BatchName NVARCHAR(100),
    @Breed NVARCHAR(50), @NumberOfBirds INT, @StartDate DATETIME2, @Status NVARCHAR(20) = N'active',
    @CostPerChick DECIMAL(18,2) = 0, @TotalCost DECIMAL(18,2) = 0, @SupplierType NVARCHAR(20) = NULL,
    @SupplierId INT = NULL, @AmountPaid DECIMAL(18,2) = 0, @Notes NVARCHAR(MAX) = NULL,
    @OrderPlacementDate DATE = NULL, @EstimatedArrivalDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF (@TotalCost IS NULL OR @TotalCost = 0) AND @CostPerChick > 0 SET @TotalCost = @CostPerChick * @NumberOfBirds;
    BEGIN TRANSACTION;
    INSERT INTO [dbo].[MainFlockBatch] (UserId, FarmId, BatchCode, BatchName, Breed, NumberOfBirds, StartDate, Status, CostPerChick, TotalCost, AmountPaid, SupplierType, SupplierId, Notes, OrderPlacementDate, EstimatedArrivalDate, CreatedDate)
    VALUES (@UserId, @FarmId, @BatchCode, @BatchName, @Breed, @NumberOfBirds, @StartDate, ISNULL(@Status, N'active'), ISNULL(@CostPerChick,0), ISNULL(@TotalCost,0), ISNULL(@AmountPaid,0), @SupplierType, @SupplierId, @Notes, @OrderPlacementDate, @EstimatedArrivalDate, SYSUTCDATETIME());
    DECLARE @NewId INT = CAST(SCOPE_IDENTITY() AS INT);

    IF (ISNULL(@NumberOfBirds,0) > 0)
        EXEC dbo.spPoultryBirdStock_Sync @FarmId, N'Bird Batch Purchase', @NumberOfBirds, @NewId, N'Flock batch purchase', @UserId;

    EXEC dbo.spFlockBatchExpense_Sync @FarmId, @NewId, @TotalCost, @StartDate, @BatchName, @NumberOfBirds, @UserId;

    COMMIT TRANSACTION;
    SELECT @NewId;
END
GO

-- ---------------------------------------------------------------------------
-- Update — carries 142's bird + expense re-sync, plus the two new dates.
-- ---------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[spMainFlockBatch_Update]
    @BatchId INT, @UserId NVARCHAR(450), @FarmId NVARCHAR(450), @BatchCode NVARCHAR(25), @BatchName NVARCHAR(100),
    @Breed NVARCHAR(50), @NumberOfBirds INT, @StartDate DATETIME2, @Status NVARCHAR(20) = N'active',
    @CostPerChick DECIMAL(18,2) = 0, @TotalCost DECIMAL(18,2) = 0, @SupplierType NVARCHAR(20) = NULL,
    @SupplierId INT = NULL, @AmountPaid DECIMAL(18,2) = 0, @Notes NVARCHAR(MAX) = NULL,
    @OrderPlacementDate DATE = NULL, @EstimatedArrivalDate DATE = NULL
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
        [SupplierId]=@SupplierId, [Notes]=@Notes,
        [OrderPlacementDate]=@OrderPlacementDate, [EstimatedArrivalDate]=@EstimatedArrivalDate
    WHERE [BatchId]=@BatchId AND [FarmId]=@FarmId;

    -- Re-sync the bird stock movement to the (possibly changed) bird count.
    EXEC dbo.spPoultryBirdStock_Sync @FarmId, N'Bird Batch Purchase', @NumberOfBirds, @BatchId, N'Flock batch purchase', @UserId;
    -- Re-sync the linked expense.
    EXEC dbo.spFlockBatchExpense_Sync @FarmId, @BatchId, @TotalCost, @StartDate, @BatchName, @NumberOfBirds, @UserId;
    COMMIT TRANSACTION;
END
GO

-- ---------------------------------------------------------------------------
-- GetById / GetAll — project the two new columns alongs''''''''''''''ide the existing shape.
-- ---------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[spMainFlockBatch_GetById]
    @BatchId INT,
    @UserId  NVARCHAR(450),
    @FarmId  NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        b.[BatchId], b.[UserId], b.[FarmId], b.[BatchCode], b.[BatchName],
        b.[Breed], b.[NumberOfBirds], b.[StartDate], b.[CreatedDate],
        b.[Status], b.[CostPerChick], b.[TotalCost], b.[AmountPaid],
        b.[SupplierType], b.[SupplierId], b.[Notes],
        b.[OrderPlacementDate], b.[EstimatedArrivalDate],
        ISNULL(s.[Name], N'') AS [SupplierName]
    FROM [dbo].[MainFlockBatch] b
    LEFT JOIN [dbo].[Supplier] s
        ON s.[SupplierId] = b.[SupplierId] AND s.[FarmId] = b.[FarmId]
    WHERE b.[BatchId] = @BatchId
      AND b.[FarmId]  = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spMainFlockBatch_GetAll]
    @UserId NVARCHAR(450),
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        b.[BatchId], b.[UserId], b.[FarmId], b.[BatchCode], b.[BatchName],
        b.[Breed], b.[NumberOfBirds], b.[StartDate], b.[CreatedDate],
        b.[Status], b.[CostPerChick], b.[TotalCost], b.[AmountPaid],
        b.[SupplierType], b.[SupplierId], b.[Notes],
        b.[OrderPlacementDate], b.[EstimatedArrivalDate],
        ISNULL(s.[Name], N'') AS [SupplierName]
    FROM [dbo].[MainFlockBatch] b
    LEFT JOIN [dbo].[Supplier] s
        ON s.[SupplierId] = b.[SupplierId] AND s.[FarmId] = b.[FarmId]
    WHERE b.[FarmId] = @FarmId
    ORDER BY b.[CreatedDate] DESC, b.[BatchId] DESC;
END
GO

PRINT N'Migration 150 applied: flock batch order placement + estimated arrival dates.';
GO
