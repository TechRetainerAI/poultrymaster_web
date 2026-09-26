using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    public class HotelCustomerModel
    {
        [Key] public int HotelCustomerId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required][StringLength(200)] public string CustomerName { get; set; } = string.Empty;
        [StringLength(40)] public string CustomerType { get; set; } = "Corporate";
        [StringLength(50)] public string? Phone { get; set; }
        [StringLength(200)] public string? Email { get; set; }
        [StringLength(500)] public string? Address { get; set; }
        [StringLength(100)] public string? City { get; set; }
        public int PaymentTermDays { get; set; }
        public decimal CreditLimit { get; set; }
        public decimal OpeningBalance { get; set; }
        public decimal CurrentBalance { get; set; }
        public bool IsActive { get; set; } = true;
        [StringLength(1000)] public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class HotelCustomerLedgerEntryModel
    {
        public long HotelCustomerLedgerId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public int HotelCustomerId { get; set; }
        public DateTime TransactionDate { get; set; }
        public string TransactionType { get; set; } = string.Empty;
        public int? InvoiceId { get; set; }
        public int? PaymentId { get; set; }
        public decimal DebitAmount { get; set; }
        public decimal CreditAmount { get; set; }
        public decimal BalanceAfterTransaction { get; set; }
        public string? Description { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    public class HotelCustomerPaymentModel
    {
        [Key] public int HotelCustomerPaymentId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required] public int HotelCustomerId { get; set; }
        public string? CustomerName { get; set; }
        public DateTime PaymentDate { get; set; }
        [Range(0.01, double.MaxValue)] public decimal Amount { get; set; }
        [StringLength(40)] public string PaymentMethod { get; set; } = "Cash";
        public int? HotelCashAccountId { get; set; }
        public string? Reference { get; set; }
        public int? LinkedInvoiceId { get; set; }
        [StringLength(20)] public string Status { get; set; } = "Draft";
        [StringLength(1000)] public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
        public string? ApprovedBy { get; set; }
        public DateTime? ApprovedAt { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class HotelCustomerBalanceSummaryModel
    {
        public int TotalCustomers { get; set; }
        public int CustomersOwing { get; set; }
        public decimal TotalBalance { get; set; }
        public int TotalOverdueCount { get; set; }
    }

    public class HotelCustomerOwedRowModel
    {
        public int HotelCustomerId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public string CustomerName { get; set; } = string.Empty;
        public string? CustomerType { get; set; }
        public string? Phone { get; set; }
        public int PaymentTermDays { get; set; }
        public decimal CurrentBalance { get; set; }
    }

    public class HotelCustomerAdjustmentRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required] public int HotelCustomerId { get; set; }
        public decimal Amount { get; set; }
        public string? Description { get; set; }
    }

    public class HotelCustomerInvoicePostRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required] public int HotelCustomerId { get; set; }
        public int InvoiceId { get; set; }
        public decimal Amount { get; set; }
        public string? Description { get; set; }
    }

    public class HotelCustomerPaymentCreateRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required] public int HotelCustomerId { get; set; }
        public decimal Amount { get; set; }
        public string PaymentMethod { get; set; } = "Cash";
        public int? HotelCashAccountId { get; set; }
        public string? Reference { get; set; }
        public int? LinkedInvoiceId { get; set; }
        public string? PaymentDate { get; set; }
        public string? Notes { get; set; }
    }
}
