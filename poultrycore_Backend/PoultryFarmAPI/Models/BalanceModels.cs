using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    // Shapes for the Customer Balances and Supplier Balances control pages.
    //
    // Deliberately module-neutral: the poultry, water and generic balance pages
    // answer the same five questions (who owes, on which documents, how old, how
    // much, and what did we just pay), and the SQL behind them returns the same
    // columns. Water and Generic reuse these rather than defining their own.
    //
    // "Document" rather than "Sale"/"Purchase" because the poultry payables side
    // spans two tables -- raw-material purchases and flock batches -- so an id
    // alone is ambiguous and DocumentType has to travel with it.

    public static class BalanceStatusFilters
    {
        public const string All = "All";
        public const string Partial = "Partial";
        public const string Unpaid = "Unpaid";
        public const string Overdue = "Overdue";
    }

    public static class PayableDocumentTypes
    {
        public const string RawMaterialPurchase = "RawMaterialPurchase";
        public const string FlockBatch = "FlockBatch";
        /// <summary>Generic module's single purchase document. Unused by poultry.</summary>
        public const string Purchase = "Purchase";
        /// <summary>An expense that names a supplier and is not yet fully paid
        /// (migration 238). Unlike a purchase, paying one books NO new expense --
        /// the expense being settled is already the cost.</summary>
        public const string Expense = "Expense";
    }

    public static class PaymentSourceTypes
    {
        /// <summary>Recorded on the Sale itself.</summary>
        public const string SaleEntry = "SaleEntry";
        /// <summary>Recorded on the Purchase itself.</summary>
        public const string PurchaseEntry = "PurchaseEntry";
        public const string CustomerBalances = "CustomerBalances";
        public const string SupplierBalances = "SupplierBalances";
    }

    /// <summary>One summary row: a customer who owes us, or a supplier we owe.</summary>
    public class PartyBalanceRow
    {
        public int PartyId { get; set; }
        public string PartyName { get; set; } = string.Empty;
        public string? ContactPhone { get; set; }
        public string? ContactEmail { get; set; }
        public int PaymentTermsDays { get; set; }
        public decimal TotalBalance { get; set; }
        /// <summary>Open sales for a customer; open purchases for a supplier.</summary>
        public int OpenDocumentCount { get; set; }
        public DateTime? OldestDocumentDate { get; set; }
        public DateTime? LatestDocumentDate { get; set; }
        public DateTime? LastPaymentDate { get; set; }
        public decimal OverdueAmount { get; set; }
        public decimal TotalInvoiced { get; set; }
        public decimal TotalPaid { get; set; }
    }

    /// <summary>The unpaid or part-paid document behind a balance.</summary>
    public class OpenDocumentRow
    {
        /// <summary>Sale for customers; RawMaterialPurchase or FlockBatch for suppliers.</summary>
        public string DocumentType { get; set; } = string.Empty;
        public int DocumentId { get; set; }
        /// <summary>Human-facing number, e.g. S14 or B0031.</summary>
        public string? Reference { get; set; }
        public DateTime DocumentDate { get; set; }
        /// <summary>Product, item or batch name -- what the line is actually for.</summary>
        public string? Label { get; set; }
        public string? Description { get; set; }
        public decimal TotalAmount { get; set; }
        public decimal AmountPaid { get; set; }
        public decimal Balance { get; set; }
        /// <summary>Derived: document date + the party's payment terms.</summary>
        public DateTime? DueDate { get; set; }
        public int AgeDays { get; set; }
        /// <summary>Unpaid | Partially Paid.</summary>
        public string Status { get; set; } = string.Empty;
        public bool IsOverdue { get; set; }
        public int? CashAccountId { get; set; }
    }

    public class BalanceSummary
    {
        public decimal TotalBalance { get; set; }
        /// <summary>Customers owing, or suppliers owed.</summary>
        public int PartyCount { get; set; }
        public decimal OverdueBalance { get; set; }
        public decimal PaymentsToday { get; set; }
        public decimal LargestBalance { get; set; }
        public string? LargestBalanceParty { get; set; }
    }

    /// <summary>One line of a payment's allocation grid, as submitted.</summary>
    public class PaymentAllocationInput
    {
        /// <summary>Customer side: the sale id. Ignored when DocumentId is set.</summary>
        public int SaleId { get; set; }
        public string? DocumentType { get; set; }
        public int DocumentId { get; set; }
        [Range(0.01, double.MaxValue, ErrorMessage = "Each allocation must be greater than 0.")]
        public decimal Amount { get; set; }
    }

    /// <summary>
    /// A payment plus how it is spread across open documents. One allocation for a
    /// payment taken on the sale/purchase itself; several for a bulk payment.
    /// </summary>
    public class RecordPaymentRequest
    {
        public string FarmId { get; set; } = string.Empty;
        /// <summary>Customer id, or supplier id. Null suppliers are allowed (see migration 224).</summary>
        public int? PartyId { get; set; }
        [Range(0.01, double.MaxValue, ErrorMessage = "Payment amount must be greater than 0.")]
        public decimal Amount { get; set; }
        public DateTime? PaymentDate { get; set; }
        public string? PaymentMethod { get; set; }
        public int? CashAccountId { get; set; }
        public string? Reference { get; set; }
        public string? Notes { get; set; }
        public string? SourceType { get; set; }
        public string? CreatedBy { get; set; }
        public List<PaymentAllocationInput> Allocations { get; set; } = new();
    }

    public class ReversePaymentRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public string? Reason { get; set; }
        public string? ReversedBy { get; set; }
    }

    /// <summary>
    /// A payment as the user made it. On the customer side this is a
    /// paymentgroupid -- poultrypayments stores one row per sale, and the group
    /// is the payment -- so the identifier is a uuid rather than an int.
    /// </summary>
    public class PaymentHistoryRow
    {
        public string PaymentId { get; set; } = string.Empty;
        public int? PartyId { get; set; }
        public string? PartyName { get; set; }
        public DateTime PaymentDate { get; set; }
        public decimal TotalAmount { get; set; }
        public string? PaymentMethod { get; set; }
        public string? Reference { get; set; }
        public string? Notes { get; set; }
        public string? SourceType { get; set; }
        public string Status { get; set; } = "Posted";
        public int AllocationCount { get; set; }
        public int? CashAccountId { get; set; }
        public string? CreatedBy { get; set; }
        public string? ReversedBy { get; set; }
        public DateTime? ReversedAt { get; set; }
        public string? ReversalReason { get; set; }
    }

    public class PaymentAllocationRow
    {
        public int AllocationId { get; set; }
        public string DocumentType { get; set; } = string.Empty;
        public int DocumentId { get; set; }
        public string? Reference { get; set; }
        public DateTime? DocumentDate { get; set; }
        public string? Label { get; set; }
        public decimal DocumentTotal { get; set; }
        public decimal AmountApplied { get; set; }
        public decimal BalanceBefore { get; set; }
        public decimal BalanceAfter { get; set; }
        public string Status { get; set; } = "Posted";
    }

    /// <summary>One line of a customer or supplier statement.</summary>
    public class StatementLine
    {
        public DateTime? EntryDate { get; set; }
        /// <summary>OpeningBalance | Sale | Purchase | Payment.</summary>
        public string EntryType { get; set; } = string.Empty;
        public string? Reference { get; set; }
        public string? Description { get; set; }
        /// <summary>What increases the balance owed.</summary>
        public decimal Debit { get; set; }
        /// <summary>What reduces it.</summary>
        public decimal Credit { get; set; }
        public decimal RunningBalance { get; set; }
        public string? DocumentType { get; set; }
        public int? DocumentId { get; set; }
    }

    /// <summary>Filters shared by both balance pages.</summary>
    public class BalanceQuery
    {
        public string FarmId { get; set; } = string.Empty;
        public DateTime? From { get; set; }
        public DateTime? To { get; set; }
        public int? PartyId { get; set; }
        public string? Status { get; set; }
        public decimal? MinBalance { get; set; }
        public string? Search { get; set; }
    }

    /// <summary>A row where the allocation layer has drifted from the documents.</summary>
    public class BalanceAuditRow
    {
        public string Side { get; set; } = string.Empty;
        public string DocumentType { get; set; } = string.Empty;
        public int DocumentId { get; set; }
        public decimal AmountPaid { get; set; }
        public decimal Allocated { get; set; }
        public decimal Difference { get; set; }
    }
}
