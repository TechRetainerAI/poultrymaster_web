namespace PoultryFarmAPIWeb.Models
{
    public class GenericCustomerCreditModel
    {
        public int GenericCustomerCreditId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public int GenericCustomerId { get; set; }
        public string? CustomerName { get; set; }
        public string CreditType { get; set; } = "Overpayment";
        public decimal Amount { get; set; }
        public decimal RemainingBalance { get; set; }
        public DateTime CreditDate { get; set; }
        public string? Notes { get; set; }
        public string Status { get; set; } = "Active";
        public DateTime CreatedAt { get; set; }
    }

    public class GenericCustomerCreditCreateRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public int GenericCustomerId { get; set; }
        public string CreditType { get; set; } = "Overpayment";
        public decimal Amount { get; set; }
        public DateTime? CreditDate { get; set; }
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
    }

    public class GenericSupplierCreditModel
    {
        public int GenericSupplierCreditId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public int GenericSupplierId { get; set; }
        public string? SupplierName { get; set; }
        public string CreditType { get; set; } = "Advance";
        public decimal Amount { get; set; }
        public decimal RemainingBalance { get; set; }
        public DateTime CreditDate { get; set; }
        public string? Notes { get; set; }
        public string Status { get; set; } = "Active";
        public DateTime CreatedAt { get; set; }
    }

    public class GenericSupplierCreditCreateRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public int GenericSupplierId { get; set; }
        public string CreditType { get; set; } = "Advance";
        public decimal Amount { get; set; }
        public DateTime? CreditDate { get; set; }
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
    }

    // =========================================================================
    // Credit Applications (Phase A — auto-applied during sale approval)
    // =========================================================================
    public class GenericCustomerCreditApplicationModel
    {
        public int GenericCustomerCreditApplicationId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public int GenericCustomerId { get; set; }
        public string? CustomerName { get; set; }
        public int GenericSaleId { get; set; }
        public string? ReceiptNumber { get; set; }
        public decimal AmountApplied { get; set; }
        public DateTime ApplicationDate { get; set; }
        public string? Description { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    // =========================================================================
    // Bulk Payment Allocation (Phase B)
    // =========================================================================
    public class GenericBulkPaymentAllocation
    {
        public int SaleId { get; set; }
        public decimal Amount { get; set; }
    }

    public class GenericBulkPaymentRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public int GenericCustomerId { get; set; }
        public string PaymentMethod { get; set; } = "Cash";
        public int? GenericCashAccountId { get; set; }
        public int? ReceivedByStaffId { get; set; }
        public DateTime? PaymentDate { get; set; }
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
        public List<GenericBulkPaymentAllocation> Allocations { get; set; } = new();
    }

    // =========================================================================
    // Credit Refunds (Phase C)
    // =========================================================================
    public class GenericCustomerCreditRefundModel
    {
        public int GenericCustomerCreditRefundId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public int GenericCustomerId { get; set; }
        public string? CustomerName { get; set; }
        public decimal Amount { get; set; }
        public string RefundMethod { get; set; } = "Cash";
        public int? GenericCashAccountId { get; set; }
        public string? AccountName { get; set; }
        public DateTime RefundDate { get; set; }
        public string? Reason { get; set; }
        public string Status { get; set; } = "Approved";
        public string? CreatedBy { get; set; }
        public string? ApprovedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? ApprovedAt { get; set; }
    }

    public class GenericCustomerCreditRefundRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public int GenericCustomerId { get; set; }
        public decimal Amount { get; set; }
        public string RefundMethod { get; set; } = "Cash";
        public int? GenericCashAccountId { get; set; }
        public string? Reason { get; set; }
        public string? CreatedBy { get; set; }
    }

    // =========================================================================
    // Deferred Inventory Cost (read-only report)
    // =========================================================================
    public class GenericDeferredCostRow
    {
        public int GenericProductId { get; set; }
        public string ProductName { get; set; } = string.Empty;
        public decimal TotalPurchased { get; set; }
        public decimal TotalSoldCost { get; set; }
        public decimal DeferredBalance { get; set; }
        public decimal CurrentStock { get; set; }
    }
}
