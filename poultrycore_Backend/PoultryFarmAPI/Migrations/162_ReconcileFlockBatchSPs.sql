-- =============================================================================
-- Migration 162: reconcile the flock-batch SPs after the Enock↔dev merge
-- =============================================================================
-- Two features landed on the same four SPs from different branches:
--   * 150/151 (Enock): OrderPlacementDate + EstimatedArrivalDate columns, and a
--     PART-PAYMENT accounting model — the batch's initial expense records the
--     down-payment (@AmountPaid), the rest is booked later via
--     spMainFlockBatch_PayBalance.
--   * 160 (dev): DollarConversionRate column (USD-priced foreign purchases).
-- Because 160 is numbered higher it ran last and its CREATE OR ALTER dropped
-- Enock's date params AND reverted the expense sync to full @TotalCost. This
-- migration is the single source of truth going forward: it redefines Insert,
-- Update, GetAll and GetById with the UNION of both feature sets, on top of
-- 151's part-payment logic (the agreed accounting model). PayBalance (151) is
-- unchanged and intentionally not redefined here. Idempotent: guarded column
-- adds + CREATE OR ALTER. Additive only.
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- Columns from both features (no-ops if 150/160 already added them).
IF COL_LENGTH(N'dbo.MainFlockBatch', N'OrderPlacementDate') IS NULL
    ALTER TABLE dbo.MainFlockBatch ADD OrderPlacementDate DATE NULL;
GO
IF COL_LENGTH(N'dbo.MainFlockBatch', N'EstimatedArrivalDate') IS NULL
    ALTER TABLE dbo.MainFlockBatch ADD EstimatedArrivalDate DATE NULL;
GO
IF COL_LENGTH(N'dbo.MainFlockBatch', N'DollarConversionRate') IS NULL
    ALTER TABLE dbo.MainFlockBatch ADD DollarConversionRate DECIMAL(18,4) NULL;
GO

-- ---------------------------------------------------------------------------
-- Insert — part-payment expense (=@AmountPaid, per 151) + all three new fields.
-- ---------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[spMainFlockBatch_Insert]
    @UserId NVARCHAR(450), @FarmId NVARCHAR(450), @BatchCode NVARCHAR(25), @BatchName NVARCHAR(100),
    @Breed NVARCHAR(50), @NumberOfBirds INT, @StartDate DATETIME2, @Status NVARCHAR(20) = N'active',
    @CostPerChick DECIMAL(18,2) = 0, @TotalCost DECIMAL(18,2) = 0, @SupplierType NVARCHAR(20) = NULL,
    @SupplierId INT = NULL, @AmountPaid DECIMAL(18,2) = 0, @Notes NVARCHAR(MAX) = NULL,
    @OrderPlacementDate DATE = NULL, @EstimatedArrivalDate DATE = NULL,
    @DollarConversionRate DECIMAL(18,4) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF (@TotalCost IS NULL OR @TotalCost = 0) AND @CostPerChick > 0 SET @TotalCost = @CostPerChick * @NumberOfBirds;
    IF (@AmountPaid IS NULL) SET @AmountPaid = 0;
    IF (@TotalCost IS NOT NULL AND @AmountPaid > @TotalCost) SET @AmountPaid = @TotalCost;
    BEGIN TRANSACTION;
    INSERT INTO [dbo].[MainFlockBatch] (UserId, FarmId, BatchCode, BatchName, Breed, NumberOfBirds, StartDate, Status, CostPerChick, TotalCost, AmountPaid, SupplierType, SupplierId, Notes, OrderPlacementDate, EstimatedArrivalDate, DollarConversionRate, CreatedDate)
    VALUES (@UserId, @FarmId, @BatchCode, @BatchName, @Breed, @NumberOfBirds, @StartDate, ISNULL(@Status, N'active'), ISNULL(@CostPerChick,0), ISNULL(@TotalCost,0), ISNULL(@AmountPaid,0), @SupplierType, @SupplierId, @Notes, @OrderPlacementDate, @EstimatedArrivalDate, @DollarConversionRate, SYSUTCDATETIME());
    DECLARE @NewId INT = CAST(SCOPE_IDENTITY() AS INT);

    IF (ISNULL(@NumberOfBirds,0) > 0)
        EXEC dbo.spPoultryBirdStock_Sync @FarmId, N'Bird Batch Purchase', @NumberOfBirds, @NewId, N'Flock batch purchase', @UserId;

    -- Expense = cash actually paid (down payment). Brand-new batch, so the sync's
    -- delete-for-source is a no-op; it then posts one expense = @AmountPaid.
    EXEC dbo.spFlockBatchExpense_Sync @FarmId, @NewId, @AmountPaid, @StartDate, @BatchName, @NumberOfBirds, @UserId;

    COMMIT TRANSACTION;
    SELECT @NewId;
END
GO

-- ---------------------------------------------------------------------------
-- Update — keeps 151's initial-expense-minus-balance-payments logic + all three fields.
-- ---------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[spMainFlockBatch_Update]
    @BatchId INT, @UserId NVARCHAR(450), @FarmId NVARCHAR(450), @BatchCode NVARCHAR(25), @BatchName NVARCHAR(100),
    @Breed NVARCHAR(50), @NumberOfBirds INT, @StartDate DATETIME2, @Status NVARCHAR(20) = N'active',
    @CostPerChick DECIMAL(18,2) = 0, @TotalCost DECIMAL(18,2) = 0, @SupplierType NVARCHAR(20) = NULL,
    @SupplierId INT = NULL, @AmountPaid DECIMAL(18,2) = 0, @Notes NVARCHAR(MAX) = NULL,
    @OrderPlacementDate DATE = NULL, @EstimatedArrivalDate DATE = NULL,
    @DollarConversionRate DECIMAL(18,4) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF (@TotalCost IS NULL OR @TotalCost = 0) AND @CostPerChick > 0 SET @TotalCost = @CostPerChick * @NumberOfBirds;
    IF (@AmountPaid IS NULL) SET @AmountPaid = 0;
    BEGIN TRANSACTION;
    UPDATE [dbo].[MainFlockBatch]
    SET [BatchCode]=@BatchCode, [BatchName]=@BatchName, [Breed]=@Breed, [NumberOfBirds]=@NumberOfBirds,
        [StartDate]=@StartDate, [Status]=ISNULL(@Status,[Status]), [CostPerChick]=ISNULL(@CostPerChick,0),
        [TotalCost]=ISNULL(@TotalCost,0), [AmountPaid]=ISNULL(@AmountPaid,0), [SupplierType]=@SupplierType,
        [SupplierId]=@SupplierId, [Notes]=@Notes,
        [OrderPlacementDate]=@OrderPlacementDate, [EstimatedArrivalDate]=@EstimatedArrivalDate,
        [DollarConversionRate]=@DollarConversionRate
    WHERE [BatchId]=@BatchId AND [FarmId]=@FarmId;

    -- Re-sync the bird stock movement to the (possibly changed) bird count.
    EXEC dbo.spPoultryBirdStock_Sync @FarmId, N'Bird Batch Purchase', @NumberOfBirds, @BatchId, N'Flock batch purchase', @UserId;

    -- Keep the initial linked expense in sync without touching balance payments.
    DECLARE @Gid UNIQUEIDENTIFIER = TRY_CAST(@FarmId AS UNIQUEIDENTIFIER);
    IF (@Gid IS NOT NULL)
    BEGIN
        DECLARE @InitExpId INT =
            (SELECT MIN(ExpenseId) FROM dbo.Expense
             WHERE FarmId = @Gid AND SourceType = N'MainFlockBatch' AND SourceId = @BatchId);
        -- Amounts already booked via later balance-payment rows.
        DECLARE @OtherPaid DECIMAL(18,2) =
            (SELECT ISNULL(SUM(Amount),0) FROM dbo.Expense
             WHERE FarmId = @Gid AND SourceType = N'MainFlockBatch' AND SourceId = @BatchId
               AND (@InitExpId IS NULL OR ExpenseId <> @InitExpId));
        DECLARE @InitAmount DECIMAL(18,2) = @AmountPaid - @OtherPaid;
        IF (@InitAmount < 0) SET @InitAmount = 0;

        DECLARE @Desc NVARCHAR(400) =
            CONCAT(N'Flock batch purchase: ', ISNULL(@BatchName, N'batch'),
                   N' (', CAST(ISNULL(@NumberOfBirds,0) AS NVARCHAR(30)), N' birds)');

        IF (@InitExpId IS NOT NULL)
            UPDATE dbo.Expense
            SET Amount = @InitAmount, ExpenseDate = @StartDate, Description = @Desc
            WHERE ExpenseId = @InitExpId;
        ELSE IF (@InitAmount > 0 AND @UserId IS NOT NULL)
            INSERT INTO dbo.Expense (ExpenseDate, Category, Description, Amount, PaymentMethod, Supplier, FlockId, CreatedDate, UserId, FarmId, SourceType, SourceId)
            VALUES (@StartDate, N'Flock / Bird Purchase', @Desc, @InitAmount, N'Cash', NULL, NULL, SYSUTCDATETIME(), @UserId, @Gid, N'MainFlockBatch', @BatchId);
    END

    COMMIT TRANSACTION;
END
GO

-- ---------------------------------------------------------------------------
-- GetAll / GetById — project all three new columns alongside the existing shape.
-- ---------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[spMainFlockBatch_GetAll]
    @UserId NVARCHAR(450), @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        b.[BatchId], b.[UserId], b.[FarmId], b.[BatchCode], b.[BatchName],
        b.[Breed], b.[NumberOfBirds], b.[StartDate], b.[CreatedDate],
        b.[Status], b.[CostPerChick], b.[TotalCost], b.[AmountPaid],
        b.[SupplierType], b.[SupplierId], b.[Notes],
        b.[OrderPlacementDate], b.[EstimatedArrivalDate], b.[DollarConversionRate],
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
        b.[SupplierType], b.[SupplierId], b.[Notes],
        b.[OrderPlacementDate], b.[EstimatedArrivalDate], b.[DollarConversionRate],
        ISNULL(s.[Name], N'') AS [SupplierName]
    FROM [dbo].[MainFlockBatch] b
    LEFT JOIN [dbo].[Supplier] s ON s.[SupplierId] = b.[SupplierId] AND s.[FarmId] = b.[FarmId]
    WHERE b.[BatchId] = @BatchId AND b.[FarmId] = @FarmId;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spMainFlockBatch_Insert  TO [Techretainer];
    GRANT EXECUTE ON dbo.spMainFlockBatch_Update  TO [Techretainer];
    GRANT EXECUTE ON dbo.spMainFlockBatch_GetAll  TO [Techretainer];
    GRANT EXECUTE ON dbo.spMainFlockBatch_GetById TO [Techretainer];
END
GO

PRINT '162_ReconcileFlockBatchSPs.sql complete.';
GO
