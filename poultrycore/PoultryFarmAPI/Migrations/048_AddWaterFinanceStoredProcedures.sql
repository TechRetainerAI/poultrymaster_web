-- =============================================================================
-- Migration 048: Stored procedures for the Water Company finance layer
-- =============================================================================
-- Pairs with 047. Procs covered:
--
--   WaterExpenseCategory:  GetAll, Insert, Update, Delete (soft)
--   WaterExpense:          GetAll, GetById, Insert (Draft),
--                          Submit, Approve (writes paired CashOut + audits the
--                          CashAccount), Reject, Cancel, Delete (soft)
--   WaterCashAccount:      GetAll, GetById, Insert, Update, Delete (soft),
--                          ReconcileBalance
--   WaterCashTransaction:  GetByFarm (date + account filter)
--   WaterCashTransfer:     GetAll, GetById, Insert (Draft), Approve, Cancel
--   WaterCustomerLedger:   GetForCustomer, AddEntry
--   WaterFinance_SeedDefaults: per-farm seed for the default categories +
--                              cash accounts (called by the water-company
--                              create flow).
--
-- Approval semantics (Expenses):
--   * Draft → Submitted → Approved | Rejected | Cancelled.
--   * Approve is transactional: status update + WaterCashTransaction CashOut
--     + WaterCashAccount.CurrentBalance update, all in one transaction.
--   * Cancelling an Approved expense REVERSES the cash transaction.
--   * Credit-method expenses (PaymentMethod='Credit') do NOT touch a cash
--     account on approve — they only book the expense for P&L.
--
-- Approval semantics (CashTransfer):
--   * Draft → Approved | Cancelled.
--   * Approve writes paired TransferOut + TransferIn rows in one transaction.
--   * Negative balance is rejected unless the source account has
--     AllowNegativeBalance = 1.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- =============================================================================
-- WaterExpenseCategory
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spWaterExpenseCategory_GetAll
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT WaterExpenseCategoryId, FarmId, Name, Description, IsActive, IsDeleted,
           CreatedAt, UpdatedAt
    FROM   dbo.WaterExpenseCategories
    WHERE  FarmId = @FarmId AND IsDeleted = 0
    ORDER  BY IsActive DESC, Name;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterExpenseCategory_Insert
    @FarmId      NVARCHAR(450),
    @Name        NVARCHAR(100),
    @Description NVARCHAR(500) = NULL,
    @IsActive    BIT           = 1
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.WaterExpenseCategories (FarmId, Name, Description, IsActive)
    VALUES (@FarmId, @Name, @Description, @IsActive);
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterExpenseCategory_Update
    @WaterExpenseCategoryId INT,
    @FarmId                 NVARCHAR(450),
    @Name                   NVARCHAR(100),
    @Description            NVARCHAR(500) = NULL,
    @IsActive               BIT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.WaterExpenseCategories
    SET    Name = @Name, Description = @Description, IsActive = @IsActive,
           UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterExpenseCategoryId = @WaterExpenseCategoryId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterExpenseCategory_Delete
    @WaterExpenseCategoryId INT,
    @FarmId                 NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.WaterExpenseCategories
    SET    IsDeleted = 1, IsActive = 0, UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterExpenseCategoryId = @WaterExpenseCategoryId AND FarmId = @FarmId;
END
GO

-- =============================================================================
-- WaterCashAccount
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spWaterCashAccount_GetAll
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT WaterCashAccountId, FarmId, AccountName, AccountType,
           OpeningBalance, CurrentBalance, AllowNegativeBalance, IsActive, Notes,
           CreatedAt, UpdatedAt
    FROM   dbo.WaterCashAccounts
    WHERE  FarmId = @FarmId
    ORDER  BY IsActive DESC, AccountName;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterCashAccount_GetById
    @WaterCashAccountId INT,
    @FarmId             NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT WaterCashAccountId, FarmId, AccountName, AccountType,
           OpeningBalance, CurrentBalance, AllowNegativeBalance, IsActive, Notes,
           CreatedAt, UpdatedAt
    FROM   dbo.WaterCashAccounts
    WHERE  WaterCashAccountId = @WaterCashAccountId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterCashAccount_Insert
    @FarmId                NVARCHAR(450),
    @AccountName           NVARCHAR(100),
    @AccountType           NVARCHAR(30),
    @OpeningBalance        DECIMAL(14,2) = 0,
    @AllowNegativeBalance  BIT           = 0,
    @Notes                 NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.WaterCashAccounts (
        FarmId, AccountName, AccountType, OpeningBalance, CurrentBalance,
        AllowNegativeBalance, Notes
    )
    VALUES (@FarmId, @AccountName, @AccountType, @OpeningBalance, @OpeningBalance,
            @AllowNegativeBalance, @Notes);
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterCashAccount_Update
    @WaterCashAccountId   INT,
    @FarmId               NVARCHAR(450),
    @AccountName          NVARCHAR(100),
    @AccountType          NVARCHAR(30),
    @AllowNegativeBalance BIT,
    @IsActive             BIT,
    @Notes                NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    -- OpeningBalance + CurrentBalance not editable here — they're append-only
    -- via WaterCashTransactions.
    UPDATE dbo.WaterCashAccounts
    SET    AccountName          = @AccountName,
           AccountType           = @AccountType,
           AllowNegativeBalance  = @AllowNegativeBalance,
           IsActive              = @IsActive,
           Notes                 = @Notes,
           UpdatedAt             = SYSUTCDATETIME()
    WHERE  WaterCashAccountId = @WaterCashAccountId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterCashAccount_Delete
    @WaterCashAccountId INT,
    @FarmId             NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    -- Soft via IsActive = 0; we don't truly delete because WaterCashTransactions
    -- references it for historical reports.
    UPDATE dbo.WaterCashAccounts
    SET    IsActive = 0, UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterCashAccountId = @WaterCashAccountId AND FarmId = @FarmId;
END
GO

-- Rebuild CurrentBalance from OpeningBalance + SUM(WaterCashTransactions.Amount).
-- Reserved for the owner/admin if the denormalised cache drifts.
CREATE OR ALTER PROCEDURE dbo.spWaterCashAccount_ReconcileBalance
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE a
    SET    CurrentBalance = a.OpeningBalance + ISNULL(t.NetAmount, 0),
           UpdatedAt = SYSUTCDATETIME()
    FROM   dbo.WaterCashAccounts a
    LEFT   JOIN (
              SELECT WaterCashAccountId, SUM(Amount) AS NetAmount
              FROM   dbo.WaterCashTransactions
              WHERE  FarmId = @FarmId
              GROUP  BY WaterCashAccountId
           ) t ON t.WaterCashAccountId = a.WaterCashAccountId
    WHERE  a.FarmId = @FarmId;
END
GO

-- =============================================================================
-- WaterCashTransaction (read-only externally; writes happen inside the
-- transactional approve SPs)
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spWaterCashTransaction_GetByFarm
    @FarmId             NVARCHAR(450),
    @WaterCashAccountId INT       = NULL,
    @FromDate           DATETIME2 = NULL,
    @ToDate             DATETIME2 = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT t.WaterCashTransactionId, t.FarmId, t.WaterCashAccountId, a.AccountName,
           t.TransactionDate, t.TransactionType, t.SourceType, t.SourceId,
           t.Amount, t.BalanceAfterTransaction, t.Description,
           t.CreatedBy, t.ApprovedBy, t.ApprovedAt, t.CreatedAt
    FROM   dbo.WaterCashTransactions t
    INNER  JOIN dbo.WaterCashAccounts a ON a.WaterCashAccountId = t.WaterCashAccountId
    WHERE  t.FarmId = @FarmId
       AND (@WaterCashAccountId IS NULL OR t.WaterCashAccountId = @WaterCashAccountId)
       AND (@FromDate IS NULL OR t.TransactionDate >= @FromDate)
       AND (@ToDate   IS NULL OR t.TransactionDate <= @ToDate)
    ORDER  BY t.TransactionDate DESC, t.WaterCashTransactionId DESC;
END
GO

-- =============================================================================
-- WaterCashTransfer
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spWaterCashTransfer_GetAll
    @FarmId NVARCHAR(450),
    @Status NVARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  t.WaterCashTransferId, t.FarmId,
            t.FromWaterCashAccountId, fa.AccountName AS FromAccountName,
            t.ToWaterCashAccountId,   ta.AccountName AS ToAccountName,
            t.TransferDate, t.Amount, t.Status, t.Notes,
            t.CreatedBy, t.ApprovedBy, t.ApprovedAt, t.CreatedAt, t.UpdatedAt
    FROM    dbo.WaterCashTransfers t
    INNER   JOIN dbo.WaterCashAccounts fa ON fa.WaterCashAccountId = t.FromWaterCashAccountId
    INNER   JOIN dbo.WaterCashAccounts ta ON ta.WaterCashAccountId = t.ToWaterCashAccountId
    WHERE   t.FarmId = @FarmId
       AND  (@Status IS NULL OR t.Status = @Status)
    ORDER   BY t.TransferDate DESC, t.WaterCashTransferId DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterCashTransfer_GetById
    @WaterCashTransferId INT,
    @FarmId              NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  t.WaterCashTransferId, t.FarmId,
            t.FromWaterCashAccountId, fa.AccountName AS FromAccountName,
            t.ToWaterCashAccountId,   ta.AccountName AS ToAccountName,
            t.TransferDate, t.Amount, t.Status, t.Notes,
            t.CreatedBy, t.ApprovedBy, t.ApprovedAt, t.CreatedAt, t.UpdatedAt
    FROM    dbo.WaterCashTransfers t
    INNER   JOIN dbo.WaterCashAccounts fa ON fa.WaterCashAccountId = t.FromWaterCashAccountId
    INNER   JOIN dbo.WaterCashAccounts ta ON ta.WaterCashAccountId = t.ToWaterCashAccountId
    WHERE   t.WaterCashTransferId = @WaterCashTransferId AND t.FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterCashTransfer_Insert
    @FarmId                  NVARCHAR(450),
    @FromWaterCashAccountId  INT,
    @ToWaterCashAccountId    INT,
    @Amount                  DECIMAL(14,2),
    @TransferDate            DATETIME2     = NULL,
    @Notes                   NVARCHAR(500) = NULL,
    @CreatedBy               NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF (@FromWaterCashAccountId = @ToWaterCashAccountId)
    BEGIN
        RAISERROR('Cash transfer cannot be to the same account.', 16, 1); RETURN;
    END
    IF (@Amount <= 0)
    BEGIN
        RAISERROR('Transfer amount must be greater than zero.', 16, 1); RETURN;
    END

    INSERT INTO dbo.WaterCashTransfers (
        FarmId, FromWaterCashAccountId, ToWaterCashAccountId, TransferDate, Amount,
        Status, Notes, CreatedBy
    )
    VALUES (
        @FarmId, @FromWaterCashAccountId, @ToWaterCashAccountId,
        ISNULL(@TransferDate, SYSUTCDATETIME()), @Amount, 'Draft', @Notes, @CreatedBy
    );
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterCashTransfer_Approve
    @WaterCashTransferId INT,
    @FarmId              NVARCHAR(450),
    @ApprovedBy          NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Idempotency
    IF EXISTS (SELECT 1 FROM dbo.WaterCashTransfers
               WHERE WaterCashTransferId = @WaterCashTransferId AND FarmId = @FarmId AND Status = 'Approved')
    BEGIN
        SELECT WaterCashTransferId, Status, ApprovedBy, ApprovedAt
        FROM   dbo.WaterCashTransfers
        WHERE  WaterCashTransferId = @WaterCashTransferId AND FarmId = @FarmId;
        RETURN;
    END

    DECLARE @FromId INT, @ToId INT, @Amount DECIMAL(14,2), @Date DATETIME2, @Status NVARCHAR(20);
    SELECT @FromId = FromWaterCashAccountId,
           @ToId   = ToWaterCashAccountId,
           @Amount = Amount,
           @Date   = TransferDate,
           @Status = Status
    FROM   dbo.WaterCashTransfers
    WHERE  WaterCashTransferId = @WaterCashTransferId AND FarmId = @FarmId;

    IF @FromId IS NULL
    BEGIN RAISERROR('Cash transfer %d not found.', 16, 1, @WaterCashTransferId); RETURN; END
    IF @Status <> 'Draft'
    BEGIN RAISERROR('Cash transfer cannot be approved from status %s.', 16, 1, @Status); RETURN; END

    -- Negative balance gate on source account
    DECLARE @FromBalance DECIMAL(14,2), @AllowNeg BIT;
    SELECT @FromBalance = CurrentBalance, @AllowNeg = AllowNegativeBalance
    FROM   dbo.WaterCashAccounts
    WHERE  WaterCashAccountId = @FromId;
    IF (@AllowNeg = 0 AND (@FromBalance - @Amount) < 0)
    BEGIN
        RAISERROR('Source cash account would go negative; transfer rejected.', 16, 1); RETURN;
    END

    BEGIN TRANSACTION;

    UPDATE dbo.WaterCashTransfers
    SET    Status = 'Approved', ApprovedBy = @ApprovedBy, ApprovedAt = SYSUTCDATETIME(),
           UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterCashTransferId = @WaterCashTransferId AND FarmId = @FarmId;

    -- TransferOut leg
    INSERT INTO dbo.WaterCashTransactions (
        FarmId, WaterCashAccountId, TransactionDate, TransactionType,
        SourceType, SourceId, Amount, Description, CreatedBy, ApprovedBy, ApprovedAt
    )
    VALUES (
        @FarmId, @FromId, @Date, 'TransferOut',
        'Transfer', @WaterCashTransferId, -@Amount, 'Transfer out', @ApprovedBy, @ApprovedBy, SYSUTCDATETIME()
    );

    UPDATE dbo.WaterCashAccounts SET CurrentBalance = CurrentBalance - @Amount, UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterCashAccountId = @FromId;

    -- TransferIn leg
    INSERT INTO dbo.WaterCashTransactions (
        FarmId, WaterCashAccountId, TransactionDate, TransactionType,
        SourceType, SourceId, Amount, Description, CreatedBy, ApprovedBy, ApprovedAt
    )
    VALUES (
        @FarmId, @ToId, @Date, 'TransferIn',
        'Transfer', @WaterCashTransferId, @Amount, 'Transfer in', @ApprovedBy, @ApprovedBy, SYSUTCDATETIME()
    );

    UPDATE dbo.WaterCashAccounts SET CurrentBalance = CurrentBalance + @Amount, UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterCashAccountId = @ToId;

    COMMIT TRANSACTION;

    SELECT WaterCashTransferId, Status, ApprovedBy, ApprovedAt
    FROM   dbo.WaterCashTransfers
    WHERE  WaterCashTransferId = @WaterCashTransferId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterCashTransfer_Cancel
    @WaterCashTransferId INT,
    @FarmId              NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.WaterCashTransfers
    SET    Status = 'Cancelled', UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterCashTransferId = @WaterCashTransferId AND FarmId = @FarmId AND Status = 'Draft';

    IF @@ROWCOUNT = 0
    BEGIN
        RAISERROR('Transfer cannot be cancelled (not found or already finalized).', 16, 1);
        RETURN;
    END
END
GO

-- =============================================================================
-- WaterExpense
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spWaterExpense_GetAll
    @FarmId   NVARCHAR(450),
    @Status   NVARCHAR(20) = NULL,
    @FromDate DATETIME2    = NULL,
    @ToDate   DATETIME2    = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT e.WaterExpenseId, e.FarmId, e.ExpenseDate,
           e.WaterExpenseCategoryId, c.Name AS CategoryName,
           e.Description, e.Amount, e.PaidTo, e.PaymentMethod,
           e.WaterCashAccountId, ca.AccountName AS CashAccountName,
           e.ReceiptUrl,
           e.LinkedWaterVehicleId, e.LinkedWaterMachineId, e.LinkedWaterProductionBatchId,
           e.Status, e.Notes,
           e.CreatedBy, e.ApprovedBy, e.ApprovedAt,
           e.CreatedAt, e.UpdatedAt
    FROM   dbo.WaterExpenses e
    INNER  JOIN dbo.WaterExpenseCategories c ON c.WaterExpenseCategoryId = e.WaterExpenseCategoryId
    LEFT   JOIN dbo.WaterCashAccounts ca     ON ca.WaterCashAccountId   = e.WaterCashAccountId
    WHERE  e.FarmId = @FarmId AND e.IsDeleted = 0
       AND (@Status   IS NULL OR e.Status = @Status)
       AND (@FromDate IS NULL OR e.ExpenseDate >= @FromDate)
       AND (@ToDate   IS NULL OR e.ExpenseDate <= @ToDate)
    ORDER  BY e.ExpenseDate DESC, e.WaterExpenseId DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterExpense_GetById
    @WaterExpenseId INT,
    @FarmId         NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT e.WaterExpenseId, e.FarmId, e.ExpenseDate,
           e.WaterExpenseCategoryId, c.Name AS CategoryName,
           e.Description, e.Amount, e.PaidTo, e.PaymentMethod,
           e.WaterCashAccountId, ca.AccountName AS CashAccountName,
           e.ReceiptUrl,
           e.LinkedWaterVehicleId, e.LinkedWaterMachineId, e.LinkedWaterProductionBatchId,
           e.Status, e.Notes,
           e.CreatedBy, e.ApprovedBy, e.ApprovedAt,
           e.CreatedAt, e.UpdatedAt
    FROM   dbo.WaterExpenses e
    INNER  JOIN dbo.WaterExpenseCategories c ON c.WaterExpenseCategoryId = e.WaterExpenseCategoryId
    LEFT   JOIN dbo.WaterCashAccounts ca     ON ca.WaterCashAccountId   = e.WaterCashAccountId
    WHERE  e.WaterExpenseId = @WaterExpenseId AND e.FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterExpense_Insert
    @FarmId                       NVARCHAR(450),
    @ExpenseDate                  DATETIME2     = NULL,
    @WaterExpenseCategoryId       INT,
    @Description                  NVARCHAR(500) = NULL,
    @Amount                       DECIMAL(14,2),
    @PaidTo                       NVARCHAR(200) = NULL,
    @PaymentMethod                NVARCHAR(20)  = 'Cash',
    @WaterCashAccountId           INT           = NULL,
    @ReceiptUrl                   NVARCHAR(500) = NULL,
    @LinkedWaterVehicleId         INT           = NULL,
    @LinkedWaterMachineId         INT           = NULL,
    @LinkedWaterProductionBatchId INT           = NULL,
    @Notes                        NVARCHAR(1000)= NULL,
    @CreatedBy                    NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF (@Amount <= 0) BEGIN RAISERROR('Expense amount must be greater than zero.', 16, 1); RETURN; END
    IF (@PaymentMethod <> 'Credit' AND @WaterCashAccountId IS NULL)
    BEGIN RAISERROR('Cash account is required for non-credit expenses.', 16, 1); RETURN; END

    INSERT INTO dbo.WaterExpenses (
        FarmId, ExpenseDate, WaterExpenseCategoryId, Description, Amount, PaidTo,
        PaymentMethod, WaterCashAccountId, ReceiptUrl,
        LinkedWaterVehicleId, LinkedWaterMachineId, LinkedWaterProductionBatchId,
        Status, Notes, CreatedBy
    )
    VALUES (
        @FarmId, ISNULL(@ExpenseDate, SYSUTCDATETIME()), @WaterExpenseCategoryId, @Description, @Amount, @PaidTo,
        @PaymentMethod, @WaterCashAccountId, @ReceiptUrl,
        @LinkedWaterVehicleId, @LinkedWaterMachineId, @LinkedWaterProductionBatchId,
        'Draft', @Notes, @CreatedBy
    );
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterExpense_Submit
    @WaterExpenseId INT,
    @FarmId         NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.WaterExpenses
    SET    Status = 'Submitted', UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterExpenseId = @WaterExpenseId AND FarmId = @FarmId AND Status = 'Draft';
    IF @@ROWCOUNT = 0
    BEGIN RAISERROR('Expense cannot be submitted (not found or not in Draft).', 16, 1); RETURN; END
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterExpense_Approve
    @WaterExpenseId INT,
    @FarmId         NVARCHAR(450),
    @ApprovedBy     NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF EXISTS (SELECT 1 FROM dbo.WaterExpenses WHERE WaterExpenseId = @WaterExpenseId AND FarmId = @FarmId AND Status = 'Approved')
    BEGIN
        SELECT WaterExpenseId, Status, ApprovedBy, ApprovedAt FROM dbo.WaterExpenses
        WHERE WaterExpenseId = @WaterExpenseId AND FarmId = @FarmId;
        RETURN;
    END

    DECLARE @Status NVARCHAR(20), @PaymentMethod NVARCHAR(20),
            @Amount DECIMAL(14,2), @CashAccountId INT, @Description NVARCHAR(500),
            @ExpenseDate DATETIME2;
    SELECT @Status = Status, @PaymentMethod = PaymentMethod, @Amount = Amount,
           @CashAccountId = WaterCashAccountId, @Description = Description, @ExpenseDate = ExpenseDate
    FROM   dbo.WaterExpenses WHERE WaterExpenseId = @WaterExpenseId AND FarmId = @FarmId;

    IF @Status IS NULL BEGIN RAISERROR('Expense %d not found.', 16, 1, @WaterExpenseId); RETURN; END
    IF @Status NOT IN ('Draft','Submitted') BEGIN RAISERROR('Expense cannot be approved from status %s.', 16, 1, @Status); RETURN; END

    BEGIN TRANSACTION;

    UPDATE dbo.WaterExpenses
    SET    Status = 'Approved', ApprovedBy = @ApprovedBy, ApprovedAt = SYSUTCDATETIME(),
           UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterExpenseId = @WaterExpenseId AND FarmId = @FarmId;

    -- Non-credit: book the CashOut and update the cash account balance.
    IF (@PaymentMethod <> 'Credit' AND @CashAccountId IS NOT NULL)
    BEGIN
        DECLARE @AllowNeg BIT, @Bal DECIMAL(14,2);
        SELECT @AllowNeg = AllowNegativeBalance, @Bal = CurrentBalance
        FROM   dbo.WaterCashAccounts WHERE WaterCashAccountId = @CashAccountId;
        IF (@AllowNeg = 0 AND (@Bal - @Amount) < 0)
        BEGIN
            RAISERROR('Cash account would go negative; expense approve rejected.', 16, 1); RETURN;
        END

        INSERT INTO dbo.WaterCashTransactions (
            FarmId, WaterCashAccountId, TransactionDate, TransactionType,
            SourceType, SourceId, Amount, Description, CreatedBy, ApprovedBy, ApprovedAt
        )
        VALUES (
            @FarmId, @CashAccountId, @ExpenseDate, 'CashOut',
            'Expense', @WaterExpenseId, -@Amount, ISNULL(@Description, 'Expense'),
            @ApprovedBy, @ApprovedBy, SYSUTCDATETIME()
        );

        UPDATE dbo.WaterCashAccounts SET CurrentBalance = CurrentBalance - @Amount, UpdatedAt = SYSUTCDATETIME()
        WHERE  WaterCashAccountId = @CashAccountId;
    END

    COMMIT TRANSACTION;

    SELECT WaterExpenseId, Status, ApprovedBy, ApprovedAt
    FROM   dbo.WaterExpenses WHERE WaterExpenseId = @WaterExpenseId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterExpense_Reject
    @WaterExpenseId INT,
    @FarmId         NVARCHAR(450),
    @ApprovedBy     NVARCHAR(450) = NULL,
    @Reason         NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.WaterExpenses
    SET    Status = 'Rejected', ApprovedBy = @ApprovedBy, ApprovedAt = SYSUTCDATETIME(),
           Notes = CASE WHEN @Reason IS NULL THEN Notes ELSE LEFT(ISNULL(Notes,'') + CHAR(10) + 'Rejected: ' + @Reason, 1000) END,
           UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterExpenseId = @WaterExpenseId AND FarmId = @FarmId AND Status IN ('Draft','Submitted');
    IF @@ROWCOUNT = 0
    BEGIN RAISERROR('Expense cannot be rejected (not found or already finalized).', 16, 1); RETURN; END
END
GO

-- Cancel an Approved expense: reverse the cash impact and flip to Cancelled.
CREATE OR ALTER PROCEDURE dbo.spWaterExpense_Cancel
    @WaterExpenseId INT,
    @FarmId         NVARCHAR(450),
    @CancelledBy    NVARCHAR(450) = NULL,
    @Reason         NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Status NVARCHAR(20), @PaymentMethod NVARCHAR(20),
            @Amount DECIMAL(14,2), @CashAccountId INT, @ExpenseDate DATETIME2;
    SELECT @Status = Status, @PaymentMethod = PaymentMethod, @Amount = Amount,
           @CashAccountId = WaterCashAccountId, @ExpenseDate = ExpenseDate
    FROM   dbo.WaterExpenses WHERE WaterExpenseId = @WaterExpenseId AND FarmId = @FarmId;

    IF @Status IS NULL BEGIN RAISERROR('Expense not found.', 16, 1); RETURN; END
    IF @Status = 'Cancelled' RETURN;

    BEGIN TRANSACTION;

    IF @Status = 'Approved' AND @PaymentMethod <> 'Credit' AND @CashAccountId IS NOT NULL
    BEGIN
        INSERT INTO dbo.WaterCashTransactions (
            FarmId, WaterCashAccountId, TransactionDate, TransactionType,
            SourceType, SourceId, Amount, Description, CreatedBy, ApprovedBy, ApprovedAt
        )
        VALUES (
            @FarmId, @CashAccountId, SYSUTCDATETIME(), 'Adjustment',
            'Expense', @WaterExpenseId, @Amount, 'Expense cancelled — reversal',
            @CancelledBy, @CancelledBy, SYSUTCDATETIME()
        );

        UPDATE dbo.WaterCashAccounts SET CurrentBalance = CurrentBalance + @Amount, UpdatedAt = SYSUTCDATETIME()
        WHERE  WaterCashAccountId = @CashAccountId;
    END

    UPDATE dbo.WaterExpenses
    SET    Status = 'Cancelled',
           Notes  = CASE WHEN @Reason IS NULL THEN Notes ELSE LEFT(ISNULL(Notes,'') + CHAR(10) + 'Cancelled: ' + @Reason, 1000) END,
           UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterExpenseId = @WaterExpenseId AND FarmId = @FarmId;

    COMMIT TRANSACTION;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterExpense_Delete
    @WaterExpenseId INT,
    @FarmId         NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.WaterExpenses
    SET    IsDeleted = 1, UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterExpenseId = @WaterExpenseId AND FarmId = @FarmId AND Status IN ('Draft','Submitted','Rejected','Cancelled');
    IF @@ROWCOUNT = 0
    BEGIN RAISERROR('Cannot delete an Approved expense — cancel it first.', 16, 1); RETURN; END
END
GO

-- =============================================================================
-- WaterCustomerLedger (append-only)
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spWaterCustomerLedger_GetForCustomer
    @FarmId          NVARCHAR(450),
    @WaterCustomerId INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT WaterCustomerLedgerId, FarmId, WaterCustomerId, TransactionDate,
           TransactionType, WaterSaleId, WaterPaymentId,
           DebitAmount, CreditAmount, BalanceAfterTransaction, Description,
           CreatedBy, CreatedAt
    FROM   dbo.WaterCustomerLedger
    WHERE  FarmId = @FarmId AND WaterCustomerId = @WaterCustomerId
    ORDER  BY TransactionDate, WaterCustomerLedgerId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterCustomerLedger_AddEntry
    @FarmId          NVARCHAR(450),
    @WaterCustomerId INT,
    @TransactionType NVARCHAR(30),
    @WaterSaleId     INT            = NULL,
    @WaterPaymentId  INT            = NULL,
    @DebitAmount     DECIMAL(14,2)  = 0,
    @CreditAmount    DECIMAL(14,2)  = 0,
    @Description     NVARCHAR(500)  = NULL,
    @CreatedBy       NVARCHAR(450)  = NULL,
    @TransactionDate DATETIME2      = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Prev DECIMAL(14,2) = ISNULL((
        SELECT TOP 1 BalanceAfterTransaction
        FROM   dbo.WaterCustomerLedger
        WHERE  FarmId = @FarmId AND WaterCustomerId = @WaterCustomerId
        ORDER  BY WaterCustomerLedgerId DESC
    ), 0);

    DECLARE @NewBalance DECIMAL(14,2) = @Prev + ISNULL(@DebitAmount,0) - ISNULL(@CreditAmount,0);

    INSERT INTO dbo.WaterCustomerLedger (
        FarmId, WaterCustomerId, TransactionDate, TransactionType,
        WaterSaleId, WaterPaymentId, DebitAmount, CreditAmount,
        BalanceAfterTransaction, Description, CreatedBy
    )
    VALUES (
        @FarmId, @WaterCustomerId, ISNULL(@TransactionDate, SYSUTCDATETIME()), @TransactionType,
        @WaterSaleId, @WaterPaymentId, ISNULL(@DebitAmount,0), ISNULL(@CreditAmount,0),
        @NewBalance, @Description, @CreatedBy
    );

    SELECT CAST(SCOPE_IDENTITY() AS INT) AS WaterCustomerLedgerId, @NewBalance AS BalanceAfterTransaction;
END
GO

-- =============================================================================
-- Per-farm finance defaults seed (called from the Water Company create flow)
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spWaterFinance_SeedDefaults
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;

    -- Default expense categories (idempotent).
    DECLARE @cats TABLE (Name NVARCHAR(100));
    INSERT INTO @cats(Name) VALUES
        ('Raw Materials'),
        ('Packaging Rolls'),
        ('Fuel'),
        ('Electricity'),
        ('Water Treatment'),
        ('Machine Repairs'),
        ('Vehicle Repairs'),
        ('Driver Wages'),
        ('Factory Worker Wages'),
        ('Loading Boys'),
        ('Security'),
        ('Rent'),
        ('Borehole Maintenance'),
        ('Generator Maintenance'),
        ('Marketing'),
        ('Phone/Internet'),
        ('Government Fees'),
        ('Water Quality Testing'),
        ('Cleaning Supplies'),
        ('Miscellaneous');

    INSERT INTO dbo.WaterExpenseCategories (FarmId, Name, IsActive)
    SELECT @FarmId, c.Name, 1
    FROM   @cats c
    WHERE  NOT EXISTS (
        SELECT 1 FROM dbo.WaterExpenseCategories x
        WHERE  x.FarmId = @FarmId AND x.Name = c.Name
    );

    -- Default cash accounts (idempotent).
    DECLARE @accts TABLE (AccountName NVARCHAR(100), AccountType NVARCHAR(30));
    INSERT INTO @accts(AccountName, AccountType) VALUES
        ('Factory Cash Box', 'FactoryCashBox'),
        ('MoMo Wallet',      'MoMoWallet'),
        ('Bank Account',     'BankAccount'),
        ('Petty Cash',       'PettyCash');

    INSERT INTO dbo.WaterCashAccounts (FarmId, AccountName, AccountType, OpeningBalance, CurrentBalance)
    SELECT @FarmId, a.AccountName, a.AccountType, 0, 0
    FROM   @accts a
    WHERE  NOT EXISTS (
        SELECT 1 FROM dbo.WaterCashAccounts x
        WHERE  x.FarmId = @FarmId AND x.AccountName = a.AccountName
    );

    -- Verification readout
    SELECT
        (SELECT COUNT(*) FROM dbo.WaterExpenseCategories WHERE FarmId = @FarmId) AS ExpenseCategoryCount,
        (SELECT COUNT(*) FROM dbo.WaterCashAccounts     WHERE FarmId = @FarmId) AS CashAccountCount;
END
GO

-- =============================================================================
-- Grant EXECUTE to the runtime user (same pattern as migration 042)
-- =============================================================================
IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    DECLARE @procName SYSNAME;
    DECLARE proc_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT name FROM sys.procedures
        WHERE name LIKE 'spWaterExpense%'
           OR name LIKE 'spWaterCashAccount%'
           OR name LIKE 'spWaterCashTransaction%'
           OR name LIKE 'spWaterCashTransfer%'
           OR name LIKE 'spWaterCustomerLedger%'
           OR name LIKE 'spWaterFinance%';
    OPEN proc_cursor;
    FETCH NEXT FROM proc_cursor INTO @procName;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE @grantSql NVARCHAR(MAX) =
            N'GRANT EXECUTE ON [dbo].' + QUOTENAME(@procName) + N' TO [Techretainer];';
        EXEC sp_executesql @grantSql;
        FETCH NEXT FROM proc_cursor INTO @procName;
    END;
    CLOSE proc_cursor;
    DEALLOCATE proc_cursor;
    PRINT '048: granted EXECUTE on water finance SPs to Techretainer.';
END
GO

PRINT '048_AddWaterFinanceStoredProcedures.sql complete.';
GO
