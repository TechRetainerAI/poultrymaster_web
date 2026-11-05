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
        public string? CustomerName { get; set; }
        public string? Destination { get; set; }
        public string Status { get; set; } = "Loaded";
        public string? Notes { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? ReconciledAt { get; set; }
        public DateTime? DeliveredAt { get; set; }
        public string? DeliveredBy { get; set; }
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
        public string? CustomerName { get; set; }
        public string? Destination { get; set; }
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
    }

    public class GenericDriverReportRow
    {
        public string DriverName { get; set; } = string.Empty;
        public long TotalDeliveries { get; set; }
        public decimal TotalLoaded { get; set; }
        public decimal TotalSold { get; set; }
        public decimal TotalReturned { get; set; }
        public decimal TotalDamaged { get; set; }
        public decimal TotalShort { get; set; }
        public decimal TotalSales { get; set; }
        public decimal TotalCashCollected { get; set; }
        public decimal TotalCreditSales { get; set; }
        public decimal TotalExpenses { get; set; }
        public decimal DeliveryRate { get; set; }
        public long LoadedDeliveries { get; set; }
        public long InTransitDeliveries { get; set; }
        public long DeliveredDeliveries { get; set; }
        public long ReconciledDeliveries { get; set; }
        public long CancelledDeliveries { get; set; }
    }

    public class GenericProductDeliveryRow
    {
        public string ProductName { get; set; } = string.Empty;
        public long TotalDeliveries { get; set; }
        public decimal TotalLoaded { get; set; }
        public decimal TotalSold { get; set; }
        public decimal TotalReturned { get; set; }
        public decimal TotalDamaged { get; set; }
        public decimal TotalShort { get; set; }
        public decimal TotalSales { get; set; }
        public decimal SellThroughRate { get; set; }
    }

    public class GenericRouteReportRow
    {
        public string Route { get; set; } = string.Empty;
        public long TotalDeliveries { get; set; }
        public decimal TotalLoaded { get; set; }
        public decimal TotalSold { get; set; }
        public decimal TotalSales { get; set; }
        public decimal TotalExpenses { get; set; }
        public decimal NetRevenue { get; set; }
    }

    // =========================================================================
    // Drivers
    // =========================================================================
    public class GenericDriverModel
    {
        public int GenericDriverId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public string DriverName { get; set; } = string.Empty;
        public string? PhoneNumber { get; set; }
        public string? LicenseNumber { get; set; }
        public string? VehicleName { get; set; }
        public string? VehicleRegistration { get; set; }
        public bool IsActive { get; set; } = true;
        public string? Notes { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    public class GenericDriverInput
    {
        public string FarmId { get; set; } = string.Empty;
        public string DriverName { get; set; } = string.Empty;
        public string? PhoneNumber { get; set; }
        public string? LicenseNumber { get; set; }
        public string? VehicleName { get; set; }
        public string? VehicleRegistration { get; set; }
        public bool IsActive { get; set; } = true;
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
    }

    // =========================================================================
    // Routes
    // =========================================================================
    public class GenericRouteModel
    {
        public int GenericRouteId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public string RouteName { get; set; } = string.Empty;
        public string? Description { get; set; }
        public string? StartPoint { get; set; }
        public string? EndPoint { get; set; }
        public string? EstimatedTime { get; set; }
        public bool IsActive { get; set; } = true;
        public string? Notes { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    public class GenericRouteInput
    {
        public string FarmId { get; set; } = string.Empty;
        public string RouteName { get; set; } = string.Empty;
        public string? Description { get; set; }
        public string? StartPoint { get; set; }
        public string? EndPoint { get; set; }
        public string? EstimatedTime { get; set; }
        public bool IsActive { get; set; } = true;
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
