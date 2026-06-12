-- =============================================================================
-- 110_AddGenericCashNegativeBalancePolicy
-- =============================================================================
-- Cash Account integration - Slice 3 (tiered negative-balance policy).
--
-- Replaces the binary AllowNegativeBalance with a tiered policy:
--   DoNotAllow | AllowWithApproval | AllowUpToLimit | AlwaysAllow  (+ a limit).
--
-- Enforcement is CENTRALIZED in an AFTER UPDATE trigger on GenericCashAccounts
-- so EVERY writer (legacy spGeneric*_Approve, transfers, payroll, the new
-- movement/reverse/adjustment procs) is covered WITHOUT editing those procs.
--
-- Backward compatibility: the legacy BIT column AllowNegativeBalance is kept and
-- auto-synced from the policy (DoNotAllow/AllowWithApproval -> 0, others -> 1) so
-- existing procs that read the bit still behave correctly. AllowWithApproval maps
-- to 0 (blocks) because the override workflow is a later increment; the trigger
-- treats it with a zero floor for the same reason.
-- =============================================================================

SET XACT_ABORT ON;
GO

-- -----------------------------------------------------------------------------
-- 1. Policy columns + backfill from the existing bit
-- -----------------------------------------------------------------------------
IF COL_LENGTH('dbo.GenericCashAccounts', 'NegativeBalancePolicy') IS NULL
    ALTER TABLE dbo.GenericCashAccounts
        ADD NegativeBalancePolicy NVARCHAR(20) NOT NULL
            CONSTRAINT DF_GenericCashAccounts_NegPolicy DEFAULT ('DoNotAllow');
GO

IF COL_LENGTH('dbo.GenericCashAccounts', 'NegativeBalanceLimit') IS NULL
    ALTER TABLE dbo.GenericCashAccounts
        ADD NegativeBalanceLimit DECIMAL(14,2) NOT NULL
            CONSTRAINT DF_GenericCashAccounts_NegLimit DEFAULT (0);
GO

-- Map any account that previously allowed negatives to AlwaysAllow.
UPDATE dbo.GenericCashAccounts
SET    NegativeBalancePolicy = 'AlwaysAllow'
WHERE  AllowNegativeBalance = 1
  AND  NegativeBalancePolicy = 'DoNotAllow';
GO

-- -----------------------------------------------------------------------------
-- 2. Central enforcement trigger
-- -----------------------------------------------------------------------------
-- Fires only when CurrentBalance is updated. Blocks an update that DECREASES the
-- balance below the policy floor. Increases, name-only edits, and AlwaysAllow
-- accounts are never blocked.
CREATE OR ALTER TRIGGER dbo.trgGenericCashAccounts_EnforceNegativePolicy
ON dbo.GenericCashAccounts
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT UPDATE(CurrentBalance) RETURN;

    IF EXISTS (
        SELECT 1
        FROM   inserted i
        INNER  JOIN deleted d ON d.GenericCashAccountId = i.GenericCashAccountId
        WHERE  i.CurrentBalance < d.CurrentBalance                 -- balance decreased
           AND i.NegativeBalancePolicy <> 'AlwaysAllow'
           AND i.CurrentBalance < CASE i.NegativeBalancePolicy
                                      WHEN 'AllowUpToLimit' THEN -i.NegativeBalanceLimit
                                      ELSE 0                       -- DoNotAllow / AllowWithApproval
                                  END
    )
    BEGIN
        ROLLBACK TRANSACTION;
        RAISERROR('Cash account negative-balance policy violated: this transaction would push the balance below the allowed limit. Add money, transfer funds, choose another account, or change the account''s negative-balance policy.', 16, 1);
        RETURN;
    END
END
GO

-- -----------------------------------------------------------------------------
-- 3. Account create/update become policy-aware (and keep the bit in sync)
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spGenericCashAccount_Insert
    @FarmId                NVARCHAR(450),
    @AccountName           NVARCHAR(150),
    @AccountType           NVARCHAR(40),
    @OpeningBalance        DECIMAL(14,2) = 0,
    @AllowNegativeBalance  BIT           = 0,
    @Notes                 NVARCHAR(500) = NULL,
    @CreatedBy             NVARCHAR(450) = NULL,
    @NegativeBalancePolicy NVARCHAR(20)  = NULL,
    @NegativeBalanceLimit  DECIMAL(14,2) = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Derive policy from the legacy bit when not supplied; then re-sync the bit.
    IF @NegativeBalancePolicy IS NULL
        SET @NegativeBalancePolicy = CASE WHEN @AllowNegativeBalance = 1 THEN 'AlwaysAllow' ELSE 'DoNotAllow' END;
    IF @NegativeBalancePolicy NOT IN ('DoNotAllow', 'AllowWithApproval', 'AllowUpToLimit', 'AlwaysAllow')
    BEGIN
        RAISERROR('Invalid NegativeBalancePolicy.', 16, 1);
        RETURN;
    END
    DECLARE @Bit BIT = CASE WHEN @NegativeBalancePolicy IN ('AllowUpToLimit', 'AlwaysAllow') THEN 1 ELSE 0 END;

    BEGIN TRANSACTION;

    INSERT INTO dbo.GenericCashAccounts
        (FarmId, AccountName, AccountType, OpeningBalance, CurrentBalance,
         AllowNegativeBalance, NegativeBalancePolicy, NegativeBalanceLimit, Notes)
    VALUES
        (@FarmId, @AccountName, @AccountType, @OpeningBalance, @OpeningBalance,
         @Bit, @NegativeBalancePolicy, @NegativeBalanceLimit, @Notes);

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

CREATE OR ALTER PROCEDURE dbo.spGenericCashAccount_Update
    @GenericCashAccountId  INT,
    @FarmId                NVARCHAR(450),
    @AccountName           NVARCHAR(150),
    @AccountType           NVARCHAR(40),
    @AllowNegativeBalance  BIT,
    @IsActive              BIT,
    @Notes                 NVARCHAR(500) = NULL,
    @NegativeBalancePolicy NVARCHAR(20)  = NULL,
    @NegativeBalanceLimit  DECIMAL(14,2) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    -- OpeningBalance and CurrentBalance are NOT updateable here; balance changes
    -- must flow through cash transactions for an audit trail.
    IF @NegativeBalancePolicy IS NULL
        SET @NegativeBalancePolicy = CASE WHEN @AllowNegativeBalance = 1 THEN 'AlwaysAllow' ELSE 'DoNotAllow' END;
    IF @NegativeBalancePolicy NOT IN ('DoNotAllow', 'AllowWithApproval', 'AllowUpToLimit', 'AlwaysAllow')
    BEGIN
        RAISERROR('Invalid NegativeBalancePolicy.', 16, 1);
        RETURN;
    END
    DECLARE @Bit BIT = CASE WHEN @NegativeBalancePolicy IN ('AllowUpToLimit', 'AlwaysAllow') THEN 1 ELSE 0 END;

    UPDATE dbo.GenericCashAccounts
    SET    AccountName = @AccountName, AccountType = @AccountType,
           AllowNegativeBalance = @Bit,
           NegativeBalancePolicy = @NegativeBalancePolicy,
           NegativeBalanceLimit = ISNULL(@NegativeBalanceLimit, NegativeBalanceLimit),
           IsActive = @IsActive, Notes = @Notes, UpdatedAt = SYSUTCDATETIME()
    WHERE  GenericCashAccountId = @GenericCashAccountId AND FarmId = @FarmId;
END
GO

-- -----------------------------------------------------------------------------
-- 4. Read proc returns the policy columns
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spGenericCashAccount_GetAll
    @FarmId  NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT GenericCashAccountId, FarmId, AccountName, AccountType, OpeningBalance,
           CurrentBalance, AllowNegativeBalance, NegativeBalancePolicy, NegativeBalanceLimit,
           IsActive, Notes, CreatedAt, UpdatedAt
    FROM   dbo.GenericCashAccounts
    WHERE  FarmId = @FarmId
    ORDER  BY IsActive DESC, AccountName;
END
GO
