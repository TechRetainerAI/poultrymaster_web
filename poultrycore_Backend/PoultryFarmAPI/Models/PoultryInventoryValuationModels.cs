// Poultry inventory valuation (migrations 267 and 268).
//
// TWO VALUES, NOT ONE, and the distinction is the reason this file exists.
//
//   OperationalValue   what the stock cost. What it is worth to the business,
//                      what cost-per-kg is built on, and what an owner means by
//                      "how much stock do I have".
//   DeferredValue      only the part still waiting to reach Profit & Loss. Zero
//                      for stock bought under expense-at-purchase, however much
//                      that stock cost.
//
// They are equal only on a farm that defers everything. Reporting only the
// second would call an expense-at-purchase farm's entire store worthless.

namespace PoultryFarmAPIWeb.Models
{
    /// <summary>One raw-material item's stock, valued both ways.</summary>
    public class PoultryInventoryValuationModel
    {
        public int PoultryRawMaterialItemId { get; set; }
        public string? ItemName { get; set; }
        public string? Category { get; set; }
        public string? UnitOfMeasure { get; set; }

        /// <summary>FIFO | LIFO | HIFO -- which lot is drawn first.</summary>
        public string? UsageMethod { get; set; }

        /// <summary>The item's resolved recognition method today.</summary>
        public string? EffectiveMethod { get; set; }

        /// <summary>FarmDefault | ItemOverride.</summary>
        public string? CostRecognitionSource { get; set; }

        /// <summary>The item's own quantity counter.</summary>
        public decimal PhysicalQuantity { get; set; }

        /// <summary>What the open cost layers say is left.</summary>
        public decimal CostLayerQuantity { get; set; }

        /// <summary>
        /// The difference. Non-zero means stock left without drawing a lot --
        /// internal use and stock adjustments still do that, and Phase 3 owns it.
        /// Reported, never silently repaired.
        /// </summary>
        public decimal QuantityDrift { get; set; }

        public decimal OperationalValue { get; set; }
        public decimal DeferredValue { get; set; }
        public int OpenLots { get; set; }
        public int DeferredLots { get; set; }
    }

    /// <summary>The same picture for a whole farm, plus how far it can be trusted.</summary>
    public class PoultryInventoryValuationSummaryModel
    {
        public int ItemsWithStock { get; set; }
        public decimal OperationalValue { get; set; }
        public decimal DeferredValue { get; set; }

        /// <summary>How many items are on expense-at-consumption today.</summary>
        public int ItemsDeferring { get; set; }

        public int OpenLots { get; set; }
        public int DeferredLots { get; set; }

        /// <summary>Items whose stock and cost layers disagree.</summary>
        public int ItemsWithDrift { get; set; }

        /// <summary>
        /// Rows the cost-layer audit raised. ZERO on a healthy farm -- the audit
        /// is silent when there is nothing to say, so a non-zero count here is
        /// always worth reading.
        /// </summary>
        public int AuditFindings { get; set; }
    }

    /// <summary>
    /// One thing the cost-layer audit found. Severity is the triage:
    ///
    ///   Corrupt    the numbers contradict themselves
    ///   Stranded   deferred cost that can no longer reach the P&amp;L
    ///   Drift      stock and lots disagree, but no money is stuck
    /// </summary>
    public class PoultryCostLayerAuditModel
    {
        public string? Finding { get; set; }
        public string? Severity { get; set; }
        public int? ItemId { get; set; }
        public string? ItemName { get; set; }
        public int? PurchaseId { get; set; }
        public decimal? Amount { get; set; }
        public string? Detail { get; set; }
    }

    /// <summary>What GET /api/Poultry/inventory-valuation returns in one round trip.</summary>
    public class PoultryInventoryValuationResponse
    {
        public PoultryInventoryValuationSummaryModel Summary { get; set; } = new();
        public List<PoultryInventoryValuationModel> Items { get; set; } = new();

        /// <summary>Empty on a healthy farm.</summary>
        public List<PoultryCostLayerAuditModel> AuditFindings { get; set; } = new();
    }
}
