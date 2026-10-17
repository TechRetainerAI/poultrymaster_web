namespace PoultryFarmAPIWeb.Models
{
    // 370: supplier credit, advances, refunds and debt (poultry). Credit is
    // derived on the server: a payment's amount - what is applied - refunds.

    public class SupplierCreditSummaryRow
    {
        public int SupplierId { get; set; }
        public string SupplierName { get; set; } = string.Empty;
        public decimal AvailableCredit { get; set; }
        public int CreditCount { get; set; }
        /// <summary>What the business still owes this supplier -- shown beside the credit, never netted.</summary>
        public decimal Owed { get; set; }
    }

    public class SupplierCreditEventRow
    {
        public int PoultrySupplierPaymentId { get; set; }
        public string CreditNumber { get; set; } = string.Empty;
        public DateTime? CreditDate { get; set; }
        public int SupplierId { get; set; }
        public string? SupplierName { get; set; }
        public string Source { get; set; } = string.Empty;
        public string? SourceType { get; set; }
        public string? Reference { get; set; }
        public string? Notes { get; set; }
        public decimal OriginalAmount { get; set; }
        public decimal Applied { get; set; }
        public decimal Refunded { get; set; }
        public decimal Available { get; set; }
        public string Status { get; set; } = string.Empty;
        /// <summary>An advance or a credit added by hand: reversed from Supplier Credits.</summary>
        public bool IsManual { get; set; }
        public int? PoultryCashAccountId { get; set; }
        public string? AccountName { get; set; }
    }

    public class SupplierCreditApplicationRow
    {
        public int AllocationId { get; set; }
        public int PoultrySupplierPaymentId { get; set; }
        public string CreditNumber { get; set; } = string.Empty;
        public int SupplierId { get; set; }
        public string? SupplierName { get; set; }
        public string DocumentType { get; set; } = string.Empty;
        public int DocumentId { get; set; }
        public string? Reference { get; set; }
        public string? Label { get; set; }
        public decimal Amount { get; set; }
        public DateTime? AppliedDate { get; set; }
        public string Status { get; set; } = "Posted";
        public string? CreatedBy { get; set; }
        public DateTime? ReversedAt { get; set; }
        public string? ReversalReason { get; set; }
    }

    /// <summary>A supplier credit with no cash: SupplierCreditNote | SupplierOpeningCredit | SupplierManualCredit.</summary>
    public class SupplierCreditCreateRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public int SupplierId { get; set; }
        public string Kind { get; set; } = string.Empty;
        public decimal Amount { get; set; }
        public DateTime? CreditDate { get; set; }
        public string? Reference { get; set; }
        public string Reason { get; set; } = string.Empty;
        public string? CreatedBy { get; set; }
    }

    public class SupplierCreditApplyRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public int PoultrySupplierPaymentId { get; set; }
        public string DocumentType { get; set; } = string.Empty;
        public int DocumentId { get; set; }
        public decimal Amount { get; set; }
        public string? CreatedBy { get; set; }
    }

    public class SupplierReasonRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public string Reason { get; set; } = string.Empty;
        public string? By { get; set; }
    }

    public class SupplierRefundRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public int PoultrySupplierPaymentId { get; set; }
        public decimal Amount { get; set; }
        public int PoultryCashAccountId { get; set; }
        public string? PaymentMethod { get; set; }
        public DateTime? RefundDate { get; set; }
        public string Reason { get; set; } = string.Empty;
        public string? CreatedBy { get; set; }
    }

    public class SupplierRefundRow
    {
        public int RefundId { get; set; }
        public string RefundNumber { get; set; } = string.Empty;
        public int SupplierId { get; set; }
        public string? SupplierName { get; set; }
        public decimal Amount { get; set; }
        public DateTime? RefundDate { get; set; }
        public int PoultryCashAccountId { get; set; }
        public string? AccountName { get; set; }
        public string? PaymentMethod { get; set; }
        public string Reason { get; set; } = string.Empty;
        public string Status { get; set; } = "Posted";
        public string? CreatedBy { get; set; }
        public DateTime? CreatedAt { get; set; }
        public string? CreditNumbers { get; set; }
        public DateTime? ReversedAt { get; set; }
        public string? ReversedBy { get; set; }
        public string? ReversalReason { get; set; }
        public DateTime? ReversalDate { get; set; }
    }

    public class SupplierDebtRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public int SupplierId { get; set; }
        public decimal Amount { get; set; }
        public DateTime? DebtDate { get; set; }
        public string EntryType { get; set; } = string.Empty;
        public string Description { get; set; } = string.Empty;
        public string? Reference { get; set; }
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
    }

    public class SupplierDebtRow
    {
        public int DebtId { get; set; }
        public string DebtNumber { get; set; } = string.Empty;
        public int SupplierId { get; set; }
        public string? SupplierName { get; set; }
        public decimal Amount { get; set; }
        public decimal Paid { get; set; }
        public decimal Balance { get; set; }
        public DateTime? DebtDate { get; set; }
        public string EntryType { get; set; } = string.Empty;
        public string Description { get; set; } = string.Empty;
        public string? Reference { get; set; }
        public string? Notes { get; set; }
        public string Status { get; set; } = "Posted";
        public string? CreatedBy { get; set; }
        public DateTime? CreatedAt { get; set; }
        public string? ReversedBy { get; set; }
        public DateTime? ReversedAt { get; set; }
        public string? ReversalReason { get; set; }
    }
}
