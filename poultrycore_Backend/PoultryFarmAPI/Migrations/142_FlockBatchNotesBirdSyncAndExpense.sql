-- =============================================================================
-- Migration 142: Flock batch — fix insert, sync birds on edit, create expense
-- =============================================================================
-- Three fixes reported on dev:
--  1. Adding a batch failed ("Error inserting Main Flock Batch record") because
--     the C# service passes @Notes but spMainFlockBatch_Insert had no @Notes
--     parameter (too many arguments). Add @Notes (the MainFlockBatch.Notes
--     column already exists).
--  2. Editing a batch did not change the birds inventory / stock movement —
--     spMainFlockBatch_Update never called the bird-stock sync. Add it (re-syncs
--     the 'Bird Batch Purchase' movement to the new NumberOfBirds).
--  3. A batch purchase should create an Expense record (like raw-material
--     purchases). Insert/Update post an idempotent expense; Delete reverses it.
--     dbo.Expense.FarmId is UNIQUEIDENTIFIER, so TRY_CAST the nvarchar farmId.
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- Helper: idempotently post/replace the expense for a flock batch purchase.
CREATE OR ALTER PROCEDURE dbo.spFlockBatchExpense_Sync
    @FarmId NVARCHAR(450), @BatchId INT, @Amount DECIMAL(18,2), @Date DATETIME2,
    @BatchName NVARCHAR(100), @NumberOfBirds INT, @CreatedBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Gid UNIQUEIDENTIFIER = TRY_CAST(@FarmId AS UNIQUEIDENTIFIER);
    IF (@Gid IS NULL) RETURN;  -- Expense.FarmId is a GUID; skip if farmId isn't one.

    -- Idempotent: drop any prior batch-purchase expense for this batch.
    DELETE FROM dbo.Expense WHERE FarmId = @Gid AND SourceType = N'MainFlockBatch' AND SourceId = @BatchId;

    IF (ISNULL(@Amount,0) <= 0) RETURN;

    INSERT INTO dbo.Expense (ExpenseDate, Category, Description, Amount, PaymentMethod, Supplier, FlockId, CreatedDate, UserId, FarmId, SourceType, SourceId)
    VALUES (ISNULL(@Date, SYSUTCDATETIME()), N'Flock / Bird Purchase',
            CONCAT(N'Flock batch purchase: ', ISNULL(@BatchName, N'batch'), N' (', CAST(ISNULL(@NumberOfBirds,0) AS NVARCHAR(30)), N' birds)'),
            @Amount, N'Cash', NULL, NULL, SYSUTCDATETIME(), @CreatedBy, @Gid, N'MainFlockBatch', @BatchId);
END
GO
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'Techretainer')
    GRANT EXECUTE ON dbo.spFlockBatchExpense_Sync TO [Techretainer];
GO

-- ---------------------------------------------------------------------------
-- Insert — add @Notes (fixes the error), keep bird sync, add expense.
-- ---------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[spMainFlockBatch_Insert]
    @UserId NVARCHAR(450), @FarmId NVARCHAR(450), @BatchCode NVARCHAR(25), @BatchName NVARCHAR(100),
    @Breed NVARCHAR(50), @NumberOfBirds INT, @StartDate DATETIME2, @Status NVARCHAR(20) = N'active',
    @CostPerChick DECIMAL(18,2) = 0, @TotalCost DECIMAL(18,2) = 0, @SupplierType NVARCHAR(20) = NULL,
    @SupplierId INT = NULL, @AmountPaid DECIMAL(18,2) = 0, @Notes NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF (@TotalCost IS NULL OR @TotalCost = 0) AND @CostPerChick > 0 SET @TotalCost = @CostPerChick * @NumberOfBirds;
    BEGIN TRANSACTION;
    INSERT INTO [dbo].[MainFlockBatch] (UserId, FarmId, BatchCode, BatchName, Breed, NumberOfBirds, StartDate, Status, CostPerChick, TotalCost, AmountPaid, SupplierType, SupplierId, Notes, CreatedDate)
    VALUES (@UserId, @FarmId, @BatchCode, @BatchName, @Breed, @NumberOfBirds, @StartDate, ISNULL(@Status, N'active'), ISNULL(@CostPerChick,0), ISNULL(@TotalCost,0), ISNULL(@AmountPaid,0), @SupplierType, @SupplierId, @Notes, SYSUTCDATETIME());
    DECLARE @NewId INT = CAST(SCOPE_IDENTITY() AS INT);

    IF (ISNULL(@NumberOfBirds,0) > 0)
        EXEC dbo.spPoultryBirdStock_Sync @FarmId, N'Bird Batch Purchase', @NumberOfBirds, @NewId, N'Flock batch purchase', @UserId;

    EXEC dbo.spFlockBatchExpense_Sync @FarmId, @NewId, @TotalCost, @StartDate, @BatchName, @NumberOfBirds, @UserId;

    COMMIT TRANSACTION;
    SELECT @NewId;
END
GO

-- ---------------------------------------------------------------------------
-- Update — re-sync birds + expense (was missing entirely).
-- ---------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[spMainFlockBatch_Update]
    @BatchId INT, @UserId NVARCHAR(450), @FarmId NVARCHAR(450), @BatchCode NVARCHAR(25), @BatchName NVARCHAR(100),
    @Breed NVARCHAR(50), @NumberOfBirds INT, @StartDate DATETIME2, @Status NVARCHAR(20) = N'active',
    @CostPerChick DECIMAL(18,2) = 0, @TotalCost DECIMAL(18,2) = 0, @SupplierType NVARCHAR(20) = NULL,
    @SupplierId INT = NULL, @AmountPaid DECIMAL(18,2) = 0, @Notes NVARCHAR(MAX) = NULL
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
        [SupplierId]=@SupplierId, [Notes]=@Notes
    WHERE [BatchId]=@BatchId AND [FarmId]=@FarmId;

    -- Re-sync the bird stock movement to the (possibly changed) bird count.
    EXEC dbo.spPoultryBirdStock_Sync @FarmId, N'Bird Batch Purchase', @NumberOfBirds, @BatchId, N'Flock batch purchase', @UserId;
    -- Re-sync the linked expense.
    EXEC dbo.spFlockBatchExpense_Sync @FarmId, @BatchId, @TotalCost, @StartDate, @BatchName, @NumberOfBirds, @UserId;
    COMMIT TRANSACTION;
END
GO

-- ---------------------------------------------------------------------------
-- Delete — reverse birds (existing) + expense (new).
-- ---------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[spMainFlockBatch_Delete]
    @BatchId INT, @UserId NVARCHAR(450), @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRANSACTION;
    EXEC dbo.spPoultryBirdStock_Sync @FarmId, N'Bird Batch Purchase', 0, @BatchId, NULL, @UserId;
    EXEC dbo.spFlockBatchExpense_Sync @FarmId, @BatchId, 0, NULL, NULL, 0, @UserId;
    DELETE FROM [dbo].[MainFlockBatch] WHERE [BatchId] = @BatchId AND [FarmId] = @FarmId;
    COMMIT TRANSACTION;
END
GO

PRINT 'Migration 142 applied: flock batch insert fixed (+@Notes), birds sync on edit, expense created.';
GO
