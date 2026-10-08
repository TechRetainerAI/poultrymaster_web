using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    // =========================================================================
    // Poultry Purchase Receipts (migration 345). One supplier invoice received
    // in one step. The receipt orchestrates the existing purchase, supplier
    // payment and stock-adjustment functions; it posts nothing of its own.
    // =========================================================================

    public class PoultryPurchaseReceiptLineInput
    {
        [Required] public int PoultryRawMaterialItemId { get; set; }

        /// <summary>In PURCHASE units (bags, cartons ...), as on the invoice.</summary>
        [Range(0.001, double.MaxValue)] public decimal Quantity { get; set; }

        /// <summary>Invoice price per purchase unit, before additional costs.</summary>
        [Range(0, double.MaxValue)] public decimal UnitCost { get; set; }

        [StringLength(30)] public string? ProductionUnit { get; set; }

        /// <summary>Production units in one purchase unit (e.g. 25 kg per bag). Null means 1.</summary>
        public decimal? ProductionUnitsPerPurchaseUnit { get; set; }

        [StringLength(300)] public string? Notes { get; set; }
    }

    public class PoultryPurchaseReceiptRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        public string? CreatedBy { get; set; }

        /// <summary>An existing supplier, or ...</summary>
        public int? SupplierId { get; set; }
        /// <summary>... a name, resolved to a supplier record (created if new).</summary>
        [StringLength(200)] public string? SupplierName { get; set; }

        public DateTime? PurchaseDate { get; set; }
        [StringLength(100)] public string? ReferenceNo { get; set; }
        public DateTime? DueDate { get; set; }
        [StringLength(500)] public string? Notes { get; set; }

        [Range(0, double.MaxValue)] public decimal AdditionalCosts { get; set; }
        [StringLength(200)] public string? AdditionalCostsNote { get; set; }

        /// <summary>Paid now. 0 = on credit; the total = paid in full; between = part paid.</summary>
        [Range(0, double.MaxValue)] public decimal AmountPaid { get; set; }
        [StringLength(30)] public string? PaymentMethod { get; set; }
        public int? CashAccountId { get; set; }

        /// <summary>
        /// Generated once per form by the browser. A second Save carrying the same
        /// id returns the first receipt instead of receiving the goods twice.
        /// </summary>
        public Guid? ClientRequestId { get; set; }

        [Required, MinLength(1)] public List<PoultryPurchaseReceiptLineInput> Lines { get; set; } = new();
    }

    public class PoultryPurchaseReceiptReverseRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        public string? ReversedBy { get; set; }
        [Required, StringLength(500)] public string Reason { get; set; } = string.Empty;
    }

    public class PoultryPurchaseReceiptModel
    {
        public int PoultryPurchaseReceiptId { get; set; }
        public string ReceiptNumber { get; set; } = string.Empty;
        public int SupplierId { get; set; }
        public string? SupplierName { get; set; }
        public DateTime PurchaseDate { get; set; }
        public string? ReferenceNo { get; set; }
        public DateTime? DueDate { get; set; }
        public string? Notes { get; set; }
        public decimal Subtotal { get; set; }
        public decimal AdditionalCosts { get; set; }
        public string? AdditionalCostsNote { get; set; }
        public decimal TotalCost { get; set; }
        public decimal AmountPaidAtReceipt { get; set; }

        /// <summary>Live, from the lots: later supplier payments count, reversed ones do not.</summary>
        public decimal AmountPaid { get; set; }
        public decimal Balance { get; set; }

        /// <summary>"Paid" | "Part paid" | "Unpaid" | "Reversed".</summary>
        public string PaymentStatus { get; set; } = string.Empty;
        public bool IsOverdue { get; set; }
        public string? PaymentMethod { get; set; }
        public int? PoultryCashAccountId { get; set; }
        public string? CashAccountName { get; set; }
        public int? PoultrySupplierPaymentId { get; set; }

        /// <summary>"Posted" | "Reversed".</summary>
        public string Status { get; set; } = string.Empty;
        public int LineCount { get; set; }
        public string? ItemSummary { get; set; }

        /// <summary>Line totals expensed as they are paid (EXPENSE_WHEN_PURCHASED).</summary>
        public decimal ExpensedAtPurchaseCost { get; set; }
        /// <summary>Line totals held as inventory until used (EXPENSE_WHEN_CONSUMED).</summary>
        public decimal DeferredCost { get; set; }

        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public string? ReversedBy { get; set; }
        public DateTime? ReversedAt { get; set; }
        public string? ReversalReason { get; set; }

        /// <summary>Why this receipt cannot be reversed right now; null when it can.</summary>
        public string? ReversalBlocker { get; set; }

        public List<PoultryPurchaseReceiptLineModel>? Lines { get; set; }
    }

    public class PoultryPurchaseReceiptLineModel
    {
        public int PoultryPurchaseReceiptLineId { get; set; }
        public int LineNo { get; set; }
        public int PoultryRawMaterialItemId { get; set; }
        public string? ItemName { get; set; }
        public string? Category { get; set; }
        public string? UnitOfMeasure { get; set; }
        public decimal Quantity { get; set; }
        public decimal UnitCost { get; set; }
        public decimal LineSubtotal { get; set; }
        public decimal AllocatedAdditionalCost { get; set; }
        public decimal LineTotal { get; set; }
        public decimal LandedUnitCost { get; set; }
        public string? ProductionUnit { get; set; }
        public decimal? ProductionUnitsPerPurchaseUnit { get; set; }
        public decimal ProductionQuantity { get; set; }
        public string? Notes { get; set; }
        public int PoultryRawMaterialPurchaseId { get; set; }
        public string? CostRecognitionMethod { get; set; }
        public string? RecognitionLabel { get; set; }
        public decimal RemainingQuantity { get; set; }
        public decimal ConsumedQuantity { get; set; }
        public decimal AmountPaid { get; set; }
        public decimal Balance { get; set; }
        public decimal DeferredRemainingCost { get; set; }
        public int? ReversalAdjustmentId { get; set; }
    }
}
