-- =============================================================================
-- Migration 128: Poultry Cash Account tables (port of Water finance, mig 047).
-- =============================================================================
-- Multi-account cash management for Poultry farms. FarmId is NVARCHAR(450)
-- (matches Farms.Id, same as the Water tables). Balance is a denormalised cache
-- maintained by the SPs; source-of-truth is SUM(Amount) on the signed ledger.
-- Idempotent (OBJECT_ID guards).
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- 1. PoultryCashAccounts -------------------------------------------------------
IF OBJECT_ID('dbo.PoultryCashAccounts', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PoultryCashAccounts (
        PoultryCashAccountId  INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                NVARCHAR(450)  NOT NULL,
        AccountName           NVARCHAR(100)  NOT NULL,
        AccountType           NVARCHAR(30)   NOT NULL,
        OpeningBalance        DECIMAL(14,2)  NOT NULL CONSTRAINT DF_PoultryCashAccounts_Opening DEFAULT (0),
        CurrentBalance        DECIMAL(14,2)  NOT NULL CONSTRAINT DF_PoultryCashAccounts_Current DEFAULT (0),
        AllowNegativeBalance  BIT            NOT NULL CONSTRAINT DF_PoultryCashAccounts_AllowNeg DEFAULT (0),
        IsActive              BIT            NOT NULL CONSTRAINT DF_PoultryCashAccounts_IsActive DEFAULT (1),
        Notes                 NVARCHAR(500)  NULL,
        CreatedAt             DATETIME2      NOT NULL CONSTRAINT DF_PoultryCashAccounts_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt             DATETIME2      NULL,
        CONSTRAINT UQ_PoultryCashAccounts_Farm_Name UNIQUE (FarmId, AccountName)
    );
    CREATE INDEX IX_PoultryCashAccounts_FarmId ON dbo.PoultryCashAccounts (FarmId);
    PRINT '128: created dbo.PoultryCashAccounts';
END
GO

-- 2. PoultryCashTransactions (signed ledger; + inflow, - outflow) --------------
IF OBJECT_ID('dbo.PoultryCashTransactions', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PoultryCashTransactions (
        PoultryCashTransactionId INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                   NVARCHAR(450)  NOT NULL,
        PoultryCashAccountId     INT            NOT NULL,
        TransactionDate          DATETIME2      NOT NULL CONSTRAINT DF_PoultryCashTx_Date DEFAULT (SYSUTCDATETIME()),
        TransactionType          NVARCHAR(30)   NOT NULL,   -- CashIn, CashOut, TransferIn, TransferOut, AdjustmentIn, AdjustmentOut
        SourceType               NVARCHAR(40)   NULL,        -- Payroll, Expense, Transfer, Adjustment, ...
        SourceId                 INT            NULL,
        Amount                   DECIMAL(14,2)  NOT NULL,    -- signed
        BalanceAfterTransaction  DECIMAL(14,2)  NULL,
        Description              NVARCHAR(500)  NULL,
        CreatedBy                NVARCHAR(450)  NULL,
        ApprovedBy               NVARCHAR(450)  NULL,
        ApprovedAt               DATETIME2      NULL,
        CreatedAt                DATETIME2      NOT NULL CONSTRAINT DF_PoultryCashTx_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FK_PoultryCashTx_Account
            FOREIGN KEY (PoultryCashAccountId) REFERENCES dbo.PoultryCashAccounts (PoultryCashAccountId)
    );
    CREATE INDEX IX_PoultryCashTx_FarmId  ON dbo.PoultryCashTransactions (FarmId);
    CREATE INDEX IX_PoultryCashTx_Account ON dbo.PoultryCashTransactions (PoultryCashAccountId);
    CREATE INDEX IX_PoultryCashTx_Date    ON dbo.PoultryCashTransactions (TransactionDate);
    CREATE INDEX IX_PoultryCashTx_Source  ON dbo.PoultryCashTransactions (SourceType, SourceId);
    PRINT '128: created dbo.PoultryCashTransactions';
END
GO

-- 3. PoultryCashTransfers (paired legs posted on approve) ----------------------
IF OBJECT_ID('dbo.PoultryCashTransfers', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PoultryCashTransfers (
        PoultryCashTransferId     INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                    NVARCHAR(450)  NOT NULL,
        FromPoultryCashAccountId  INT            NOT NULL,
        ToPoultryCashAccountId    INT            NOT NULL,
        TransferDate              DATETIME2      NOT NULL CONSTRAINT DF_PoultryCashTransfers_Date DEFAULT (SYSUTCDATETIME()),
        Amount                    DECIMAL(14,2)  NOT NULL,
        Status                    NVARCHAR(20)   NOT NULL CONSTRAINT DF_PoultryCashTransfers_Status DEFAULT ('Draft'),
        Notes                     NVARCHAR(500)  NULL,
        CreatedBy                 NVARCHAR(450)  NULL,
        ApprovedBy                NVARCHAR(450)  NULL,
        ApprovedAt                DATETIME2      NULL,
        CreatedAt                 DATETIME2      NOT NULL CONSTRAINT DF_PoultryCashTransfers_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt                 DATETIME2      NULL,
        CONSTRAINT FK_PoultryCashTransfers_From FOREIGN KEY (FromPoultryCashAccountId) REFERENCES dbo.PoultryCashAccounts (PoultryCashAccountId),
        CONSTRAINT FK_PoultryCashTransfers_To   FOREIGN KEY (ToPoultryCashAccountId)   REFERENCES dbo.PoultryCashAccounts (PoultryCashAccountId),
        CONSTRAINT CK_PoultryCashTransfers_DifferentAccounts CHECK (FromPoultryCashAccountId <> ToPoultryCashAccountId)
    );
    CREATE INDEX IX_PoultryCashTransfers_FarmId ON dbo.PoultryCashTransfers (FarmId);
    CREATE INDEX IX_PoultryCashTransfers_From   ON dbo.PoultryCashTransfers (FromPoultryCashAccountId);
    CREATE INDEX IX_PoultryCashTransfers_To     ON dbo.PoultryCashTransfers (ToPoultryCashAccountId);
    CREATE INDEX IX_PoultryCashTransfers_Status ON dbo.PoultryCashTransfers (Status);
    PRINT '128: created dbo.PoultryCashTransfers';
END
GO

PRINT '128_AddPoultryCashTables: complete.';
GO
