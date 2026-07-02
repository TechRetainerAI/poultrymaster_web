-- =============================================================================
-- Migration 125: Expense linkage columns for payroll integration.
-- =============================================================================
-- Additive, idempotent. Ensures SourceType / SourceId exist on dbo.Expense so a
-- payroll run can create (and later remove) a linked expense row. These columns
-- may already exist (e.g. the PoultryRawMaterialPurchase linkage uses them and
-- allows MANY expenses per source), so the unique index below is scoped to
-- SourceType='Payroll' only — at most one live linked expense per payroll run.
--
-- The linked expense is written / removed INLINE by the poultry payroll SPs
-- (migration 131) using TRY_CONVERT(UNIQUEIDENTIFIER, @FarmId) because
-- dbo.Expense.FarmId is UNIQUEIDENTIFIER while the new Poultry* tables use
-- NVARCHAR(450). On reverse (cancel / reopen) the linked row is HARD deleted so
-- the existing expense / P&L reports (which do not filter a soft-delete flag)
-- stay correct.
-- =============================================================================

IF OBJECT_ID('dbo.Expense', 'U') IS NULL
BEGIN
    RAISERROR('dbo.Expense table not found.', 16, 1);
    RETURN;
END
GO

IF COL_LENGTH('dbo.Expense', 'SourceType') IS NULL
BEGIN
    ALTER TABLE dbo.Expense ADD SourceType NVARCHAR(40) NULL;
    PRINT '125: added dbo.Expense.SourceType';
END
GO

IF COL_LENGTH('dbo.Expense', 'SourceId') IS NULL
BEGIN
    ALTER TABLE dbo.Expense ADD SourceId INT NULL;
    PRINT '125: added dbo.Expense.SourceId';
END
GO

-- Drop the earlier over-broad index name if a prior run of this migration
-- created it (it would clash with existing non-payroll source linkages such as
-- PoultryRawMaterialPurchase, which legitimately allow >1 expense per source).
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_Expense_Source' AND object_id = OBJECT_ID('dbo.Expense'))
    DROP INDEX UX_Expense_Source ON dbo.Expense;
GO

-- At most one live linked expense PER PAYROLL RUN. Scoped to SourceType='Payroll'
-- so it never conflicts with other source types that map many expenses to one
-- source record.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_Expense_PayrollSource' AND object_id = OBJECT_ID('dbo.Expense'))
BEGIN
    CREATE UNIQUE INDEX UX_Expense_PayrollSource
        ON dbo.Expense (SourceId)
        WHERE SourceType = 'Payroll' AND SourceId IS NOT NULL;
    PRINT '125: created filtered unique index UX_Expense_PayrollSource';
END
GO

PRINT '125_ExpensePayrollLinkage: complete.';
GO
