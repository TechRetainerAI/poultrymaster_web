-- =============================================================================
-- 023_MainFlockBatchAmountPaid.sql
-- Adds AmountPaid column to dbo.MainFlockBatch so the UI can record how much
-- has actually been paid for a batch (may differ from TotalCost during partial
-- payments). Updates spMainFlockBatch_Insert / _Update / _GetById / _GetAll so
-- the value round-trips.
--
-- Idempotent (safe to re-run). Column is NOT NULL with a 0 default so existing
-- rows are unaffected.
-- =============================================================================

IF DB_NAME() IN (N'master', N'model', N'msdb', N'tempdb')
BEGIN
    THROW 50000, N'Select your application database (not master). Aborting.', 1;
END
GO

SET NOCOUNT ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[MainFlockBatch]') AND type = N'U')
BEGIN
    RAISERROR(N'023: dbo.MainFlockBatch not found. Run earlier migrations first.', 16, 1);
END
GO

-- ---------------------------------------------------------------------------
-- 1. Add AmountPaid column
-- ---------------------------------------------------------------------------
IF COL_LENGTH(N'dbo.MainFlockBatch', N'AmountPaid') IS NULL
BEGIN
    ALTER TABLE [dbo].[MainFlockBatch]
        ADD [AmountPaid] DECIMAL(18, 2) NOT NULL CONSTRAINT [DF_MainFlockBatch_AmountPaid] DEFAULT (0);
    PRINT N'023: Added MainFlockBatch.AmountPaid';
END
GO

-- ---------------------------------------------------------------------------
-- 2. Stored procedures (CREATE OR ALTER — new param appended at end with
--    default so old callers continue to work).
-- ---------------------------------------------------------------------------

CREATE OR ALTER PROCEDURE [dbo].[spMainFlockBatch_Insert]
    @UserId        NVARCHAR(450),
    @FarmId        NVARCHAR(450),
    @BatchCode     NVARCHAR(25),
    @BatchName     NVARCHAR(100),
    @Breed         NVARCHAR(50),
    @NumberOfBirds INT,
    @StartDate     DATETIME2,
    @Status        NVARCHAR(20)    = N'active',
    @CostPerChick  DECIMAL(18, 2)  = 0,
    @TotalCost     DECIMAL(18, 2)  = 0,
    @SupplierType  NVARCHAR(20)    = NULL,
    @SupplierId    INT             = NULL,
    @AmountPaid    DECIMAL(18, 2)  = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF (@TotalCost IS NULL OR @TotalCost = 0) AND @CostPerChick > 0
        SET @TotalCost = @CostPerChick * @NumberOfBirds;

    INSERT INTO [dbo].[MainFlockBatch]
    (
        [UserId], [FarmId], [BatchCode], [BatchName], [Breed],
        [NumberOfBirds], [StartDate], [Status],
        [CostPerChick], [TotalCost], [AmountPaid], [SupplierType], [SupplierId],
        [CreatedDate]
    )
    VALUES
    (
        @UserId, @FarmId, @BatchCode, @BatchName, @Breed,
        @NumberOfBirds, @StartDate, ISNULL(@Status, N'active'),
        ISNULL(@CostPerChick, 0), ISNULL(@TotalCost, 0), ISNULL(@AmountPaid, 0),
        @SupplierType, @SupplierId,
        SYSUTCDATETIME()
    );

    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spMainFlockBatch_Update]
    @BatchId       INT,
    @UserId        NVARCHAR(450),
    @FarmId        NVARCHAR(450),
    @BatchCode     NVARCHAR(25),
    @BatchName     NVARCHAR(100),
    @Breed         NVARCHAR(50),
    @NumberOfBirds INT,
    @StartDate     DATETIME2,
    @Status        NVARCHAR(20)    = N'active',
    @CostPerChick  DECIMAL(18, 2)  = 0,
    @TotalCost     DECIMAL(18, 2)  = 0,
    @SupplierType  NVARCHAR(20)    = NULL,
    @SupplierId    INT             = NULL,
    @AmountPaid    DECIMAL(18, 2)  = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF (@TotalCost IS NULL OR @TotalCost = 0) AND @CostPerChick > 0
        SET @TotalCost = @CostPerChick * @NumberOfBirds;

    UPDATE [dbo].[MainFlockBatch]
    SET
        [BatchCode]     = @BatchCode,
        [BatchName]     = @BatchName,
        [Breed]         = @Breed,
        [NumberOfBirds] = @NumberOfBirds,
        [StartDate]     = @StartDate,
        [Status]        = ISNULL(@Status, [Status]),
        [CostPerChick]  = ISNULL(@CostPerChick, 0),
        [TotalCost]     = ISNULL(@TotalCost, 0),
        [AmountPaid]    = ISNULL(@AmountPaid, 0),
        [SupplierType]  = @SupplierType,
        [SupplierId]    = @SupplierId
    WHERE [BatchId] = @BatchId
      AND [FarmId]  = @FarmId;
END
GO

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
        b.[SupplierType], b.[SupplierId],
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
        b.[SupplierType], b.[SupplierId],
        ISNULL(s.[Name], N'') AS [SupplierName]
    FROM [dbo].[MainFlockBatch] b
    LEFT JOIN [dbo].[Supplier] s
        ON s.[SupplierId] = b.[SupplierId] AND s.[FarmId] = b.[FarmId]
    WHERE b.[FarmId] = @FarmId
    ORDER BY b.[CreatedDate] DESC, b.[BatchId] DESC;
END
GO

PRINT N'023_MainFlockBatchAmountPaid: complete.';
GO
