using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    // =========================================================================
    // Status constants
    // =========================================================================
    public static class GenericDailyClosingStatus
    {
        public const string Draft     = "Draft";
        public const string Submitted = "Submitted";
        public const string Approved  = "Approved";
        public const string Rejected  = "Rejected";
    }

    // =========================================================================
    // Daily Closing
    // =========================================================================
    public class GenericDailyClosingModel
    {
        [Key]
        public int GenericDailyClosingId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        public int? BranchId { get; set; }

        public DateTime ClosingDate { get; set; }

        public decimal OpeningCash { get; set; }
        public decimal TotalSales { get; set; }
        public decimal TotalCustomerPayments { get; set; }
        public decimal TotalCashIn { get; set; }
        public decimal TotalExpenses { get; set; }
        public decimal TotalPurchasesPaid { get; set; }
        public decimal TotalSupplierPayments { get; set; }
        public decimal TotalPayrollPaid { get; set; }
        public decimal TotalCashOut { get; set; }

        public decimal ExpectedCash { get; set; }
        public decimal ActualCashCounted { get; set; }
        public decimal CashDifference { get; set; }

        public decimal CreditSales { get; set; }
        public decimal CustomerDebtTotal { get; set; }
        public decimal SupplierDebtTotal { get; set; }
        public int InventoryAdjustmentsCount { get; set; }

        [StringLength(2000)]
        public string? ManagerNotes { get; set; }

        [StringLength(500)]
        public string? DifferenceReason { get; set; }

        [StringLength(20)]
        public string Status { get; set; } = GenericDailyClosingStatus.Draft;

        public string? CreatedBy { get; set; }
        public string? SubmittedBy { get; set; }
        public DateTime? SubmittedAt { get; set; }
        public string? ApprovedBy { get; set; }
        public DateTime? ApprovedAt { get; set; }

        [StringLength(500)]
        public string? RejectionReason { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class GenericDailyClosingCreateRequest
    {
        [Required]
        public DateTime ClosingDate { get; set; }

        public int? BranchId { get; set; }

        // If null, the SP defaults to the previous closing's ActualCashCounted
        // (or the sum of cash-account OpeningBalances if there's no prior).
        public decimal? OpeningCash { get; set; }

        public decimal ActualCashCounted { get; set; }

        [StringLength(2000)]
        public string? ManagerNotes { get; set; }

        [StringLength(500)]
        public string? DifferenceReason { get; set; }
    }

    public class GenericDailyClosingSubmitRequest
    {
        // Optional overrides — pass nulls to leave existing values alone.
        public decimal? ActualCashCounted { get; set; }

        [StringLength(2000)]
        public string? ManagerNotes { get; set; }

        [StringLength(500)]
        public string? DifferenceReason { get; set; }
    }

    public class GenericDailyClosingRejectRequest
    {
        [Required]
        [StringLength(500)]
        public string RejectionReason { get; set; } = string.Empty;
    }

    // =========================================================================
    // Dashboard view model
    // =========================================================================
    public class GenericDashboardModel
    {
        public GenericDashboardToday Today { get; set; } = new();
        public GenericDashboardWeek Week { get; set; } = new();
        public List<GenericDashboardCashAccount> CashAccounts { get; set; } = new();
        public GenericDashboardAlerts Alerts { get; set; } = new();
    }

    public class GenericDashboardToday
    {
        public decimal TodaySales { get; set; }
        public decimal TodayExpenses { get; set; }
        public decimal TodayPurchasesPaid { get; set; }
        public decimal TodayGrossProfit { get; set; }
        public decimal YesterdaySales { get; set; }
        public decimal CashAtHand { get; set; }
        public decimal InventoryValue { get; set; }
        public decimal CustomerDebt { get; set; }
        public decimal SupplierDebt { get; set; }
    }

    public class GenericDashboardWeek
    {
        public decimal WeekSales { get; set; }
        public decimal WeekExpenses { get; set; }
        public decimal WeekPurchasesPaid { get; set; }
        public decimal WeekGrossProfit { get; set; }
        public string? TopSellingItem { get; set; }
        public decimal TopSellingQuantity { get; set; }
        public string? TopExpenseCategory { get; set; }
        public decimal TopExpenseAmount { get; set; }
    }

    public class GenericDashboardCashAccount
    {
        public int GenericCashAccountId { get; set; }
        public string AccountName { get; set; } = string.Empty;
        public string AccountType { get; set; } = string.Empty;
        public decimal CurrentBalance { get; set; }
        public bool IsActive { get; set; }
    }

    public class GenericDashboardAlerts
    {
        public int LowStockCount { get; set; }
        public int DraftSalesCount { get; set; }
        public int DraftExpensesCount { get; set; }
        public int CustomersOwingCount { get; set; }
        public int SuppliersOwedCount { get; set; }
        public int PendingClosingsCount { get; set; }
    }

    // =========================================================================
    // Period P&L
    // =========================================================================
    public class GenericPeriodPnLModel
    {
        public DateTime PeriodStart { get; set; }
        public DateTime PeriodEnd { get; set; }
        public decimal TotalIncome { get; set; }
        public decimal TotalExpenses { get; set; }
        public decimal CostOfGoodsSold { get; set; }
        public decimal GrossProfit { get; set; }
        public decimal NetProfit { get; set; }
        public decimal ProfitMarginPct { get; set; }
        public decimal TotalPurchasesPaid { get; set; }
        public int SalesCount { get; set; }
    }

    // =========================================================================
    // Report rows
    // =========================================================================
    public class GenericSalesByProductRow
    {
        public int? GenericProductId { get; set; }
        public string ProductName { get; set; } = string.Empty;
        public string? SKU { get; set; }
        public decimal TotalQuantity { get; set; }
        public decimal TotalRevenue { get; set; }
        public decimal TotalCost { get; set; }
        public int SalesCount { get; set; }
    }

    public class GenericSalesByCustomerRow
    {
        public int? GenericCustomerId { get; set; }
        public string CustomerName { get; set; } = string.Empty;
        public string? PhoneNumber { get; set; }
        public int SalesCount { get; set; }
        public decimal TotalRevenue { get; set; }
        public decimal TotalPaid { get; set; }
        public decimal TotalOutstanding { get; set; }
    }

    public class GenericExpenseByCategoryRow
    {
        public int GenericExpenseCategoryId { get; set; }
        public string CategoryName { get; set; } = string.Empty;
        public int ExpenseCount { get; set; }
        public decimal TotalAmount { get; set; }
    }

    public class GenericInventoryValueRow
    {
        public int? GenericProductCategoryId { get; set; }
        public string CategoryName { get; set; } = string.Empty;
        public int ProductCount { get; set; }
        public decimal TotalUnits { get; set; }
        public decimal TotalCostValue { get; set; }
        public decimal TotalRetailValue { get; set; }
    }

    public class GenericInventoryValueReport
    {
        public List<GenericInventoryValueRow> ByCategory { get; set; } = new();
        public decimal TotalCostValue { get; set; }
        public decimal TotalRetailValue { get; set; }
        public int ProductCount { get; set; }
    }

    public class GenericCashSummaryRow
    {
        public int GenericCashAccountId { get; set; }
        public string AccountName { get; set; } = string.Empty;
        public string AccountType { get; set; } = string.Empty;
        public decimal CurrentBalance { get; set; }
        public decimal PeriodCashIn { get; set; }
        public decimal PeriodCashOut { get; set; }
        public bool IsActive { get; set; }
    }

    public class GenericCashSummaryReport
    {
        public List<GenericCashSummaryRow> Accounts { get; set; } = new();
        public decimal TotalCashAtHand { get; set; }
    }
}
