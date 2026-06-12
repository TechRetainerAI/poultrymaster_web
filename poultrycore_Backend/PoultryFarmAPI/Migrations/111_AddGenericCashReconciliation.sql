-- =============================================================================
-- 111_AddGenericCashReconciliation
-- =============================================================================
-- Cash Account integration - Slice 4 (reconciliation). Additive.
--
-- Lets a user reconcile a cash account against a physical/bank count. The
-- difference (Actual - System) is posted as a 'ReconciliationAdjustment' cash
-- transaction so the running ledger stays the source of truth, and the account
-- records its last-reconciled point.
-- =============================================================================

SET XACT_ABORT ON;
GO

-- Last-reconciled tracking on the account (additive).
IF COL_LENGTH('dbo.GenericCashAccounts', 'LastReconciledAt') IS NULL
    ALTER TABLE dbo.GenericCashAccounts ADD LastReconciledAt DATETIME2 NULL;
GO
IF COL_LENGTH('dbo.GenericCashAccounts', 'LastReconciledBalance') IS NULL
    ALTER TABLE dbo.GenericCashAccounts ADD LastReconciledBalance DECIMAL(14,2) NULL;
GO

IF OBJECT_ID('dbo.GenericCashReconciliations', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.GenericCashReconciliations (
        GenericCashReconciliationId INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                      NVARCHAR(450)  NOT NULL,
        GenericCashAccountId        INT            NOT NULL,
        ReconciliationDate          DATETIME2      NOT NULL CONSTRAINT DF_GenericCashRecon_Date DEFAULT (SYSUTCDATETIME()),
        SystemBalance               DECIMAL(14,2)  NOT NULL,
        ActualBalance               DECIMAL(14,2)  NOT NULL,
        Difference                  DECIMAL(14,2)  NOT NULL,   -- Actual - System
        AdjustmentTransactionId     BIGINT         NULL,       -- the posted ReconciliationAdjustment, if any
        Reason                      NVARCHAR(500)  NULL,
        Notes                       NVARCHAR(1000) NULL,
        Status                      NVARCHAR(20)   NOT NULL CONSTRAINT DF_GenericCashRecon_Status DEFAULT ('Approved'),
        RequestedBy                 NVARCHAR(450)  NULL,
        ApprovedBy                  NVARCHAR(450)  NULL,
        CreatedAt                   DATETIME2      NOT NULL CONSTRAINT DF_GenericCashRecon_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FK_GenericCashRecon_Account
            FOREIGN KEY (GenericCashAccountId) REFERENCES dbo.GenericCashAccounts (GenericCashAccountId)
    );
    CREATE INDEX IX_GenericCashRecon_FarmId  ON dbo.GenericCashReconciliations (FarmId);
    CREATE INDEX IX_GenericCashRecon_Account ON dbo.GenericCashReconciliations (GenericCashAccountId);
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericCashReconciliation_Create
    @FarmId               NVARCHAR(450),
    @GenericCashAccountId INT,
    @ActualBalance        DECIMAL(14,2),
    @ReconciliationDate   DATETIME2     = NULL,
    @Reason               NVARCHAR(500) = NULL,
    @Notes                NVARCHAR(1000) = NULL,
    @RequestedBy          NVARCHAR(450) = NULL,
    @ApprovedBy           NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @System DECIMAL(14,2), @IsActive BIT;
    SELECT @System = CurrentBalance, @IsActive = IsActive
    FROM   dbo.GenericCashAccounts
    WHERE  GenericCashAccountId = @GenericCashAccountId AND FarmId = @FarmId;

    IF @System IS NULL
    BEGIN
        RAISERROR('Cash account not found.', 16, 1);
        RETURN;
    END

    DECLARE @Diff DECIMAL(14,2) = @ActualBalance - @System;
    DECLARE @When DATETIME2 = ISNULL(@ReconciliationDate, SYSUTCDATETIME());
    DECLARE @AdjId BIGINT = NULL;

    BEGIN TRANSACTION;

    IF (@Diff <> 0)
    BEGIN
        INSERT INTO dbo.GenericCashTransactions (
            FarmId, GenericCashAccountId, TransactionDate, TransactionType,
            SourceType, SourceId, Amount, BalanceAfterTransaction, Description,
            Status, CreatedBy, ApprovedBy, ApprovedAt, Notes
        )
        VALUES (
            @FarmId, @GenericCashAccountId, @When,
            CASE WHEN @Diff > 0 THEN 'CashIn' ELSE 'CashOut' END,
            'ReconciliationAdjustment', NULL, @Diff, @ActualBalance,
            CONCAT('Reconciliation adjustment (', CASE WHEN @Diff > 0 THEN 'over' ELSE 'short' END, ')'),
            'Approved', @RequestedBy, @ApprovedBy, SYSUTCDATETIME(), @Reason
        );
        SET @AdjId = CAST(SCOPE_IDENTITY() AS BIGINT);

        UPDATE dbo.GenericCashAccounts
        SET    CurrentBalance = @ActualBalance, UpdatedAt = SYSUTCDATETIME()
        WHERE  GenericCashAccountId = @GenericCashAccountId AND FarmId = @FarmId;
    END

    INSERT INTO dbo.GenericCashReconciliations (
        FarmId, GenericCashAccountId, ReconciliationDate, SystemBalance,
        ActualBalance, Difference, AdjustmentTransactionId, Reason, Notes,
        Status, RequestedBy, ApprovedBy
    )
    VALUES (
        @FarmId, @GenericCashAccountId, @When, @System,
        @ActualBalance, @Diff, @AdjId, @Reason, @Notes,
        'Approved', @RequestedBy, @ApprovedBy
    );

    DECLARE @ReconId INT = CAST(SCOPE_IDENTITY() AS INT);

    UPDATE dbo.GenericCashAccounts
    SET    LastReconciledAt = @When, LastReconciledBalance = @ActualBalance,
           UpdatedAt = SYSUTCDATETIME()
    WHERE  GenericCashAccountId = @GenericCashAccountId AND FarmId = @FarmId;

    COMMIT TRANSACTION;

    SELECT @ReconId AS GenericCashReconciliationId, @Diff AS Difference,
           @AdjId AS AdjustmentTransactionId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericCashReconciliation_GetByAccount
    @GenericCashAccountId INT,
    @FarmId               NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT r.GenericCashReconciliationId, r.FarmId, r.GenericCashAccountId, a.AccountName,
           r.ReconciliationDate, r.SystemBalance, r.ActualBalance, r.Difference,
           r.AdjustmentTransactionId, r.Reason, r.Notes, r.Status,
           r.RequestedBy, r.ApprovedBy, r.CreatedAt
    FROM   dbo.GenericCashReconciliations r
    INNER  JOIN dbo.GenericCashAccounts a ON a.GenericCashAccountId = r.GenericCashAccountId
    WHERE  r.GenericCashAccountId = @GenericCashAccountId AND r.FarmId = @FarmId
    ORDER  BY r.ReconciliationDate DESC, r.GenericCashReconciliationId DESC;
END
GO

-- Account read now also surfaces the policy + last-reconciled columns.
CREATE OR ALTER PROCEDURE dbo.spGenericCashAccount_GetAll
    @FarmId  NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT GenericCashAccountId, FarmId, AccountName, AccountType, OpeningBalance,
           CurrentBalance, AllowNegativeBalance, NegativeBalancePolicy, NegativeBalanceLimit,
           IsActive, Notes, CreatedAt, UpdatedAt, LastReconciledAt, LastReconciledBalance
    FROM   dbo.GenericCashAccounts
    WHERE  FarmId = @FarmId
    ORDER  BY IsActive DESC, AccountName;
END
GO
