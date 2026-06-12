-- =============================================================================
-- Migration 034: Suppliers, Purchases, Expenses, Cash Transfers
-- =============================================================================
-- Builds on 028-033. This is the money-out / supplier side of the platform.
-- Purchase / Expense / SupplierPayment approvals are the mirror image of the
-- Sale / CustomerPayment approvals from Phase 3.
--
-- Run order:
--   028 → 029 → 030 → 031 → 032 → 033 → 034 (this file) → 035.
--
-- Safety:
--   * Idempotent (IF NOT EXISTS).
--   * Additive only.
--
-- Design notes:
--   * GenericSupplierLedger is IMMUTABLE — every supplier balance change
--     writes a new row with the running BalanceAfterTransaction.
--     Convention: a supplier's CurrentBalance > 0 means *we owe them money*.
--     CreditAmount adds to balance (we received goods/services on credit),
--     DebitAmount reduces it (we paid them).
--   * GenericCashTransfers writes a pair of rows in GenericCashTransactions
--     (TransferOut on source, TransferIn on dest) — the transfer row itself
--     is the audit trail / approval workflow header.
--   * GenericExpenses can be paid-in-full (PaymentMethod != Credit, charges
--     a cash account) OR on-credit (PaymentMethod = Credit + SupplierId,
--     adds to the supplier's ledger as ExpenseCredit). The approve SP
--     branches on this.
--   * No FK from GenericPurchaseItems → GenericProducts. Same reason as
--     SaleItems: products can be soft-deleted and we want historical
--     purchase lines to stay intact.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- 1. GenericSuppliers (per-FarmId)
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.GenericSuppliers', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.GenericSuppliers (
        GenericSupplierId   INT IDENTITY(1,1) PRIMARY KEY,
        FarmId              NVARCHAR(450)  NOT NULL,
        SupplierName        NVARCHAR(200)  NOT NULL,
        SupplierType        NVARCHAR(40)   NOT NULL CONSTRAINT DF_GenericSuppliers_Type DEFAULT ('ProductSupplier'),
        PhoneNumber         NVARCHAR(50)   NULL,
        Email               NVARCHAR(150)  NULL,
        Location            NVARCHAR(255)  NULL,
        Address             NVARCHAR(500)  NULL,
        PaymentTermsDays    INT            NOT NULL CONSTRAINT DF_GenericSuppliers_PaymentTermsDays DEFAULT (0),
        OpeningBalance      DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericSuppliers_OpeningBalance DEFAULT (0),
        CurrentBalance      DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericSuppliers_CurrentBalance DEFAULT (0),
        IsActive            BIT            NOT NULL CONSTRAINT DF_GenericSuppliers_IsActive DEFAULT (1),
        IsDeleted           BIT            NOT NULL CONSTRAINT DF_GenericSuppliers_IsDeleted DEFAULT (0),
        Notes               NVARCHAR(1000) NULL,
        CreatedAt           DATETIME2      NOT NULL CONSTRAINT DF_GenericSuppliers_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt           DATETIME2      NULL
    );

    CREATE INDEX IX_GenericSuppliers_FarmId ON dbo.GenericSuppliers (FarmId);
    CREATE INDEX IX_GenericSuppliers_Phone  ON dbo.GenericSuppliers (FarmId, PhoneNumber);
END
GO

-- -----------------------------------------------------------------------------
-- 2. GenericSupplierLedger (immutable; source of truth for supplier balance)
-- -----------------------------------------------------------------------------
-- TransactionType allowed values (app-layer validated):
--   OpeningBalance, PurchaseCredit, ExpenseCredit, PaymentDebit,
--   AdjustmentDebit, AdjustmentCredit
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.GenericSupplierLedger', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.GenericSupplierLedger (
        GenericSupplierLedgerId  BIGINT IDENTITY(1,1) PRIMARY KEY,
        FarmId                   NVARCHAR(450)  NOT NULL,
        GenericSupplierId        INT            NOT NULL,
        TransactionDate          DATETIME2      NOT NULL CONSTRAINT DF_GenericSupplierLedger_Date DEFAULT (SYSUTCDATETIME()),
        TransactionType          NVARCHAR(30)   NOT NULL,
        PurchaseId               INT            NULL,
        ExpenseId                INT            NULL,
        PaymentId                INT            NULL,
        DebitAmount              DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericSupplierLedger_Debit DEFAULT (0),
        CreditAmount             DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericSupplierLedger_Credit DEFAULT (0),
        BalanceAfterTransaction  DECIMAL(14,2)  NOT NULL,
        Description              NVARCHAR(500)  NULL,
        CreatedBy                NVARCHAR(450)  NULL,
        CreatedAt                DATETIME2      NOT NULL CONSTRAINT DF_GenericSupplierLedger_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FK_GenericSupplierLedger_Supplier
            FOREIGN KEY (GenericSupplierId) REFERENCES dbo.GenericSuppliers (GenericSupplierId),
        CONSTRAINT CK_GenericSupplierLedger_DebitOrCredit
            CHECK ((DebitAmount = 0 AND CreditAmount > 0)
                OR (DebitAmount > 0 AND CreditAmount = 0)
                OR (DebitAmount = 0 AND CreditAmount = 0))
    );

    CREATE INDEX IX_GenericSupplierLedger_Supplier ON dbo.GenericSupplierLedger (GenericSupplierId);
    CREATE INDEX IX_GenericSupplierLedger_FarmId   ON dbo.GenericSupplierLedger (FarmId);
    CREATE INDEX IX_GenericSupplierLedger_Date     ON dbo.GenericSupplierLedger (TransactionDate);
END
GO

-- -----------------------------------------------------------------------------
-- 3. GenericSupplierPayments (we pay them)
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.GenericSupplierPayments', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.GenericSupplierPayments (
        GenericSupplierPaymentId  INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                    NVARCHAR(450)  NOT NULL,
        GenericSupplierId         INT            NOT NULL,
        PaymentDate               DATETIME2      NOT NULL CONSTRAINT DF_GenericSupplierPayments_Date DEFAULT (SYSUTCDATETIME()),
        Amount                    DECIMAL(14,2)  NOT NULL,
        PaymentMethod             NVARCHAR(40)   NOT NULL,
        GenericCashAccountId      INT            NULL,
        PaidByStaffId             INT            NULL,
        LinkedPurchaseId          INT            NULL,
        LinkedExpenseId           INT            NULL,
        Status                    NVARCHAR(20)   NOT NULL CONSTRAINT DF_GenericSupplierPayments_Status DEFAULT ('Draft'),
        Notes                     NVARCHAR(1000) NULL,
        CreatedBy                 NVARCHAR(450)  NULL,
        ApprovedBy                NVARCHAR(450)  NULL,
        ApprovedAt                DATETIME2      NULL,
        CreatedAt                 DATETIME2      NOT NULL CONSTRAINT DF_GenericSupplierPayments_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt                 DATETIME2      NULL,
        CONSTRAINT FK_GenericSupplierPayments_Supplier
            FOREIGN KEY (GenericSupplierId) REFERENCES dbo.GenericSuppliers (GenericSupplierId)
    );

    CREATE INDEX IX_GenericSupplierPayments_FarmId   ON dbo.GenericSupplierPayments (FarmId);
    CREATE INDEX IX_GenericSupplierPayments_Supplier ON dbo.GenericSupplierPayments (GenericSupplierId);
    CREATE INDEX IX_GenericSupplierPayments_Status   ON dbo.GenericSupplierPayments (Status);
END
GO

-- -----------------------------------------------------------------------------
-- 4. GenericPurchases (header)
-- -----------------------------------------------------------------------------
-- Workflow: Draft → Approved → (optionally) Cancelled.
-- Approval increases inventory, charges a cash account (if AmountPaid > 0),
-- and creates a supplier ledger entry (if Balance > 0 and SupplierId set).
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.GenericPurchases', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.GenericPurchases (
        GenericPurchaseId      INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                 NVARCHAR(450)  NOT NULL,
        GenericSupplierId      INT            NULL,
        PurchaseDate           DATETIME2      NOT NULL CONSTRAINT DF_GenericPurchases_Date DEFAULT (SYSUTCDATETIME()),
        BranchId               INT            NULL,
        SubtotalAmount         DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericPurchases_Subtotal DEFAULT (0),
        DiscountAmount         DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericPurchases_Discount DEFAULT (0),
        TaxAmount              DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericPurchases_Tax DEFAULT (0),
        TotalAmount            DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericPurchases_Total DEFAULT (0),
        AmountPaid             DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericPurchases_AmountPaid DEFAULT (0),
        Balance                DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericPurchases_Balance DEFAULT (0),
        PaymentStatus          NVARCHAR(20)   NOT NULL CONSTRAINT DF_GenericPurchases_PaymentStatus DEFAULT ('Unpaid'),
        PaymentMethod          NVARCHAR(20)   NULL,
        GenericCashAccountId   INT            NULL,
        InvoiceNumber          NVARCHAR(60)   NULL,
        ReceiptUrl             NVARCHAR(500)  NULL,
        ReceivedByStaffId      INT            NULL,
        Status                 NVARCHAR(20)   NOT NULL CONSTRAINT DF_GenericPurchases_Status DEFAULT ('Draft'),
        Notes                  NVARCHAR(1000) NULL,
        CreatedBy              NVARCHAR(450)  NULL,
        ApprovedBy             NVARCHAR(450)  NULL,
        ApprovedAt             DATETIME2      NULL,
        CancelledBy            NVARCHAR(450)  NULL,
        CancelledAt            DATETIME2      NULL,
        CancellationReason     NVARCHAR(500)  NULL,
        CreatedAt              DATETIME2      NOT NULL CONSTRAINT DF_GenericPurchases_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt              DATETIME2      NULL,
        IsDeleted              BIT            NOT NULL CONSTRAINT DF_GenericPurchases_IsDeleted DEFAULT (0)
    );

    CREATE INDEX IX_GenericPurchases_FarmId   ON dbo.GenericPurchases (FarmId);
    CREATE INDEX IX_GenericPurchases_Supplier ON dbo.GenericPurchases (GenericSupplierId);
    CREATE INDEX IX_GenericPurchases_Date     ON dbo.GenericPurchases (PurchaseDate);
    CREATE INDEX IX_GenericPurchases_Status   ON dbo.GenericPurchases (Status);
END
GO

-- -----------------------------------------------------------------------------
-- 5. GenericPurchaseItems (line items - products only)
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.GenericPurchaseItems', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.GenericPurchaseItems (
        GenericPurchaseItemId  INT IDENTITY(1,1) PRIMARY KEY,
        GenericPurchaseId      INT            NOT NULL,
        FarmId                 NVARCHAR(450)  NOT NULL,
        GenericProductId       INT            NOT NULL,
        Description            NVARCHAR(500)  NULL,
        Quantity               DECIMAL(14,3)  NOT NULL,
        UnitCost               DECIMAL(14,2)  NOT NULL,
        DiscountAmount         DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericPurchaseItems_Discount DEFAULT (0),
        LineTotal              AS (Quantity * UnitCost - DiscountAmount) PERSISTED,
        Notes                  NVARCHAR(500)  NULL,
        CONSTRAINT FK_GenericPurchaseItems_Purchase FOREIGN KEY (GenericPurchaseId)
            REFERENCES dbo.GenericPurchases (GenericPurchaseId) ON DELETE CASCADE
    );

    CREATE INDEX IX_GenericPurchaseItems_PurchaseId ON dbo.GenericPurchaseItems (GenericPurchaseId);
    CREATE INDEX IX_GenericPurchaseItems_ProductId  ON dbo.GenericPurchaseItems (GenericProductId);
END
GO

-- -----------------------------------------------------------------------------
-- 6. GenericExpenses
-- -----------------------------------------------------------------------------
-- One-line operating expenses (rent, electricity, transport, etc.).
-- Workflow: Draft → Submitted → Approved → (or Rejected / Cancelled).
-- For simplicity we collapse Draft and Submitted into a single Draft state
-- and let the Approve SP be the gate. Reject still exists for symmetry.
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.GenericExpenses', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.GenericExpenses (
        GenericExpenseId           INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                     NVARCHAR(450)  NOT NULL,
        ExpenseDate                DATETIME2      NOT NULL CONSTRAINT DF_GenericExpenses_Date DEFAULT (SYSUTCDATETIME()),
        GenericExpenseCategoryId   INT            NOT NULL,
        GenericSupplierId          INT            NULL,
        Description                NVARCHAR(500)  NULL,
        Amount                     DECIMAL(14,2)  NOT NULL,
        PaidTo                     NVARCHAR(200)  NULL,
        PaymentMethod              NVARCHAR(20)   NOT NULL,    -- 'Cash' | 'MoMo' | 'Bank' | 'Card' | 'Credit'
        GenericCashAccountId       INT            NULL,
        ReceiptUrl                 NVARCHAR(500)  NULL,
        BranchId                   INT            NULL,
        StaffId                    INT            NULL,
        Status                     NVARCHAR(20)   NOT NULL CONSTRAINT DF_GenericExpenses_Status DEFAULT ('Draft'),
        Notes                      NVARCHAR(1000) NULL,
        CreatedBy                  NVARCHAR(450)  NULL,
        ApprovedBy                 NVARCHAR(450)  NULL,
        ApprovedAt                 DATETIME2      NULL,
        RejectionReason            NVARCHAR(500)  NULL,
        CreatedAt                  DATETIME2      NOT NULL CONSTRAINT DF_GenericExpenses_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt                  DATETIME2      NULL,
        IsDeleted                  BIT            NOT NULL CONSTRAINT DF_GenericExpenses_IsDeleted DEFAULT (0),
        CONSTRAINT FK_GenericExpenses_Category
            FOREIGN KEY (GenericExpenseCategoryId) REFERENCES dbo.GenericExpenseCategories (GenericExpenseCategoryId)
    );

    CREATE INDEX IX_GenericExpenses_FarmId   ON dbo.GenericExpenses (FarmId);
    CREATE INDEX IX_GenericExpenses_Date     ON dbo.GenericExpenses (ExpenseDate);
    CREATE INDEX IX_GenericExpenses_Category ON dbo.GenericExpenses (GenericExpenseCategoryId);
    CREATE INDEX IX_GenericExpenses_Supplier ON dbo.GenericExpenses (GenericSupplierId);
    CREATE INDEX IX_GenericExpenses_Status   ON dbo.GenericExpenses (Status);
END
GO

-- -----------------------------------------------------------------------------
-- 7. GenericCashTransfers (transfer between two cash accounts in one farm)
-- -----------------------------------------------------------------------------
-- Workflow: Draft → Approved (writes paired TransferOut + TransferIn cash
-- transactions) → Cancelled (Draft only).
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.GenericCashTransfers', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.GenericCashTransfers (
        GenericCashTransferId       INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                      NVARCHAR(450)  NOT NULL,
        FromGenericCashAccountId    INT            NOT NULL,
        ToGenericCashAccountId      INT            NOT NULL,
        TransferDate                DATETIME2      NOT NULL CONSTRAINT DF_GenericCashTransfers_Date DEFAULT (SYSUTCDATETIME()),
        Amount                      DECIMAL(14,2)  NOT NULL,
        Status                      NVARCHAR(20)   NOT NULL CONSTRAINT DF_GenericCashTransfers_Status DEFAULT ('Draft'),
        Notes                       NVARCHAR(500)  NULL,
        CreatedBy                   NVARCHAR(450)  NULL,
        ApprovedBy                  NVARCHAR(450)  NULL,
        ApprovedAt                  DATETIME2      NULL,
        CreatedAt                   DATETIME2      NOT NULL CONSTRAINT DF_GenericCashTransfers_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt                   DATETIME2      NULL,
        CONSTRAINT FK_GenericCashTransfers_From
            FOREIGN KEY (FromGenericCashAccountId) REFERENCES dbo.GenericCashAccounts (GenericCashAccountId),
        CONSTRAINT FK_GenericCashTransfers_To
            FOREIGN KEY (ToGenericCashAccountId)   REFERENCES dbo.GenericCashAccounts (GenericCashAccountId),
        CONSTRAINT CK_GenericCashTransfers_Different CHECK (FromGenericCashAccountId <> ToGenericCashAccountId),
        CONSTRAINT CK_GenericCashTransfers_Positive  CHECK (Amount > 0)
    );

    CREATE INDEX IX_GenericCashTransfers_FarmId ON dbo.GenericCashTransfers (FarmId);
    CREATE INDEX IX_GenericCashTransfers_Status ON dbo.GenericCashTransfers (Status);
END
GO

-- -----------------------------------------------------------------------------
-- 8. Table-valued type for purchase items
-- -----------------------------------------------------------------------------
IF TYPE_ID(N'dbo.GenericPurchaseItemTvp') IS NULL
BEGIN
    CREATE TYPE dbo.GenericPurchaseItemTvp AS TABLE (
        GenericProductId INT            NOT NULL,
        Description      NVARCHAR(500)  NULL,
        Quantity         DECIMAL(14,3)  NOT NULL,
        UnitCost         DECIMAL(14,2)  NOT NULL,
        DiscountAmount   DECIMAL(14,2)  NOT NULL DEFAULT (0),
        Notes            NVARCHAR(500)  NULL
    );
END
GO

PRINT '034_AddGenericSuppliersPurchasesExpenses.sql complete.';
GO
