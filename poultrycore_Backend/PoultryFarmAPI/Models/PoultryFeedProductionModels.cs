using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    // Feed Production module — feed formulas, production batches, ingredient
    // breakdown lines and additional costs. Additive; a dedicated module that
    // reuses the poultry raw-material inventory, costing, cash and payable infra.

    // ---------------------------------------------------------------- Formulas
    public class PoultryFeedFormulaLineModel
    {
        public int PoultryFeedFormulaLineId { get; set; }
        public int PoultryFeedFormulaId { get; set; }
        public int IngredientItemId { get; set; }
        public string? IngredientName { get; set; }
        public string? IngredientUnit { get; set; }
        public decimal AvailableStock { get; set; }
        public decimal LatestUnitCost { get; set; }
        [StringLength(20)] public string QuantityMode { get; set; } = "Percentage";
        public decimal? Percentage { get; set; }
        public decimal? FixedQuantity { get; set; }
        [StringLength(30)] public string? UnitOfMeasure { get; set; }
        public int SortOrder { get; set; }
        [StringLength(300)] public string? Notes { get; set; }
    }

    public class PoultryFeedFormulaModel
    {
        public int PoultryFeedFormulaId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required] [StringLength(150)] public string FormulaName { get; set; } = string.Empty;
        public int FinishedFeedItemId { get; set; }
        public string? FinishedFeedItemName { get; set; }
        public string? FinishedFeedUnit { get; set; }
        [StringLength(30)] public string? DefaultOutputUnit { get; set; }
        [StringLength(500)] public string? Notes { get; set; }
        public bool IsActive { get; set; } = true;
        public string? CreatedBy { get; set; }
        public DateTime? CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
        // List-view aggregates (GetAll only)
        public int LineCount { get; set; }
        public decimal PercentageTotal { get; set; }
        public List<PoultryFeedFormulaLineModel> Lines { get; set; } = new();
    }

    public class PoultryFeedFormulaLineInput
    {
        public int IngredientItemId { get; set; }
        public string QuantityMode { get; set; } = "Percentage";
        public decimal? Percentage { get; set; }
        public decimal? FixedQuantity { get; set; }
        public string? UnitOfMeasure { get; set; }
        public int SortOrder { get; set; }
        public string? Notes { get; set; }
    }

    public class PoultryFeedFormulaUpsertRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        public int? PoultryFeedFormulaId { get; set; }
        [Required] [StringLength(150)] public string FormulaName { get; set; } = string.Empty;
        public int FinishedFeedItemId { get; set; }
        [StringLength(30)] public string? DefaultOutputUnit { get; set; }
        [StringLength(500)] public string? Notes { get; set; }
        public bool IsActive { get; set; } = true;
        public string? UserId { get; set; }
        public List<PoultryFeedFormulaLineInput> Lines { get; set; } = new();
    }

    // -------------------------------------------------------- Production batch
    public class PoultryFeedProductionBatchLineModel
    {
        public int PoultryFeedProductionBatchLineId { get; set; }
        public int PoultryFeedProductionBatchId { get; set; }
        public int IngredientItemId { get; set; }
        public string? IngredientName { get; set; }
        public decimal AvailableStock { get; set; }
        [StringLength(30)] public string SourceType { get; set; } = "FromInventory";
        public decimal QuantityUsed { get; set; }
        [StringLength(30)] public string? UnitOfMeasure { get; set; }
        public decimal? InventoryQuantityUsed { get; set; }
        public decimal? PurchasedQuantityUsed { get; set; }
        public decimal? InventoryUnitCost { get; set; }
        public decimal? PurchasedUnitCost { get; set; }
        public decimal UnitCost { get; set; }
        public decimal TotalCost { get; set; }
        public int? SupplierId { get; set; }
        [StringLength(200)] public string? SupplierName { get; set; }
        [StringLength(100)] public string? PurchaseReference { get; set; }
        [StringLength(20)] public string? PaymentStatus { get; set; }
        public decimal? AmountPaid { get; set; }
        public int? PaidFromCashAccountId { get; set; }
        [StringLength(30)] public string? PaymentMethod { get; set; }
        public int SortOrder { get; set; }
        [StringLength(300)] public string? Notes { get; set; }
    }

    public class PoultryFeedProductionAdditionalCostModel
    {
        public int PoultryFeedProductionAdditionalCostId { get; set; }
        public int PoultryFeedProductionBatchId { get; set; }
        [StringLength(40)] public string CostType { get; set; } = "Other";
        public decimal Amount { get; set; }
        [StringLength(20)] public string? PaymentStatus { get; set; }
        public decimal? AmountPaid { get; set; }
        public int? PaidFromCashAccountId { get; set; }
        [StringLength(30)] public string? PaymentMethod { get; set; }
        public int? SupplierId { get; set; }
        [StringLength(200)] public string? PayeeName { get; set; }
        public int SortOrder { get; set; }
        [StringLength(300)] public string? Notes { get; set; }
    }

    public class PoultryFeedProductionBatchModel
    {
        public int PoultryFeedProductionBatchId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        [StringLength(60)] public string? BatchNumber { get; set; }
        public DateTime? ProductionDate { get; set; }
        public int FinishedFeedItemId { get; set; }
        public string? FinishedFeedItemName { get; set; }
        public string? FinishedFeedUnit { get; set; }
        public int? FormulaId { get; set; }
        public string? FormulaName { get; set; }
        public decimal QuantityProduced { get; set; }
        [StringLength(30)] public string? OutputUnit { get; set; }
        public decimal TotalIngredientCost { get; set; }
        public decimal TotalAdditionalCost { get; set; }
        public decimal TotalProductionCost { get; set; }
        public decimal CostPerOutputUnit { get; set; }
        [StringLength(20)] public string Status { get; set; } = "Draft";
        [StringLength(500)] public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime? CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public string? PostedBy { get; set; }
        public DateTime? PostedAt { get; set; }
        public string? ReversedBy { get; set; }
        public DateTime? ReversedAt { get; set; }
        [StringLength(500)] public string? ReversalReason { get; set; }
        public List<PoultryFeedProductionBatchLineModel> Lines { get; set; } = new();
        public List<PoultryFeedProductionAdditionalCostModel> AdditionalCosts { get; set; } = new();
    }

    public class PoultryFeedProductionBatchLineInput
    {
        public int IngredientItemId { get; set; }
        public string SourceType { get; set; } = "FromInventory";
        public decimal QuantityUsed { get; set; }
        public string? UnitOfMeasure { get; set; }
        public decimal? InventoryQuantityUsed { get; set; }
        public decimal? PurchasedQuantityUsed { get; set; }
        public decimal? InventoryUnitCost { get; set; }
        public decimal? PurchasedUnitCost { get; set; }
        public int? SupplierId { get; set; }
        public string? SupplierName { get; set; }
        public string? PurchaseReference { get; set; }
        public string? PaymentStatus { get; set; }
        public decimal? AmountPaid { get; set; }
        public int? PaidFromCashAccountId { get; set; }
        public string? PaymentMethod { get; set; }
        public int SortOrder { get; set; }
        public string? Notes { get; set; }
    }

    public class PoultryFeedProductionAdditionalCostInput
    {
        public string CostType { get; set; } = "Other";
        public decimal Amount { get; set; }
        public string? PaymentStatus { get; set; }
        public decimal? AmountPaid { get; set; }
        public int? PaidFromCashAccountId { get; set; }
        public string? PaymentMethod { get; set; }
        public int? SupplierId { get; set; }
        public string? PayeeName { get; set; }
        public int SortOrder { get; set; }
        public string? Notes { get; set; }
    }

    public class PoultryFeedProductionBatchSaveRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        public int? PoultryFeedProductionBatchId { get; set; }
        [StringLength(60)] public string? BatchNumber { get; set; }
        public DateTime? ProductionDate { get; set; }
        public int FinishedFeedItemId { get; set; }
        public int? FormulaId { get; set; }
        public decimal QuantityProduced { get; set; }
        [StringLength(30)] public string? OutputUnit { get; set; }
        [StringLength(500)] public string? Notes { get; set; }
        public string? UserId { get; set; }
        public List<PoultryFeedProductionBatchLineInput> Lines { get; set; } = new();
        public List<PoultryFeedProductionAdditionalCostInput> AdditionalCosts { get; set; } = new();
    }

    public class PoultryFeedIngredientUsageRow
    {
        public int IngredientItemId { get; set; }
        public string? IngredientName { get; set; }
        public string? UnitOfMeasure { get; set; }
        public decimal TotalQuantityUsed { get; set; }
        public decimal TotalCost { get; set; }
        public decimal FromInventoryQuantity { get; set; }
        public decimal PurchasedQuantity { get; set; }
        public int BatchCount { get; set; }
    }

    public class PoultryFeedTraceabilityRow
    {
        public int PoultryFeedProductionBatchId { get; set; }
        public string? BatchNumber { get; set; }
        public int FinishedFeedItemId { get; set; }
        public string? FinishedFeedName { get; set; }
        public int PoultryRawMaterialUsageId { get; set; }
        public int? ProductionRecordId { get; set; }
        public decimal QuantityUsed { get; set; }
        public decimal QuantityDrawn { get; set; }
        public decimal UnitCostAtDraw { get; set; }
        public DateTime? UsedDate { get; set; }
    }

    public class PoultryFeedProductionActionRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        public string? UserId { get; set; }
        [StringLength(500)] public string? ReversalReason { get; set; }
    }

    // Feed-related raw-material item with latest cost — powers the batch form's
    // finished-feed + ingredient dropdowns and cost previews.
    public class PoultryFeedProductionBatchItemModel
    {
        public int PoultryRawMaterialItemId { get; set; }
        public string ItemName { get; set; } = string.Empty;
        public string Category { get; set; } = string.Empty;
        public string? UnitOfMeasure { get; set; }
        public decimal CurrentQuantity { get; set; }
        public bool IsActive { get; set; }
        public decimal LatestUnitCost { get; set; }
    }
}
