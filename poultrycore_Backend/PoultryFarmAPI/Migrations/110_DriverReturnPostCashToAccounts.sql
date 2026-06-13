/* ============================================================================
   110_DriverReturnPostCashToAccounts.sql

   Driver-return reconciliation never posted the collected money to a cash
   account, so the Cash Accounts page balances never moved (James 2026-06-13).

   These two helper SPs are called by the C# service right after approve and
   reverse. They are idempotent and only touch WaterCashTransactions +
   WaterCashAccounts.CurrentBalance — the daily-closing reads driver returns
   directly, so this does NOT change any closing figure (no double count).

   Routing: Cash -> first active cash-type account, MoMo -> MoMo account,
   Bank -> bank account, each falling back to the first active account.
   Idempotent (CREATE OR ALTER + guards).
   ============================================================================ */

CREATE OR ALTER PROCEDURE dbo.spWaterDriverReturn_PostCashAccounts
    @WaterDriverReturnId INT,
    @FarmId    NVARCHAR(450),
    @PostedBy  NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;

    -- Idempotent: never double-post for the same return.
    IF EXISTS (SELECT 1 FROM dbo.WaterCashTransactions
               WHERE FarmId = @FarmId AND SourceType = N'DriverReturn'
                 AND SourceId = @WaterDriverReturnId)
        RETURN;

    DECLARE @Cash DECIMAL(14,2), @MoMo DECIMAL(14,2), @Bank DECIMAL(14,2),
            @Date DATETIME2(7), @Status NVARCHAR(20);
    SELECT @Cash = ISNULL(CashCollected,0), @MoMo = ISNULL(MoMoCollected,0),
           @Bank = ISNULL(BankCollected,0), @Date = ReturnDate, @Status = Status
    FROM   dbo.WaterDriverReturns
    WHERE  WaterDriverReturnId = @WaterDriverReturnId AND FarmId = @FarmId;

    -- Only an approved return represents real money in.
    IF @Status IS NULL OR @Status <> N'Approved' RETURN;
    IF (@Cash <= 0 AND @MoMo <= 0 AND @Bank <= 0) RETURN;

    DECLARE @First INT, @CashAcc INT, @MoMoAcc INT, @BankAcc INT;
    SELECT TOP 1 @First = WaterCashAccountId FROM dbo.WaterCashAccounts
    WHERE  FarmId = @FarmId AND IsActive = 1 ORDER BY WaterCashAccountId;
    IF @First IS NULL RETURN;   -- no cash accounts to post into

    SELECT TOP 1 @CashAcc = WaterCashAccountId FROM dbo.WaterCashAccounts
    WHERE  FarmId = @FarmId AND IsActive = 1
       AND AccountType IN (N'FactoryCashBox',N'PettyCash',N'DriverCash',N'Cash') ORDER BY WaterCashAccountId;
    SELECT TOP 1 @MoMoAcc = WaterCashAccountId FROM dbo.WaterCashAccounts
    WHERE  FarmId = @FarmId AND IsActive = 1
       AND AccountType IN (N'MoMoWallet',N'MoMo',N'Mobile Money') ORDER BY WaterCashAccountId;
    SELECT TOP 1 @BankAcc = WaterCashAccountId FROM dbo.WaterCashAccounts
    WHERE  FarmId = @FarmId AND IsActive = 1
       AND AccountType IN (N'BankAccount',N'Bank',N'Bank Transfer') ORDER BY WaterCashAccountId;

    SET @CashAcc = ISNULL(@CashAcc, @First);
    SET @MoMoAcc = ISNULL(@MoMoAcc, @First);
    SET @BankAcc = ISNULL(@BankAcc, @First);
    DECLARE @when DATETIME2(7) = ISNULL(@Date, SYSUTCDATETIME());

    BEGIN TRANSACTION;

    IF @Cash > 0
    BEGIN
        INSERT INTO dbo.WaterCashTransactions
            (FarmId, WaterCashAccountId, TransactionDate, TransactionType, SourceType, SourceId, Amount, Description, CreatedBy, ApprovedBy, ApprovedAt)
        VALUES (@FarmId, @CashAcc, @when, N'CashIn', N'DriverReturn', @WaterDriverReturnId, @Cash,
                CONCAT(N'Driver return #', @WaterDriverReturnId, N' — cash collected'), @PostedBy, @PostedBy, SYSUTCDATETIME());
        UPDATE dbo.WaterCashAccounts SET CurrentBalance = CurrentBalance + @Cash, UpdatedAt = SYSUTCDATETIME()
        WHERE  WaterCashAccountId = @CashAcc;
    END

    IF @MoMo > 0
    BEGIN
        INSERT INTO dbo.WaterCashTransactions
            (FarmId, WaterCashAccountId, TransactionDate, TransactionType, SourceType, SourceId, Amount, Description, CreatedBy, ApprovedBy, ApprovedAt)
        VALUES (@FarmId, @MoMoAcc, @when, N'CashIn', N'DriverReturn', @WaterDriverReturnId, @MoMo,
                CONCAT(N'Driver return #', @WaterDriverReturnId, N' — MoMo collected'), @PostedBy, @PostedBy, SYSUTCDATETIME());
        UPDATE dbo.WaterCashAccounts SET CurrentBalance = CurrentBalance + @MoMo, UpdatedAt = SYSUTCDATETIME()
        WHERE  WaterCashAccountId = @MoMoAcc;
    END

    IF @Bank > 0
    BEGIN
        INSERT INTO dbo.WaterCashTransactions
            (FarmId, WaterCashAccountId, TransactionDate, TransactionType, SourceType, SourceId, Amount, Description, CreatedBy, ApprovedBy, ApprovedAt)
        VALUES (@FarmId, @BankAcc, @when, N'CashIn', N'DriverReturn', @WaterDriverReturnId, @Bank,
                CONCAT(N'Driver return #', @WaterDriverReturnId, N' — bank collected'), @PostedBy, @PostedBy, SYSUTCDATETIME());
        UPDATE dbo.WaterCashAccounts SET CurrentBalance = CurrentBalance + @Bank, UpdatedAt = SYSUTCDATETIME()
        WHERE  WaterCashAccountId = @BankAcc;
    END

    COMMIT TRANSACTION;
END
GO

-- Undo the cash posted above when a reconciliation is reversed. Idempotent.
CREATE OR ALTER PROCEDURE dbo.spWaterDriverReturn_ReverseCashAccounts
    @WaterDriverReturnId INT,
    @FarmId     NVARCHAR(450),
    @ReversedBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.WaterCashTransactions
                   WHERE FarmId = @FarmId AND SourceType = N'DriverReturn'
                     AND SourceId = @WaterDriverReturnId)
        RETURN;

    BEGIN TRANSACTION;

    -- Roll each affected account back by what this return added.
    UPDATE a
    SET    a.CurrentBalance = a.CurrentBalance - x.PostedAmount, a.UpdatedAt = SYSUTCDATETIME()
    FROM   dbo.WaterCashAccounts a
    JOIN  (SELECT WaterCashAccountId, PostedAmount = SUM(Amount)
           FROM dbo.WaterCashTransactions
           WHERE FarmId = @FarmId AND SourceType = N'DriverReturn' AND SourceId = @WaterDriverReturnId
           GROUP BY WaterCashAccountId) x
      ON   x.WaterCashAccountId = a.WaterCashAccountId;

    DELETE FROM dbo.WaterCashTransactions
    WHERE  FarmId = @FarmId AND SourceType = N'DriverReturn' AND SourceId = @WaterDriverReturnId;

    COMMIT TRANSACTION;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spWaterDriverReturn_PostCashAccounts    TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterDriverReturn_ReverseCashAccounts TO [Techretainer];
END
GO
