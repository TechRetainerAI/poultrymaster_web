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
