-- =============================================================================
-- Migration 032: Customers, Sales, Customer Payments, Cash Transactions
-- =============================================================================
-- Builds on Migrations 028-031 (Generic Company foundation + products/inventory).
-- This is the core transactional layer where money + stock + customer balance
-- all move together when a sale is approved.
--
-- Run order:
--   028 → 029 → 030 → 031 → 032 (this file) → 033.
--
-- Safety:
--   * Idempotent (IF NOT EXISTS / COL_LENGTH).
--   * Additive only.
--
-- Design notes:
--   * GenericCustomerLedger is IMMUTABLE — every customer balance change
--     writes a new row with the running BalanceAfterTransaction. DebitAmount
--     and CreditAmount are both non-negative; exactly one is non-zero per
--     row. GenericCustomers.CurrentBalance is the denormalised cache.
--   * GenericCashTransactions is similarly immutable. Amount is SIGNED
--     (positive = cash in, negative = cash out) to match the StockMovements
--     pattern from Migration 030. SUM(Amount) WHERE CashAccountId = X is the
--     live balance. GenericCashAccounts.CurrentBalance is the cache.
--   * GenericSaleItems.LineTotal is a computed PERSISTED column so it stays
--     consistent without a trigger.
--   * GenericSales.CashAccountId records which cash account *received* the
--     AmountPaid portion when the sale is approved. Required when AmountPaid
--     > 0; nullable for pure credit sales.
--   * No FK from GenericSales.CustomerId → GenericCustomers yet; we want
--     walk-in / one-off sales to work without forcing the user to create a
--     customer record. The SP enforces consistency.
--   * No FK from GenericSaleItems → GenericProducts / GenericServices for
--     the same reason: products can be soft-deleted, and we'd rather keep
--     historical sale lines intact via the captured Description column.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- 1. GenericCustomers (per-FarmId)
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.GenericCustomers', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.GenericCustomers (
        GenericCustomerId   INT IDENTITY(1,1) PRIMARY KEY,
        FarmId              NVARCHAR(450)  NOT NULL,
        CustomerName        NVARCHAR(200)  NOT NULL,
        CustomerType        NVARCHAR(40)   NOT NULL CONSTRAINT DF_GenericCustomers_Type DEFAULT ('Individual'),
        PhoneNumber         NVARCHAR(50)   NULL,
        Email               NVARCHAR(150)  NULL,
        Location            NVARCHAR(255)  NULL,
        Address             NVARCHAR(500)  NULL,
        CreditLimit         DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericCustomers_CreditLimit DEFAULT (0),
        PaymentTermsDays    INT            NOT NULL CONSTRAINT DF_GenericCustomers_PaymentTermsDays DEFAULT (0),
        OpeningBalance      DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericCustomers_OpeningBalance DEFAULT (0),
        CurrentBalance      DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericCustomers_CurrentBalance DEFAULT (0),
        AssignedStaffId     INT            NULL,
        IsActive            BIT            NOT NULL CONSTRAINT DF_GenericCustomers_IsActive DEFAULT (1),
        IsDeleted           BIT            NOT NULL CONSTRAINT DF_GenericCustomers_IsDeleted DEFAULT (0),
        Notes               NVARCHAR(1000) NULL,
        CreatedAt           DATETIME2      NOT NULL CONSTRAINT DF_GenericCustomers_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt           DATETIME2      NULL
    );

    CREATE INDEX IX_GenericCustomers_FarmId ON dbo.GenericCustomers (FarmId);
    CREATE INDEX IX_GenericCustomers_Phone  ON dbo.GenericCustomers (FarmId, PhoneNumber);
END
GO

-- -----------------------------------------------------------------------------
-- 2. GenericCustomerLedger (immutable; source of truth for customer balance)
-- -----------------------------------------------------------------------------
-- TransactionType allowed values (validated at the app layer):
--   OpeningBalance, SaleDebit, PaymentCredit, RefundDebit,
--   AdjustmentDebit, AdjustmentCredit, BadDebtWriteOff
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.GenericCustomerLedger', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.GenericCustomerLedger (
        GenericCustomerLedgerId  BIGINT IDENTITY(1,1) PRIMARY KEY,
        FarmId                   NVARCHAR(450)  NOT NULL,
        GenericCustomerId        INT            NOT NULL,
        TransactionDate          DATETIME2      NOT NULL CONSTRAINT DF_GenericCustomerLedger_Date DEFAULT (SYSUTCDATETIME()),
        TransactionType          NVARCHAR(30)   NOT NULL,
        SaleId                   INT            NULL,
        PaymentId                INT            NULL,
        DebitAmount              DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericCustomerLedger_Debit DEFAULT (0),
        CreditAmount             DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericCustomerLedger_Credit DEFAULT (0),
        BalanceAfterTransaction  DECIMAL(14,2)  NOT NULL,
        Description              NVARCHAR(500)  NULL,
        CreatedBy                NVARCHAR(450)  NULL,
        CreatedAt                DATETIME2      NOT NULL CONSTRAINT DF_GenericCustomerLedger_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FK_GenericCustomerLedger_Customer
            FOREIGN KEY (GenericCustomerId) REFERENCES dbo.GenericCustomers (GenericCustomerId),
        CONSTRAINT CK_GenericCustomerLedger_DebitOrCredit
            CHECK ((DebitAmount = 0 AND CreditAmount > 0)
                OR (DebitAmount > 0 AND CreditAmount = 0)
                OR (DebitAmount = 0 AND CreditAmount = 0))   -- allow 0/0 for synthetic seed rows
    );

    CREATE INDEX IX_GenericCustomerLedger_Customer ON dbo.GenericCustomerLedger (GenericCustomerId);
    CREATE INDEX IX_GenericCustomerLedger_FarmId   ON dbo.GenericCustomerLedger (FarmId);
    CREATE INDEX IX_GenericCustomerLedger_Date     ON dbo.GenericCustomerLedger (TransactionDate);
END
GO

-- -----------------------------------------------------------------------------
-- 3. GenericCustomerPayments (header for payments received from customers)
-- -----------------------------------------------------------------------------
-- Workflow: Draft → Approved or Cancelled. Approval is what writes the
-- ledger PaymentCredit and the cash CashIn.
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.GenericCustomerPayments', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.GenericCustomerPayments (
        GenericCustomerPaymentId  INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                    NVARCHAR(450)  NOT NULL,
        GenericCustomerId         INT            NOT NULL,
        PaymentDate               DATETIME2      NOT NULL CONSTRAINT DF_GenericCustomerPayments_Date DEFAULT (SYSUTCDATETIME()),
        Amount                    DECIMAL(14,2)  NOT NULL,
        PaymentMethod             NVARCHAR(40)   NOT NULL,
        GenericCashAccountId      INT            NULL,
        ReceivedByStaffId         INT            NULL,
        LinkedSaleId              INT            NULL,
        Status                    NVARCHAR(20)   NOT NULL CONSTRAINT DF_GenericCustomerPayments_Status DEFAULT ('Draft'),
        Notes                     NVARCHAR(1000) NULL,
        CreatedBy                 NVARCHAR(450)  NULL,
        ApprovedBy                NVARCHAR(450)  NULL,
        ApprovedAt                DATETIME2      NULL,
        CreatedAt                 DATETIME2      NOT NULL CONSTRAINT DF_GenericCustomerPayments_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt                 DATETIME2      NULL,
        CONSTRAINT FK_GenericCustomerPayments_Customer
            FOREIGN KEY (GenericCustomerId) REFERENCES dbo.GenericCustomers (GenericCustomerId)
    );

    CREATE INDEX IX_GenericCustomerPayments_FarmId   ON dbo.GenericCustomerPayments (FarmId);
    CREATE INDEX IX_GenericCustomerPayments_Customer ON dbo.GenericCustomerPayments (GenericCustomerId);
    CREATE INDEX IX_GenericCustomerPayments_Status   ON dbo.GenericCustomerPayments (Status);
END
GO

-- -----------------------------------------------------------------------------
-- 4. GenericCashTransactions (immutable; source of truth for cash balances)
-- -----------------------------------------------------------------------------
-- Amount is SIGNED: + for cash in, - for cash out. SUM(Amount) per
-- CashAccountId is the live balance. BalanceAfterTransaction is captured
-- at insert time for audit display.
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.GenericCashTransactions', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.GenericCashTransactions (
        GenericCashTransactionId  BIGINT IDENTITY(1,1) PRIMARY KEY,
        FarmId                    NVARCHAR(450)  NOT NULL,
        GenericCashAccountId      INT            NOT NULL,
        TransactionDate           DATETIME2      NOT NULL CONSTRAINT DF_GenericCashTransactions_Date DEFAULT (SYSUTCDATETIME()),
        TransactionType           NVARCHAR(20)   NOT NULL,      -- 'CashIn' | 'CashOut' | 'TransferIn' | 'TransferOut' | 'Adjustment'
        SourceType                NVARCHAR(40)   NULL,          -- 'Sale' | 'CustomerPayment' | 'Purchase' | 'SupplierPayment' | 'Expense' | 'OwnerDeposit' | 'OwnerWithdrawal' | 'Payroll' | 'Refund' | 'Adjustment' | 'Transfer' | 'DailyClosing'
        SourceId                  INT            NULL,
        Amount                    DECIMAL(14,2)  NOT NULL,      -- signed
        BalanceAfterTransaction   DECIMAL(14,2)  NOT NULL,
        Description               NVARCHAR(500)  NULL,
        CreatedBy                 NVARCHAR(450)  NULL,
        ApprovedBy                NVARCHAR(450)  NULL,
        ApprovedAt                DATETIME2      NULL,
        CreatedAt                 DATETIME2      NOT NULL CONSTRAINT DF_GenericCashTransactions_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FK_GenericCashTransactions_Account
            FOREIGN KEY (GenericCashAccountId) REFERENCES dbo.GenericCashAccounts (GenericCashAccountId)
    );

    CREATE INDEX IX_GenericCashTransactions_FarmId   ON dbo.GenericCashTransactions (FarmId);
    CREATE INDEX IX_GenericCashTransactions_Account  ON dbo.GenericCashTransactions (GenericCashAccountId);
    CREATE INDEX IX_GenericCashTransactions_Date     ON dbo.GenericCashTransactions (TransactionDate);
    CREATE INDEX IX_GenericCashTransactions_Source   ON dbo.GenericCashTransactions (SourceType, SourceId);
END
GO

-- -----------------------------------------------------------------------------
-- 5. GenericSales (header)
-- -----------------------------------------------------------------------------
-- Workflow: Draft → Approved → (optionally) Cancelled or Refunded.
-- Approval is where the magic happens (see spGenericSale_Approve in 033):
-- atomic across sale items, stock movements, cash transaction, and customer
-- ledger.
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.GenericSales', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.GenericSales (
        GenericSaleId          INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                 NVARCHAR(450)  NOT NULL,
        SaleDate               DATETIME2      NOT NULL CONSTRAINT DF_GenericSales_Date DEFAULT (SYSUTCDATETIME()),
        GenericCustomerId      INT            NULL,
        BranchId               INT            NULL,
        SalesType              NVARCHAR(30)   NOT NULL CONSTRAINT DF_GenericSales_SalesType DEFAULT ('WalkInSale'),
        SalesChannel           NVARCHAR(30)   NULL,
        SalespersonStaffId     INT            NULL,
        SubtotalAmount         DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericSales_Subtotal DEFAULT (0),
        DiscountAmount         DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericSales_Discount DEFAULT (0),
        TaxAmount              DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericSales_Tax DEFAULT (0),
        TotalAmount            DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericSales_Total DEFAULT (0),
        AmountPaid             DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericSales_AmountPaid DEFAULT (0),
        Balance                DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericSales_Balance DEFAULT (0),
        PaymentStatus          NVARCHAR(20)   NOT NULL CONSTRAINT DF_GenericSales_PaymentStatus DEFAULT ('Unpaid'),
        PaymentMethod          NVARCHAR(20)   NULL,
        GenericCashAccountId   INT            NULL,       -- which account received AmountPaid
        ReceiptNumber          NVARCHAR(60)   NULL,
        Status                 NVARCHAR(20)   NOT NULL CONSTRAINT DF_GenericSales_Status DEFAULT ('Draft'),
        Notes                  NVARCHAR(1000) NULL,
        CreatedBy              NVARCHAR(450)  NULL,
        ApprovedBy             NVARCHAR(450)  NULL,
        ApprovedAt             DATETIME2      NULL,
        CancelledBy            NVARCHAR(450)  NULL,
        CancelledAt            DATETIME2      NULL,
        CancellationReason     NVARCHAR(500)  NULL,
        CreatedAt              DATETIME2      NOT NULL CONSTRAINT DF_GenericSales_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt              DATETIME2      NULL,
        IsDeleted              BIT            NOT NULL CONSTRAINT DF_GenericSales_IsDeleted DEFAULT (0)
    );

    CREATE INDEX IX_GenericSales_FarmId   ON dbo.GenericSales (FarmId);
    CREATE INDEX IX_GenericSales_Date     ON dbo.GenericSales (SaleDate);
    CREATE INDEX IX_GenericSales_Customer ON dbo.GenericSales (GenericCustomerId);
    CREATE INDEX IX_GenericSales_Status   ON dbo.GenericSales (Status);
END
GO

-- -----------------------------------------------------------------------------
-- 6. GenericSaleItems (line items)
-- -----------------------------------------------------------------------------
-- ItemType is 'Product' or 'Service'. Exactly one of GenericProductId /
-- GenericServiceId should be set; the SP layer validates this.
--
-- LineTotal is a PERSISTED computed column so it never drifts from
-- Quantity / UnitPrice / DiscountAmount.
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.GenericSaleItems', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.GenericSaleItems (
        GenericSaleItemId   INT IDENTITY(1,1) PRIMARY KEY,
        GenericSaleId       INT            NOT NULL,
        FarmId              NVARCHAR(450)  NOT NULL,
        ItemType            NVARCHAR(10)   NOT NULL,
        GenericProductId    INT            NULL,
        GenericServiceId    INT            NULL,
        Description         NVARCHAR(500)  NULL,
        Quantity            DECIMAL(14,3)  NOT NULL,
        UnitPrice           DECIMAL(14,2)  NOT NULL,
        DiscountAmount      DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericSaleItems_Discount DEFAULT (0),
        LineTotal           AS (Quantity * UnitPrice - DiscountAmount) PERSISTED,
        CostAmount          DECIMAL(14,2)  NULL,
        Notes               NVARCHAR(500)  NULL,
        CONSTRAINT FK_GenericSaleItems_Sale FOREIGN KEY (GenericSaleId)
            REFERENCES dbo.GenericSales (GenericSaleId) ON DELETE CASCADE
    );

    CREATE INDEX IX_GenericSaleItems_SaleId    ON dbo.GenericSaleItems (GenericSaleId);
    CREATE INDEX IX_GenericSaleItems_ProductId ON dbo.GenericSaleItems (GenericProductId);
    CREATE INDEX IX_GenericSaleItems_ServiceId ON dbo.GenericSaleItems (GenericServiceId);
END
GO

-- -----------------------------------------------------------------------------
-- 7. Table-valued type for passing line items to spGenericSale_Insert /
--    spGenericSale_Replace.
-- -----------------------------------------------------------------------------
-- Idempotent guard: drop existing if signature changed, then recreate.
-- We CANNOT alter a TVT in place, but it's safe to drop+recreate when no
-- procs reference it yet (this is the first migration to introduce it).
-- -----------------------------------------------------------------------------
IF TYPE_ID(N'dbo.GenericSaleItemTvp') IS NULL
BEGIN
    CREATE TYPE dbo.GenericSaleItemTvp AS TABLE (
        ItemType         NVARCHAR(10)   NOT NULL,
        GenericProductId INT            NULL,
        GenericServiceId INT            NULL,
        Description      NVARCHAR(500)  NULL,
        Quantity         DECIMAL(14,3)  NOT NULL,
        UnitPrice        DECIMAL(14,2)  NOT NULL,
        DiscountAmount   DECIMAL(14,2)  NOT NULL DEFAULT (0),
        CostAmount       DECIMAL(14,2)  NULL,
        Notes            NVARCHAR(500)  NULL
    );
END
GO

PRINT '032_AddGenericCustomersSalesCash.sql complete.';
GO
