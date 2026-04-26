namespace PoultryFarmAPIWeb.Models
{
    public class InventoryItemModel
    {
        public string FarmId { get; set; }
        public string UserId { get; set; }
        public int ItemId { get; set; }
        public string ItemName { get; set; } = string.Empty;
        public string Category { get; set; } = string.Empty;
        public decimal QuantityInStock { get; set; }
        public string UnitOfMeasure { get; set; }
        public decimal? ReorderLevel { get; set; }
        public bool IsActive { get; set; }
    }
}