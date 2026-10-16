using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    // Poultry products, stock, recipes, batches, losses, daily closing (slices 2-6).
    // Additive; mirrors the Water production models.

    public class PoultryProductModel
    {
        [Key] public int PoultryProductId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required] [StringLength(150)] public string Name { get; set; } = string.Empty;
        [StringLength(60)] public string? Sku { get; set; }
        [StringLength(30)] public string? Unit { get; set; }
        public decimal UnitPrice { get; set; }
        [StringLength(30)] public string ProductType { get; set; } = "FinishedGood";
        public bool IsActive { get; set; } = true;
        [StringLength(500)] public string? Notes { get; set; }
        public bool IsRawEggProduct { get; set; }
        public bool RequiresRecipeSetup { get; set; } = true;
        public bool IsBirdProduct { get; set; }
        [StringLength(60)] public string? Size { get; set; }
        public decimal StockOnHand { get; set; }
        public DateTime CreatedDate { get; set; }
        public DateTime? UpdatedDate { get; set; }
    }

    public class PoultryStockTransactionModel
    {
        [Key] public int PoultryStockTransactionId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required] public int PoultryProductId { get; set; }
        public string? ProductName { get; set; }
        [Required] [StringLength(20)] public string TxnType { get; set; } = "Adjust";
        public decimal Quantity { get; set; }
        public decimal? UnitCost { get; set; }
        public int? RelatedId { get; set; }
        [StringLength(500)] public string? Note { get; set; }
        public DateTime CreatedDate { get; set; }
        public string? CreatedBy { get; set; }

        // 373: provenance of manual movements (and the byproducts they made).
        public int? BatchId { get; set; }
        public string? BatchCode { get; set; }
        public int? FlockId { get; set; }
        public string? FlockName { get; set; }
        public DateTime? EffectiveDate { get; set; }
        public string? Reason { get; set; }
        public int? ManualMovementId { get; set; }
        public bool ManualReversal { get; set; }
    }

    /// <summary>
    /// 373: one manual stock movement (Stock page). Exactly one of
    /// PoultryProductId / RawMaterialItemId. Quantity is POSITIVE; the movement
    /// type gives the direction. Batch / flock are checked by the database.
    /// </summary>
    public class PoultryManualMovementRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        public int? PoultryProductId { get; set; }
        public int? RawMaterialItemId { get; set; }
        [Required] public string MovementType { get; set; } = "Increase";
        public decimal Quantity { get; set; }
        public decimal? UnitCost { get; set; }
        public int? BatchId { get; set; }
        public int? FlockId { get; set; }
        public DateTime? EffectiveDate { get; set; }
        [Required] public string Reason { get; set; } = string.Empty;
        /// <summary>Historical Mortality of birds only: Keep / Disposed.</summary>
        public string? Disposition { get; set; }
        [StringLength(500)] public string? Note { get; set; }
        /// <summary>Same key = same movement (a double click posts once).</summary>
        [StringLength(100)] public string? RequestKey { get; set; }
        public string? CreatedBy { get; set; }
    }

    /// <summary>374: whether Broken Eggs / Dead Birds are offered in Add Sale.</summary>
    public class PoultryByproductSettings
    {
        public string FarmId { get; set; } = string.Empty;
        public bool? BrokenEggsInSales { get; set; }
        public bool? DeadBirdsInSales { get; set; }
        public DateTime? CutoverAt { get; set; }
        public string? UpdatedBy { get; set; }
    }

    /// <summary>
    /// Broken Eggs / Dead Birds tracker: stock on hand now, the period by flock
    /// (pooled entries on a row with no flock) and every movement in the period.
    /// Built on the same functions as the Byproduct Inventory report (375).
    /// </summary>
    public class PoultryByproductTrackerResponse
    {
        public string Role { get; set; } = string.Empty;
        public decimal OnHand { get; set; }
        public List<PoultryByproductTrackerFlockRow> Flocks { get; set; } = new();
        public List<PoultryByproductTrackerMovement> Movements { get; set; } = new();
    }

    public class PoultryByproductTrackerFlockRow
    {
        public int? FlockId { get; set; }
        public string? FlockName { get; set; }
        public string? BatchCode { get; set; }
        public decimal Opening { get; set; }
        public decimal Generated { get; set; }
        public decimal Sold { get; set; }
        public decimal Disposed { get; set; }
        public decimal InternalUse { get; set; }
        public decimal ManualIn { get; set; }
        public decimal ManualOut { get; set; }
        public decimal Reversals { get; set; }
        public decimal Closing { get; set; }
        public decimal Revenue { get; set; }
    }

    public class PoultryByproductTrackerMovement
    {
        public int TxnId { get; set; }
        public DateTime Date { get; set; }
        public string Category { get; set; } = string.Empty;
        public string TxnType { get; set; } = string.Empty;
        public decimal Quantity { get; set; }
        public int? FlockId { get; set; }
        public string? FlockName { get; set; }
        public string? BatchCode { get; set; }
        public int? SaleId { get; set; }
        public decimal Revenue { get; set; }
        public int? ManualMovementId { get; set; }
        public string? MovementNo { get; set; }
        public string? Note { get; set; }
    }

    public class PoultryManualMovementReverseRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required] public string Reason { get; set; } = string.Empty;
        public string? ReversedBy { get; set; }
    }

    public class PoultryManualMovementModel
    {
        public int MovementId { get; set; }
        public string MovementNo { get; set; } = string.Empty;
        public string ItemKind { get; set; } = string.Empty;
        public int? PoultryProductId { get; set; }
        public int? RawMaterialItemId { get; set; }
        public string ItemName { get; set; } = string.Empty;
        public string MovementType { get; set; } = string.Empty;
        public decimal Quantity { get; set; }
        public decimal? UnitCost { get; set; }
        public int? BatchId { get; set; }
        public string? BatchCode { get; set; }
        public int? FlockId { get; set; }
        public string? FlockName { get; set; }
        public DateTime EffectiveDate { get; set; }
        public string Reason { get; set; } = string.Empty;
        public string? Disposition { get; set; }
        public bool ConvertedToBroken { get; set; }
        public string? Note { get; set; }
        public decimal? ItemBefore { get; set; }
        public decimal? ItemAfter { get; set; }
        public int? BirdAdjustmentId { get; set; }
        public int? RawAdjustmentId { get; set; }
        public string Status { get; set; } = "Posted";
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? ReversedAt { get; set; }
        public string? ReversedBy { get; set; }
        public string? ReversalReason { get; set; }
    }

    /// <summary>
    /// 359: a bird adjustment. FlockId set = that flock's birds (its latest
    /// production record opens with the corrected count); FlockId null = the
    /// batch's birds not yet placed in any flock. Quantity is SIGNED.
    /// </summary>
    public class PoultryBirdAdjustmentRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required] public int BatchId { get; set; }
        public int? FlockId { get; set; }
        public string MovementType { get; set; } = "Adjustment";
        public int Quantity { get; set; }
        [StringLength(500)] public string? Note { get; set; }
        public string? CreatedBy { get; set; }
    }

    public class PoultryBirdAdjustmentModel
    {
        public int BirdAdjustmentId { get; set; }
        public DateTime AdjustmentDate { get; set; }
        public int BatchId { get; set; }
        public string? BatchCode { get; set; }
        public int? FlockId { get; set; }
        public string? FlockName { get; set; }
        public string MovementType { get; set; } = string.Empty;
        public int Quantity { get; set; }
        public int BirdsBefore { get; set; }
        public int BirdsAfter { get; set; }
        public int? ProductionRecordId { get; set; }
        public string? Note { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    /// <summary>One batch, and one of its flocks if FlockId is set, as the adjust form offers them.</summary>
    public class PoultryBirdAdjustmentOption
    {
        public int BatchId { get; set; }
        public string BatchCode { get; set; } = string.Empty;
        public string BatchName { get; set; } = string.Empty;
        public int BatchBirds { get; set; }
        /// <summary>Birds of the batch not placed in any flock.</summary>
        public int UnplacedBirds { get; set; }
        public int? FlockId { get; set; }
        public string? FlockName { get; set; }
        /// <summary>The flock's birds now (fnflock_birdposition.currentlivebirds).</summary>
        public int? LiveBirds { get; set; }
        public DateTime? LastCountDate { get; set; }
        public bool HasProductionRecord { get; set; }
        public bool IsClosed { get; set; }
    }

    public class PoultryProductionRecipeItemModel
    {
        public int PoultryProductionRecipeItemId { get; set; }
        public int PoultryProductionRecipeId { get; set; }
        public int PoultryRawMaterialItemId { get; set; }
        public string? ItemName { get; set; }
        public string? UnitOfMeasure { get; set; }
        public decimal AvailableStock { get; set; }
        public decimal LatestUnitCost { get; set; }
        public decimal QuantityPerOutputUnit { get; set; }
        public decimal WasteAllowancePercent { get; set; }
        public bool IsOptional { get; set; }
        public int DisplayOrder { get; set; }
        [StringLength(300)] public string? Notes { get; set; }
    }

    public class PoultryProductionRecipeModel
    {
        public int PoultryProductionRecipeId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        public int PoultryProductId { get; set; }
        [StringLength(150)] public string? RecipeName { get; set; }
        public bool IsActive { get; set; } = true;
        [StringLength(500)] public string? Notes { get; set; }
        public List<PoultryProductionRecipeItemModel> Items { get; set; } = new();
    }

    public class PoultryProductionRecipeUpsertRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        [StringLength(150)] public string? RecipeName { get; set; }
        [StringLength(500)] public string? Notes { get; set; }
        public string? UpdatedBy { get; set; }
        public List<PoultryProductionRecipeItemInput> Items { get; set; } = new();
    }

    public class PoultryProductionRecipeItemInput
    {
        public int PoultryRawMaterialItemId { get; set; }
        public decimal QuantityPerOutputUnit { get; set; }
        public decimal WasteAllowancePercent { get; set; }
        public bool IsOptional { get; set; }
        public int DisplayOrder { get; set; }
        public string? Notes { get; set; }
    }

    public class PoultryProductionMaterialUsageInput
    {
        public int PoultryRawMaterialItemId { get; set; }
        public decimal QuantityUsed { get; set; }
        public decimal? ExpectedQuantityUsed { get; set; }
        public decimal? UnitCost { get; set; }
    }

    public class PoultryProductionBatchModel
    {
        [Key] public int PoultryProductionBatchId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required] [StringLength(60)] public string BatchNumber { get; set; } = string.Empty;
        public DateTime ProductionDate { get; set; }
        [Required] public int PoultryProductId { get; set; }
        public string? ProductName { get; set; }
        public decimal QuantityProduced { get; set; }
        [StringLength(30)] public string? Unit { get; set; }
        public decimal DamagedQuantity { get; set; }
        public decimal LaborCost { get; set; }
        public decimal OtherCost { get; set; }
        public decimal MaterialsCost { get; set; }
        public decimal TotalCost { get; set; }
        public decimal CostPerUnit { get; set; }
        [StringLength(20)] public string Status { get; set; } = "Draft";
        [StringLength(500)] public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
        public string? ApprovedBy { get; set; }
        public DateTime? ApprovedAt { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public List<PoultryProductionMaterialUsageInput> MaterialsUsed { get; set; } = new();
    }

    public class PoultryProductionLossModel
    {
        [Key] public int PoultryProductionLossId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        [StringLength(40)] public string SourceType { get; set; } = "ProductionBatch";
        public int? SourceId { get; set; }
        public DateTime LossDate { get; set; }
        public int? PoultryProductId { get; set; }
        public string? ProductName { get; set; }
        public decimal QuantityLost { get; set; }
        public decimal? EstimatedValue { get; set; }
        [StringLength(500)] public string? Reason { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    public class PoultryLossRecordModel
    {
        [Key] public int PoultryLossRecordId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        public DateTime LossDate { get; set; }
        [Required] [StringLength(40)] public string LossType { get; set; } = "Other";
        public int? PoultryProductId { get; set; }
        public string? ProductName { get; set; }
        public decimal? Quantity { get; set; }
        public decimal? EstimatedValue { get; set; }
        public int? ResponsibleStaffId { get; set; }
        [StringLength(500)] public string? Reason { get; set; }
        [StringLength(20)] public string Status { get; set; } = "Pending";
        public string? ApprovedBy { get; set; }
        public DateTime? ApprovedAt { get; set; }
        [StringLength(500)] public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class PoultryDailyClosingModel
    {
        [Key] public int PoultryDailyClosingId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        public DateTime ClosingDate { get; set; }
        public decimal QuantityProduced { get; set; }
        public decimal QuantityDamaged { get; set; }
        public decimal TotalProductionCost { get; set; }
        public decimal ClosingStock { get; set; }
        public decimal CashAtHand { get; set; }
        public decimal ActualCashCounted { get; set; }
        public decimal CashDifference { get; set; }
        [StringLength(2000)] public string? ManagerNotes { get; set; }
        [StringLength(20)] public string Status { get; set; } = "Draft";
        [StringLength(500)] public string? RejectionReason { get; set; }
        public string? CreatedBy { get; set; }
        public string? SubmittedBy { get; set; }
        public DateTime? SubmittedAt { get; set; }
        public string? ApprovedBy { get; set; }
        public DateTime? ApprovedAt { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
        // Enriched live figures (migration 148) — water-parity closing detail.
        public decimal EggsSold { get; set; }
        public decimal EggsReturned { get; set; }
        public decimal Mortality { get; set; }
        public decimal FeedUsedQty { get; set; }
        public decimal MedUsedQty { get; set; }
        public decimal TotalIncome { get; set; }
        public decimal TotalExpenses { get; set; }
        public decimal CreditSales { get; set; }
        public decimal CustomerCollections { get; set; }
        public decimal CashCollected { get; set; }
        public decimal MoMoCollected { get; set; }
        public decimal BankCollected { get; set; }
        public decimal CashBalance { get; set; }
        public decimal MoMoBalance { get; set; }
        public decimal BankBalance { get; set; }
    }

    public class PoultryDailyClosingSubmitRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        public decimal ActualCashCounted { get; set; }
        public string? ManagerNotes { get; set; }
        public string? SubmittedBy { get; set; }
    }

    // Finished-product stock reconciliation row (shared by Poultry + Water).
    // Finished stock is derived from the transaction ledger; this shows the
    // total in vs out that make up the current stock.
    public class ProductReconcileRow
    {
        public int ProductId { get; set; }
        public string? Name { get; set; }
        public decimal StockIn { get; set; }
        public decimal StockOut { get; set; }
        public decimal CurrentStock { get; set; }
    }

    // "Set to actual count" — corrects a finished product's stock to a physical
    // count by writing an Adjust transaction for (target - current).
    public class ProductSetStockRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public decimal TargetQuantity { get; set; }
        public string? Note { get; set; }
        public string? CreatedBy { get; set; }
    }
}
