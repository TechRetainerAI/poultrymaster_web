-- =============================================================================
-- Migration 129: Poultry Cash Account stored procedures (port of mig 048/112).
-- Idempotent (CREATE OR ALTER). Ends with a GRANT EXECUTE loop.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- =============================================================================
-- PoultryCashAccount
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.spPoultryCashAccount_GetAll
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT PoultryCashAccountId, FarmId, AccountName, AccountType,
           OpeningBalance, CurrentBalance, AllowNegativeBalance, IsActive, Notes,
           CreatedAt, UpdatedAt
    FROM   dbo.PoultryCashAccounts
    WHERE  FarmId = @FarmId
    ORDER  BY IsActive DESC, AccountName;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryCashAccount_GetById
    @PoultryCashAccountId INT,
    @FarmId               NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT PoultryCashAccountId, FarmId, AccountName, AccountType,
           OpeningBalance, CurrentBalance, AllowNegativeBalance, IsActive, Notes,
           CreatedAt, UpdatedAt
    FROM   dbo.PoultryCashAccounts
    WHERE  PoultryCashAccountId = @PoultryCashAccountId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryCashAccount_Insert
    @FarmId                NVARCHAR(450),
    @AccountName           NVARCHAR(100),
    @AccountType           NVARCHAR(30),
    @OpeningBalance        DECIMAL(14,2) = 0,
    @AllowNegativeBalance  BIT           = 0,
    @Notes                 NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.PoultryCashAccounts (
        FarmId, AccountName, AccountType, OpeningBalance, CurrentBalance,
        AllowNegativeBalance, Notes
    )
    VALUES (@FarmId, @AccountName, @AccountType, @OpeningBalance, @OpeningBalance,
            @AllowNegativeBalance, @Notes);
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryCashAccount_Update
    @PoultryCashAccountId INT,
    @FarmId               NVARCHAR(450),
    @AccountName          NVARCHAR(100),
    @AccountType          NVARCHAR(30),
    @AllowNegativeBalance BIT,
    @IsActive             BIT,
    @Notes                NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    -- OpeningBalance + CurrentBalance are append-only via transactions.
    UPDATE dbo.PoultryCashAccounts
    SET    AccountName          = @AccountName,
           AccountType          = @AccountType,
           AllowNegativeBalance = @AllowNegativeBalance,
           IsActive             = @IsActive,
           Notes                = @Notes,
           UpdatedAt            = SYSUTCDATETIME()
    WHERE  PoultryCashAccountId = @PoultryCashAccountId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryCashAccount_Delete
    @PoultryCashAccountId INT,
    @FarmId               NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    -- Soft delete (IsActive = 0) to preserve historical ledger.
    UPDATE dbo.PoultryCashAccounts
    SET    IsActive = 0, UpdatedAt = SYSUTCDATETIME()
    WHERE  PoultryCashAccountId = @PoultryCashAccountId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryCashAccount_ReconcileBalance
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE a
    SET    CurrentBalance = a.OpeningBalance + ISNULL(t.NetAmount, 0),
           UpdatedAt = SYSUTCDATETIME()
    FROM   dbo.PoultryCashAccounts a
    LEFT   JOIN (
              SELECT PoultryCashAccountId, SUM(Amount) AS NetAmount
              FROM   dbo.PoultryCashTransactions
              WHERE  FarmId = @FarmId
              GROUP  BY PoultryCashAccountId
           ) t ON t.PoultryCashAccountId = a.PoultryCashAccountId
    WHERE  a.FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryCashAccount_Adjust
    @PoultryCashAccountId INT,
    @FarmId    NVARCHAR(450),
    @Amount    DECIMAL(14,2),     -- signed: + adds cash, - removes cash
    @Reason    NVARCHAR(500),
    @CreatedBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;

    IF (@Amount = 0)
    BEGIN RAISERROR('Adjustment amount cannot be zero.', 16, 1); RETURN; END
    IF (@Reason IS NULL OR LTRIM(RTRIM(@Reason)) = N'')
    BEGIN RAISERROR('A reason is required for an adjustment.', 16, 1); RETURN; END
    IF NOT EXISTS (SELECT 1 FROM dbo.PoultryCashAccounts WHERE PoultryCashAccountId = @PoultryCashAccountId AND FarmId = @FarmId)
    BEGIN RAISERROR('Cash account not found.', 16, 1); RETURN; END

    DECLARE @type NVARCHAR(30) = CASE WHEN @Amount > 0 THEN N'AdjustmentIn' ELSE N'AdjustmentOut' END;

    BEGIN TRANSACTION;

    UPDATE dbo.PoultryCashAccounts
    SET    CurrentBalance = CurrentBalance + @Amount, UpdatedAt = SYSUTCDATETIME()
    WHERE  PoultryCashAccountId = @PoultryCashAccountId AND FarmId = @FarmId;

    DECLARE @bal DECIMAL(14,2) = (SELECT CurrentBalance FROM dbo.PoultryCashAccounts WHERE PoultryCashAccountId = @PoultryCashAccountId);

    INSERT INTO dbo.PoultryCashTransactions
        (FarmId, PoultryCashAccountId, TransactionDate, TransactionType, SourceType, SourceId,
         Amount, BalanceAfterTransaction, Description, CreatedBy, ApprovedBy, ApprovedAt, CreatedAt)
    VALUES
        (@FarmId, @PoultryCashAccountId, SYSUTCDATETIME(), @type, N'Adjustment', NULL,
         @Amount, @bal, @Reason, @CreatedBy, @CreatedBy, SYSUTCDATETIME(), SYSUTCDATETIME());

    COMMIT TRANSACTION;
END
GO

-- =============================================================================
-- PoultryCashTransaction (read)
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.spPoultryCashTransaction_GetByFarm
    @FarmId               NVARCHAR(450),
    @PoultryCashAccountId INT       = NULL,
    @FromDate             DATETIME2 = NULL,
    @ToDate               DATETIME2 = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT t.PoultryCashTransactionId, t.FarmId, t.PoultryCashAccountId, a.AccountName,
           t.TransactionDate, t.TransactionType, t.SourceType, t.SourceId,
           t.Amount, t.BalanceAfterTransaction, t.Description,
           t.CreatedBy, t.ApprovedBy, t.ApprovedAt, t.CreatedAt
    FROM   dbo.PoultryCashTransactions t
    INNER  JOIN dbo.PoultryCashAccounts a ON a.PoultryCashAccountId = t.PoultryCashAccountId
    WHERE  t.FarmId = @FarmId
       AND (@PoultryCashAccountId IS NULL OR t.PoultryCashAccountId = @PoultryCashAccountId)
       AND (@FromDate IS NULL OR t.TransactionDate >= @FromDate)
       AND (@ToDate   IS NULL OR t.TransactionDate <= @ToDate)
    ORDER  BY t.TransactionDate DESC, t.PoultryCashTransactionId DESC;
END
GO

-- =============================================================================
-- PoultryCashTransfer
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.spPoultryCashTransfer_GetAll
    @FarmId NVARCHAR(450),
    @Status NVARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  t.PoultryCashTransferId, t.FarmId,
            t.FromPoultryCashAccountId, fa.AccountName AS FromAccountName,
            t.ToPoultryCashAccountId,   ta.AccountName AS ToAccountName,
            t.TransferDate, t.Amount, t.Status, t.Notes,
            t.CreatedBy, t.ApprovedBy, t.ApprovedAt, t.CreatedAt, t.UpdatedAt
    FROM    dbo.PoultryCashTransfers t
    INNER   JOIN dbo.PoultryCashAccounts fa ON fa.PoultryCashAccountId = t.FromPoultryCashAccountId
    INNER   JOIN dbo.PoultryCashAccounts ta ON ta.PoultryCashAccountId = t.ToPoultryCashAccountId
    WHERE   t.FarmId = @FarmId
       AND  (@Status IS NULL OR t.Status = @Status)
    ORDER   BY t.TransferDate DESC, t.PoultryCashTransferId DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryCashTransfer_GetById
    @PoultryCashTransferId INT,
    @FarmId                NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  t.PoultryCashTransferId, t.FarmId,
            t.FromPoultryCashAccountId, fa.AccountName AS FromAccountName,
            t.ToPoultryCashAccountId,   ta.AccountName AS ToAccountName,
            t.TransferDate, t.Amount, t.Status, t.Notes,
            t.CreatedBy, t.ApprovedBy, t.ApprovedAt, t.CreatedAt, t.UpdatedAt
    FROM    dbo.PoultryCashTransfers t
    INNER   JOIN dbo.PoultryCashAccounts fa ON fa.PoultryCashAccountId = t.FromPoultryCashAccountId
    INNER   JOIN dbo.PoultryCashAccounts ta ON ta.PoultryCashAccountId = t.ToPoultryCashAccountId
    WHERE   t.PoultryCashTransferId = @PoultryCashTransferId AND t.FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryCashTransfer_Insert
    @FarmId                    NVARCHAR(450),
    @FromPoultryCashAccountId  INT,
    @ToPoultryCashAccountId    INT,
    @Amount                    DECIMAL(14,2),
    @TransferDate              DATETIME2     = NULL,
    @Notes                     NVARCHAR(500) = NULL,
    @CreatedBy                 NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF (@FromPoultryCashAccountId = @ToPoultryCashAccountId)
    BEGIN RAISERROR('Cash transfer cannot be to the same account.', 16, 1); RETURN; END
    IF (@Amount <= 0)
    BEGIN RAISERROR('Transfer amount must be greater than zero.', 16, 1); RETURN; END

    INSERT INTO dbo.PoultryCashTransfers (
        FarmId, FromPoultryCashAccountId, ToPoultryCashAccountId, TransferDate, Amount,
        Status, Notes, CreatedBy
    )
    VALUES (
        @FarmId, @FromPoultryCashAccountId, @ToPoultryCashAccountId,
        ISNULL(@TransferDate, SYSUTCDATETIME()), @Amount, 'Draft', @Notes, @CreatedBy
    );
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryCashTransfer_Approve
    @PoultryCashTransferId INT,
    @FarmId                NVARCHAR(450),
    @ApprovedBy            NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF EXISTS (SELECT 1 FROM dbo.PoultryCashTransfers
               WHERE PoultryCashTransferId = @PoultryCashTransferId AND FarmId = @FarmId AND Status = 'Approved')
    BEGIN
        SELECT PoultryCashTransferId, Status, ApprovedBy, ApprovedAt
        FROM   dbo.PoultryCashTransfers
        WHERE  PoultryCashTransferId = @PoultryCashTransferId AND FarmId = @FarmId;
        RETURN;
    END

    DECLARE @FromId INT, @ToId INT, @Amount DECIMAL(14,2), @Date DATETIME2, @Status NVARCHAR(20);
    SELECT @FromId = FromPoultryCashAccountId,
           @ToId   = ToPoultryCashAccountId,
           @Amount = Amount,
           @Date   = TransferDate,
           @Status = Status
    FROM   dbo.PoultryCashTransfers
    WHERE  PoultryCashTransferId = @PoultryCashTransferId AND FarmId = @FarmId;

    IF @FromId IS NULL
    BEGIN RAISERROR('Cash transfer %d not found.', 16, 1, @PoultryCashTransferId); RETURN; END
    IF @Status <> 'Draft'
    BEGIN RAISERROR('Cash transfer cannot be approved from status %s.', 16, 1, @Status); RETURN; END

    DECLARE @FromBalance DECIMAL(14,2), @AllowNeg BIT;
    SELECT @FromBalance = CurrentBalance, @AllowNeg = AllowNegativeBalance
    FROM   dbo.PoultryCashAccounts
    WHERE  PoultryCashAccountId = @FromId;
    IF (@AllowNeg = 0 AND (@FromBalance - @Amount) < 0)
    BEGIN RAISERROR('Source cash account would go negative; transfer rejected.', 16, 1); RETURN; END

    BEGIN TRANSACTION;

    UPDATE dbo.PoultryCashTransfers
    SET    Status = 'Approved', ApprovedBy = @ApprovedBy, ApprovedAt = SYSUTCDATETIME(),
           UpdatedAt = SYSUTCDATETIME()
    WHERE  PoultryCashTransferId = @PoultryCashTransferId AND FarmId = @FarmId;

    -- TransferOut leg
    INSERT INTO dbo.PoultryCashTransactions (
        FarmId, PoultryCashAccountId, TransactionDate, TransactionType,
        SourceType, SourceId, Amount, Description, CreatedBy, ApprovedBy, ApprovedAt
    )
    VALUES (
        @FarmId, @FromId, @Date, 'TransferOut',
        'Transfer', @PoultryCashTransferId, -@Amount, 'Transfer out', @ApprovedBy, @ApprovedBy, SYSUTCDATETIME()
    );
    UPDATE dbo.PoultryCashAccounts SET CurrentBalance = CurrentBalance - @Amount, UpdatedAt = SYSUTCDATETIME()
    WHERE  PoultryCashAccountId = @FromId;

    -- TransferIn leg
    INSERT INTO dbo.PoultryCashTransactions (
        FarmId, PoultryCashAccountId, TransactionDate, TransactionType,
        SourceType, SourceId, Amount, Description, CreatedBy, ApprovedBy, ApprovedAt
    )
    VALUES (
        @FarmId, @ToId, @Date, 'TransferIn',
        'Transfer', @PoultryCashTransferId, @Amount, 'Transfer in', @ApprovedBy, @ApprovedBy, SYSUTCDATETIME()
    );
    UPDATE dbo.PoultryCashAccounts SET CurrentBalance = CurrentBalance + @Amount, UpdatedAt = SYSUTCDATETIME()
    WHERE  PoultryCashAccountId = @ToId;

    COMMIT TRANSACTION;

    SELECT PoultryCashTransferId, Status, ApprovedBy, ApprovedAt
    FROM   dbo.PoultryCashTransfers
    WHERE  PoultryCashTransferId = @PoultryCashTransferId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryCashTransfer_Cancel
    @PoultryCashTransferId INT,
    @FarmId                NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.PoultryCashTransfers
    SET    Status = 'Cancelled', UpdatedAt = SYSUTCDATETIME()
    WHERE  PoultryCashTransferId = @PoultryCashTransferId AND FarmId = @FarmId AND Status = 'Draft';

    IF @@ROWCOUNT = 0
    BEGIN RAISERROR('Only draft transfers can be cancelled.', 16, 1); RETURN; END
END
GO

-- =============================================================================
-- Per-farm defaults seed (a few starter cash accounts). Poultry expenses use a
-- free-text Category, so no expense-category seeding is needed.
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.spPoultryFinance_SeedDefaults
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @accts TABLE (AccountName NVARCHAR(100), AccountType NVARCHAR(30));
    INSERT INTO @accts(AccountName, AccountType) VALUES
        ('Farm Cash Box', 'FarmCashBox'),
        ('MoMo Wallet',   'MoMoWallet'),
        ('Bank Account',  'BankAccount'),
        ('Petty Cash',    'PettyCash');

    INSERT INTO dbo.PoultryCashAccounts (FarmId, AccountName, AccountType, OpeningBalance, CurrentBalance)
    SELECT @FarmId, a.AccountName, a.AccountType, 0, 0
    FROM   @accts a
    WHERE  NOT EXISTS (
        SELECT 1 FROM dbo.PoultryCashAccounts x
        WHERE  x.FarmId = @FarmId AND x.AccountName = a.AccountName
    );

    SELECT (SELECT COUNT(*) FROM dbo.PoultryCashAccounts WHERE FarmId = @FarmId) AS CashAccountCount;
END
GO

-- =============================================================================
-- GRANT EXECUTE to the runtime login (app login is EXECUTE-only)
-- =============================================================================
IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    DECLARE @procName SYSNAME;
    DECLARE proc_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT name FROM sys.procedures
        WHERE name LIKE 'spPoultryCash%' OR name = 'spPoultryFinance_SeedDefaults';
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
    PRINT '129: granted EXECUTE on spPoultryCash*/spPoultryFinance_SeedDefaults to Techretainer.';
END
GO

PRINT '129_AddPoultryCashStoredProcedures: complete.';
GO
