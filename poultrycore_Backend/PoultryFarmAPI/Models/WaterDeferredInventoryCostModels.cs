// Water deferred inventory costs (migration 281).
//
// Shapes for the Deferred Inventory Costs page. Every figure here is computed in
// SQL -- see 281 -- and these types only carry it. There is deliberately no
// arithmetic in this file: a total recomputed in C# would be a second answer to
// a question the database has already answered, and the two would drift.
//
// THREE READS, THREE SHAPES
//   WaterDeferredPurchaseModel        one purchase lot, for the main table
//   WaterDeferredRecognitionModel     one usage that drew on it, for the
//                                     expanded row
//   WaterConsumptionCostLayerModel    one lot a consumption drew from, for the
//                                     cost breakdown on a production batch or
//                                     an expense
//
// WHERE THIS DIFFERS FROM THE POULTRY TWIN
// ----------------------------------------
// Water has no feed production, so every lot is BOUGHT. The poultry models carry
// SourceFeedProductionBatchId, FeedProductionBatchNumber and IsLotProduced to
// describe a lot that was manufactured out of other lots; there is no such thing
// here and those fields are absent rather than present-and-always-null. A
// nullable field that can never be set is a question the UI has to keep asking.
//
// Water also has no flocks and no production records. A water consumption is
// attached to a WATER PRODUCTION BATCH -- the run that made the sachets -- so
// that one id replaces poultry's ProductionRecordId / PoultryProductionBatchId /
// FlockId trio.

namespace PoultryFarmAPIWeb.Models
{
    /// <summary>
    /// One inventory purchase lot and where its cost has got to.
    /// </summary>
    public class WaterDeferredPurchaseModel
    {
        public int WaterRawMaterialPurchaseId { get; set; }
        public DateTime PurchaseDate { get; set; }
        public int WaterRawMaterialItemId { get; set; }
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

        public int RecognitionEvents { get; set; }
        public DateTime? LastRecognitionDate { get; set; }

        // ---- the consumption queue ------------------------------------------
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
    public class WaterDeferredRecognitionModel
    {
        public int WaterRawMaterialUsageId { get; set; }
        public DateTime UsedDate { get; set; }
        public string? SourceType { get; set; }
        /// <summary>Ready-made human label, built in SQL so the UI never has to
        /// assemble one from nullable ids.</summary>
        public string? SourceLabel { get; set; }
        /// <summary>The production run that consumed the stock. Water's only
        /// consumption context: there is no flock and no production record.</summary>
        public int? WaterProductionBatchId { get; set; }
        /// <summary>The batch's own number. Read from 281's
        /// `productionbatchnumber` column; the property is named for the JSON
        /// the page reads (`batchNumber`).</summary>
        public string? BatchNumber { get; set; }
        /// <summary>What that batch was making. 281 returns it as `productname`
        /// (waterproducts calls the column `name`).</summary>
        public string? ProductName { get; set; }

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
        /// <summary>The waterexpenses row this draw was recognised into. 281
        /// returns it as `expenseid`; the property is named for the JSON the
        /// page reads (`waterExpenseId`).</summary>
        public int? WaterExpenseId { get; set; }
        /// <summary>The whole production batch's expense, NOT this row's share.
        /// One expense covers everything a batch consumed, which may include
        /// other items drawing on other lots. RecognizedCost is this row's
        /// share; this is here so the row can link to the expense it landed in.</summary>
        public decimal? ExpenseAmount { get; set; }
        public string? ExpenseStatus { get; set; }
    }

    /// <summary>
    /// One cost layer a consumption drew from -- a row of "how was this cost
    /// worked out".
    /// </summary>
    public class WaterConsumptionCostLayerModel
    {
        public int WaterRawMaterialUsageId { get; set; }
        public int WaterRawMaterialItemId { get; set; }
        public string? ItemName { get; set; }
        public string? Category { get; set; }
        public DateTime UsedDate { get; set; }
        public decimal TotalQuantityUsed { get; set; }
        public string? ProductionUnit { get; set; }

        public int WaterRawMaterialPurchaseId { get; set; }
        public DateTime PurchaseDate { get; set; }
        public string? SupplierName { get; set; }

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
    public class WaterDeferredCostSummaryModel
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
        /// <summary>How many filtered lots cannot be reached yet because older
        /// stock stands in front of them. Zero is the reassuring answer.</summary>
        public int BlockedPurchases { get; set; }
        public decimal BlockedCost { get; set; }
    }

    /// <summary>Summary plus rows, fetched in one round trip.</summary>
    public class WaterDeferredCostResponse
    {
        public WaterDeferredCostSummaryModel Summary { get; set; } = new();
        public List<WaterDeferredPurchaseModel> Purchases { get; set; } = new();
    }
}
