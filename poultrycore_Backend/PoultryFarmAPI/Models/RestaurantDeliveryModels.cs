using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    // =========================================================================
    // Phase R6: Delivery Management
    // =========================================================================

    public class RestaurantDriverModel
    {
        [Key] public int DriverId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required] public string FirstName { get; set; } = string.Empty;
        [Required] public string LastName { get; set; } = string.Empty;
        [Required] public string Phone { get; set; } = string.Empty;
        public string? Email { get; set; }
        public string VehicleType { get; set; } = "Motorcycle";
        public string? VehiclePlate { get; set; }
        public string? LicenseNumber { get; set; }
        public string Status { get; set; } = "OffDuty";
        public decimal? CurrentLatitude { get; set; }
        public decimal? CurrentLongitude { get; set; }
        public DateTime? LastLocationUpdate { get; set; }
        public bool IsActive { get; set; } = true;
        public string? Notes { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public long ActiveDeliveries { get; set; }
        public long TotalDeliveries { get; set; }
        public double? AvgRating { get; set; }
    }

    public class RestaurantDeliveryZoneModel
    {
        [Key] public int DeliveryZoneId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required] public string Name { get; set; } = string.Empty;
        public decimal MinDistanceKm { get; set; }
        public decimal MaxDistanceKm { get; set; } = 5;
        public decimal DeliveryFee { get; set; }
        public int EstimatedMins { get; set; } = 30;
        public bool IsActive { get; set; } = true;
        public int SortOrder { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class RestaurantDeliveryAssignmentModel
    {
        [Key] public int DeliveryAssignmentId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        public int OrderId { get; set; }
        public string? OrderNumber { get; set; }
        public int? DriverId { get; set; }
        public string? DriverName { get; set; }
        public string? DriverPhone { get; set; }
        public string Status { get; set; } = "Pending";
        public DateTime? AssignedAt { get; set; }
        public DateTime? PickedUpAt { get; set; }
        public DateTime? DeliveredAt { get; set; }
        public string? DeliveryAddress { get; set; }
        public string? DeliveryNotes { get; set; }
        public int? DeliveryZoneId { get; set; }
        public decimal DeliveryFee { get; set; }
        public int? EstimatedMins { get; set; }
        public int? ActualMins { get; set; }
        public decimal? DistanceKm { get; set; }
        public string? ProofType { get; set; }
        public string? ProofData { get; set; }
        public int? Rating { get; set; }
        public string? FailReason { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class RestaurantThirdPartyPlatformModel
    {
        [Key] public int PlatformId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required] public string Name { get; set; } = string.Empty;
        public string? ApiKey { get; set; }
        public string? ApiSecret { get; set; }
        public string? StoreId { get; set; }
        public decimal CommissionRate { get; set; }
        public bool AutoAccept { get; set; }
        public bool IsEnabled { get; set; }
        public bool IsActive { get; set; } = true;
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public long OrderCount { get; set; }
        public decimal TotalRevenue { get; set; }
    }

    public class RestaurantThirdPartyOrderModel
    {
        [Key] public int ThirdPartyOrderId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        public int? PlatformId { get; set; }
        public string PlatformName { get; set; } = string.Empty;
        public string ExternalOrderId { get; set; } = string.Empty;
        public int? OrderId { get; set; }
        public string Status { get; set; } = "Received";
        public string? CustomerName { get; set; }
        public string? CustomerPhone { get; set; }
        public string? DeliveryAddress { get; set; }
        public string? ItemsJson { get; set; }
        public decimal Subtotal { get; set; }
        public decimal DeliveryFee { get; set; }
        public decimal PlatformFee { get; set; }
        public decimal TotalAmount { get; set; }
        public decimal CommissionAmount { get; set; }
        public decimal NetAmount { get; set; }
        public string? Notes { get; set; }
        public DateTime? ReceivedAt { get; set; }
        public DateTime? AcceptedAt { get; set; }
        public DateTime? RejectedAt { get; set; }
        public string? RejectReason { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class DriverStatsModel
    {
        public long TotalDeliveries { get; set; }
        public long CompletedDeliveries { get; set; }
        public long FailedDeliveries { get; set; }
        public double? AvgDeliveryMins { get; set; }
        public double? AvgRating { get; set; }
        public decimal TotalDeliveryFees { get; set; }
    }

    public class DeliveryStatsModel
    {
        public long TotalAssignments { get; set; }
        public long PendingCount { get; set; }
        public long ActiveCount { get; set; }
        public long DeliveredCount { get; set; }
        public long FailedCount { get; set; }
        public double? AvgDeliveryMins { get; set; }
        public decimal TotalFees { get; set; }
        public long AvailableDrivers { get; set; }
        public long OnDeliveryDrivers { get; set; }
    }
}
