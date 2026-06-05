-- =============================================================================
-- Migration 047: Water Company finance layer (Expenses, Cash, Customer Ledger)
-- =============================================================================
-- Fills the gaps in the Water Company module that the spec
-- (Main Prompt - Water Company for Claude Code.txt) describes:
--
--   §6.5 Customer Ledger
--   §9   Expense Categories + Expenses
--   §10  Cash Accounts + Transactions + Transfers
--
-- Same FarmId-scoping + status-workflow patterns as the Generic Company
-- finance layer (migrations 030-036). Stored procs come in migration 048.
--
-- Run order (sqlcmd):
--   025 (multi-company schema) → 026 (multi-company SPs) → ... → 046 → 047 → 048
--
-- Safety:
--   * Idempotent via IF OBJECT_ID(...) IS NULL.
--   * Additive only — no existing rows altered.
--   * No drops, no schema changes on existing tables.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- 1. WaterExpenseCategories  (per-FarmId; seeded with Ghana sachet-water defaults)
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.WaterExpenseCategories', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterExpenseCategories (
        WaterExpenseCategoryId  INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                  NVARCHAR(450)  NOT NULL,
        Name                    NVARCHAR(100)  NOT NULL,
        Description             NVARCHAR(500)  NULL,
        IsActive                BIT            NOT NULL CONSTRAINT DF_WaterExpenseCategories_IsActive  DEFAULT (1),
        IsDeleted               BIT            NOT NULL CONSTRAINT DF_WaterExpenseCategories_IsDeleted DEFAULT (0),
        CreatedAt               DATETIME2      NOT NULL CONSTRAINT DF_WaterExpenseCategories_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt               DATETIME2      NULL,
        CONSTRAINT UQ_WaterExpenseCategories_Farm_Name UNIQUE (FarmId, Name)
    );

    CREATE INDEX IX_WaterExpenseCategories_FarmId ON dbo.WaterExpenseCategories (FarmId);
END
GO

-- -----------------------------------------------------------------------------
-- 2. WaterExpenses (Draft → Submitted → Approved/Rejected/Cancelled)
-- -----------------------------------------------------------------------------
-- Status values (validated at app layer): Draft, Submitted, Approved, Rejected,
-- Cancelled.
-- PaymentMethod values: Cash, MoMo, Bank, Card, Credit, Mixed.
-- On Approve: if PaymentMethod <> Credit, debit the linked CashAccount.
-- Optional links to vehicle/machine/production batch let us pivot Expenses by
-- asset for "fuel cost by vehicle" and "repair cost by machine" reports.
IF OBJECT_ID('dbo.WaterExpenses', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterExpenses (
        WaterExpenseId             INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                     NVARCHAR(450)  NOT NULL,
        ExpenseDate                DATETIME2      NOT NULL CONSTRAINT DF_WaterExpenses_Date DEFAULT (SYSUTCDATETIME()),
        WaterExpenseCategoryId     INT            NOT NULL,
        Description                NVARCHAR(500)  NULL,
        Amount                     DECIMAL(14,2)  NOT NULL,
        PaidTo                     NVARCHAR(200)  NULL,
        PaymentMethod              NVARCHAR(20)   NOT NULL CONSTRAINT DF_WaterExpenses_PaymentMethod DEFAULT ('Cash'),
        WaterCashAccountId         INT            NULL,          -- which account paid; NULL for Credit
        ReceiptUrl                 NVARCHAR(500)  NULL,
        LinkedWaterVehicleId       INT            NULL,
        LinkedWaterMachineId       INT            NULL,
        LinkedWaterProductionBatchId INT          NULL,
        Status                     NVARCHAR(20)   NOT NULL CONSTRAINT DF_WaterExpenses_Status DEFAULT ('Draft'),
        Notes                      NVARCHAR(1000) NULL,
        CreatedBy                  NVARCHAR(450)  NULL,
        ApprovedBy                 NVARCHAR(450)  NULL,
        ApprovedAt                 DATETIME2      NULL,
        IsDeleted                  BIT            NOT NULL CONSTRAINT DF_WaterExpenses_IsDeleted DEFAULT (0),
        CreatedAt                  DATETIME2      NOT NULL CONSTRAINT DF_WaterExpenses_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt                  DATETIME2      NULL,
        CONSTRAINT FK_WaterExpenses_Category
            FOREIGN KEY (WaterExpenseCategoryId) REFERENCES dbo.WaterExpenseCategories (WaterExpenseCategoryId)
    );

    CREATE INDEX IX_WaterExpenses_FarmId    ON dbo.WaterExpenses (FarmId);
    CREATE INDEX IX_WaterExpenses_Date      ON dbo.WaterExpenses (ExpenseDate);
    CREATE INDEX IX_WaterExpenses_Status    ON dbo.WaterExpenses (Status);
    CREATE INDEX IX_WaterExpenses_Category  ON dbo.WaterExpenses (WaterExpenseCategoryId);
    CREATE INDEX IX_WaterExpenses_Vehicle   ON dbo.WaterExpenses (LinkedWaterVehicleId);
    CREATE INDEX IX_WaterExpenses_Machine   ON dbo.WaterExpenses (LinkedWaterMachineId);
END
GO

-- -----------------------------------------------------------------------------
-- 3. WaterCashAccounts (multi-account; balance is denormalised cache for fast reads)
-- -----------------------------------------------------------------------------
-- AccountType allowed (app-layer validated): FactoryCashBox, OwnerCash, MoMoWallet,
--   BankAccount, DriverCash, PettyCash, Other.
-- CurrentBalance is maintained by SPs (mirrors GenericCashAccount pattern).
-- The source-of-truth is SUM(amount) on WaterCashTransactions; ReconcileBalance
-- SP in 048 rebuilds the cache if drift is detected.
IF OBJECT_ID('dbo.WaterCashAccounts', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterCashAccounts (
        WaterCashAccountId    INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                NVARCHAR(450)  NOT NULL,
        AccountName           NVARCHAR(100)  NOT NULL,
        AccountType           NVARCHAR(30)   NOT NULL,
        OpeningBalance        DECIMAL(14,2)  NOT NULL CONSTRAINT DF_WaterCashAccounts_Opening DEFAULT (0),
        CurrentBalance        DECIMAL(14,2)  NOT NULL CONSTRAINT DF_WaterCashAccounts_Current DEFAULT (0),
        AllowNegativeBalance  BIT            NOT NULL CONSTRAINT DF_WaterCashAccounts_AllowNeg DEFAULT (0),
        IsActive              BIT            NOT NULL CONSTRAINT DF_WaterCashAccounts_IsActive DEFAULT (1),
        Notes                 NVARCHAR(500)  NULL,
        CreatedAt             DATETIME2      NOT NULL CONSTRAINT DF_WaterCashAccounts_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt             DATETIME2      NULL,
        CONSTRAINT UQ_WaterCashAccounts_Farm_Name UNIQUE (FarmId, AccountName)
    );

    CREATE INDEX IX_WaterCashAccounts_FarmId ON dbo.WaterCashAccounts (FarmId);
END
GO

-- -----------------------------------------------------------------------------
-- 4. WaterCashTransactions (signed ledger; positive = inflow, negative = outflow)
-- -----------------------------------------------------------------------------
-- TransactionType: CashIn, CashOut, TransferIn, TransferOut, Adjustment.
-- SourceType:      Sale, CustomerPayment, Expense, DriverReturn, OwnerDeposit,
--                  Withdrawal, Adjustment, Transfer, DailyClosing.
-- Amount is SIGNED (matches GenericCashTransactions pattern). SUM(amount)
-- GROUPED BY WaterCashAccountId = current balance.
IF OBJECT_ID('dbo.WaterCashTransactions', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterCashTransactions (
        WaterCashTransactionId  INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                  NVARCHAR(450)  NOT NULL,
        WaterCashAccountId      INT            NOT NULL,
        TransactionDate         DATETIME2      NOT NULL CONSTRAINT DF_WaterCashTransactions_Date DEFAULT (SYSUTCDATETIME()),
        TransactionType         NVARCHAR(30)   NOT NULL,
        SourceType              NVARCHAR(40)   NULL,
        SourceId                INT            NULL,
        Amount                  DECIMAL(14,2)  NOT NULL,    -- signed
        BalanceAfterTransaction DECIMAL(14,2)  NULL,
        Description             NVARCHAR(500)  NULL,
        CreatedBy               NVARCHAR(450)  NULL,
        ApprovedBy              NVARCHAR(450)  NULL,
        ApprovedAt              DATETIME2      NULL,
        CreatedAt               DATETIME2      NOT NULL CONSTRAINT DF_WaterCashTransactions_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FK_WaterCashTransactions_Account
            FOREIGN KEY (WaterCashAccountId) REFERENCES dbo.WaterCashAccounts (WaterCashAccountId)
    );

    CREATE INDEX IX_WaterCashTransactions_FarmId    ON dbo.WaterCashTransactions (FarmId);
    CREATE INDEX IX_WaterCashTransactions_Account   ON dbo.WaterCashTransactions (WaterCashAccountId);
    CREATE INDEX IX_WaterCashTransactions_Date      ON dbo.WaterCashTransactions (TransactionDate);
    CREATE INDEX IX_WaterCashTransactions_Source    ON dbo.WaterCashTransactions (SourceType, SourceId);
END
GO

-- -----------------------------------------------------------------------------
-- 5. WaterCashTransfers (paired TransferOut/TransferIn rows on approve)
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.WaterCashTransfers', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterCashTransfers (
        WaterCashTransferId       INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                    NVARCHAR(450)  NOT NULL,
        FromWaterCashAccountId    INT            NOT NULL,
        ToWaterCashAccountId      INT            NOT NULL,
        TransferDate              DATETIME2      NOT NULL CONSTRAINT DF_WaterCashTransfers_Date DEFAULT (SYSUTCDATETIME()),
        Amount                    DECIMAL(14,2)  NOT NULL,
        Status                    NVARCHAR(20)   NOT NULL CONSTRAINT DF_WaterCashTransfers_Status DEFAULT ('Draft'),
        Notes                     NVARCHAR(500)  NULL,
        CreatedBy                 NVARCHAR(450)  NULL,
        ApprovedBy                NVARCHAR(450)  NULL,
        ApprovedAt                DATETIME2      NULL,
        CreatedAt                 DATETIME2      NOT NULL CONSTRAINT DF_WaterCashTransfers_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt                 DATETIME2      NULL,
        CONSTRAINT FK_WaterCashTransfers_From FOREIGN KEY (FromWaterCashAccountId) REFERENCES dbo.WaterCashAccounts (WaterCashAccountId),
        CONSTRAINT FK_WaterCashTransfers_To   FOREIGN KEY (ToWaterCashAccountId)   REFERENCES dbo.WaterCashAccounts (WaterCashAccountId),
        CONSTRAINT CK_WaterCashTransfers_DifferentAccounts CHECK (FromWaterCashAccountId <> ToWaterCashAccountId)
    );

    CREATE INDEX IX_WaterCashTransfers_FarmId ON dbo.WaterCashTransfers (FarmId);
    CREATE INDEX IX_WaterCashTransfers_From   ON dbo.WaterCashTransfers (FromWaterCashAccountId);
    CREATE INDEX IX_WaterCashTransfers_To     ON dbo.WaterCashTransfers (ToWaterCashAccountId);
    CREATE INDEX IX_WaterCashTransfers_Status ON dbo.WaterCashTransfers (Status);
END
GO

-- -----------------------------------------------------------------------------
-- 6. WaterCustomerLedger (append-only ledger per customer)
-- -----------------------------------------------------------------------------
-- TransactionType: OpeningBalance, SaleDebit, PaymentCredit, RefundDebit,
--                  AdjustmentDebit, AdjustmentCredit, BadDebtWriteOff.
-- BalanceAfterTransaction is the running balance per customer.
IF OBJECT_ID('dbo.WaterCustomerLedger', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterCustomerLedger (
        WaterCustomerLedgerId    INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                   NVARCHAR(450)  NOT NULL,
        WaterCustomerId          INT            NOT NULL,
        TransactionDate          DATETIME2      NOT NULL CONSTRAINT DF_WaterCustomerLedger_Date DEFAULT (SYSUTCDATETIME()),
        TransactionType          NVARCHAR(30)   NOT NULL,
        WaterSaleId              INT            NULL,
        WaterPaymentId           INT            NULL,
        DebitAmount              DECIMAL(14,2)  NOT NULL CONSTRAINT DF_WaterCustomerLedger_Debit  DEFAULT (0),
        CreditAmount             DECIMAL(14,2)  NOT NULL CONSTRAINT DF_WaterCustomerLedger_Credit DEFAULT (0),
        BalanceAfterTransaction  DECIMAL(14,2)  NOT NULL CONSTRAINT DF_WaterCustomerLedger_Balance DEFAULT (0),
        Description              NVARCHAR(500)  NULL,
        CreatedBy                NVARCHAR(450)  NULL,
        CreatedAt                DATETIME2      NOT NULL CONSTRAINT DF_WaterCustomerLedger_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FK_WaterCustomerLedger_Customer
            FOREIGN KEY (WaterCustomerId) REFERENCES dbo.WaterCustomers (WaterCustomerId)
    );

    CREATE INDEX IX_WaterCustomerLedger_FarmId   ON dbo.WaterCustomerLedger (FarmId);
    CREATE INDEX IX_WaterCustomerLedger_Customer ON dbo.WaterCustomerLedger (WaterCustomerId);
    CREATE INDEX IX_WaterCustomerLedger_Date     ON dbo.WaterCustomerLedger (TransactionDate);
END
GO

PRINT '047_AddWaterFinanceTables.sql complete.';
GO
