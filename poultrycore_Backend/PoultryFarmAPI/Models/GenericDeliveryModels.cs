namespace PoultryFarmAPIWeb.Models
{
    public class GenericDeliveryModel
    {
        public int GenericDeliveryId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public DateTime DeliveryDate { get; set; }
        public string? DriverName { get; set; }
        public string? VehicleName { get; set; }
        public string? Route { get; set; }
        public int GenericProductId { get; set; }
        public string? ProductName { get; set; }
        public decimal QuantityLoaded { get; set; }
        public string? Unit { get; set; }
        public decimal UnitPrice { get; set; }
        public decimal QuantitySold { get; set; }
        public decimal QuantityReturned { get; set; }
        public decimal QuantityDamaged { get; set; }
        public decimal QuantityShort { get; set; }
        public decimal CashCollected { get; set; }
        public decimal CreditSales { get; set; }
        public decimal DeliveryExpenses { get; set; }
        public decimal TotalSales { get; set; }
        public string Status { get; set; } = "Loaded";
        public string? Notes { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? ReconciledAt { get; set; }
    }

    public class GenericDeliveryLoadRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public DateTime? DeliveryDate { get; set; }
        public string? DriverName { get; set; }
        public string? VehicleName { get; set; }
        public string? Route { get; set; }
        public int GenericProductId { get; set; }
        public decimal QuantityLoaded { get; set; }
        public string? Unit { get; set; }
        public decimal UnitPrice { get; set; }
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
    }

    public class GenericDeliveryReconcileRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public decimal QuantitySold { get; set; }
        public decimal QuantityReturned { get; set; }
        public decimal QuantityDamaged { get; set; }
        public decimal QuantityShort { get; set; }
        public decimal CashCollected { get; set; }
        public decimal CreditSales { get; set; }
        public decimal DeliveryExpenses { get; set; }
        public string? ReconciledBy { get; set; }
    }
}
