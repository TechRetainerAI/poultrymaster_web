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
}
