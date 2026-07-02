using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    // Doc 9: poultry egg delivery. Additive.
    public class PoultryDeliveryModel
    {
        [Key] public int PoultryDeliveryId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        public DateTime DeliveryDate { get; set; }
        public string? DriverName { get; set; }
        public string? VehicleName { get; set; }
        public string? Route { get; set; }
        public int PoultryProductId { get; set; }
        public string? ProductName { get; set; }
        public decimal QuantityLoaded { get; set; }
        public string? Unit { get; set; }
        public decimal UnitPrice { get; set; }
        public decimal QuantitySold { get; set; }
        public decimal QuantityReturned { get; set; }
        public decimal QuantityBroken { get; set; }
        public decimal QuantityShort { get; set; }
        public decimal CashCollected { get; set; }
        public decimal CreditSales { get; set; }
        public decimal DeliveryExpenses { get; set; }
        public decimal TotalSales { get; set; }
        public decimal CashVariance { get; set; }
        public string Status { get; set; } = "Loaded";
        public string? Notes { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? ReconciledAt { get; set; }
    }

    public class PoultryDeliveryLoadRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public DateTime? DeliveryDate { get; set; }
        public string? DriverName { get; set; }
        public string? VehicleName { get; set; }
        public string? Route { get; set; }
        public int PoultryProductId { get; set; }
        public decimal QuantityLoaded { get; set; }
        public string? Unit { get; set; }
        public decimal UnitPrice { get; set; }
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
    }

    public class PoultryDeliveryReconcileRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public decimal QuantitySold { get; set; }
        public decimal QuantityReturned { get; set; }
        public decimal QuantityBroken { get; set; }
        public decimal QuantityShort { get; set; }
        public decimal CashCollected { get; set; }
        public decimal CreditSales { get; set; }
        public decimal DeliveryExpenses { get; set; }
        public string? PaymentMethod { get; set; }
        public string? ReconciledBy { get; set; }
    }
}
