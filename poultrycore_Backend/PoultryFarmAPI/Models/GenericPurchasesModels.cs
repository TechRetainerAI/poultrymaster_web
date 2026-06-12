using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    // =========================================================================
    // Status / type constants for Phase 4
    // =========================================================================
    public static class GenericSupplierLedgerTransactionTypes
    {
        public const string OpeningBalance   = "OpeningBalance";
        public const string PurchaseCredit   = "PurchaseCredit";
        public const string ExpenseCredit    = "ExpenseCredit";
        public const string PaymentDebit     = "PaymentDebit";
        public const string AdjustmentDebit  = "AdjustmentDebit";
        public const string AdjustmentCredit = "AdjustmentCredit";
    }

    public static class GenericSupplierPaymentStatus
    {
        public const string Draft     = "Draft";
        public const string Approved  = "Approved";
        public const string Cancelled = "Cancelled";
    }

    public static class GenericPurchaseStatus
    {
        public const string Draft     = "Draft";
        public const string Approved  = "Approved";
        public const string Cancelled = "Cancelled";
    }

    public static class GenericPurchasePaymentStatus
    {
        public const string Paid    = "Paid";
        public const string Partial = "Partial";
        public const string Unpaid  = "Unpaid";
    }

    public static class GenericExpenseStatus
    {
        public const string Draft     = "Draft";
        public const string Submitted = "Submitted";
        public const string Approved  = "Approved";
        public const string Rejected  = "Rejected";
        public const string Cancelled = "Cancelled";
    }

    public static class GenericExpensePaymentMethods
    {
        public const string Cash   = "Cash";
        public const string MoMo   = "MoMo";
        public const string Bank   = "Bank";
        public const string Card   = "Card";
        public const string Credit = "Credit";
    }

    public static class GenericCashTransferStatus
    {
        public const string Draft     = "Draft";
        public const string Approved  = "Approved";
        public const string Cancelled = "Cancelled";
    }

    // =========================================================================
    // Suppliers
    // =========================================================================
    public class GenericSupplierModel
    {
        [Key]
        public int GenericSupplierId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        [Required]
        [StringLength(200)]
        public string SupplierName { get; set; } = string.Empty;

        [Required]
        [StringLength(40)]
        public string SupplierType { get; set; } = "ProductSupplier";

        [StringLength(50)]
        public string? PhoneNumber { get; set; }

        [EmailAddress]
        [StringLength(150)]
        public string? Email { get; set; }

        [StringLength(255)]
        public string? Location { get; set; }

        [StringLength(500)]
        public string? Address { get; set; }

        [Range(0, int.MaxValue)]
        public int PaymentTermsDays { get; set; }

        public decimal OpeningBalance { get; set; }
        public decimal CurrentBalance { get; set; }

        public bool IsActive { get; set; } = true;
        public bool IsDeleted { get; set; }

        [StringLength(1000)]
        public string? Notes { get; set; }

        public string? CreatedBy { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class GenericSupplierLedgerEntryModel
    {
        public long GenericSupplierLedgerId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public int GenericSupplierId { get; set; }
        public DateTime TransactionDate { get; set; }
        public string TransactionType { get; set; } = string.Empty;
        public int? PurchaseId { get; set; }
        public int? ExpenseId { get; set; }
        public int? PaymentId { get; set; }
        public decimal DebitAmount { get; set; }
        public decimal CreditAmount { get; set; }
        public decimal BalanceAfterTransaction { get; set; }
        public string? Description { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    public class GenericSupplierOwedRowModel
    {
        public int GenericSupplierId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public string SupplierName { get; set; } = string.Empty;
        public string? SupplierType { get; set; }
        public string? PhoneNumber { get; set; }
        public int PaymentTermsDays { get; set; }
        public decimal CurrentBalance { get; set; }
    }

    public class GenericSupplierPaymentModel
    {
        [Key]
        public int GenericSupplierPaymentId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        [Required]
        public int GenericSupplierId { get; set; }

        public string? SupplierName { get; set; }

        public DateTime PaymentDate { get; set; }

        [Range(0.01, double.MaxValue)]
        public decimal Amount { get; set; }

        [Required]
        [StringLength(40)]
        public string PaymentMethod { get; set; } = "Cash";

        public int? GenericCashAccountId { get; set; }
        public int? PaidByStaffId { get; set; }
        public int? LinkedPurchaseId { get; set; }
        public int? LinkedExpenseId { get; set; }

        [StringLength(20)]
        public string Status { get; set; } = GenericSupplierPaymentStatus.Draft;

        [StringLength(1000)]
        public string? Notes { get; set; }

        public string? CreatedBy { get; set; }
        public string? ApprovedBy { get; set; }
        public DateTime? ApprovedAt { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    // =========================================================================
    // Purchases
    // =========================================================================
    public class GenericPurchaseItemModel
    {
        [Key]
        public int GenericPurchaseItemId { get; set; }
        public int GenericPurchaseId { get; set; }
        public string FarmId { get; set; } = string.Empty;

        [Required]
        public int GenericProductId { get; set; }

        [StringLength(500)]
        public string? Description { get; set; }

        [Range(0.0001, double.MaxValue)]
        public decimal Quantity { get; set; }

        [Range(0, double.MaxValue)]
        public decimal UnitCost { get; set; }

        [Range(0, double.MaxValue)]
        public decimal DiscountAmount { get; set; }

        public decimal LineTotal { get; set; }   // computed by DB

        [StringLength(500)]
        public string? Notes { get; set; }
    }

    public class GenericPurchaseModel
    {
        [Key]
        public int GenericPurchaseId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        public int? GenericSupplierId { get; set; }
        public string? SupplierName { get; set; }

        public DateTime PurchaseDate { get; set; }
        public int? BranchId { get; set; }

        public decimal SubtotalAmount { get; set; }
        public decimal DiscountAmount { get; set; }
        public decimal TaxAmount { get; set; }
        public decimal TotalAmount { get; set; }
        public decimal AmountPaid { get; set; }
        public decimal Balance { get; set; }

        [StringLength(20)]
        public string PaymentStatus { get; set; } = GenericPurchasePaymentStatus.Unpaid;

        [StringLength(20)]
        public string? PaymentMethod { get; set; }

        public int? GenericCashAccountId { get; set; }

        [StringLength(60)]
        public string? InvoiceNumber { get; set; }

        [StringLength(500)]
        public string? ReceiptUrl { get; set; }

        public int? ReceivedByStaffId { get; set; }

        [StringLength(20)]
        public string Status { get; set; } = GenericPurchaseStatus.Draft;

        [StringLength(1000)]
        public string? Notes { get; set; }

        public string? CreatedBy { get; set; }
        public string? ApprovedBy { get; set; }
        public DateTime? ApprovedAt { get; set; }
        public string? CancelledBy { get; set; }
        public DateTime? CancelledAt { get; set; }
        public string? CancellationReason { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }

        public List<GenericPurchaseItemModel> Items { get; set; } = new();
    }

    public class GenericPurchaseCreateRequest
    {
        public DateTime? PurchaseDate { get; set; }
        public int? GenericSupplierId { get; set; }
        public int? BranchId { get; set; }

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
        public string? InvoiceNumber { get; set; }

        [StringLength(500)]
        public string? ReceiptUrl { get; set; }

        public int? ReceivedByStaffId { get; set; }

        [StringLength(1000)]
        public string? Notes { get; set; }

        [MinLength(1, ErrorMessage = "Purchase must have at least one item.")]
        public List<GenericPurchaseItemModel> Items { get; set; } = new();
    }

    public class GenericPurchaseCancelRequest
    {
        [StringLength(500)]
        public string? Reason { get; set; }
    }

    // =========================================================================
    // Expenses
    // =========================================================================
    public class GenericExpenseModel
    {
        [Key]
        public int GenericExpenseId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        public DateTime ExpenseDate { get; set; }

        [Required]
        public int GenericExpenseCategoryId { get; set; }
        public string? CategoryName { get; set; }

        public int? GenericSupplierId { get; set; }
        public string? SupplierName { get; set; }

        [StringLength(500)]
        public string? Description { get; set; }

        [Range(0.01, double.MaxValue)]
        public decimal Amount { get; set; }

        [StringLength(200)]
        public string? PaidTo { get; set; }

        [Required]
        [StringLength(20)]
        public string PaymentMethod { get; set; } = GenericExpensePaymentMethods.Cash;

        public int? GenericCashAccountId { get; set; }

        [StringLength(500)]
        public string? ReceiptUrl { get; set; }

        public int? BranchId { get; set; }
        public int? StaffId { get; set; }

        [StringLength(20)]
        public string Status { get; set; } = GenericExpenseStatus.Draft;

        [StringLength(1000)]
        public string? Notes { get; set; }

        public string? CreatedBy { get; set; }
        public string? ApprovedBy { get; set; }
        public DateTime? ApprovedAt { get; set; }

        [StringLength(500)]
        public string? RejectionReason { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class GenericExpenseRejectRequest
    {
        [Required]
        [StringLength(500)]
        public string RejectionReason { get; set; } = string.Empty;
    }

    // =========================================================================
    // Cash transfers
    // =========================================================================
    public class GenericCashTransferModel
    {
        [Key]
        public int GenericCashTransferId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        [Required]
        public int FromGenericCashAccountId { get; set; }
        public string? FromAccountName { get; set; }

        [Required]
        public int ToGenericCashAccountId { get; set; }
        public string? ToAccountName { get; set; }

        public DateTime TransferDate { get; set; }

        [Range(0.01, double.MaxValue)]
        public decimal Amount { get; set; }

        [StringLength(20)]
        public string Status { get; set; } = GenericCashTransferStatus.Draft;

        [StringLength(500)]
        public string? Notes { get; set; }

        public string? CreatedBy { get; set; }
        public string? ApprovedBy { get; set; }
        public DateTime? ApprovedAt { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }
}
