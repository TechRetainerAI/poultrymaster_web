using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    // =========================================================================
    // String constants for the workflow state machines and the open enum
    // columns. Same approach as Phase 2 — strings everywhere, validated at
    // the boundary.
    // =========================================================================
    public static class GenericCustomerLedgerTransactionTypes
    {
        public const string OpeningBalance   = "OpeningBalance";
        public const string SaleDebit        = "SaleDebit";
        public const string PaymentCredit    = "PaymentCredit";
        public const string RefundDebit      = "RefundDebit";
        public const string AdjustmentDebit  = "AdjustmentDebit";
        public const string AdjustmentCredit = "AdjustmentCredit";
        public const string BadDebtWriteOff  = "BadDebtWriteOff";
    }

    public static class GenericCustomerPaymentStatus
    {
        public const string Draft     = "Draft";
        public const string Approved  = "Approved";
        public const string Cancelled = "Cancelled";
    }

    public static class GenericSaleStatus
    {
        public const string Draft     = "Draft";
        public const string Approved  = "Approved";
        public const string Cancelled = "Cancelled";
        public const string Refunded  = "Refunded";
    }

    public static class GenericSalePaymentStatus
    {
        public const string Paid      = "Paid";
        public const string Partial   = "Partial";
        public const string Unpaid    = "Unpaid";
        public const string Refunded  = "Refunded";
        public const string Cancelled = "Cancelled";
    }

    public static class GenericSaleItemTypes
    {
        public const string Product = "Product";
        public const string Service = "Service";
    }

    public static class GenericCashTransactionTypes
    {
        public const string CashIn       = "CashIn";
        public const string CashOut      = "CashOut";
        public const string TransferIn   = "TransferIn";
        public const string TransferOut  = "TransferOut";
        public const string Adjustment   = "Adjustment";
    }

    // =========================================================================
    // Customers
    // =========================================================================
    public class GenericCustomerModel
    {
        [Key]
        public int GenericCustomerId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        [Required]
        [StringLength(200)]
        public string CustomerName { get; set; } = string.Empty;

        [Required]
        [StringLength(40)]
        public string CustomerType { get; set; } = "Individual";

        [StringLength(50)]
        public string? PhoneNumber { get; set; }

        [EmailAddress]
        [StringLength(150)]
        public string? Email { get; set; }

        [StringLength(255)]
        public string? Location { get; set; }

        [StringLength(500)]
        public string? Address { get; set; }

        [Range(0, double.MaxValue)]
        public decimal CreditLimit { get; set; }

        [Range(0, int.MaxValue)]
        public int PaymentTermsDays { get; set; }

        public decimal OpeningBalance { get; set; }
        public decimal CurrentBalance { get; set; }

        public int? AssignedStaffId { get; set; }

        public bool IsActive { get; set; } = true;
        public bool IsDeleted { get; set; }

        [StringLength(1000)]
        public string? Notes { get; set; }

        // Filled by the controller from auth context. Not validated.
        public string? CreatedBy { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class GenericCustomerLedgerEntryModel
    {
        public long GenericCustomerLedgerId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public int GenericCustomerId { get; set; }
        public DateTime TransactionDate { get; set; }
        public string TransactionType { get; set; } = string.Empty;
        public int? SaleId { get; set; }
        public int? PaymentId { get; set; }
        public decimal DebitAmount { get; set; }
        public decimal CreditAmount { get; set; }
        public decimal BalanceAfterTransaction { get; set; }
        public string? Description { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    public class GenericCustomerOwingRowModel
    {
        public int GenericCustomerId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public string CustomerName { get; set; } = string.Empty;
        public string? CustomerType { get; set; }
        public string? PhoneNumber { get; set; }
        public decimal CreditLimit { get; set; }
        public decimal CurrentBalance { get; set; }
        public bool IsOverLimit { get; set; }
    }

    // =========================================================================
    // Customer payments
    // =========================================================================
    public class GenericCustomerPaymentModel
    {
        [Key]
        public int GenericCustomerPaymentId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        [Required]
        public int GenericCustomerId { get; set; }

        public string? CustomerName { get; set; }   // populated by SP

        public DateTime PaymentDate { get; set; }

        [Range(0.01, double.MaxValue)]
        public decimal Amount { get; set; }

        [Required]
        [StringLength(40)]
        public string PaymentMethod { get; set; } = "Cash";

        public int? GenericCashAccountId { get; set; }
        public int? ReceivedByStaffId { get; set; }
        public int? LinkedSaleId { get; set; }

        [StringLength(20)]
        public string Status { get; set; } = GenericCustomerPaymentStatus.Draft;

        [StringLength(1000)]
        public string? Notes { get; set; }

        public string? CreatedBy { get; set; }
        public string? ApprovedBy { get; set; }
        public DateTime? ApprovedAt { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    // =========================================================================
    // Cash transactions
    // =========================================================================
    public class GenericCashTransactionModel
    {
        public long GenericCashTransactionId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public int GenericCashAccountId { get; set; }
        public string? AccountName { get; set; }
        public DateTime TransactionDate { get; set; }
        public string TransactionType { get; set; } = string.Empty;
        public string? SourceType { get; set; }
        public int? SourceId { get; set; }
        public decimal Amount { get; set; }   // signed
        public decimal BalanceAfterTransaction { get; set; }
        public string? Description { get; set; }
        public string? CreatedBy { get; set; }
        public string? ApprovedBy { get; set; }
        public DateTime? ApprovedAt { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    public class GenericCashAdjustmentRequest
    {
        [Required]
        public int GenericCashAccountId { get; set; }

        // Signed: + cash in, - cash out
        [Required]
        public decimal Amount { get; set; }

        [Required]
        [StringLength(500)]
        public string Reason { get; set; } = string.Empty;

        public DateTime? TransactionDate { get; set; }
    }

    // =========================================================================
    // Sales
    // =========================================================================
    public class GenericSaleItemModel
    {
        [Key]
        public int GenericSaleItemId { get; set; }
        public int GenericSaleId { get; set; }
        public string FarmId { get; set; } = string.Empty;

        [Required]
        [StringLength(10)]
        public string ItemType { get; set; } = GenericSaleItemTypes.Product;

        public int? GenericProductId { get; set; }
        public int? GenericServiceId { get; set; }

        [StringLength(500)]
        public string? Description { get; set; }

        [Range(0.0001, double.MaxValue)]
        public decimal Quantity { get; set; }

        [Range(0, double.MaxValue)]
        public decimal UnitPrice { get; set; }

        [Range(0, double.MaxValue)]
        public decimal DiscountAmount { get; set; }

        public decimal LineTotal { get; set; }   // computed by DB

        public decimal? CostAmount { get; set; }

        [StringLength(500)]
        public string? Notes { get; set; }
    }

    public class GenericSaleModel
    {
        [Key]
        public int GenericSaleId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        public DateTime SaleDate { get; set; }

        public int? GenericCustomerId { get; set; }
        public string? CustomerName { get; set; }

        public int? BranchId { get; set; }

        [Required]
        [StringLength(30)]
        public string SalesType { get; set; } = "WalkInSale";

        [StringLength(30)]
        public string? SalesChannel { get; set; }

        public int? SalespersonStaffId { get; set; }

        public decimal SubtotalAmount { get; set; }
        public decimal DiscountAmount { get; set; }
        public decimal TaxAmount { get; set; }
        public decimal TotalAmount { get; set; }
        public decimal AmountPaid { get; set; }
        public decimal Balance { get; set; }

        [StringLength(20)]
        public string PaymentStatus { get; set; } = GenericSalePaymentStatus.Unpaid;

        [StringLength(20)]
        public string? PaymentMethod { get; set; }

        public int? GenericCashAccountId { get; set; }

        [StringLength(60)]
        public string? ReceiptNumber { get; set; }

        [StringLength(20)]
        public string Status { get; set; } = GenericSaleStatus.Draft;

        [StringLength(1000)]
        public string? Notes { get; set; }

        public string? CreatedBy { get; set; }
        public string? ApprovedBy { get; set; }
        public DateTime? ApprovedAt { get; set; }
        public string? CancelledBy { get; set; }
        public DateTime? CancelledAt { get; set; }
        [StringLength(500)]
        public string? CancellationReason { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public bool IsDeleted { get; set; }

        public List<GenericSaleItemModel> Items { get; set; } = new();
    }

    // Used by POST /sales — bundles header + items.
    public class GenericSaleCreateRequest
    {
        public DateTime? SaleDate { get; set; }
        public int? GenericCustomerId { get; set; }
        public int? BranchId { get; set; }

        [StringLength(30)]
        public string SalesType { get; set; } = "WalkInSale";

        [StringLength(30)]
        public string? SalesChannel { get; set; }

        public int? SalespersonStaffId { get; set; }

        [Range(0, double.MaxValue)]
        public decimal HeaderDiscountAmount { get; set; }

        [Range(0, double.MaxValue)]
        public decimal TaxAmount { get; set; }

        [Range(0, double.MaxValue)]
        public decimal AmountPaid { get; set; }

        [StringLength(20)]
        public string? PaymentMethod { get; set; }

        public int? GenericCashAccountId { get; set; }

        [StringLength(60)]
        public string? ReceiptNumber { get; set; }

        [StringLength(1000)]
        public string? Notes { get; set; }

        [MinLength(1, ErrorMessage = "Sale must have at least one item.")]
        public List<GenericSaleItemModel> Items { get; set; } = new();
    }

    public class GenericSaleCancelRequest
    {
        [StringLength(500)]
        public string? Reason { get; set; }
    }

    public class GenericSaleRefundRequest
    {
        [StringLength(500)]
        public string? Reason { get; set; }
    }
}
