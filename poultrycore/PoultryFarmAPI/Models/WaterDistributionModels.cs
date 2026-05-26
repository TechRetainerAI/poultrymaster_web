using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    public static class WaterVehicleLoadingStatus
    {
        public const string Draft       = "Draft";
        public const string Loaded      = "Loaded";
        public const string Reconciled  = "Reconciled";
        public const string Cancelled   = "Cancelled";
    }

    public static class WaterDriverReturnStatus
    {
        public const string Draft     = "Draft";
        public const string Approved  = "Approved";
        public const string Cancelled = "Cancelled";
    }

    public static class WaterDriverShortageStatus
    {
        public const string Pending  = "Pending";
        public const string Approved = "Approved";
        public const string Deducted = "Deducted";
        public const string Waived   = "Waived";
    }

    public class WaterDriverModel
    {
        [Key] public int WaterDriverId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required] [StringLength(150)] public string DriverName { get; set; } = string.Empty;
        [StringLength(50)] public string? PhoneNumber { get; set; }
        [StringLength(60)] public string? LicenseNumber { get; set; }
        public int? DefaultVehicleId { get; set; }
        public int? DefaultRouteId { get; set; }
        public decimal? BasePay { get; set; }
        public decimal? CommissionPerBag { get; set; }
        public bool IsActive { get; set; } = true;
        [StringLength(500)] public string? Notes { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class WaterVehicleModel
    {
        [Key] public int WaterVehicleId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required] [StringLength(150)] public string VehicleName { get; set; } = string.Empty;
        [StringLength(30)] public string? VehicleType { get; set; }
        [StringLength(60)] public string? RegistrationNumber { get; set; }
        public int? DefaultDriverId { get; set; }
        public string? DefaultDriverName { get; set; }
        public int? CapacityBags { get; set; }
        [StringLength(30)] public string? FuelType { get; set; }
        [StringLength(30)] public string Status { get; set; } = "Active";
        [StringLength(500)] public string? Notes { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class WaterRouteModel
    {
        [Key] public int WaterRouteId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required] [StringLength(150)] public string RouteName { get; set; } = string.Empty;
        [StringLength(500)] public string? AreaCovered { get; set; }
        public int? DefaultDriverId { get; set; }
        public string? DefaultDriverName { get; set; }
        public int? DefaultVehicleId { get; set; }
        public string? DefaultVehicleName { get; set; }
        public int? ExpectedCustomers { get; set; }
        public int? ExpectedBagsSold { get; set; }
        [StringLength(500)] public string? Notes { get; set; }
        public bool IsActive { get; set; } = true;
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class WaterVehicleLoadingModel
    {
        [Key] public int WaterVehicleLoadingId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        public DateTime LoadDate { get; set; }
        [Required] public int WaterVehicleId { get; set; }
        public string? VehicleName { get; set; }
        public int? WaterDriverId { get; set; }
        public string? DriverName { get; set; }
        public int? AssistantStaffId { get; set; }
        public int? WaterRouteId { get; set; }
        public string? RouteName { get; set; }
        [Required] public int WaterProductId { get; set; }
        public string? ProductName { get; set; }
        [Range(1, int.MaxValue)] public int BagsLoaded { get; set; }
        public int SachetsPerBag { get; set; } = 30;
        [Range(0, double.MaxValue)] public decimal ExpectedSellingPricePerBag { get; set; }
        public decimal ExpectedCash { get; set; }
        public decimal OpeningCashWithDriver { get; set; }
        public int? LoadedByStaffId { get; set; }
        [StringLength(20)] public string Status { get; set; } = WaterVehicleLoadingStatus.Draft;
        [StringLength(500)] public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
        public string? ApprovedBy { get; set; }
        public DateTime? ApprovedAt { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public bool IsDeleted { get; set; }
    }

    public class WaterDriverReturnModel
    {
        [Key] public int WaterDriverReturnId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required] public int WaterVehicleLoadingId { get; set; }
        public DateTime ReturnDate { get; set; }
        [Range(0, int.MaxValue)] public int BagsSold { get; set; }
        [Range(0, int.MaxValue)] public int BagsReturned { get; set; }
        [Range(0, int.MaxValue)] public int BagsDamaged { get; set; }
        [Range(0, int.MaxValue)] public int MissingBags { get; set; }
        [Range(0, double.MaxValue)] public decimal CashCollected { get; set; }
        [Range(0, double.MaxValue)] public decimal MoMoCollected { get; set; }
        [Range(0, double.MaxValue)] public decimal BankCollected { get; set; }
        [Range(0, double.MaxValue)] public decimal CreditSalesAmount { get; set; }
        public decimal TotalAccountedFor { get; set; }
        public decimal ShortageAmount { get; set; }
        public decimal OverageAmount { get; set; }
        public int? ReconciledByStaffId { get; set; }
        [StringLength(20)] public string Status { get; set; } = WaterDriverReturnStatus.Draft;
        [StringLength(1000)] public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
        public string? ApprovedBy { get; set; }
        public DateTime? ApprovedAt { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }

        // Joined for convenience
        public int? WaterVehicleId { get; set; }
        public int? WaterDriverId { get; set; }
        public int? WaterRouteId { get; set; }
        public int? LoadingBagsLoaded { get; set; }
        public decimal? LoadingExpectedCash { get; set; }
        public decimal? ExpectedSellingPricePerBag { get; set; }
        public string? VehicleName { get; set; }
        public string? DriverName { get; set; }
        public string? RouteName { get; set; }
    }

    public class WaterDriverShortageModel
    {
        [Key] public int WaterDriverShortageId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        public int? WaterDriverId { get; set; }
        public string? DriverName { get; set; }
        public int? WaterVehicleLoadingId { get; set; }
        public int WaterDriverReturnId { get; set; }
        public DateTime ShortageDate { get; set; }
        public decimal ExpectedAmount { get; set; }
        public decimal ActualAmount { get; set; }
        public decimal ShortageAmount { get; set; }
        [StringLength(500)] public string? Reason { get; set; }
        [StringLength(20)] public string Status { get; set; } = WaterDriverShortageStatus.Pending;
        public string? ApprovedBy { get; set; }
        [StringLength(500)] public string? Notes { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class WaterDriverShortageResolveRequest
    {
        [Required] [StringLength(20)] public string NewStatus { get; set; } = "Approved";
        [StringLength(500)] public string? Reason { get; set; }
    }
}
