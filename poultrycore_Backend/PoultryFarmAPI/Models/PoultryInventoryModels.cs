using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    // Poultry raw materials + inventory (mirrors the Water raw-material models).
    // Additive: new types only; existing poultry models are untouched.

    public class PoultryRawMaterialItemModel
    {
        [Key] public int PoultryRawMaterialItemId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required] [StringLength(150)] public string ItemName { get; set; } = string.Empty;
        [Required] [StringLength(40)] public string Category { get; set; } = "Other";
        [StringLength(30)] public string? UnitOfMeasure { get; set; }          // production-level unit
        [StringLength(30)] public string? PurchaseUnitOfMeasure { get; set; }  // how it's bought
        public decimal MinimumStockAlert { get; set; }
        public decimal CurrentQuantity { get; set; }
        public bool IsActive { get; set; } = true;
        public bool IsLowStock { get; set; }
        [StringLength(500)] public string? Notes { get; set; }
        /// <summary>Which purchase batch gets drawn from first when this item is consumed: FIFO | LIFO | HIFO.</summary>
        [StringLength(10)] public string UsageMethod { get; set; } = "FIFO";

        // ---- cost recognition (migration 261) --------------------------------

        /// <summary>
        /// This item's own choice, or null to follow the farm default for its
        /// category. Null is a real value here -- it is what "use farm default"
        /// means -- which is why writes carry SetCostRecognitionOverride to say
        /// whether the field was meant at all.
        /// </summary>
        [StringLength(40)] public string? CostRecognitionOverride { get; set; }

        /// <summary>
        /// Resolved by the server: the override if there is one, else the farm
        /// default for the category, else EXPENSE_WHEN_PURCHASED. Read-only --
        /// writing it has no effect, because the resolver decides.
        /// </summary>
        public string? EffectiveCostRecognitionMethod { get; set; }

        /// <summary>FarmDefault | ItemOverride. Read-only.</summary>
        public string? CostRecognitionSource { get; set; }

        /// <summary>
        /// Feed | Medication | Unconfigured -- which farm setting this item's
        /// category listens to, if any. Read-only, and what lets the form say
        /// "the farm default for feed is ..." rather than guessing.
        /// </summary>
        public string? CostRecognitionCategoryGroup { get; set; }

        /// <summary>
        /// Whether this write means to set CostRecognitionOverride at all. False
        /// leaves the item's existing choice alone, so editing a name or a
        /// category can never silently clear an override.
        /// </summary>
        public bool SetCostRecognitionOverride { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class PoultryRawMaterialPurchaseModel
    {
        [Key] public int PoultryRawMaterialPurchaseId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required] public int PoultryRawMaterialItemId { get; set; }
        public string? ItemName { get; set; }
        public string? Category { get; set; }
        public string? UnitOfMeasure { get; set; }
        [StringLength(200)] public string? SupplierName { get; set; }
        public int? SupplierId { get; set; }
        public DateTime PurchaseDate { get; set; }
        [Range(0.0001, double.MaxValue)] public decimal Quantity { get; set; }
        [Range(0, double.MaxValue)] public decimal UnitCost { get; set; }
        public decimal TotalCost { get; set; }
        /// <summary>How much of this purchase batch hasn't been consumed yet (drives FIFO/LIFO/HIFO draws).</summary>
        public decimal RemainingQuantity { get; set; }
        // Production-unit conversion (buy in purchase unit, consume in production unit).
        [StringLength(30)] public string? ProductionUnit { get; set; }
        public decimal? ProductionUnitsPerPurchaseUnit { get; set; }
        public decimal? ProductionQuantity { get; set; }   // derived (read-only)
        public decimal? ProductionUnitCost { get; set; }   // derived (read-only)
        [StringLength(30)] public string? PaymentMethod { get; set; }
        /// <summary>Optional cash account this purchase is paid from (posts a cash-out).</summary>
        public int? PoultryCashAccountId { get; set; }
        public decimal AmountPaid { get; set; }
        public decimal Balance { get; set; }               // derived (read-only)
        [StringLength(500)] public string? ReceiptUrl { get; set; }
        [StringLength(500)] public string? Notes { get; set; }
        /// <summary>Set when the posting engine created this lot, not "Record Purchase".</summary>
        public int? SourceFeedProductionBatchId { get; set; }
        public string? FeedProductionBatchNumber { get; set; }
        /// <summary>'Produced' (the feed the batch made), 'Purchased' (an ingredient it bought), or null.</summary>
        public string? FeedProductionRole { get; set; }

        // ---- cost recognition (migrations 261-268) ---------------------------

        /// <summary>
        /// The method SNAPSHOT taken when this lot was created, not today's farm
        /// setting. Changing the farm default must never restate a lot that has
        /// already been expensed. Read-only.
        /// </summary>
        public string? CostRecognitionMethod { get; set; }

        /// <summary>
        /// What this lot owed Profit &amp; Loss when it opened: its whole cost on a
        /// deferred lot, zero on one expensed at purchase. Read-only.
        /// </summary>
        public decimal DeferredTotalCost { get; set; }

        /// <summary>What it still owes. Falls pro rata as the stock is drawn. Read-only.</summary>
        public decimal DeferredRemainingCost { get; set; }

        /// <summary>
        /// Deferred cost per PRODUCTION unit remaining, so it is directly
        /// comparable with ProductionUnitCost beside it. Null on an exhausted
        /// lot -- there is no rate, and zero would be a lie.
        /// </summary>
        public decimal? DeferredUnitCost { get; set; }

        /// <summary>
        /// "Expensed at purchase" | "Deferred - not yet expensed" | "Deferred -
        /// fully expensed". Said in words so no screen has to read meaning into
        /// a zero. Read-only.
        /// </summary>
        public string? CostRecognitionStatus { get; set; }

        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class PoultryRawMaterialUsageModel
    {
        [Key] public int PoultryRawMaterialUsageId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required] public int PoultryRawMaterialItemId { get; set; }
        public string? ItemName { get; set; }
        public string? UnitOfMeasure { get; set; }
        public int? PoultryProductionBatchId { get; set; }
        public DateTime UsedDate { get; set; }
        [Range(0.0001, double.MaxValue)] public decimal QuantityUsed { get; set; }
        public decimal? ExpectedQuantityUsed { get; set; }
        public decimal Variance { get; set; }
        [StringLength(500)] public string? VarianceReason { get; set; }
        public int? UsedByStaffId { get; set; }
        [StringLength(500)] public string? Notes { get; set; }
        /// <summary>Set when a feed production batch consumed this stock.</summary>
        public int? PoultryFeedProductionBatchId { get; set; }
        public string? FeedProductionBatchNumber { get; set; }
        /// <summary>The finished feed that batch produced.</summary>
        public string? FeedProductionFeedName { get; set; }
        /// <summary>The production record this draw belongs to, when it came from one.</summary>
        public int? ProductionRecordId { get; set; }
        /// <summary>Reversed draws are KEPT, not deleted (append-only ledger).</summary>
        public bool IsReversed { get; set; }
        public DateTime? ReversedAt { get; set; }

        // ---- cost recognition (migration 268) --------------------------------

        /// <summary>
        /// What the stock drawn was worth. ALWAYS populated, whichever method the
        /// lots were on -- this is what a farm manager means by "what did that
        /// feed cost me", and what cost-per-bird is built on.
        /// </summary>
        public decimal OperationalCost { get; set; }

        /// <summary>
        /// Only the part that reached Profit &amp; Loss at THIS consumption. Zero on
        /// stock already expensed at purchase, which does not mean the feed was
        /// free -- it means the expense was taken earlier.
        /// </summary>
        public decimal RecognizedCost { get; set; }

        /// <summary>How many purchase lots this single draw crossed.</summary>
        public int CostLayerCount { get; set; }

        /// <summary>
        /// "Expensed at consumption" | "Already expensed at purchase" |
        /// "Reversed" | "No cost layers".
        /// </summary>
        public string? CostRecognitionStatus { get; set; }

        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    public class PoultryPayBalanceRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public decimal Amount { get; set; }
        public string? PaymentMethod { get; set; }
        public DateTime? PaymentDate { get; set; }
        public string? CreatedBy { get; set; }
    }

    // A manual stock adjustment on a raw material / supply. Signed Quantity:
    // positive increases stock, negative decreases it.
    public class PoultryRawMaterialAdjustmentModel
    {
        [Key] public int PoultryRawMaterialAdjustmentId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required] public int PoultryRawMaterialItemId { get; set; }
        public string? ItemName { get; set; }
        public string? Category { get; set; }
        public string? UnitOfMeasure { get; set; }
        public DateTime AdjustedDate { get; set; }
        public decimal Quantity { get; set; }
        public decimal? UnitCost { get; set; }
        [StringLength(30)] public string? MovementType { get; set; }
        [StringLength(500)] public string? Note { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    // POST body for adjusting a raw-material item's stock.
    public class PoultryRawMaterialAdjustRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public decimal Quantity { get; set; }   // signed delta
        public decimal? UnitCost { get; set; }
        public string? MovementType { get; set; }
        public string? Note { get; set; }
        public string? CreatedBy { get; set; }
    }

    // One row of a stock recalculation: what an item's CurrentQuantity was vs the
    // value recomputed from purchases, usage and adjustments.
    public class PoultryRawMaterialRecalcRow
    {
        public int PoultryRawMaterialItemId { get; set; }
        public string? ItemName { get; set; }
        public string? Category { get; set; }
        public string? UnitOfMeasure { get; set; }
        public decimal OldQuantity { get; set; }
        public decimal NewQuantity { get; set; }
        public decimal Delta { get; set; }
    }
}
