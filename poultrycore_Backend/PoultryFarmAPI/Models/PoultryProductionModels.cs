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
    }

    public class PoultryDailyClosingSubmitRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        public decimal ActualCashCounted { get; set; }
        public string? ManagerNotes { get; set; }
        public string? SubmittedBy { get; set; }
    }
}
