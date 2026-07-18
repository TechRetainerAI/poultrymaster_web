-- =============================================================================
-- Migration 151: Flock batch part payment ("Pay Balance"), mirroring the
--                raw-material purchase model (migrations 090/091/130).
-- =============================================================================
-- Feedback: a bird purchase should support part payment and a follow-up "pay the
-- balance later" action, exactly like poultry raw-material purchases.
--
-- Changes to the flock-batch procedures (cash-basis expense, like raw materials):
--   1. Insert  — the linked Expense now records the amount actually PAID
--                (@AmountPaid), not the full @TotalCost. A batch bought on part
--                payment therefore books only the down payment as an expense; the
--                rest is booked as it is paid (see PayBalance).
--   2. Update  — keeps the INITIAL linked expense (the lowest ExpenseId for this
--                batch) in sync with AmountPaid WITHOUT deleting the separate
--                balance-payment expense rows. Initial = AmountPaid − (sum of the
--                later balance-payment expenses), so total booked always equals
--                AmountPaid.
--   3. PayBalance (new) — records a follow-up payment: caps it at the outstanding
--                balance (TotalCost − AmountPaid), increases AmountPaid, posts a
--                SEPARATE Approved expense for the amount paid, and returns the
--                new outstanding balance.
--
-- Bird-stock sync (spPoultryBirdStock_Sync) and the delete-time expense reversal
-- (spFlockBatchExpense_Sync with amount 0) are preserved. The order/arrival date
-- columns from migration 150 are unchanged. Idempotent (CREATE OR ALTER).
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
-- Insert — expense now records @AmountPaid (down payment), not @TotalCost.
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
    IF (@AmountPaid IS NULL) SET @AmountPaid = 0;
    IF (@TotalCost IS NOT NULL AND @AmountPaid > @TotalCost) SET @AmountPaid = @TotalCost;
    BEGIN TRANSACTION;
    INSERT INTO [dbo].[MainFlockBatch] (UserId, FarmId, BatchCode, BatchName, Breed, NumberOfBirds, StartDate, Status, CostPerChick, TotalCost, AmountPaid, SupplierType, SupplierId, Notes, OrderPlacementDate, EstimatedArrivalDate, CreatedDate)
    VALUES (@UserId, @FarmId, @BatchCode, @BatchName, @Breed, @NumberOfBirds, @StartDate, ISNULL(@Status, N'active'), ISNULL(@CostPerChick,0), ISNULL(@TotalCost,0), ISNULL(@AmountPaid,0), @SupplierType, @SupplierId, @Notes, @OrderPlacementDate, @EstimatedArrivalDate, SYSUTCDATETIME());
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
-- Update — sync the INITIAL expense to AmountPaid minus later balance payments;
-- never delete the separate balance-payment rows. Bird stock re-synced.
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
    IF (@AmountPaid IS NULL) SET @AmountPaid = 0;
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
-- PayBalance (new) — record a follow-up payment toward an outstanding batch.
-- Mirrors spPoultryRawMaterialPurchase_PayBalance.
-- ---------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[spMainFlockBatch_PayBalance]
    @BatchId       INT,
    @FarmId        NVARCHAR(450),
    @Amount        DECIMAL(18,2),
    @PaymentMethod NVARCHAR(30)  = NULL,
    @PaymentDate   DATETIME2     = NULL,
    @CreatedBy     NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Total DECIMAL(18,2), @Paid DECIMAL(18,2), @BatchName NVARCHAR(100), @NumberOfBirds INT, @SupplierId INT;
    SELECT @Total = TotalCost, @Paid = AmountPaid, @BatchName = BatchName, @NumberOfBirds = NumberOfBirds, @SupplierId = SupplierId
    FROM   dbo.MainFlockBatch WHERE BatchId = @BatchId AND FarmId = @FarmId;

    IF @Total IS NULL BEGIN RAISERROR('Flock batch not found for this company.', 16, 1); RETURN; END
    DECLARE @Outstanding DECIMAL(18,2) = @Total - @Paid;
    IF (@Outstanding <= 0) BEGIN RAISERROR('This flock batch has no outstanding balance.', 16, 1); RETURN; END
    IF (@Amount IS NULL OR @Amount <= 0) BEGIN RAISERROR('Payment amount must be greater than 0.', 16, 1); RETURN; END
    IF (@Amount > @Outstanding) SET @Amount = @Outstanding;

    DECLARE @SupplierName NVARCHAR(200) = NULL;
    IF (@SupplierId IS NOT NULL)
        SELECT @SupplierName = [Name] FROM dbo.Supplier WHERE SupplierId = @SupplierId AND FarmId = @FarmId;

    BEGIN TRANSACTION;
    UPDATE dbo.MainFlockBatch SET AmountPaid = AmountPaid + @Amount
    WHERE  BatchId = @BatchId AND FarmId = @FarmId;

    -- Separate Approved expense for this cash outflow (like raw-material pay-balance).
    DECLARE @Gid UNIQUEIDENTIFIER = TRY_CAST(@FarmId AS UNIQUEIDENTIFIER);
    IF (@Gid IS NOT NULL AND @CreatedBy IS NOT NULL)
        INSERT INTO dbo.Expense (ExpenseDate, Category, Description, Amount, PaymentMethod, Supplier, FlockId, CreatedDate, UserId, FarmId, SourceType, SourceId)
        VALUES (ISNULL(@PaymentDate, SYSUTCDATETIME()), N'Flock / Bird Purchase',
                CONCAT(N'Balance payment for flock batch #', @BatchId, N': ', ISNULL(@BatchName, N'batch')),
                @Amount, ISNULL(@PaymentMethod, N'Cash'), @SupplierName, NULL, SYSUTCDATETIME(), @CreatedBy, @Gid,
                N'MainFlockBatch', @BatchId);
    COMMIT TRANSACTION;

    SELECT CAST(TotalCost - AmountPaid AS DECIMAL(18,2)) AS Balance
    FROM   dbo.MainFlockBatch WHERE BatchId = @BatchId AND FarmId = @FarmId;
END
GO

IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'Techretainer')
    GRANT EXECUTE ON dbo.spMainFlockBatch_PayBalance TO [Techretainer];
GO

PRINT N'Migration 151 applied: flock batch part payment (Pay Balance) + cash-basis expense.';
GO
