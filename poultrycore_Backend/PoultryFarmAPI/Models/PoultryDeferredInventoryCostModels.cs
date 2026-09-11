// Poultry deferred inventory costs (migration 288).
//
// Shapes for the Deferred Inventory Costs page. Every figure here is computed in
// SQL -- see 288 -- and these types only carry it. There is deliberately no
// arithmetic in this file: a total recomputed in C# would be a second answer to
// a question the database has already answered, and the two would drift.
//
// THREE READS, THREE SHAPES
//   PoultryDeferredPurchaseModel        one purchase lot, for the main table
//   PoultryDeferredRecognitionModel     one usage that drew on it, for the
//                                       expanded row
//   PoultryConsumptionCostLayerModel    one lot a consumption drew from, for
//                                       the cost breakdown on a production
//                                       record or an expense

namespace PoultryFarmAPIWeb.Models
{
    /// <summary>
    /// One inventory purchase lot and where its cost has got to.
    /// </summary>
    public class PoultryDeferredPurchaseModel
    {
        public int PoultryRawMaterialPurchaseId { get; set; }
        public DateTime PurchaseDate { get; set; }
        public int PoultryRawMaterialItemId { get; set; }
        public string? ItemName { get; set; }
        public string? Category { get; set; }
        public string? UnitOfMeasure { get; set; }
        public string? ProductionUnit { get; set; }
        public int? SupplierId { get; set; }
        public string? SupplierName { get; set; }

        // All three in PRODUCTION units -- the unit the stock is consumed in.
        public decimal PurchasedQuantity { get; set; }
        public decimal ConsumedQuantity { get; set; }
        public decimal RemainingQuantity { get; set; }

        /// <summary>What the stock cost. NOT the deferred basis: on a lot
        /// expensed at purchase this is a real number while the deferred
        /// basis is zero.</summary>
        public decimal OperationalCost { get; set; }
        /// <summary>What this lot deferred when it was created.</summary>
        public decimal DeferredTotalCost { get; set; }
        /// <summary>How much of that has reached Profit &amp; Loss. Already net
        /// of reversals.</summary>
        public decimal RecognizedCost { get; set; }
        /// <summary>How much is still waiting.</summary>
        public decimal DeferredRemainingCost { get; set; }
        public decimal RecognitionPercent { get; set; }

        /// <summary>The same recognised figure counted independently, from the
        /// individual allocations rather than the lot balance.</summary>
        public decimal AllocatedRecognizedCost { get; set; }
        /// <summary>The gap between the two counts. Non-zero means the row is
        /// an Exception and neither figure should be quoted.</summary>
        public decimal RecognitionDrift { get; set; }

        public string? CostRecognitionMethod { get; set; }
        public string? RecognitionMethodLabel { get; set; }
        public string? Status { get; set; }
        /// <summary>Plain-language reason, set only on Exception rows.</summary>
        public string? ExceptionReason { get; set; }

        public int? SourceFeedProductionBatchId { get; set; }
        public string? FeedProductionBatchNumber { get; set; }
        /// <summary>True when this lot was produced by feed production rather
        /// than bought, in which case it has a batch instead of a supplier.</summary>
        public bool IsLotProduced { get; set; }

        public int RecognitionEvents { get; set; }
        public DateTime? LastRecognitionDate { get; set; }

        // ---- 289: the consumption queue ------------------------------------
        /// <summary>FIFO | LIFO | HIFO — the item's costing method, which
        /// decides draw order and therefore everything below.</summary>
        public string? CostingMethod { get; set; }
        /// <summary>Place in the queue for this item, 1 = drawn next. NULL when
        /// the lot has no stock left, so it is not queued at all.</summary>
        public int? QueuePosition { get; set; }
        /// <summary>Stock (production units) that will be consumed before this
        /// lot is reached. 0 means next. This is why a deferred cost can sit
        /// still while stock is being consumed.</summary>
        public decimal? QuantityAheadInQueue { get; set; }
    }

    /// <summary>
    /// One consumption that drew on a purchase lot -- a row of the expanded
    /// recognition history.
    /// </summary>
    public class PoultryDeferredRecognitionModel
    {
        public int PoultryRawMaterialUsageId { get; set; }
        public DateTime UsedDate { get; set; }
        public string? SourceType { get; set; }
        /// <summary>Ready-made human label, built in SQL so the UI never has to
        /// assemble one from three nullable ids.</summary>
        public string? SourceLabel { get; set; }
        public int? ProductionRecordId { get; set; }
        public int? PoultryProductionBatchId { get; set; }
        public string? ProductionBatchNumber { get; set; }
        public int? FlockId { get; set; }
        public string? FlockName { get; set; }
        public int? PoultryFeedProductionBatchId { get; set; }
        public string? FeedProductionBatchNumber { get; set; }

        public string? ItemName { get; set; }
        public string? ProductionUnit { get; set; }
        public decimal QuantityDrawn { get; set; }
        public decimal UnitCostAtDraw { get; set; }
        public decimal OperationalCost { get; set; }
        /// <summary>THIS allocation's recognised amount. Zero on a lot expensed
        /// at purchase -- the stock was not free, its cost was taken earlier.</summary>
        public decimal RecognizedCost { get; set; }
        public string? RecognitionOutcome { get; set; }

        public bool IsReversed { get; set; }
        public DateTime? ReversedAt { get; set; }
        public int? ExpenseId { get; set; }
        /// <summary>The whole production record's expense, NOT this row's share.
        /// One expense covers everything a record consumed, which may include
        /// other items drawing on other lots. RecognizedCost is this row's
        /// share; this is here so the row can link to the expense it landed in.</summary>
        public decimal? ExpenseAmount { get; set; }
        public string? ExpenseStatus { get; set; }
    }

    /// <summary>
    /// One cost layer a consumption drew from -- a row of "how was this cost
    /// worked out".
    /// </summary>
    public class PoultryConsumptionCostLayerModel
    {
        public int PoultryRawMaterialUsageId { get; set; }
        public int PoultryRawMaterialItemId { get; set; }
        public string? ItemName { get; set; }
        public string? Category { get; set; }
        public DateTime UsedDate { get; set; }
        public decimal TotalQuantityUsed { get; set; }
        public string? ProductionUnit { get; set; }

        public int PoultryRawMaterialPurchaseId { get; set; }
        public DateTime PurchaseDate { get; set; }
        public string? SupplierName { get; set; }
        public int? SourceFeedProductionBatchId { get; set; }
        public string? FeedProductionBatchNumber { get; set; }

        public decimal QuantityDrawn { get; set; }
        public decimal UnitCostAtDraw { get; set; }
        public decimal OperationalCost { get; set; }
        public decimal RecognizedCost { get; set; }
        /// <summary>The LOT's snapshot, not the item's current setting. Two rows
        /// of one breakdown can and do disagree here.</summary>
        public string? LotRecognitionMethod { get; set; }
        public string? RecognitionLabel { get; set; }
        public bool IsReversed { get; set; }
    }

    /// <summary>
    /// The summary cards. Computed by the same SQL that produces the rows, so
    /// the cards cannot disagree with the table beneath them.
    /// </summary>
    public class PoultryDeferredCostSummaryModel
    {
        public decimal RemainingDeferredCost { get; set; }
        public decimal RecognizedCost { get; set; }
        public decimal DeferredBasis { get; set; }
        public decimal OperationalCost { get; set; }
        public int PurchaseCount { get; set; }
        public int DeferredPurchases { get; set; }
        public int FullyRecognized { get; set; }
        public int NotRecognized { get; set; }
        public int Exceptions { get; set; }
        public decimal ExceptionDrift { get; set; }
        public decimal RecognitionPercent { get; set; }
        /// <summary>289. How many filtered lots cannot be reached yet because
        /// older stock stands in front of them. Zero is the reassuring answer.</summary>
        public int BlockedPurchases { get; set; }
        public decimal BlockedCost { get; set; }
    }

    /// <summary>Summary plus rows, fetched in one round trip.</summary>
    public class PoultryDeferredCostResponse
    {
        public PoultryDeferredCostSummaryModel Summary { get; set; } = new();
        public List<PoultryDeferredPurchaseModel> Purchases { get; set; } = new();
    }
}
