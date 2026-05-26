using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    public static class WaterDailyClosingStatus
    {
        public const string Draft     = "Draft";
        public const string Submitted = "Submitted";
        public const string Approved  = "Approved";
        public const string Rejected  = "Rejected";
    }

    public class WaterRawMaterialItemModel
    {
        [Key] public int WaterRawMaterialItemId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required] [StringLength(150)] public string ItemName { get; set; } = string.Empty;
        [Required] [StringLength(40)] public string Category { get; set; } = "Other";
        [StringLength(30)] public string? UnitOfMeasure { get; set; }
        public decimal MinimumStockAlert { get; set; }
        public decimal CurrentQuantity { get; set; }
        public bool IsActive { get; set; } = true;
        [StringLength(500)] public string? Notes { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class WaterRawMaterialPurchaseModel
    {
        [Key] public int WaterRawMaterialPurchaseId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required] public int WaterRawMaterialItemId { get; set; }
        public string? ItemName { get; set; }
        public string? Category { get; set; }
        public string? UnitOfMeasure { get; set; }
        [StringLength(200)] public string? SupplierName { get; set; }
        public DateTime PurchaseDate { get; set; }
        [Range(0.0001, double.MaxValue)] public decimal Quantity { get; set; }
        [Range(0, double.MaxValue)] public decimal UnitCost { get; set; }
        public decimal TotalCost { get; set; }
        [StringLength(30)] public string? PaymentMethod { get; set; }
        public decimal AmountPaid { get; set; }
        [StringLength(500)] public string? ReceiptUrl { get; set; }
        public int? ReceivedByStaffId { get; set; }
        [StringLength(500)] public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class WaterRawMaterialUsageModel
    {
        [Key] public int WaterRawMaterialUsageId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required] public int WaterRawMaterialItemId { get; set; }
        public string? ItemName { get; set; }
        public string? Category { get; set; }
        public string? UnitOfMeasure { get; set; }
        public int? WaterProductionBatchId { get; set; }
        public string? BatchNumber { get; set; }
        public DateTime UsedDate { get; set; }
        [Range(0.0001, double.MaxValue)] public decimal QuantityUsed { get; set; }
        public decimal? ExpectedQuantityUsed { get; set; }
        public decimal Variance { get; set; }
        [StringLength(500)] public string? VarianceReason { get; set; }
        public int? UsedByStaffId { get; set; }
        [StringLength(500)] public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class WaterLossRecordModel
    {
        [Key] public int WaterLossRecordId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        public DateTime LossDate { get; set; }
        [Required] [StringLength(40)] public string LossType { get; set; } = "Other";
        public int? WaterProductId { get; set; }
        public string? ProductName { get; set; }
        public decimal? QuantityBags { get; set; }
        public decimal? QuantitySachets { get; set; }
        public decimal? EstimatedValue { get; set; }
        public int? ResponsibleStaffId { get; set; }
        [StringLength(500)] public string? Reason { get; set; }
        [StringLength(20)] public string Status { get; set; } = "Pending";
        public string? ApprovedBy { get; set; }
        [StringLength(500)] public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class WaterDailyClosingModel
    {
        [Key] public int WaterDailyClosingId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        public DateTime ClosingDate { get; set; }
        public decimal OpeningStockBags { get; set; }
        public decimal BagsProduced { get; set; }
        public decimal BagsSold { get; set; }
        public decimal BagsReturned { get; set; }
        public decimal BagsDamaged { get; set; }
        public decimal ClosingStockBags { get; set; }
        public decimal TotalIncome { get; set; }
        public decimal TotalExpenses { get; set; }
        public decimal TotalProductionCost { get; set; }
        public decimal CashAtHand { get; set; }
        public decimal ActualCashCounted { get; set; }
        public decimal CashDifference { get; set; }
        public decimal CreditSales { get; set; }
        public decimal CustomerCollections { get; set; }
        public decimal DriverShortagesTotal { get; set; }
        [StringLength(2000)] public string? ManagerNotes { get; set; }
        [StringLength(500)] public string? DifferenceReason { get; set; }
        [StringLength(20)] public string Status { get; set; } = WaterDailyClosingStatus.Draft;
        public string? CreatedBy { get; set; }
        public string? SubmittedBy { get; set; }
        public DateTime? SubmittedAt { get; set; }
        public string? ApprovedBy { get; set; }
        public DateTime? ApprovedAt { get; set; }
        [StringLength(500)] public string? RejectionReason { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class WaterDailyClosingSubmitRequest
    {
        public decimal? ActualCashCounted { get; set; }
        [StringLength(2000)] public string? ManagerNotes { get; set; }
        [StringLength(500)] public string? DifferenceReason { get; set; }
    }

    public class WaterDailyClosingRejectRequest
    {
        [Required] [StringLength(500)] public string RejectionReason { get; set; } = string.Empty;
    }

    // Report row models
    public class WaterPeriodPnLModel
    {
        public DateTime PeriodStart { get; set; }
        public DateTime PeriodEnd { get; set; }
        public decimal TotalIncome { get; set; }
        public decimal TotalExpenses { get; set; }
        public decimal RawMaterialCost { get; set; }
        public decimal ProductionCost { get; set; }
        public decimal NetProfit { get; set; }
        public decimal ProfitMarginPct { get; set; }
        public int BagsProduced { get; set; }
        public int BagsSold { get; set; }
        public decimal AvgProfitPerBag { get; set; }
    }

    public class WaterRouteProfitabilityRow
    {
        public int WaterRouteId { get; set; }
        public string RouteName { get; set; } = string.Empty;
        public decimal TotalBagsLoaded { get; set; }
        public decimal TotalBagsSold { get; set; }
        public decimal TotalBagsReturned { get; set; }
        public decimal TotalBagsLost { get; set; }
        public decimal TotalRevenue { get; set; }
        public decimal TotalShortages { get; set; }
        public decimal TotalOverages { get; set; }
        public decimal NetRouteIncome { get; set; }
    }

    public class WaterDriverReconciliationRow
    {
        public int WaterDriverId { get; set; }
        public string DriverName { get; set; } = string.Empty;
        public string? PhoneNumber { get; set; }
        public decimal TotalBagsLoaded { get; set; }
        public decimal TotalBagsSold { get; set; }
        public decimal TotalBagsReturned { get; set; }
        public decimal TotalBagsLost { get; set; }
        public decimal ExpectedRevenue { get; set; }
        public decimal ActualAccountedFor { get; set; }
        public decimal TotalShortages { get; set; }
        public int ShortageOccurrences { get; set; }
    }

    public class WaterRawMaterialVarianceRow
    {
        public int WaterRawMaterialItemId { get; set; }
        public string ItemName { get; set; } = string.Empty;
        public string Category { get; set; } = string.Empty;
        public string? UnitOfMeasure { get; set; }
        public decimal TotalExpected { get; set; }
        public decimal TotalActual { get; set; }
        public decimal TotalVariance { get; set; }
        public int UsageCount { get; set; }
    }

    public class WaterDashboardExtendedToday
    {
        public decimal TodayBagsProduced { get; set; }
        public decimal TodayBagsSold { get; set; }
        public decimal TodayRevenue { get; set; }
        public decimal TodayProductionCost { get; set; }
        public decimal BagsOnHand { get; set; }
        public decimal TotalCustomerDebt { get; set; }
        public decimal PendingDriverShortages { get; set; }
    }

    public class WaterDashboardExtendedAlerts
    {
        public int LowRawMaterialCount { get; set; }
        public int PendingShortagesCount { get; set; }
        public int DraftBatchesCount { get; set; }
        public int LoadingsAwaitingReturnCount { get; set; }
        public int DraftReturnsCount { get; set; }
        public int MachinesDownCount { get; set; }
        public int VehiclesDownCount { get; set; }
    }

    public class WaterDashboardExtendedModel
    {
        public WaterDashboardExtendedToday Today { get; set; } = new();
        public WaterDashboardExtendedAlerts Alerts { get; set; } = new();
    }

    // Migration 057: dashboard intelligence (gap #7 — owner-intelligence cards)
    public class WaterExpenseByCategoryRow
    {
        public int WaterExpenseCategoryId { get; set; }
        public string CategoryName { get; set; } = string.Empty;
        public int ExpenseCount { get; set; }
        public decimal TotalAmount { get; set; }
    }

    public class WaterTopCustomerRow
    {
        public int WaterCustomerId { get; set; }
        public string CustomerName { get; set; } = string.Empty;
        public string? PhoneNumber { get; set; }
        public int SalesCount { get; set; }
        public decimal TotalSales { get; set; }
        public decimal TotalPaid { get; set; }
        public decimal OutstandingBalance { get; set; }
    }
}
