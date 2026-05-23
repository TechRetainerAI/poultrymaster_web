-- MainFlockBatch: Amount Paid column + stored procedures
-- Idempotent — safe to re-run. Aligns with migration 021 / 023.
-- Run against your application database (not master).

SET NOCOUNT ON;
GO

IF COL_LENGTH(N'dbo.MainFlockBatch', N'AmountPaid') IS NULL
BEGIN
    ALTER TABLE [dbo].[MainFlockBatch]
        ADD [AmountPaid] DECIMAL(18, 2) NOT NULL CONSTRAINT [DF_MainFlockBatch_AmountPaid] DEFAULT (0);
    PRINT N'Added MainFlockBatch.AmountPaid';
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spMainFlockBatch_GetAll]
    @UserId NVARCHAR(450),
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        b.[BatchId],
        b.[FarmId],
        b.[UserId],
        b.[BatchCode],
        b.[BatchName],
        b.[Breed],
        b.[NumberOfBirds],
        b.[StartDate],
        b.[CreatedDate],
        b.[Status],
        b.[CostPerChick],
        b.[TotalCost],
        b.[AmountPaid],
        b.[SupplierType],
        b.[SupplierId],
        ISNULL(s.[Name], N'') AS [SupplierName]
    FROM [dbo].[MainFlockBatch] b
    LEFT JOIN [dbo].[Supplier] s
        ON s.[SupplierId] = b.[SupplierId] AND s.[FarmId] = b.[FarmId]
    WHERE b.[FarmId] = @FarmId
    ORDER BY b.[CreatedDate] DESC, b.[BatchId] DESC;
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
        b.[BatchId],
        b.[FarmId],
        b.[UserId],
        b.[BatchCode],
        b.[BatchName],
        b.[Breed],
        b.[NumberOfBirds],
        b.[StartDate],
        b.[CreatedDate],
        b.[Status],
        b.[CostPerChick],
        b.[TotalCost],
        b.[AmountPaid],
        b.[SupplierType],
        b.[SupplierId],
        ISNULL(s.[Name], N'') AS [SupplierName]
    FROM [dbo].[MainFlockBatch] b
    LEFT JOIN [dbo].[Supplier] s
        ON s.[SupplierId] = b.[SupplierId] AND s.[FarmId] = b.[FarmId]
    WHERE b.[BatchId] = @BatchId
      AND b.[FarmId]  = @FarmId;
END
GO

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

PRINT N'create-mainflockbatch-procedures: complete (includes Amount Paid).';
GO
