using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    public record GenericProfitLossEntry(string Section, string Line, DateOnly Date, string Reference, string Description, decimal Amount);

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

    // =========================================================================
    // Financial Impact Preview (migration 442)
    // =========================================================================
    public class GenericFinancialPreviewModel
    {
        public string ProductName { get; set; } = string.Empty;
        public string TransactionType { get; set; } = string.Empty;
        public decimal Quantity { get; set; }
        public decimal UnitCost { get; set; }
        public decimal TotalCost { get; set; }
        public decimal InventoryChange { get; set; }
        public decimal RevenueEffect { get; set; }
        public decimal COGSEffect { get; set; }
        public decimal ExpenseEffect { get; set; }
        public decimal CashEffect { get; set; }
        public decimal SupplierEffect { get; set; }
        public decimal CurrentStock { get; set; }
        public decimal StockAfter { get; set; }
        public string? ExpenseCategory { get; set; }
        public string? Notes { get; set; }
    }

    // =========================================================================
    // P&L Expense Breakdown (migration 442)
    // =========================================================================
    public class GenericPnLBreakdownModel
    {
        public decimal TotalIncome { get; set; }
        public decimal CostOfGoodsSold { get; set; }
        public decimal GrossProfit { get; set; }
        public decimal InternalUseExpenses { get; set; }
        public decimal OperatingExpenses { get; set; }
        public decimal PayrollExpenses { get; set; }
        public decimal TotalExpenses { get; set; }
        public decimal NetProfit { get; set; }
        public decimal ProfitMarginPct { get; set; }
        public int SalesCount { get; set; }
        public int InternalUseCount { get; set; }
    }

    // =========================================================================
    // Item Cost Reconciliation (migration 442)
    // =========================================================================
    public class GenericItemCostReconciliationModel
    {
        public string ProductName { get; set; } = string.Empty;
        public decimal TotalPurchasedQty { get; set; }
        public decimal TotalPurchasedCost { get; set; }
        public decimal TotalProducedQty { get; set; }
        public decimal TotalProducedCost { get; set; }
        public decimal SoldQty { get; set; }
        public decimal SoldCost { get; set; }
        public decimal InternalUseQty { get; set; }
        public decimal InternalUseCost { get; set; }
        public decimal ProductionConsumedQty { get; set; }
        public decimal ProductionConsumedCost { get; set; }
        public decimal AdjustmentQty { get; set; }
        public decimal RemainingQty { get; set; }
        public decimal RemainingCostBasis { get; set; }
        public bool CostReconciled { get; set; }
    }

    // =========================================================================
    // Phase 5 Reports (migration 443)
    // =========================================================================

    public class GenericInventoryBalanceRow
    {
        public int GenericProductId { get; set; }
        public string ProductName { get; set; } = string.Empty;
        public string? CategoryName { get; set; }
        public string? Purpose { get; set; }
        public string? UnitOfMeasure { get; set; }
        public decimal OpeningQty { get; set; }
        public decimal PurchasesQty { get; set; }
        public decimal ProductionInQty { get; set; }
        public decimal ReturnsInQty { get; set; }
        public decimal SalesQty { get; set; }
        public decimal InternalUseQty { get; set; }
        public decimal ProductionOutQty { get; set; }
        public decimal DamageQty { get; set; }
        public decimal AdjustmentQty { get; set; }
        public decimal OtherQty { get; set; }
        public decimal ClosingQty { get; set; }
        public decimal UnitCost { get; set; }
        public decimal InventoryValue { get; set; }
    }

    public class GenericConsumptionRow
    {
        public DateTime UsageDate { get; set; }
        public int GenericProductId { get; set; }
        public string ProductName { get; set; } = string.Empty;
        public string? CategoryName { get; set; }
        public decimal QuantityUsed { get; set; }
        public string? UnitOfMeasure { get; set; }
        public decimal UnitCost { get; set; }
        public decimal TotalCost { get; set; }
        public string? ExpenseCategory { get; set; }
        public string? Reason { get; set; }
        public string? ReferenceNumber { get; set; }
        public string? RecordedBy { get; set; }
        public string? Status { get; set; }
        public int GenericInternalUsageId { get; set; }
    }

    public class GenericConsumptionSummary
    {
        public decimal TotalConsumptionCost { get; set; }
        public int TotalItemsConsumed { get; set; }
        public int TotalRecords { get; set; }
        public string? TopItemName { get; set; }
        public decimal TopItemCost { get; set; }
        public string? CategoryBreakdown { get; set; } // JSON
    }

    public class GenericReconciliationRow
    {
        public int GenericProductId { get; set; }
        public string ProductName { get; set; } = string.Empty;
        public decimal LedgerTotal { get; set; }
        public decimal CachedStock { get; set; }
        public decimal Drift { get; set; }
        public bool IsReconciled { get; set; }
    }

    public class GenericRestockForecastRow
    {
        public int GenericProductId { get; set; }
        public string ProductName { get; set; } = string.Empty;
        public decimal CurrentStock { get; set; }
        public decimal MinimumStockAlert { get; set; }
        public string? UnitOfMeasure { get; set; }
        public decimal AvgDailySales { get; set; }
        public decimal AvgDailyInternalUse { get; set; }
        public decimal AvgDailyProduction { get; set; }
        public decimal AvgDailyOtherOut { get; set; }
        public decimal AvgDailyTotalOut { get; set; }
        public decimal DaysUntilStockout { get; set; }
        public decimal DaysUntilReorderPoint { get; set; }
        public decimal SuggestedReorderQty { get; set; }
        public string UrgencyLevel { get; set; } = "OK";
    }
}
