using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    // ============================================================
    // String constants — kept as classes (not enums) because the SP
    // layer passes them as NVARCHAR. Single source of truth here
    // beats stringly-typed callsites.
    // ============================================================
    public static class WaterExpenseStatus
    {
        public const string Draft     = "Draft";
        public const string Submitted = "Submitted";
        public const string Approved  = "Approved";
        public const string Rejected  = "Rejected";
        public const string Cancelled = "Cancelled";
    }

    public static class WaterPaymentMethods
    {
        public const string Cash   = "Cash";
        public const string MoMo   = "MoMo";
        public const string Bank   = "Bank";
        public const string Card   = "Card";
        public const string Credit = "Credit";
        public const string Mixed  = "Mixed";
    }

    public static class WaterCashAccountTypes
    {
        public const string FactoryCashBox = "FactoryCashBox";
        public const string OwnerCash      = "OwnerCash";
        public const string MoMoWallet     = "MoMoWallet";
        public const string BankAccount    = "BankAccount";
        public const string DriverCash     = "DriverCash";
        public const string PettyCash      = "PettyCash";
        public const string Other          = "Other";
    }

    public static class WaterCashTransactionTypes
    {
        public const string CashIn      = "CashIn";
        public const string CashOut     = "CashOut";
        public const string TransferIn  = "TransferIn";
        public const string TransferOut = "TransferOut";
        public const string Adjustment  = "Adjustment";
    }

    public static class WaterCustomerLedgerTypes
    {
        public const string OpeningBalance    = "OpeningBalance";
        public const string SaleDebit         = "SaleDebit";
        public const string PaymentCredit     = "PaymentCredit";
        public const string RefundDebit       = "RefundDebit";
        public const string AdjustmentDebit   = "AdjustmentDebit";
        public const string AdjustmentCredit  = "AdjustmentCredit";
        public const string BadDebtWriteOff   = "BadDebtWriteOff";
    }

    // ============================================================
    // Expense Categories
    // ============================================================
    public class WaterExpenseCategoryModel
    {
        [Key] public int WaterExpenseCategoryId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required, StringLength(100)] public string Name { get; set; } = string.Empty;
        [StringLength(500)] public string? Description { get; set; }
        public bool IsActive { get; set; } = true;
        public bool IsDeleted { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    // ============================================================
    // Expenses
    // ============================================================
    public class WaterExpenseModel
    {
        [Key] public int WaterExpenseId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;

        public DateTime ExpenseDate { get; set; }

        [Required] public int WaterExpenseCategoryId { get; set; }

        // Populated by SP join for read APIs; ignored on insert/update.
        [StringLength(100)] public string? CategoryName { get; set; }

        [StringLength(500)] public string? Description { get; set; }

        [Range(0.01, double.MaxValue)] public decimal Amount { get; set; }

        [StringLength(200)] public string? PaidTo { get; set; }

        [Required, StringLength(20)] public string PaymentMethod { get; set; } = WaterPaymentMethods.Cash;

        public int? WaterCashAccountId { get; set; }
        [StringLength(100)] public string? CashAccountName { get; set; }

        [StringLength(500)] public string? ReceiptUrl { get; set; }

        public int? LinkedWaterVehicleId { get; set; }
        public int? LinkedWaterMachineId { get; set; }
        public int? LinkedWaterProductionBatchId { get; set; }

        // Supplier ("Paid To") — populated from the WaterSuppliers master list.
        // PaidTo above stays as a freetext fallback for legacy rows.
        public int? SupplierId { get; set; }
        [StringLength(200)] public string? SupplierName { get; set; }

        // Payment state (migration 240). Read-only on this model: they are set
        // through SetPaymentAsync, or by a supplier payment posting against the
        // bill, never as a side effect of editing the expense itself.
        //
        // AmountPaid comes back RESOLVED -- a bill with nothing recorded reads as
        // paid in full unless its PaymentMethod is Credit, which is the rule 047
        // established and migration 236 already relies on.
        public decimal AmountPaid { get; set; }
        public decimal Balance { get; set; }
        [StringLength(20)] public string? PaymentStatus { get; set; }
        public DateTime? DueDate { get; set; }

        // Source link for auto-generated expenses (Payroll, RawMaterialPurchase,
        // ProductionBatch). Drives the clickable Source column on the Expenses page.
        [StringLength(40)]  public string? SourceType { get; set; }
        public int? SourceId { get; set; }

        [StringLength(20)] public string Status { get; set; } = WaterExpenseStatus.Draft;

        [StringLength(1000)] public string? Notes { get; set; }

        public string? CreatedBy { get; set; }
        public string? ApprovedBy { get; set; }
        public DateTime? ApprovedAt { get; set; }

        public bool IsDeleted { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class WaterExpenseRejectRequest
    {
        [StringLength(500)] public string? Reason { get; set; }
    }

    /// <summary>Body for POST api/Water/expenses/{id}/payment (migration 240).</summary>
    public class WaterExpensePaymentRequest
    {
        /// <summary>
        /// Cash paid so far. NULL means paid in full — the same reading the
        /// column carries, and the reason this is nullable rather than a plain
        /// decimal: 0 means the opposite, that the whole bill is still owed.
        /// </summary>
        public decimal? AmountPaid { get; set; }

        public DateTime? DueDate { get; set; }

        /// <summary>
        /// How it was actually settled. Migration 246 records this money as a
        /// real supplier payment, and a payment needs a method of its own — the
        /// bill's own method is often 'Credit', which by definition means it was
        /// NOT paid. Unset falls back to the bill's method.
        /// </summary>
        public string? PaymentMethod { get; set; }

        /// <summary>
        /// Which account the money left. Unset falls back to the account already
        /// stamped on the bill.
        /// </summary>
        public int? CashAccountId { get; set; }
    }

    // ====================================================================
    // WaterSupplier — the "Paid To" master list used by expenses, raw material
    // purchases, and the Supplier Report. Soft-deleted; see migration 076.
    // ====================================================================
    public class WaterSupplierModel
    {
        [Key] public int WaterSupplierId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required, StringLength(200)] public string SupplierName { get; set; } = string.Empty;
        [StringLength(200)] public string? ContactPerson { get; set; }
        [StringLength(50)]  public string? Phone { get; set; }
        [StringLength(200)] public string? Email { get; set; }
        [StringLength(500)] public string? Address { get; set; }
        [StringLength(60)]  public string? SupplierType { get; set; }
        [StringLength(1000)]public string? Notes { get; set; }
        public bool IsActive { get; set; } = true;
        public bool IsDeleted { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public string? UpdatedBy { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class WaterExpenseCancelRequest
    {
        [StringLength(500)] public string? Reason { get; set; }
    }

    // ============================================================
    // Cash Accounts
    // ============================================================
    public class WaterCashAccountModel
    {
        [Key] public int WaterCashAccountId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required, StringLength(100)] public string AccountName { get; set; } = string.Empty;
        [Required, StringLength(30)] public string AccountType { get; set; } = WaterCashAccountTypes.FactoryCashBox;
        public decimal OpeningBalance { get; set; }
        public decimal CurrentBalance { get; set; }
        public bool AllowNegativeBalance { get; set; }
        public bool IsActive { get; set; } = true;
        [StringLength(500)] public string? Notes { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    // ============================================================
    // Cash Transactions (read-only externally)
    // ============================================================
    public class WaterCashTransactionModel
    {
        [Key] public int WaterCashTransactionId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public int WaterCashAccountId { get; set; }
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

        // Migration 222. Populated only by spwatercashtransaction_getledger; the
        // older spwatercashtransaction_getbyfarm does not return them, so these
        // stay null on any path still reading through it.
        public string? ClearingStatus { get; set; }
        public DateTime? ClearedDate { get; set; }
        public string? ClearedBy { get; set; }
        public int? WaterCashReconciliationId { get; set; }
        public string? ClearingNotes { get; set; }
        public string? ReconciliationReference { get; set; }
    }

    // ============================================================
    // Cash Reconciliation (migration 222) — a CASH COUNT, not the
    // balance recalculation that spWaterCashAccount_ReconcileBalance does.
    // ============================================================
    public static class WaterCashClearingStatuses
    {
        public const string Uncleared = "Uncleared";
        public const string Cleared   = "Cleared";
        public const string Disputed  = "Disputed";
    }

    public static class WaterCashReconciliationStatuses
    {
        public const string Draft    = "Draft";
        public const string Posted   = "Posted";
        public const string Reversed = "Reversed";
    }

    public class WaterCashReconciliationModel
    {
        [Key] public int WaterCashReconciliationId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public int WaterCashAccountId { get; set; }
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
        public string Status { get; set; } = WaterCashReconciliationStatuses.Draft;
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
    /// separate model rather than extra properties on WaterCashAccountModel:
    /// that one is read by GetOrdinal against spwatercashaccount_getall, which
    /// migration 222 does not change, and GetOrdinal throws on a missing column.
    /// </summary>
    public class WaterCashAccountReconStatusModel
    {
        public int WaterCashAccountId { get; set; }
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

    public class WaterCashReconciliationPostRequest
    {
        /// <summary>Transactions the counter ticked off while counting. Optional.</summary>
        public List<int>? ClearedTransactionIds { get; set; }
        public string? PostedBy { get; set; }
    }

    public class WaterCashReconciliationReverseRequest
    {
        public string? Reason { get; set; }
        public string? ReversedBy { get; set; }
    }

    public class WaterCashClearingRequest
    {
        public int WaterCashAccountId { get; set; }
        public List<int> TransactionIds { get; set; } = new();
        public string ClearingStatus { get; set; } = WaterCashClearingStatuses.Cleared;
        public string? ClearingNotes { get; set; }
        public string? UserId { get; set; }
    }

    // ============================================================
    // Cash Transfers
    // ============================================================
    public class WaterCashTransferModel
    {
        [Key] public int WaterCashTransferId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;

        [Required] public int FromWaterCashAccountId { get; set; }
        public string? FromAccountName { get; set; }

        [Required] public int ToWaterCashAccountId { get; set; }
        public string? ToAccountName { get; set; }

        public DateTime TransferDate { get; set; }

        [Range(0.01, double.MaxValue)] public decimal Amount { get; set; }

        [StringLength(20)] public string Status { get; set; } = WaterExpenseStatus.Draft;
        [StringLength(500)] public string? Notes { get; set; }

        public string? CreatedBy { get; set; }
        public string? ApprovedBy { get; set; }
        public DateTime? ApprovedAt { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    // ============================================================
    // Customer Ledger
    // ============================================================
    public class WaterCustomerLedgerEntryModel
    {
        [Key] public int WaterCustomerLedgerId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public int WaterCustomerId { get; set; }
        public DateTime TransactionDate { get; set; }
        public string TransactionType { get; set; } = string.Empty;
        public int? WaterSaleId { get; set; }
        public int? WaterPaymentId { get; set; }
        public decimal DebitAmount { get; set; }
        public decimal CreditAmount { get; set; }
        public decimal BalanceAfterTransaction { get; set; }
        public string? Description { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    public class WaterCustomerLedgerAddRequest
    {
        [Required] public int WaterCustomerId { get; set; }
        [Required, StringLength(30)] public string TransactionType { get; set; } = WaterCustomerLedgerTypes.AdjustmentDebit;
        public int? WaterSaleId { get; set; }
        public int? WaterPaymentId { get; set; }
        public decimal DebitAmount { get; set; }
        public decimal CreditAmount { get; set; }
        [StringLength(500)] public string? Description { get; set; }
        public DateTime? TransactionDate { get; set; }
    }
}
