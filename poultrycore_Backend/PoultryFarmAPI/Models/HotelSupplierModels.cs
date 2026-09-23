using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    public class HotelSupplierModel
    {
        [Key] public int HotelSupplierId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required][StringLength(200)] public string SupplierName { get; set; } = string.Empty;
        [StringLength(40)] public string SupplierType { get; set; } = "ProductSupplier";
        [StringLength(50)] public string? Phone { get; set; }
        [StringLength(200)] public string? Email { get; set; }
        [StringLength(200)] public string? Location { get; set; }
        [StringLength(500)] public string? Address { get; set; }
        public int PaymentTermDays { get; set; }
        public decimal OpeningBalance { get; set; }
        public decimal CurrentBalance { get; set; }
        public bool IsActive { get; set; } = true;
        [StringLength(1000)] public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class HotelSupplierLedgerEntryModel
    {
        public long HotelSupplierLedgerId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public int HotelSupplierId { get; set; }
        public DateTime TransactionDate { get; set; }
        public string TransactionType { get; set; } = string.Empty;
        public int? ExpenseId { get; set; }
        public int? PaymentId { get; set; }
        public decimal DebitAmount { get; set; }
        public decimal CreditAmount { get; set; }
        public decimal BalanceAfterTransaction { get; set; }
        public string? Description { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    public class HotelSupplierPaymentModel
    {
        [Key] public int HotelSupplierPaymentId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required] public int HotelSupplierId { get; set; }
        public string? SupplierName { get; set; }
        public DateTime PaymentDate { get; set; }
        [Range(0.01, double.MaxValue)] public decimal Amount { get; set; }
        [StringLength(40)] public string PaymentMethod { get; set; } = "Cash";
        public int? HotelCashAccountId { get; set; }
        public string? Reference { get; set; }
        public int? LinkedExpenseId { get; set; }
        [StringLength(20)] public string Status { get; set; } = "Draft";
        [StringLength(1000)] public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
        public string? ApprovedBy { get; set; }
        public DateTime? ApprovedAt { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class HotelSupplierBalanceSummaryModel
    {
        public int TotalSuppliers { get; set; }
        public int SuppliersOwed { get; set; }
        public decimal TotalBalance { get; set; }
    }

    public class HotelSupplierPaymentCreateRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required] public int HotelSupplierId { get; set; }
        public decimal Amount { get; set; }
        public string PaymentMethod { get; set; } = "Cash";
        public int? HotelCashAccountId { get; set; }
        public string? Reference { get; set; }
        public int? LinkedExpenseId { get; set; }
        public string? PaymentDate { get; set; }
        public string? Notes { get; set; }
    }

    public class HotelSupplierAdjustmentRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required] public int HotelSupplierId { get; set; }
        public decimal Amount { get; set; }
        public string? Description { get; set; }
    }
}
