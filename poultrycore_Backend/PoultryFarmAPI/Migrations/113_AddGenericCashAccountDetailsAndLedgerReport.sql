-- =============================================================================
-- 113_AddGenericCashAccountDetailsAndLedgerReport
-- =============================================================================
-- Cash Account integration - Slice 6 (account details + reconciliation report).
-- Additive, read-only.
--
--   * spGenericCashAccount_GetDetails: per-account header totals (money in/out,
--     transfers, adjustments, opening, current, last reconciled, unreconciled
--     count). Pair with spGenericCashTransaction_GetByAccount (which already
--     returns BalanceAfterTransaction = running balance) for the table.
--   * spGenericCashLedgerReport_Get: ledger SUM(Amount) vs stored CurrentBalance
--     per account, flagging any drift.
-- Only Approved transactions count toward balances; Reversed rows are excluded.
-- =============================================================================

SET XACT_ABORT ON;
GO

CREATE OR ALTER PROCEDURE dbo.spGenericCashAccount_GetDetails
    @FarmId               NVARCHAR(450),
    @GenericCashAccountId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        a.GenericCashAccountId,
        a.FarmId,
        a.AccountName,
        a.AccountType,
        a.OpeningBalance,
        a.CurrentBalance,
        a.NegativeBalancePolicy,
        a.NegativeBalanceLimit,
        a.IsActive,
        a.LastReconciledAt,
        a.LastReconciledBalance,
        TotalMoneyIn    = ISNULL((SELECT SUM(t.Amount) FROM dbo.GenericCashTransactions t
                                  WHERE t.GenericCashAccountId = a.GenericCashAccountId AND t.FarmId = a.FarmId
                                    AND t.Status = 'Approved' AND t.TransactionType = 'CashIn'
                                    AND t.SourceType <> 'OpeningBalance'), 0),
        TotalMoneyOut   = ISNULL((SELECT SUM(-t.Amount) FROM dbo.GenericCashTransactions t
                                  WHERE t.GenericCashAccountId = a.GenericCashAccountId AND t.FarmId = a.FarmId
                                    AND t.Status = 'Approved' AND t.TransactionType = 'CashOut'), 0),
        TransferIn      = ISNULL((SELECT SUM(t.Amount) FROM dbo.GenericCashTransactions t
                                  WHERE t.GenericCashAccountId = a.GenericCashAccountId AND t.FarmId = a.FarmId
                                    AND t.Status = 'Approved' AND t.TransactionType = 'TransferIn'), 0),
        TransferOut     = ISNULL((SELECT SUM(-t.Amount) FROM dbo.GenericCashTransactions t
                                  WHERE t.GenericCashAccountId = a.GenericCashAccountId AND t.FarmId = a.FarmId
                                    AND t.Status = 'Approved' AND t.TransactionType = 'TransferOut'), 0),
        TotalAdjustments = ISNULL((SELECT SUM(t.Amount) FROM dbo.GenericCashTransactions t
                                  WHERE t.GenericCashAccountId = a.GenericCashAccountId AND t.FarmId = a.FarmId
                                    AND t.Status = 'Approved'
                                    AND (t.TransactionType = 'Adjustment'
                                         OR t.SourceType IN ('Adjustment','ReconciliationAdjustment'))), 0),
        LedgerBalance   = ISNULL((SELECT SUM(t.Amount) FROM dbo.GenericCashTransactions t
                                  WHERE t.GenericCashAccountId = a.GenericCashAccountId AND t.FarmId = a.FarmId
                                    AND t.Status = 'Approved'), 0),
        UnreconciledCount = (SELECT COUNT(*) FROM dbo.GenericCashTransactions t
                             WHERE t.GenericCashAccountId = a.GenericCashAccountId AND t.FarmId = a.FarmId
                               AND t.Status = 'Approved'
                               AND (a.LastReconciledAt IS NULL OR t.TransactionDate > a.LastReconciledAt))
    FROM dbo.GenericCashAccounts a
    WHERE a.GenericCashAccountId = @GenericCashAccountId AND a.FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericCashLedgerReport_Get
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        a.GenericCashAccountId,
        a.AccountName,
        a.AccountType,
        a.CurrentBalance,
        LedgerBalance = ISNULL((SELECT SUM(t.Amount) FROM dbo.GenericCashTransactions t
                                WHERE t.GenericCashAccountId = a.GenericCashAccountId AND t.FarmId = a.FarmId
                                  AND t.Status = 'Approved'), 0),
        Discrepancy   = a.CurrentBalance - ISNULL((SELECT SUM(t.Amount) FROM dbo.GenericCashTransactions t
                                WHERE t.GenericCashAccountId = a.GenericCashAccountId AND t.FarmId = a.FarmId
                                  AND t.Status = 'Approved'), 0),
        a.LastReconciledAt,
        a.IsActive
    FROM dbo.GenericCashAccounts a
    WHERE a.FarmId = @FarmId
    ORDER BY a.IsActive DESC, a.AccountName;
END
GO
