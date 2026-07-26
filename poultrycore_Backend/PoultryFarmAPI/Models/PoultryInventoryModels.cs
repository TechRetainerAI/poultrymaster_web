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
}
