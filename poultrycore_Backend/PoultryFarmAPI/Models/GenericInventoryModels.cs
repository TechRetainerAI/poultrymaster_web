using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    // =========================================================================
    // Movement type and status constants. Kept as classes (not enums) because
    // the rest of the codebase passes these as strings via ADO.NET and an
    // enum-to-string conversion at every boundary is friction with no upside.
    // =========================================================================
    public static class GenericStockMovementTypes
    {
        public const string OpeningStock    = "OpeningStock";
        public const string PurchaseIn      = "PurchaseIn";
        public const string SaleOut         = "SaleOut";
        public const string ReturnIn        = "ReturnIn";
        public const string DamageOut       = "DamageOut";
        public const string ExpiredOut      = "ExpiredOut";
        public const string InternalUseOut  = "InternalUseOut";
        public const string AdjustmentIn    = "AdjustmentIn";
        public const string AdjustmentOut   = "AdjustmentOut";
        public const string TransferIn      = "TransferIn";
        public const string TransferOut     = "TransferOut";
    }

    public static class GenericStockAdjustmentStatus
    {
        public const string Draft     = "Draft";
        public const string Submitted = "Submitted";
        public const string Approved  = "Approved";
        public const string Rejected  = "Rejected";
    }

    public static class GenericStockAdjustmentType
    {
        public const string Increase = "Increase";
        public const string Decrease = "Decrease";
    }

    // =========================================================================
    // Product catalog
    // =========================================================================
    public class GenericProductCategoryModel
    {
        [Key]
        public int GenericProductCategoryId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        [Required]
        [StringLength(100)]
        public string Name { get; set; } = string.Empty;

        [StringLength(500)]
        public string? Description { get; set; }

        public bool IsActive { get; set; } = true;
        public bool IsDeleted { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class GenericProductModel
    {
        [Key]
        public int GenericProductId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        public int? GenericProductCategoryId { get; set; }

        [StringLength(100)]
        public string? CategoryName { get; set; }   // join populated by SP

        [Required]
        [StringLength(200)]
        public string ProductName { get; set; } = string.Empty;

        [StringLength(60)]
        public string? SKU { get; set; }

        [StringLength(60)]
        public string? Barcode { get; set; }

        [StringLength(30)]
        public string? UnitOfMeasure { get; set; }

        [Range(0, double.MaxValue)]
        public decimal CostPrice { get; set; }

        [Range(0, double.MaxValue)]
        public decimal SellingPrice { get; set; }

        public decimal? WholesalePrice { get; set; }
        public decimal? RetailPrice { get; set; }

        [Range(0, double.MaxValue)]
        public decimal OpeningStock { get; set; }

        public decimal CurrentStock { get; set; }   // managed by SPs; ignored on insert/update

        [Range(0, double.MaxValue)]
        public decimal MinimumStockAlert { get; set; }

        public bool TrackInventory { get; set; } = true;

        public int? SupplierId { get; set; }

        public bool IsActive { get; set; } = true;
        public bool IsDeleted { get; set; }

        [StringLength(1000)]
        public string? Notes { get; set; }

        // Set by the controller from the auth context. Not validated here.
        public string? CreatedBy { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class GenericProductLowStockRowModel
    {
        public int GenericProductId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public string ProductName { get; set; } = string.Empty;
        public string? SKU { get; set; }
        public string? UnitOfMeasure { get; set; }
        public decimal CurrentStock { get; set; }
        public decimal MinimumStockAlert { get; set; }
        public decimal Shortfall { get; set; }
    }

    // =========================================================================
    // Service catalog
    // =========================================================================
    public class GenericServiceCategoryModel
    {
        [Key]
        public int GenericServiceCategoryId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        [Required]
        [StringLength(100)]
        public string Name { get; set; } = string.Empty;

        [StringLength(500)]
        public string? Description { get; set; }

        public bool IsActive { get; set; } = true;
        public bool IsDeleted { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class GenericServiceModel
    {
        [Key]
        public int GenericServiceId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        public int? GenericServiceCategoryId { get; set; }

        [StringLength(100)]
        public string? CategoryName { get; set; }

        [Required]
        [StringLength(200)]
        public string ServiceName { get; set; } = string.Empty;

        [Range(0, double.MaxValue)]
        public decimal DefaultPrice { get; set; }

        public decimal? EstimatedCost { get; set; }
        public int? DurationMinutes { get; set; }
        public int? AssignedStaffId { get; set; }

        public bool IsActive { get; set; } = true;
        public bool IsDeleted { get; set; }

        [StringLength(1000)]
        public string? Notes { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    // =========================================================================
    // Inventory
    // =========================================================================
    public class GenericStockMovementModel
    {
        [Key]
        public int GenericStockMovementId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        [Required]
        public int GenericProductId { get; set; }

        public string? ProductName { get; set; }   // join in GetByFarm

        public int? InventoryLocationId { get; set; }

        public DateTime MovementDate { get; set; }

        // One of GenericStockMovementTypes
        [Required]
        [StringLength(30)]
        public string MovementType { get; set; } = GenericStockMovementTypes.OpeningStock;

        // Signed: positive = inflow, negative = outflow
        public decimal Quantity { get; set; }

        public decimal? UnitCost { get; set; }
        public decimal? UnitSellingPrice { get; set; }
        public decimal? TotalCostValue { get; set; }

        [StringLength(60)]
        public string? ReferenceType { get; set; }
        public int? ReferenceId { get; set; }

        [StringLength(500)]
        public string? Reason { get; set; }

        public string? CreatedBy { get; set; }
        public string? ApprovedBy { get; set; }
        public DateTime? ApprovedAt { get; set; }

        [StringLength(500)]
        public string? Notes { get; set; }

        public DateTime CreatedAt { get; set; }
    }

    public class GenericStockAdjustmentModel
    {
        [Key]
        public int GenericStockAdjustmentId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        [Required]
        public int GenericProductId { get; set; }

        public string? ProductName { get; set; }

        public int? InventoryLocationId { get; set; }

        public DateTime AdjustmentDate { get; set; }

        // GenericStockAdjustmentType: Increase | Decrease
        [Required]
        [StringLength(10)]
        public string AdjustmentType { get; set; } = GenericStockAdjustmentType.Increase;

        // Always positive magnitude
        [Range(0.0001, double.MaxValue)]
        public decimal Quantity { get; set; }

        [Required]
        [StringLength(500)]
        public string Reason { get; set; } = string.Empty;

        [StringLength(20)]
        public string Status { get; set; } = GenericStockAdjustmentStatus.Draft;

        public string? RequestedBy { get; set; }
        public string? ApprovedBy { get; set; }
        public DateTime? ApprovedAt { get; set; }

        [StringLength(500)]
        public string? RejectionReason { get; set; }

        [StringLength(1000)]
        public string? Notes { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class GenericStockAdjustmentRejectRequest
    {
        [Required]
        [StringLength(500)]
        public string RejectionReason { get; set; } = string.Empty;
    }
}
