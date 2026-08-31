using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    // ============================================================
    // Poultry Cash Account feature (port of the Water finance cash module).
    // String constants kept as classes because the SP layer passes NVARCHAR.
    // ============================================================
    public static class PoultryCashAccountTypes
    {
        public const string FarmCashBox = "FarmCashBox";
        public const string OwnerCash   = "OwnerCash";
        public const string MoMoWallet  = "MoMoWallet";
        public const string BankAccount = "BankAccount";
        public const string PettyCash   = "PettyCash";
        public const string Other       = "Other";
    }

    public static class PoultryCashTransactionTypes
    {
        public const string CashIn        = "CashIn";
        public const string CashOut       = "CashOut";
        public const string TransferIn    = "TransferIn";
        public const string TransferOut   = "TransferOut";
        public const string AdjustmentIn  = "AdjustmentIn";
        public const string AdjustmentOut = "AdjustmentOut";
    }

    public class PoultryCashAccountModel
    {
        [Key] public int PoultryCashAccountId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required, StringLength(100)] public string AccountName { get; set; } = string.Empty;
        [Required, StringLength(30)] public string AccountType { get; set; } = PoultryCashAccountTypes.FarmCashBox;
        public decimal OpeningBalance { get; set; }
        public decimal CurrentBalance { get; set; }
        public bool AllowNegativeBalance { get; set; }
        public bool IsActive { get; set; } = true;
        [StringLength(500)] public string? Notes { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    // Read-only externally; writes happen inside the transactional SPs.
    public class PoultryCashTransactionModel
    {
        [Key] public int PoultryCashTransactionId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public int PoultryCashAccountId { get; set; }
        public string? AccountName { get; set; }
        public DateTime TransactionDate { get; set; }
        public string TransactionType { get; set; } = string.Empty;
        public string? SourceType { get; set; }
        public int? SourceId { get; set; }
        public decimal Amount { get; set; }
        public decimal? BalanceAfterTransaction { get; set; }
        public string? Description { get; set; }
        public string? CreatedBy { get; set; }
        public string? ApprovedBy { get; set; }
        public DateTime? ApprovedAt { get; set; }
        public DateTime CreatedAt { get; set; }

        // Migration 223. Populated only by sppoultrycashtransaction_getledger; the
        // older sppoultrycashtransaction_getbyfarm does not return them, so these
        // stay null on any path still reading through it.
        public string? ClearingStatus { get; set; }
        public DateTime? ClearedDate { get; set; }
        public string? ClearedBy { get; set; }
        public int? PoultryCashReconciliationId { get; set; }
        public string? ClearingNotes { get; set; }
        public string? ReconciliationReference { get; set; }
    }

    public class PoultryCashTransferModel
    {
        [Key] public int PoultryCashTransferId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;

        [Required] public int FromPoultryCashAccountId { get; set; }
        public string? FromAccountName { get; set; }

        [Required] public int ToPoultryCashAccountId { get; set; }
        public string? ToAccountName { get; set; }

        public DateTime TransferDate { get; set; }

        [Range(0.01, double.MaxValue)] public decimal Amount { get; set; }

        [StringLength(20)] public string Status { get; set; } = "Draft";
        [StringLength(500)] public string? Notes { get; set; }

        public string? CreatedBy { get; set; }
        public string? ApprovedBy { get; set; }
        public DateTime? ApprovedAt { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    // Body for POST cash-accounts/{id}/adjust.
    public class PoultryCashAdjustRequest
    {
        public decimal Amount { get; set; }
        public string Reason { get; set; } = string.Empty;
        public string? CreatedBy { get; set; }
    }

    // ============================================================
    // Cash Reconciliation (migration 223) — a CASH COUNT, not the
    // balance recalculation that spPoultryCashAccount_ReconcileBalance does.
    // ============================================================
    public static class PoultryCashClearingStatuses
    {
        public const string Uncleared = "Uncleared";
        public const string Cleared   = "Cleared";
        public const string Disputed  = "Disputed";
    }

    public static class PoultryCashReconciliationStatuses
    {
        public const string Draft    = "Draft";
        public const string Posted   = "Posted";
        public const string Reversed = "Reversed";
    }

    public class PoultryCashReconciliationModel
    {
        [Key] public int PoultryCashReconciliationId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public int PoultryCashAccountId { get; set; }
        public string? AccountName { get; set; }
        public string? AccountType { get; set; }
        public string? ReferenceNo { get; set; }
        public DateTime ReconciliationDate { get; set; }
        /// <summary>Ledger truth: openingBalance + SUM(amount).</summary>
        public decimal SystemBalance { get; set; }
        /// <summary>What the cached CurrentBalance claimed at post time. Differs
        /// from SystemBalance only when the cache had drifted and this count
        /// healed it.</summary>
        public decimal? SystemBalanceCached { get; set; }
        /// <summary>Null while drafting — 0 is a legitimate count.</summary>
        public decimal? ActualBalance { get; set; }
        public decimal Difference { get; set; }
        public int? AdjustmentTransactionId { get; set; }
        public int? ReversalTransactionId { get; set; }
        public int ClearedCount { get; set; }
        public decimal ClearedAmount { get; set; }
        public string? Reason { get; set; }
        public string? Notes { get; set; }
        public string Status { get; set; } = PoultryCashReconciliationStatuses.Draft;
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public string? PostedBy { get; set; }
        public DateTime? PostedAt { get; set; }
        public string? ReversedBy { get; set; }
        public DateTime? ReversedAt { get; set; }
        public string? ReversalReason { get; set; }
    }

    /// <summary>
    /// Per-account reconciliation state for the accounts list. Deliberately a
    /// separate model rather than extra properties on PoultryCashAccountModel:
    /// that one is read by GetOrdinal against sppoultrycashaccount_getall, which
    /// migration 223 does not change, and GetOrdinal throws on a missing column.
    /// </summary>
    public class PoultryCashAccountReconStatusModel
    {
        public int PoultryCashAccountId { get; set; }
        public string AccountName { get; set; } = string.Empty;
        public string? AccountType { get; set; }
        public bool IsActive { get; set; }
        public decimal CurrentBalance { get; set; }
        public decimal LedgerBalance { get; set; }
        public decimal CacheDrift { get; set; }
        public DateTime? LastReconciledAt { get; set; }
        public decimal? LastReconciledBalance { get; set; }
        public int? DaysSinceReconciled { get; set; }
        public long UnclearedCount { get; set; }
        public decimal UnclearedAmount { get; set; }
        public int? OpenDraftId { get; set; }
    }

    public class PoultryCashReconciliationPostRequest
    {
        /// <summary>Transactions the counter ticked off while counting. Optional.</summary>
        public List<int>? ClearedTransactionIds { get; set; }
        public string? PostedBy { get; set; }
    }

    public class PoultryCashReconciliationReverseRequest
    {
        public string? Reason { get; set; }
        public string? ReversedBy { get; set; }
    }

    public class PoultryCashClearingRequest
    {
        public int PoultryCashAccountId { get; set; }
        public List<int> TransactionIds { get; set; } = new();
        public string ClearingStatus { get; set; } = PoultryCashClearingStatuses.Cleared;
        public string? ClearingNotes { get; set; }
        public string? UserId { get; set; }
    }
}
