namespace PoultryFarmAPIWeb.Models
{
    // =========================================================================
    // Invoice Document DTOs (migration 494)
    // =========================================================================

    public class InvoiceDocumentRow
    {
        public int GenericInvoiceDocumentId { get; set; }
        public int GenericSaleId { get; set; }
        public string InvoiceNumber { get; set; } = "";
        public DateTime IssueDate { get; set; }
        public DateTime? DueDate { get; set; }
        public string PaymentTerms { get; set; } = "DueImmediately";
        public string DocumentStatus { get; set; } = "Draft";
        public string? CustomerBillingName { get; set; }
        public int? GenericProjectId { get; set; }
        public string? ProjectName { get; set; }
        // Sale financials (live from genericsales)
        public string? SaleReceiptNumber { get; set; }
        public decimal TotalAmount { get; set; }
        public decimal AmountPaid { get; set; }
        public decimal Balance { get; set; }
        public string? PaymentStatus { get; set; }
        // Derived
        public bool IsOverdue { get; set; }
        public int? DaysUntilDue { get; set; }
        public DateTime? CreatedAt { get; set; }
    }

    public class InvoiceDocumentDetail
    {
        public int GenericInvoiceDocumentId { get; set; }
        public string FarmId { get; set; } = "";
        public int GenericSaleId { get; set; }
        public string InvoiceNumber { get; set; } = "";
        public DateTime IssueDate { get; set; }
        public DateTime? DueDate { get; set; }
        public string PaymentTerms { get; set; } = "DueImmediately";
        public string DocumentStatus { get; set; } = "Draft";
        // Customer snapshot
        public string? CustomerBillingName { get; set; }
        public string? CustomerBillingAddress { get; set; }
        public string? CustomerBillingEmail { get; set; }
        public string? CustomerBillingPhone { get; set; }
        // Document fields
        public string? PaymentInstructions { get; set; }
        public string? FooterNotes { get; set; }
        public string? TermsAndConditions { get; set; }
        public string? PurchaseOrderReference { get; set; }
        public string? DeliveryReference { get; set; }
        public int? GenericProjectId { get; set; }
        public string? ProjectName { get; set; }
        public int Version { get; set; }
        public string? VoidedBy { get; set; }
        public DateTime? VoidedAt { get; set; }
        public string? VoidReason { get; set; }
        public string? IssuedBy { get; set; }
        public DateTime? IssuedAt { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime? CreatedAt { get; set; }
        // Sale fields (live)
        public string? SaleReceiptNumber { get; set; }
        public DateTime? SaleDate { get; set; }
        public string? SalesType { get; set; }
        public decimal SubtotalAmount { get; set; }
        public decimal DiscountAmount { get; set; }
        public decimal TaxAmount { get; set; }
        public decimal TotalAmount { get; set; }
        public decimal AmountPaid { get; set; }
        public decimal Balance { get; set; }
        public string? PaymentStatus { get; set; }
        public string? SaleStatus { get; set; }
        // Derived
        public bool IsOverdue { get; set; }
        public int? DaysUntilDue { get; set; }
        // Populated separately
        public List<InvoiceSaleLineRow>? Lines { get; set; }
        public List<InvoiceHistoryRow>? History { get; set; }
    }

    public class InvoiceSaleLineRow
    {
        public int GenericSaleItemId { get; set; }
        public string? ItemType { get; set; }
        public int? GenericProductId { get; set; }
        public int? GenericServiceId { get; set; }
        public string? ProductName { get; set; }
        public string? ServiceName { get; set; }
        public string? Description { get; set; }
        public decimal Quantity { get; set; }
        public string? UnitName { get; set; }
        public decimal UnitPrice { get; set; }
        public decimal DiscountAmount { get; set; }
        public decimal TaxAmount { get; set; }
        public decimal LineTotal { get; set; }
        public int? GenericProjectId { get; set; }
    }

    public class InvoiceHistoryRow
    {
        public int GenericInvoiceHistoryId { get; set; }
        public string Action { get; set; } = "";
        public string? PreviousValue { get; set; }
        public string? NewValue { get; set; }
        public string? UserId { get; set; }
        public DateTime? CreatedAt { get; set; }
    }

    public class InvoiceSettingsDto
    {
        public string FarmId { get; set; } = "";
        public string InvoicePrefix { get; set; } = "INV";
        public int NextNumber { get; set; } = 1;
        public string DefaultPaymentTerms { get; set; } = "DueImmediately";
        public string? PaymentInstructions { get; set; }
        public string? FooterNotes { get; set; }
        public string? TermsAndConditions { get; set; }
        public bool AutoGenerateInvoiceAfterSale { get; set; }
        public bool AutoSendInvoiceAfterIssuance { get; set; }
    }

    public class InvoiceSaleLookup
    {
        public int GenericInvoiceDocumentId { get; set; }
        public string InvoiceNumber { get; set; } = "";
        public string DocumentStatus { get; set; } = "";
        public DateTime IssueDate { get; set; }
        public DateTime? DueDate { get; set; }
    }

    // ---- Request models ----

    public class GenerateInvoiceDocumentRequest
    {
        public string FarmId { get; set; } = "";
        public int SaleId { get; set; }
        public DateTime? DueDate { get; set; }
        public string? PaymentTerms { get; set; }
        public string? PurchaseOrderReference { get; set; }
        public string? DeliveryReference { get; set; }
        public string? PaymentInstructions { get; set; }
        public string? CreatedBy { get; set; }
    }

    public class UpdateDraftInvoiceRequest
    {
        public string FarmId { get; set; } = "";
        public DateTime? DueDate { get; set; }
        public string? PaymentTerms { get; set; }
        public string? PurchaseOrderReference { get; set; }
        public string? DeliveryReference { get; set; }
        public string? PaymentInstructions { get; set; }
        public string? FooterNotes { get; set; }
        public string? TermsAndConditions { get; set; }
        public string? UpdatedBy { get; set; }
    }

    public class IssueInvoiceRequest
    {
        public string FarmId { get; set; } = "";
        public string? IssuedBy { get; set; }
    }

    public class VoidInvoiceRequest
    {
        public string FarmId { get; set; } = "";
        public string Reason { get; set; } = "";
        public string? VoidedBy { get; set; }
    }

    public static class PaymentTerms
    {
        public const string DueImmediately = "DueImmediately";
        public const string Net7 = "Net7";
        public const string Net14 = "Net14";
        public const string Net30 = "Net30";
        public const string Net45 = "Net45";
        public const string Net60 = "Net60";
        public const string Custom = "Custom";
    }

    public static class InvoiceDocumentStatuses
    {
        public const string Draft = "Draft";
        public const string Issued = "Issued";
        public const string Voided = "Voided";
        public const string Superseded = "Superseded";
    }

    public class InvoiceReconciliationRow
    {
        public string CheckName { get; set; } = "";
        public string Severity { get; set; } = "";
        public int? DocumentId { get; set; }
        public int? SaleId { get; set; }
        public string Detail { get; set; } = "";
    }
}
