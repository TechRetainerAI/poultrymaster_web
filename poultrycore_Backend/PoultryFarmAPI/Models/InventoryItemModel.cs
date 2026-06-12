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
        public int? SupplierId { get; set; }
        public bool IsActive { get; set; }

        // Added by migration 019 — store the full set of fields the UI form collects.
        public decimal? Cost { get; set; }
        public string? SupplierName { get; set; }
        public System.DateTime? PurchaseDate { get; set; }
        public string? Notes { get; set; }
        public string? Location { get; set; }
        public System.DateTime? ExpiryDate { get; set; }
    }
}