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
        // #18 — links the driver to its AspNetUsers employee (merged model).
        [StringLength(450)] public string? EmployeeUserId { get; set; }
    }

    // #18 — request to make an existing employee a driver (set role + upsert profile).
    public class WaterDriverFromEmployeeRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public string EmployeeUserId { get; set; } = string.Empty;
        public string Role { get; set; } = "Driver";
        public string? LicenseNumber { get; set; }
        public int? DefaultVehicleId { get; set; }
        public int? DefaultRouteId { get; set; }
        public decimal? BasePay { get; set; }
        public decimal? CommissionPerBag { get; set; }
        public string? Notes { get; set; }
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
        // Header still carries a single product (FK constraint from migration
        // 040). Migration 064 makes this optional in the SP — when Items has
        // rows the SP snapshots the first item's product into these fields.
        public int WaterProductId { get; set; }
        public string? ProductName { get; set; }
        public int BagsLoaded { get; set; }
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
        // Migration 064: multi-product items. Optional payload on POST.
        public List<WaterVehicleLoadingItemModel>? Items { get; set; }
    }

    // Migration 068: input body for /vehicle-loadings/{id}/reload. Only
    // non-null fields are applied — others fall back to the existing values.
    public class WaterVehicleLoadingReloadInput
    {
        public int? WaterDriverId { get; set; }
        public int? WaterVehicleId { get; set; }
        public int? WaterRouteId { get; set; }
        public DateTime? LoadDate { get; set; }
        public decimal? OpeningCashWithDriver { get; set; }
        [StringLength(1000)] public string? Notes { get; set; }
        public List<WaterVehicleLoadingReloadItem>? Items { get; set; }
    }

    public class WaterVehicleLoadingReloadItem
    {
        public int WaterProductId { get; set; }
        public int BagsLoaded { get; set; }
        public decimal UnitPrice { get; set; }
    }

    // Per-product line on a vehicle loading (migration 064).
    public class WaterVehicleLoadingItemModel
    {
        [Key] public int WaterVehicleLoadingItemId { get; set; }
        public int WaterVehicleLoadingId { get; set; }
        [Required] public int WaterProductId { get; set; }
        public string? ProductName { get; set; }
        public string? ProductUnit { get; set; }
        [Range(1, int.MaxValue)] public int BagsLoaded { get; set; }
        public int SachetsPerBag { get; set; } = 30;
        [Range(0, double.MaxValue)] public decimal UnitPrice { get; set; }
        public decimal ExpectedAmount { get; set; }
        [StringLength(300)] public string? Notes { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
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
        // Migration 064: separate the driver's float / approved expenses from
        // sales cash so reconciliation is clear.
        [Range(0, double.MaxValue)] public decimal CashReturnedByDriver { get; set; }
        [Range(0, double.MaxValue)] public decimal ApprovedDeliveryExpenses { get; set; }
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

        // Migration 115: when editing/replacing a return, the id being replaced
        // is excluded from the one-open-return-per-delivery guard. Not stored.
        public int? ReplaceReturnId { get; set; }

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

        // Migration 064: optional payloads on POST.
        public List<WaterDriverReturnItemModel>? Items { get; set; }
        public List<WaterDriverReturnCustomerSaleInput>? CustomerSales { get; set; }
        public List<WaterDeliveryExpenseInput>? Expenses { get; set; }

        // Migration 083: sales posting mode + primary customer for OneCustomer/Summary.
        //   'Detailed'     → use the CustomerSales breakdown (default — legacy behavior).
        //   'OneCustomer'  → entire delivery sale posts to PrimaryCustomerId.
        //   'Summary'      → falls back to the company's GeneralDelivery default customer.
        [StringLength(20)] public string? SalesPostingMode { get; set; }
        public int? PrimaryCustomerId { get; set; }
    }

    // Migration 083: POST /driver-returns/{id}/posting-mode body.
    public class WaterDriverReturnPostingModeInput
    {
        [Required, StringLength(20)] public string SalesPostingMode { get; set; } = "Detailed";
        public int? PrimaryCustomerId { get; set; }
    }

    // Per-product reconciliation row (migration 064).
    public class WaterDriverReturnItemModel
    {
        [Key] public int WaterDriverReturnItemId { get; set; }
        public int WaterDriverReturnId { get; set; }
        [Required] public int WaterProductId { get; set; }
        public string? ProductName { get; set; }
        public int BagsLoaded { get; set; }
        [Range(0, int.MaxValue)] public int BagsSold { get; set; }
        [Range(0, int.MaxValue)] public int BagsReturned { get; set; }
        [Range(0, int.MaxValue)] public int BagsDamaged { get; set; }
        [Range(0, double.MaxValue)] public decimal UnitPrice { get; set; }
        public decimal ExpectedSales { get; set; }
        [StringLength(300)] public string? Notes { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    // Customer breakdown row + items (migration 064).
    public class WaterDriverReturnCustomerSaleInput
    {
        public int? WaterCustomerId { get; set; }
        [StringLength(150)] public string? CustomerLabel { get; set; }
        public decimal CashPaid { get; set; }
        public decimal MoMoPaid { get; set; }
        public decimal BankPaid { get; set; }
        public decimal CreditAmount { get; set; }
        [StringLength(500)] public string? Notes { get; set; }
        public List<WaterDriverReturnCustomerSaleItemInput> Items { get; set; } = new();
    }

    public class WaterDriverReturnCustomerSaleItemInput
    {
        [Required] public int WaterProductId { get; set; }
        [Range(1, int.MaxValue)] public int Quantity { get; set; }
        [Range(0, double.MaxValue)] public decimal UnitPrice { get; set; }
    }

    // Returned by the GET endpoint — includes generated sale id once approved.
    public class WaterDriverReturnCustomerSaleRow
    {
        public int WaterDriverReturnCustomerSaleId { get; set; }
        public int WaterDriverReturnId { get; set; }
        public int? WaterCustomerId { get; set; }
        public string? CustomerName { get; set; }
        public string? CustomerLabel { get; set; }
        public decimal TotalAmount { get; set; }
        public decimal CashPaid { get; set; }
        public decimal MoMoPaid { get; set; }
        public decimal BankPaid { get; set; }
        public decimal CreditAmount { get; set; }
        public int? GeneratedWaterSaleId { get; set; }
        public string? Notes { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public List<WaterDriverReturnCustomerSaleItemRow> Items { get; set; } = new();
    }

    public class WaterDriverReturnCustomerSaleItemRow
    {
        public int WaterDriverReturnCustomerSaleItemId { get; set; }
        public int WaterDriverReturnCustomerSaleId { get; set; }
        public int WaterProductId { get; set; }
        public string? ProductName { get; set; }
        public int Quantity { get; set; }
        public decimal UnitPrice { get; set; }
        public decimal LineTotal { get; set; }
    }

    // Delivery expense (migration 064).
    public class WaterDeliveryExpenseInput
    {
        [StringLength(40)] public string ExpenseCategory { get; set; } = "Other";
        public decimal Amount { get; set; }
        [StringLength(500)] public string? Description { get; set; }
        public bool IsApproved { get; set; } = true;
        [StringLength(500)] public string? Notes { get; set; }
    }

    public class WaterDeliveryExpenseModel
    {
        [Key] public int WaterDeliveryExpenseId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        public int? WaterDriverReturnId { get; set; }
        public int? WaterVehicleLoadingId { get; set; }
        [StringLength(40)] public string ExpenseCategory { get; set; } = "Other";
        public decimal Amount { get; set; }
        [StringLength(500)] public string? Description { get; set; }
        public bool IsApproved { get; set; } = true;
        [StringLength(500)] public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
        // Migration 085 — Driver-return context for the unified Expenses list.
        // Populated by spWaterDeliveryExpense_ListAll, null on the per-return
        // GetByReturn path (which doesn't join the parent return).
        public DateTime? ReturnDate { get; set; }
        public string? ReturnStatus { get; set; }
        public string? DriverName { get; set; }
        public string? VehicleNumber { get; set; }
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
