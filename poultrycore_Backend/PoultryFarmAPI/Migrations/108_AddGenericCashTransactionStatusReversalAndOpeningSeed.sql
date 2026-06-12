-- =============================================================================
-- 108_AddGenericCashTransactionStatusReversalAndOpeningSeed
-- =============================================================================
-- Cash Account integration - Slice 1 (Foundation).
--
-- Purely ADDITIVE. Existing posting SPs (spGenericSale_Approve,
-- spGenericExpense_Approve, spGenericPurchase_Approve, spGenericSupplierPayment_*,
-- spGenericCashTransfer_*, payroll, adjustments) continue to work unchanged:
-- the new columns all have safe defaults so their column-listed INSERTs still
-- compile and get Status='Approved'.
--
-- What this migration adds:
--   1. GenericCashTransactions: Status, ReversalOfTransactionId, ReversedBy,
--      ReversedAt, Notes columns (+ supporting index for idempotency lookups).
--   2. Opening-balance is now represented as an auditable 'OpeningBalance'
--      cash transaction (seeded on account create + backfilled for existing
--      accounts) so SUM(Amount) reconciles to CurrentBalance.
--   3. spGenericCashTransaction_Reverse: one reusable proc that posts an
--      equal-and-opposite transaction, links it via ReversalOfTransactionId,
--      and marks the original Reversed. Used by the generic money-flow
--      reversals (slice 2) and available to any workflow that voids a posting.
--   4. The two read procs return the new columns.
-- =============================================================================

SET XACT_ABORT ON;
GO

-- -----------------------------------------------------------------------------
-- 1. New columns on GenericCashTransactions (idempotent via COL_LENGTH guards)
-- -----------------------------------------------------------------------------
IF COL_LENGTH('dbo.GenericCashTransactions', 'Status') IS NULL
    ALTER TABLE dbo.GenericCashTransactions
        ADD Status NVARCHAR(20) NOT NULL
            CONSTRAINT DF_GenericCashTransactions_Status DEFAULT ('Approved');  -- Pending | Approved | Reversed | Cancelled
GO

IF COL_LENGTH('dbo.GenericCashTransactions', 'ReversalOfTransactionId') IS NULL
    ALTER TABLE dbo.GenericCashTransactions
        ADD ReversalOfTransactionId BIGINT NULL;   -- set on a reversal row, points at the original
GO

IF COL_LENGTH('dbo.GenericCashTransactions', 'ReversedBy') IS NULL
    ALTER TABLE dbo.GenericCashTransactions ADD ReversedBy NVARCHAR(450) NULL;
GO

IF COL_LENGTH('dbo.GenericCashTransactions', 'ReversedAt') IS NULL
    ALTER TABLE dbo.GenericCashTransactions ADD ReversedAt DATETIME2 NULL;
GO

IF COL_LENGTH('dbo.GenericCashTransactions', 'Notes') IS NULL
    ALTER TABLE dbo.GenericCashTransactions ADD Notes NVARCHAR(1000) NULL;
GO

-- Supports idempotency checks (FarmId, SourceType, SourceId, TransactionType)
-- and reversal lookups. Non-unique on purpose: transfers legitimately produce
-- two rows per source and historical data is not de-duplicated here.
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_GenericCashTransactions_SourceType_TxnType'
                 AND object_id = OBJECT_ID('dbo.GenericCashTransactions'))
    CREATE INDEX IX_GenericCashTransactions_SourceType_TxnType
        ON dbo.GenericCashTransactions (FarmId, SourceType, SourceId, TransactionType);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_GenericCashTransactions_ReversalOf'
                 AND object_id = OBJECT_ID('dbo.GenericCashTransactions'))
    CREATE INDEX IX_GenericCashTransactions_ReversalOf
        ON dbo.GenericCashTransactions (ReversalOfTransactionId)
        WHERE ReversalOfTransactionId IS NOT NULL;
GO

-- -----------------------------------------------------------------------------
-- 2. Read procs return the new columns
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spGenericCashTransaction_GetByAccount
    @GenericCashAccountId INT,
    @FarmId               NVARCHAR(450),
    @FromDate             DATETIME2 = NULL,
    @ToDate               DATETIME2 = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT t.GenericCashTransactionId, t.FarmId, t.GenericCashAccountId,
           a.AccountName,
           t.TransactionDate, t.TransactionType, t.SourceType, t.SourceId,
           t.Amount, t.BalanceAfterTransaction, t.Description,
           t.CreatedBy, t.ApprovedBy, t.ApprovedAt, t.CreatedAt,
           t.Status, t.ReversalOfTransactionId, t.ReversedBy, t.ReversedAt, t.Notes
    FROM   dbo.GenericCashTransactions t
    INNER  JOIN dbo.GenericCashAccounts a ON a.GenericCashAccountId = t.GenericCashAccountId
    WHERE  t.GenericCashAccountId = @GenericCashAccountId
       AND t.FarmId = @FarmId
       AND (@FromDate IS NULL OR t.TransactionDate >= @FromDate)
       AND (@ToDate   IS NULL OR t.TransactionDate <= @ToDate)
    ORDER  BY t.TransactionDate DESC, t.GenericCashTransactionId DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericCashTransaction_GetByFarm
    @FarmId   NVARCHAR(450),
    @FromDate DATETIME2 = NULL,
    @ToDate   DATETIME2 = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT t.GenericCashTransactionId, t.FarmId, t.GenericCashAccountId,
           a.AccountName,
           t.TransactionDate, t.TransactionType, t.SourceType, t.SourceId,
           t.Amount, t.BalanceAfterTransaction, t.Description,
           t.CreatedBy, t.ApprovedBy, t.ApprovedAt, t.CreatedAt,
           t.Status, t.ReversalOfTransactionId, t.ReversedBy, t.ReversedAt, t.Notes
    FROM   dbo.GenericCashTransactions t
    INNER  JOIN dbo.GenericCashAccounts a ON a.GenericCashAccountId = t.GenericCashAccountId
    WHERE  t.FarmId = @FarmId
       AND (@FromDate IS NULL OR t.TransactionDate >= @FromDate)
       AND (@ToDate   IS NULL OR t.TransactionDate <= @ToDate)
    ORDER  BY t.TransactionDate DESC, t.GenericCashTransactionId DESC;
END
GO

-- -----------------------------------------------------------------------------
-- 3. Opening balance as an auditable transaction
-- -----------------------------------------------------------------------------
-- Account create still sets CurrentBalance = OpeningBalance (unchanged), but now
-- also seeds a matching 'OpeningBalance' cash transaction so the ledger reconciles.
CREATE OR ALTER PROCEDURE dbo.spGenericCashAccount_Insert
    @FarmId                NVARCHAR(450),
    @AccountName           NVARCHAR(150),
    @AccountType           NVARCHAR(40),
    @OpeningBalance        DECIMAL(14,2) = 0,
    @AllowNegativeBalance  BIT           = 0,
    @Notes                 NVARCHAR(500) = NULL,
    @CreatedBy             NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    INSERT INTO dbo.GenericCashAccounts
        (FarmId, AccountName, AccountType, OpeningBalance, CurrentBalance, AllowNegativeBalance, Notes)
    VALUES
        (@FarmId, @AccountName, @AccountType, @OpeningBalance, @OpeningBalance, @AllowNegativeBalance, @Notes);

    DECLARE @NewId INT = CAST(SCOPE_IDENTITY() AS INT);

    IF (@OpeningBalance <> 0)
    BEGIN
        INSERT INTO dbo.GenericCashTransactions (
            FarmId, GenericCashAccountId, TransactionDate, TransactionType,
            SourceType, SourceId, Amount, BalanceAfterTransaction, Description,
            Status, CreatedBy, ApprovedBy, ApprovedAt
        )
        VALUES (
            @FarmId, @NewId, SYSUTCDATETIME(), 'CashIn',
            'OpeningBalance', @NewId, @OpeningBalance, @OpeningBalance, 'Opening balance',
            'Approved', @CreatedBy, @CreatedBy, SYSUTCDATETIME()
        );
    END

    COMMIT TRANSACTION;

    SELECT @NewId;
END
GO

-- One-time backfill: seed an OpeningBalance transaction for existing accounts
-- that have a non-zero opening balance but no opening transaction yet.
INSERT INTO dbo.GenericCashTransactions (
    FarmId, GenericCashAccountId, TransactionDate, TransactionType,
    SourceType, SourceId, Amount, BalanceAfterTransaction, Description,
    Status, CreatedBy, ApprovedBy, ApprovedAt
)
SELECT a.FarmId, a.GenericCashAccountId, a.CreatedAt, 'CashIn',
       'OpeningBalance', a.GenericCashAccountId, a.OpeningBalance, a.OpeningBalance,
       'Opening balance (backfilled)', 'Approved', NULL, NULL, a.CreatedAt
FROM   dbo.GenericCashAccounts a
WHERE  a.OpeningBalance <> 0
  AND  NOT EXISTS (
        SELECT 1 FROM dbo.GenericCashTransactions t
        WHERE  t.GenericCashAccountId = a.GenericCashAccountId
           AND t.FarmId = a.FarmId
           AND t.SourceType = 'OpeningBalance');
GO

-- -----------------------------------------------------------------------------
-- 4. Reusable reversal proc
-- -----------------------------------------------------------------------------
-- Posts an equal-and-opposite transaction for an existing Approved transaction,
-- links it via ReversalOfTransactionId, marks the original Reversed, and updates
-- the cash account balance inside one transaction. Idempotent: a transaction
-- that is already Reversed returns its existing reversal row instead of posting
-- a second one.
CREATE OR ALTER PROCEDURE dbo.spGenericCashTransaction_Reverse
    @GenericCashTransactionId BIGINT,
    @FarmId                   NVARCHAR(450),
    @ReversedBy               NVARCHAR(450) = NULL,
    @Reason                   NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @AccountId INT, @Amount DECIMAL(14,2), @TxnType NVARCHAR(20),
            @SourceType NVARCHAR(40), @SourceId INT, @Status NVARCHAR(20),
            @TxnDate DATETIME2, @Desc NVARCHAR(500);

    SELECT @AccountId  = GenericCashAccountId,
           @Amount     = Amount,
           @TxnType    = TransactionType,
           @SourceType = SourceType,
           @SourceId   = SourceId,
           @Status     = Status,
           @TxnDate    = TransactionDate,
           @Desc       = Description
    FROM   dbo.GenericCashTransactions
    WHERE  GenericCashTransactionId = @GenericCashTransactionId AND FarmId = @FarmId;

    IF @AccountId IS NULL
    BEGIN
        RAISERROR('Cash transaction %I64d not found.', 16, 1, @GenericCashTransactionId);
        RETURN;
    END

    -- Idempotent: already reversed -> return the existing reversal row.
    IF @Status = 'Reversed'
    BEGIN
        SELECT GenericCashTransactionId, BalanceAfterTransaction AS NewBalance
        FROM   dbo.GenericCashTransactions
        WHERE  FarmId = @FarmId AND ReversalOfTransactionId = @GenericCashTransactionId;
        RETURN;
    END

    IF @TxnType = 'OpeningBalance' OR @SourceType = 'OpeningBalance'
    BEGIN
        RAISERROR('Opening-balance transactions cannot be reversed; use an Opening Balance Correction adjustment.', 16, 1);
        RETURN;
    END

    -- Opposite direction / amount.
    DECLARE @RevType NVARCHAR(20) =
        CASE @TxnType
            WHEN 'CashIn'      THEN 'CashOut'
            WHEN 'CashOut'     THEN 'CashIn'
            WHEN 'TransferIn'  THEN 'TransferOut'
            WHEN 'TransferOut' THEN 'TransferIn'
            ELSE 'Adjustment'
        END;
    DECLARE @RevAmount DECIMAL(14,2) = -@Amount;

    DECLARE @AllowNeg BIT, @Current DECIMAL(14,2);
    SELECT @AllowNeg = AllowNegativeBalance, @Current = CurrentBalance
    FROM   dbo.GenericCashAccounts
    WHERE  GenericCashAccountId = @AccountId AND FarmId = @FarmId;

    IF @Current IS NULL
    BEGIN
        RAISERROR('Cash account for this transaction no longer exists.', 16, 1);
        RETURN;
    END

    DECLARE @NewBalance DECIMAL(14,2) = @Current + @RevAmount;
    IF (@NewBalance < 0 AND @AllowNeg = 0)
    BEGIN
        RAISERROR('Reversal would push the cash account negative; account does not allow it.', 16, 1);
        RETURN;
    END

    BEGIN TRANSACTION;

    INSERT INTO dbo.GenericCashTransactions (
        FarmId, GenericCashAccountId, TransactionDate, TransactionType,
        SourceType, SourceId, Amount, BalanceAfterTransaction, Description,
        Status, CreatedBy, ApprovedBy, ApprovedAt, ReversalOfTransactionId, Notes
    )
    VALUES (
        @FarmId, @AccountId, SYSUTCDATETIME(), @RevType,
        @SourceType, @SourceId, @RevAmount, @NewBalance,
        CONCAT('Reversal of #', CAST(@GenericCashTransactionId AS NVARCHAR(20)),
               ISNULL(' - ' + @Desc, '')),
        'Approved', @ReversedBy, @ReversedBy, SYSUTCDATETIME(),
        @GenericCashTransactionId, @Reason
    );

    DECLARE @NewId BIGINT = CAST(SCOPE_IDENTITY() AS BIGINT);

    UPDATE dbo.GenericCashAccounts
    SET    CurrentBalance = @NewBalance, UpdatedAt = SYSUTCDATETIME()
    WHERE  GenericCashAccountId = @AccountId AND FarmId = @FarmId;

    UPDATE dbo.GenericCashTransactions
    SET    Status = 'Reversed', ReversedBy = @ReversedBy, ReversedAt = SYSUTCDATETIME()
    WHERE  GenericCashTransactionId = @GenericCashTransactionId AND FarmId = @FarmId;

    COMMIT TRANSACTION;

    SELECT @NewId AS GenericCashTransactionId, @NewBalance AS NewBalance;
END
GO
