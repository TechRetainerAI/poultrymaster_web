-- =============================================================================
-- 021_MainFlockBatchPurchaseFields.sql
-- Adds purchase-tracking + status fields to dbo.MainFlockBatch and updates
-- the related stored procedures so the Flock Batches page can store
-- Cost Per Chick, Total Cost, Amount Paid (USD), Supplier Type (local/foreign),
-- Supplier (FK to dbo.Supplier), and an explicit active/inactive/pending Status.
--
-- All new columns are NULLable / defaulted so existing rows and existing
-- callers keep working. Idempotent (safe to re-run).
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
    RAISERROR(N'021: dbo.MainFlockBatch not found. Run earlier migrations first.', 16, 1);
END
GO

-- ---------------------------------------------------------------------------
-- 1. Add new columns
-- ---------------------------------------------------------------------------
IF COL_LENGTH(N'dbo.MainFlockBatch', N'Status') IS NULL
BEGIN
    ALTER TABLE [dbo].[MainFlockBatch]
        ADD [Status] NVARCHAR(20) NOT NULL CONSTRAINT [DF_MainFlockBatch_Status] DEFAULT (N'active');
    PRINT N'021: Added MainFlockBatch.Status';
END
GO

IF COL_LENGTH(N'dbo.MainFlockBatch', N'CostPerChick') IS NULL
BEGIN
    ALTER TABLE [dbo].[MainFlockBatch]
        ADD [CostPerChick] DECIMAL(18, 2) NOT NULL CONSTRAINT [DF_MainFlockBatch_CostPerChick] DEFAULT (0);
    PRINT N'021: Added MainFlockBatch.CostPerChick';
END
GO

IF COL_LENGTH(N'dbo.MainFlockBatch', N'TotalCost') IS NULL
BEGIN
    ALTER TABLE [dbo].[MainFlockBatch]
        ADD [TotalCost] DECIMAL(18, 2) NOT NULL CONSTRAINT [DF_MainFlockBatch_TotalCost] DEFAULT (0);
    PRINT N'021: Added MainFlockBatch.TotalCost';
END
GO

IF COL_LENGTH(N'dbo.MainFlockBatch', N'AmountPaid') IS NULL
BEGIN
    ALTER TABLE [dbo].[MainFlockBatch]
        ADD [AmountPaid] DECIMAL(18, 2) NOT NULL CONSTRAINT [DF_MainFlockBatch_AmountPaid] DEFAULT (0);
    PRINT N'021: Added MainFlockBatch.AmountPaid';
END
GO

IF COL_LENGTH(N'dbo.MainFlockBatch', N'SupplierType') IS NULL
BEGIN
    ALTER TABLE [dbo].[MainFlockBatch] ADD [SupplierType] NVARCHAR(20) NULL;
    PRINT N'021: Added MainFlockBatch.SupplierType';
END
GO

IF COL_LENGTH(N'dbo.MainFlockBatch', N'SupplierId') IS NULL
BEGIN
    ALTER TABLE [dbo].[MainFlockBatch] ADD [SupplierId] INT NULL;
    PRINT N'021: Added MainFlockBatch.SupplierId';
END
GO

-- Helpful filter for the score-card / status filter on the UI
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_MainFlockBatch_FarmId_Status'
      AND object_id = OBJECT_ID(N'[dbo].[MainFlockBatch]')
)
BEGIN
    CREATE NONCLUSTERED INDEX [IX_MainFlockBatch_FarmId_Status]
        ON [dbo].[MainFlockBatch]([FarmId], [Status]);
    PRINT N'021: Created index IX_MainFlockBatch_FarmId_Status';
END
GO

-- ---------------------------------------------------------------------------
-- 2. Stored procedures (CREATE OR ALTER — back-compat parameter ordering:
--    existing params first, new params at the end with defaults).
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

    -- Auto-compute TotalCost when caller leaves it as the default.
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

-- Delete sp is unchanged in shape; CREATE OR ALTER for completeness so this
-- migration can rebuild the proc surface from one file.
CREATE OR ALTER PROCEDURE [dbo].[spMainFlockBatch_Delete]
    @BatchId INT,
    @UserId  NVARCHAR(450),
    @FarmId  NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM [dbo].[MainFlockBatch]
    WHERE [BatchId] = @BatchId
      AND [FarmId]  = @FarmId;
END
GO

PRINT N'021_MainFlockBatchPurchaseFields: complete.';
GO
