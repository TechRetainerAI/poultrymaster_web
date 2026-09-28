// Restaurant Internal Use (migration 330). Same shape as PoultryInternalUsageModel;
// a line is a stock item (ingredient) or a menu item (taken out through its recipe).
namespace PoultryFarmAPIWeb.Models
{
    public class RestaurantInternalUseItem
    {
        public int? InternalUsageItemId { get; set; }
        /// <summary>Ingredient | MenuItem</summary>
        public string ItemType { get; set; } = "Ingredient";
        public int? IngredientId { get; set; }
        public int? MenuItemId { get; set; }
        public string? ItemName { get; set; }          // read-side only
        public decimal EntryQuantity { get; set; }
        public string? EntryUnit { get; set; }
        public decimal? QuantityPerStaff { get; set; }
        public decimal EntryUnitCost { get; set; }
        public decimal? TotalCost { get; set; }
        public string? ItemNotes { get; set; }
    }

    public class RestaurantInternalUseRecord
    {
        public int InternalUsageId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public DateTime UsageDate { get; set; }
        public string? ReferenceNo { get; set; }
        public string Category { get; set; } = string.Empty;
        public string? Reason { get; set; }
        public string? RecipientName { get; set; }
        public int? ResponsibleStaffId { get; set; }
        public int? StaffCount { get; set; }
        public string Status { get; set; } = "Draft";
        public decimal TotalCostValue { get; set; }
        /// <summary>What the current posting moved into Profit &amp; Loss (deferred stock only).</summary>
        public decimal PlCost { get; set; }
        public string? Notes { get; set; }
        public string? PostedBy { get; set; }
        public DateTime? PostedAt { get; set; }
        public string? ReversedBy { get; set; }
        public DateTime? ReversedAt { get; set; }
        public string? ReversalReason { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public List<RestaurantInternalUseItem> Items { get; set; } = new();
    }

    public class RestaurantInternalUseSaveRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public DateTime UsageDate { get; set; } = DateTime.UtcNow;
        public string Category { get; set; } = string.Empty;
        public string? Reason { get; set; }
        public string? RecipientName { get; set; }
        public int? ResponsibleStaffId { get; set; }
        public int? StaffCount { get; set; }
        public string? Notes { get; set; }
        public List<RestaurantInternalUseItem> Items { get; set; } = new();
    }

    public class RestaurantInternalUseReverseRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public string? Reason { get; set; }
    }

    /// <summary>One pickable line: a stock item, or a menu item that has a recipe.</summary>
    public class RestaurantInternalUseOption
    {
        public string ItemType { get; set; } = "Ingredient";
        public int ItemId { get; set; }
        public string Name { get; set; } = string.Empty;
        public string? Category { get; set; }
        public string? Unit { get; set; }
        /// <summary>Stock on hand; for a menu item, whole portions the recipe can still make.</summary>
        public decimal OnHand { get; set; }
        public decimal SuggestedUnitCost { get; set; }
        public string? CostMode { get; set; }
    }
}
