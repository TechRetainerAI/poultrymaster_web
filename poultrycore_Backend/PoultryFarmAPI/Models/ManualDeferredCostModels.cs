namespace PoultryFarmAPIWeb.Models
{
    // 371: manual deferred inventory cost -- cost for stock no purchase covers
    // (e.g. opening stock), recognised as the stock is used. Never a typed total.

    public class ManualDeferredCostRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public int PoultryRawMaterialItemId { get; set; }
        public decimal Amount { get; set; }
        public decimal Quantity { get; set; }
        public DateTime? EffectiveDate { get; set; }
        /// <summary>OpeningDeferredCost | HistoricalDeferredCost | CostAdjustment | Migration | Other</summary>
        public string EntryType { get; set; } = string.Empty;
        public string Reason { get; set; } = string.Empty;
        public string? Reference { get; set; }
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
    }

    public class ManualDeferredCostReverseRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public string Reason { get; set; } = string.Empty;
        public string? ReversedBy { get; set; }
    }

    public class ManualDeferredCostRow
    {
        public int EntryId { get; set; }
        public string EntryNumber { get; set; } = string.Empty;
        public int PoultryRawMaterialPurchaseId { get; set; }
        public int PoultryRawMaterialItemId { get; set; }
        public string? ItemName { get; set; }
        public string? UnitOfMeasure { get; set; }
        public string EntryType { get; set; } = string.Empty;
        public decimal Amount { get; set; }
        public decimal Quantity { get; set; }
        public DateTime? EffectiveDate { get; set; }
        public decimal Recognised { get; set; }
        public decimal Remaining { get; set; }
        public decimal RemainingQuantity { get; set; }
        public string Reason { get; set; } = string.Empty;
        public string? Reference { get; set; }
        public string? Notes { get; set; }
        public string Status { get; set; } = "Posted";
        public string? CreatedBy { get; set; }
        public DateTime? CreatedAt { get; set; }
        public string? ReversedBy { get; set; }
        public DateTime? ReversedAt { get; set; }
        public string? ReversalReason { get; set; }
        public decimal? ReversedAmount { get; set; }
    }

    public class UncoveredStockRow
    {
        public int PoultryRawMaterialItemId { get; set; }
        public string ItemName { get; set; } = string.Empty;
        public string? UnitOfMeasure { get; set; }
        public decimal CurrentQuantity { get; set; }
        public decimal UncoveredQuantity { get; set; }
    }
}
