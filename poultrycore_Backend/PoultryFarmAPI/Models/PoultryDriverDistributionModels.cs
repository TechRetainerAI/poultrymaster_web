namespace PoultryFarmAPIWeb.Models
{
    // =========================================================================
    // Poultry Driver Distribution — entity models, request DTOs and report rows.
    // Crate vocabulary (crate / eggs-per-crate). Mirrors the Water distribution
    // models; property names in PascalCase matching the SP result columns
    // (ASP.NET serializes to camelCase for the frontend).
    // Schema: migration 138. SPs: 139. Reports: 140.
    // =========================================================================

    // ------------------------- Masters: Driver -------------------------------
    public class PoultryDriverModel
    {
        public int PoultryDriverId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public string DriverName { get; set; } = string.Empty;
        public string? PhoneNumber { get; set; }
        public string? LicenseNumber { get; set; }
        public int? DefaultVehicleId { get; set; }
        public int? DefaultRouteId { get; set; }
        public decimal? BasePay { get; set; }
        public decimal? CommissionPerCrate { get; set; }
        public bool IsActive { get; set; } = true;
        public string? EmployeeUserId { get; set; }
        public string? Notes { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
        // list-for-farm join extras
        public string? EmployeeEmail { get; set; }
        public string? EmployeeUserName { get; set; }
    }

    public class PoultryDriverFromEmployeeRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public string EmployeeUserId { get; set; } = string.Empty;
        public string? DriverName { get; set; }
        public string? PhoneNumber { get; set; }
        public string? LicenseNumber { get; set; }
        public decimal? BasePay { get; set; }
        public decimal? CommissionPerCrate { get; set; }
    }

    // ------------------------- Masters: Vehicle ------------------------------
    public class PoultryVehicleModel
    {
        public int PoultryVehicleId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public string VehicleName { get; set; } = string.Empty;
        public string? VehicleType { get; set; }
        public string? RegistrationNumber { get; set; }
        public int? DefaultDriverId { get; set; }
        public int? CapacityCrates { get; set; }
        public string? FuelType { get; set; }
        public string Status { get; set; } = "Active";
        public string? Notes { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    // ------------------------- Masters: Route --------------------------------
    public class PoultryRouteModel
    {
        public int PoultryRouteId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public string RouteName { get; set; } = string.Empty;
        public string? AreaCovered { get; set; }
        public int? DefaultDriverId { get; set; }
        public int? DefaultVehicleId { get; set; }
        public int? ExpectedCustomers { get; set; }
        public int? ExpectedCratesSold { get; set; }
        public string? Notes { get; set; }
        public bool IsActive { get; set; } = true;
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    // ------------------------- Vehicle Loading -------------------------------
    public class PoultryVehicleLoadingModel
    {
        public int PoultryVehicleLoadingId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public DateTime LoadDate { get; set; }
        public int PoultryVehicleId { get; set; }
        public int? PoultryDriverId { get; set; }
        public int? AssistantStaffId { get; set; }
        public int? PoultryRouteId { get; set; }
        public int PoultryProductId { get; set; }
        public int CratesLoaded { get; set; }
        public int EggsPerCrate { get; set; }
        public decimal ExpectedSellingPricePerCrate { get; set; }
        public decimal ExpectedCash { get; set; }
        public decimal OpeningCashWithDriver { get; set; }
        public int? LoadedByStaffId { get; set; }
        public string Status { get; set; } = "Draft";
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
        public string? ApprovedBy { get; set; }
        public DateTime? ApprovedAt { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public bool IsDeleted { get; set; }
        // joins
        public string? VehicleName { get; set; }
        public string? RegistrationNumber { get; set; }
        public string? DriverName { get; set; }
        public string? RouteName { get; set; }
        public string? ProductName { get; set; }
    }

    public class PoultryVehicleLoadingItemModel
    {
        public int PoultryVehicleLoadingItemId { get; set; }
        public int PoultryVehicleLoadingId { get; set; }
        public int PoultryProductId { get; set; }
        public string? ProductName { get; set; }
        public string? ProductUnit { get; set; }
        public int CratesLoaded { get; set; }
        public int EggsPerCrate { get; set; }
        public decimal UnitPrice { get; set; }
        public decimal ExpectedAmount { get; set; }
        public string? Notes { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    // create-loading request (nested items -> @ItemsJson)
    public class PoultryVehicleLoadingCreateRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public DateTime? LoadDate { get; set; }
        public int PoultryVehicleId { get; set; }
        public int? PoultryDriverId { get; set; }
        public int? AssistantStaffId { get; set; }
        public int? PoultryRouteId { get; set; }
        public decimal OpeningCashWithDriver { get; set; }
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
        public List<PoultryVehicleLoadingItemInput> Items { get; set; } = new();
    }

    public class PoultryVehicleLoadingItemInput
    {
        public int PoultryProductId { get; set; }
        public int CratesLoaded { get; set; }
        public decimal UnitPrice { get; set; }
        public int? EggsPerCrate { get; set; }
        public string? Notes { get; set; }
    }

    // ------------------------- Driver Return ---------------------------------
    public class PoultryDriverReturnModel
    {
        public int PoultryDriverReturnId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public int PoultryVehicleLoadingId { get; set; }
        public DateTime ReturnDate { get; set; }
        public int CratesSold { get; set; }
        public int CratesReturned { get; set; }
        public int CratesDamaged { get; set; }
        public int MissingCrates { get; set; }
        public decimal CashCollected { get; set; }
        public decimal MoMoCollected { get; set; }
        public decimal BankCollected { get; set; }
        public decimal CreditSalesAmount { get; set; }
        public decimal TotalAccountedFor { get; set; }
        public decimal CashReturnedByDriver { get; set; }
        public decimal ApprovedDeliveryExpenses { get; set; }
        public decimal ShortageAmount { get; set; }
        public decimal OverageAmount { get; set; }
        public string SalesPostingMode { get; set; } = "Detailed";
        public int? PrimaryCustomerId { get; set; }
        public int? LinkedCashAdjId { get; set; }
        public int? ReconciledByStaffId { get; set; }
        public string Status { get; set; } = "Draft";
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
        public string? ApprovedBy { get; set; }
        public DateTime? ApprovedAt { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
        // joins
        public int? PoultryVehicleId { get; set; }
        public int? PoultryDriverId { get; set; }
        public int? PoultryRouteId { get; set; }
        public int? LoadingCratesLoaded { get; set; }
        public decimal? LoadingExpectedCash { get; set; }
        public string? VehicleName { get; set; }
        public string? DriverName { get; set; }
        public string? RouteName { get; set; }
    }

    public class PoultryDriverReturnItemModel
    {
        public int PoultryDriverReturnItemId { get; set; }
        public int PoultryDriverReturnId { get; set; }
        public int PoultryProductId { get; set; }
        public string? ProductName { get; set; }
        public int CratesLoaded { get; set; }
        public int CratesSold { get; set; }
        public int CratesReturned { get; set; }
        public int CratesDamaged { get; set; }
        public decimal UnitPrice { get; set; }
        public decimal ExpectedSales { get; set; }
        public string? Notes { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class PoultryDriverReturnCustomerSaleRow
    {
        public int PoultryDriverReturnCustomerSaleId { get; set; }
        public int PoultryDriverReturnId { get; set; }
        public int? CustomerId { get; set; }
        public string? CustomerLabel { get; set; }
        public decimal TotalAmount { get; set; }
        public decimal CashPaid { get; set; }
        public decimal MoMoPaid { get; set; }
        public decimal BankPaid { get; set; }
        public decimal CreditAmount { get; set; }
        public int? GeneratedSaleId { get; set; }
        public string? Notes { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public List<PoultryDriverReturnCustomerSaleItemRow> Items { get; set; } = new();
    }

    public class PoultryDriverReturnCustomerSaleItemRow
    {
        public int PoultryDriverReturnCustomerSaleItemId { get; set; }
        public int PoultryDriverReturnCustomerSaleId { get; set; }
        public int PoultryProductId { get; set; }
        public string? ProductName { get; set; }
        public int Quantity { get; set; }
        public decimal UnitPrice { get; set; }
        public decimal LineTotal { get; set; }
    }

    public class PoultryDriverDeliveryExpenseModel
    {
        public int PoultryDriverDeliveryExpenseId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public int? PoultryDriverReturnId { get; set; }
        public int? PoultryVehicleLoadingId { get; set; }
        public string ExpenseCategory { get; set; } = string.Empty;
        public decimal Amount { get; set; }
        public string? Description { get; set; }
        public bool IsApproved { get; set; }
        public int? LinkedExpenseId { get; set; }
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
        // ListAll join extras
        public DateTime? ReturnDate { get; set; }
        public int? PoultryDriverId { get; set; }
        public string? DriverName { get; set; }
    }

    // create/approve-reconcile request (nested items/customerSales/expenses -> JSON)
    public class PoultryDriverReturnCreateRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public int PoultryVehicleLoadingId { get; set; }
        public DateTime? ReturnDate { get; set; }
        public int CratesSold { get; set; }
        public int CratesReturned { get; set; }
        public int CratesDamaged { get; set; }
        public int MissingCrates { get; set; }
        public decimal CashCollected { get; set; }
        public decimal MoMoCollected { get; set; }
        public decimal BankCollected { get; set; }
        public decimal CreditSalesAmount { get; set; }
        public decimal CashReturnedByDriver { get; set; }
        public decimal ApprovedDeliveryExpenses { get; set; }
        public string SalesPostingMode { get; set; } = "Detailed";
        public int? PrimaryCustomerId { get; set; }
        public int? ReconciledByStaffId { get; set; }
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
        public List<PoultryDriverReturnItemInput> Items { get; set; } = new();
        public List<PoultryDriverReturnCustomerSaleInput> CustomerSales { get; set; } = new();
        public List<PoultryDriverDeliveryExpenseInput> Expenses { get; set; } = new();
    }

    public class PoultryDriverReturnItemInput
    {
        public int PoultryProductId { get; set; }
        public int CratesSold { get; set; }
        public int CratesReturned { get; set; }
        public int CratesDamaged { get; set; }
        public decimal UnitPrice { get; set; }
        public string? Notes { get; set; }
    }

    public class PoultryDriverReturnCustomerSaleInput
    {
        public int? CustomerId { get; set; }
        public string? CustomerLabel { get; set; }
        public decimal CashPaid { get; set; }
        public decimal MoMoPaid { get; set; }
        public decimal BankPaid { get; set; }
        public decimal CreditAmount { get; set; }
        public string? Notes { get; set; }
        public List<PoultryDriverReturnCustomerSaleItemInput> Items { get; set; } = new();
    }

    public class PoultryDriverReturnCustomerSaleItemInput
    {
        public int PoultryProductId { get; set; }
        public int Quantity { get; set; }
        public decimal UnitPrice { get; set; }
    }

    public class PoultryDriverDeliveryExpenseInput
    {
        public string ExpenseCategory { get; set; } = "Other";
        public decimal Amount { get; set; }
        public string? Description { get; set; }
        public bool IsApproved { get; set; } = true;
        public string? Notes { get; set; }
    }

    public class PoultryDriverReturnPostingModeRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public string SalesPostingMode { get; set; } = "Detailed";
    }

    // ------------------------- Shortage --------------------------------------
    public class PoultryDriverShortageModel
    {
        public int PoultryDriverShortageId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public int? PoultryDriverId { get; set; }
        public int? PoultryVehicleLoadingId { get; set; }
        public int PoultryDriverReturnId { get; set; }
        public DateTime ShortageDate { get; set; }
        public decimal ExpectedAmount { get; set; }
        public decimal ActualAmount { get; set; }
        public decimal ShortageAmount { get; set; }
        public string? Reason { get; set; }
        public string Status { get; set; } = "Pending";
        public string? ApprovedBy { get; set; }
        public string? Notes { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public string? DriverName { get; set; }
    }

    public class PoultryDriverShortageResolveRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public string Status { get; set; } = string.Empty;
        public string? ApprovedBy { get; set; }
        public string? Notes { get; set; }
    }

    // ------------------------- Report rows -----------------------------------
    public class PoultryDriverReconciliationRow
    {
        public int? PoultryDriverId { get; set; }
        public string? DriverName { get; set; }
        public int DeliveryRuns { get; set; }
        public int TotalCratesLoaded { get; set; }
        public int TotalCratesSold { get; set; }
        public int TotalCratesReturned { get; set; }
        public int TotalCratesLost { get; set; }
        public decimal ExpectedRevenue { get; set; }
        public decimal AccountedRevenue { get; set; }
        public decimal TotalShortage { get; set; }
        public decimal TotalOverage { get; set; }
    }

    public class PoultryDriverCollectionDetailRow
    {
        public int? PoultryDriverId { get; set; }
        public string? DriverName { get; set; }
        public int PoultryDriverReturnId { get; set; }
        public DateTime ReturnDate { get; set; }
        public string? ProductName { get; set; }
        public int CratesLoaded { get; set; }
        public int CratesSold { get; set; }
        public int CratesReturned { get; set; }
        public int CratesDamaged { get; set; }
        public decimal ExpectedAmount { get; set; }
    }

    public class PoultryDriverCollectionTotalsRow
    {
        public int? PoultryDriverId { get; set; }
        public string? DriverName { get; set; }
        public int DeliveryRuns { get; set; }
        public int TotalCratesLoaded { get; set; }
        public int TotalCratesSold { get; set; }
        public int TotalCratesReturned { get; set; }
        public int TotalCratesLost { get; set; }
        public decimal TotalExpected { get; set; }
        public decimal TotalCollected { get; set; }
        public decimal TotalShortage { get; set; }
    }

    public class PoultryDriverCollectionReport
    {
        public List<PoultryDriverCollectionDetailRow> Detail { get; set; } = new();
        public List<PoultryDriverCollectionTotalsRow> Totals { get; set; } = new();
    }
}
