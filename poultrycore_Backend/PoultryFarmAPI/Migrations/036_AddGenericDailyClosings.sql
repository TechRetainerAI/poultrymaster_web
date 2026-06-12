-- =============================================================================
-- Migration 036: Daily Closings schema for Generic Company
-- =============================================================================
-- Builds on 028-035. Daily closing is the manager's end-of-day reconciliation:
-- counts cash, confirms sales/expenses/payments tallies, records any
-- difference. The Submit SP auto-aggregates from the immutable tables so the
-- manager doesn't re-enter numbers — they only enter ActualCashCounted and
-- ManagerNotes.
--
-- Run order:
--   028 → 029 → ... → 035 → 036 (this file) → 037.
--
-- Safety:
--   * Idempotent (IF NOT EXISTS).
--   * Additive only.
--
-- Uniqueness:
--   * One closing per (FarmId, BranchId-or-null, ClosingDate). The NULL-aware
--     unique index is implemented via a filtered + non-filtered pair so SQL
--     Server treats two NULL BranchIds as a conflict (rather than allowing
--     duplicates, which is the default in MSSQL).
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF OBJECT_ID('dbo.GenericDailyClosings', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.GenericDailyClosings (
        GenericDailyClosingId       INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                      NVARCHAR(450)  NOT NULL,
        BranchId                    INT            NULL,
        ClosingDate                 DATE           NOT NULL,

        -- Aggregated by spGenericDailyClosing_Submit. Stored so the closing
        -- becomes a frozen snapshot even if later approvals/cancellations
        -- shift the underlying data.
        OpeningCash                 DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericDailyClosings_OpeningCash DEFAULT (0),
        TotalSales                  DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericDailyClosings_TotalSales DEFAULT (0),
        TotalCustomerPayments       DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericDailyClosings_TotalCustomerPayments DEFAULT (0),
        TotalCashIn                 DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericDailyClosings_TotalCashIn DEFAULT (0),
        TotalExpenses               DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericDailyClosings_TotalExpenses DEFAULT (0),
        TotalPurchasesPaid          DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericDailyClosings_TotalPurchasesPaid DEFAULT (0),
        TotalSupplierPayments       DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericDailyClosings_TotalSupplierPayments DEFAULT (0),
        TotalPayrollPaid            DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericDailyClosings_TotalPayrollPaid DEFAULT (0),
        TotalCashOut                DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericDailyClosings_TotalCashOut DEFAULT (0),

        ExpectedCash                DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericDailyClosings_ExpectedCash DEFAULT (0),
        ActualCashCounted           DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericDailyClosings_ActualCashCounted DEFAULT (0),
        CashDifference              DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericDailyClosings_CashDifference DEFAULT (0),

        CreditSales                 DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericDailyClosings_CreditSales DEFAULT (0),
        CustomerDebtTotal           DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericDailyClosings_CustomerDebtTotal DEFAULT (0),
        SupplierDebtTotal           DECIMAL(14,2)  NOT NULL CONSTRAINT DF_GenericDailyClosings_SupplierDebtTotal DEFAULT (0),
        InventoryAdjustmentsCount   INT            NOT NULL CONSTRAINT DF_GenericDailyClosings_InventoryAdjustmentsCount DEFAULT (0),

        ManagerNotes                NVARCHAR(2000) NULL,
        DifferenceReason            NVARCHAR(500)  NULL,

        -- Workflow: Draft → Submitted → Approved or Rejected.
        Status                      NVARCHAR(20)   NOT NULL CONSTRAINT DF_GenericDailyClosings_Status DEFAULT ('Draft'),
        CreatedBy                   NVARCHAR(450)  NULL,
        SubmittedBy                 NVARCHAR(450)  NULL,
        SubmittedAt                 DATETIME2      NULL,
        ApprovedBy                  NVARCHAR(450)  NULL,
        ApprovedAt                  DATETIME2      NULL,
        RejectionReason             NVARCHAR(500)  NULL,

        CreatedAt                   DATETIME2      NOT NULL CONSTRAINT DF_GenericDailyClosings_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt                   DATETIME2      NULL
    );

    CREATE INDEX IX_GenericDailyClosings_FarmId ON dbo.GenericDailyClosings (FarmId);
    CREATE INDEX IX_GenericDailyClosings_Date   ON dbo.GenericDailyClosings (ClosingDate);
    CREATE INDEX IX_GenericDailyClosings_Status ON dbo.GenericDailyClosings (Status);

    -- One closing per (FarmId, BranchId-or-null, ClosingDate).
    -- Two filtered indexes handle the NULL/not-NULL branch cases respectively.
    CREATE UNIQUE INDEX UX_GenericDailyClosings_FarmDateBranch
        ON dbo.GenericDailyClosings (FarmId, BranchId, ClosingDate)
        WHERE BranchId IS NOT NULL;

    CREATE UNIQUE INDEX UX_GenericDailyClosings_FarmDateNoBranch
        ON dbo.GenericDailyClosings (FarmId, ClosingDate)
        WHERE BranchId IS NULL;
END
GO

PRINT '036_AddGenericDailyClosings.sql complete.';
GO
