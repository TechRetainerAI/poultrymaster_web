using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    // =========================================================================
    // Phase R7: Inventory & Recipes
    // =========================================================================

    public class RestaurantIngredientModel
    {
        [Key] public int IngredientId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required] public string Name { get; set; } = string.Empty;
        public string? Category { get; set; }
        public string Unit { get; set; } = "kg";
        public decimal CostPerUnit { get; set; }
        public decimal CurrentStock { get; set; }
        public decimal ParLevel { get; set; }
        public decimal ReorderPoint { get; set; }
        public int? SupplierId { get; set; }
        public string? SupplierName { get; set; }
        public int? ExpiryDays { get; set; }
        public string? StorageArea { get; set; }
        public bool IsActive { get; set; } = true;
        public string? Notes { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public bool IsLow { get; set; }
    }

    public class RestaurantRecipeModel
    {
        [Key] public int RecipeId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        public int MenuItemId { get; set; }
        public int IngredientId { get; set; }
        public string? IngredientName { get; set; }
        public decimal Quantity { get; set; }
        public string Unit { get; set; } = string.Empty;
        public decimal WastePercent { get; set; }
        public string? Notes { get; set; }
        public decimal CostPerUnit { get; set; }
        public decimal LineCost { get; set; }
    }

    public class RestaurantStockMovementModel
    {
        [Key] public int StockMovementId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        public int IngredientId { get; set; }
        public string MovementType { get; set; } = string.Empty;
        public decimal Quantity { get; set; }
        public decimal? UnitCost { get; set; }
        public string? Reference { get; set; }
        public string? Reason { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    public class RestaurantWasteLogModel
    {
        [Key] public int WasteLogId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        public int? IngredientId { get; set; }
        public int? MenuItemId { get; set; }
        public string IngredientName { get; set; } = string.Empty;
        public decimal Quantity { get; set; }
        public string Unit { get; set; } = string.Empty;
        public decimal CostAmount { get; set; }
        public string Reason { get; set; } = string.Empty;
        public string? Notes { get; set; }
        public string? LoggedBy { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    public class RestaurantStockTakeModel
    {
        [Key] public int StockTakeId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        public DateTime TakeDate { get; set; }
        public string Status { get; set; } = "Draft";
        public string? Notes { get; set; }
        public string? CompletedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? CompletedAt { get; set; }
        public long ItemCount { get; set; }
    }

    public class RestaurantStockTakeItemModel
    {
        [Key] public int StockTakeItemId { get; set; }
        public int IngredientId { get; set; }
        public string? IngredientName { get; set; }
        public string? Category { get; set; }
        public decimal SystemQty { get; set; }
        public decimal ActualQty { get; set; }
        public decimal Variance { get; set; }
        public string? Unit { get; set; }
        public string? Notes { get; set; }
    }

    public class FoodCostModel
    {
        public decimal TotalCost { get; set; }
        public decimal SellingPrice { get; set; }
        public decimal FoodCostPercent { get; set; }
    }

    public class WasteSummaryModel
    {
        public string Reason { get; set; } = string.Empty;
        public decimal TotalQuantity { get; set; }
        public decimal TotalCost { get; set; }
        public long Count { get; set; }
    }

    public class InventoryValueModel
    {
        public int IngredientId { get; set; }
        public string Name { get; set; } = string.Empty;
        public string? Category { get; set; }
        public string? Unit { get; set; }
        public decimal CurrentStock { get; set; }
        public decimal CostPerUnit { get; set; }
        public decimal TotalValue { get; set; }
        public bool IsLow { get; set; }
    }
}
