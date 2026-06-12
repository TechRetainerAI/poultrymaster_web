// Generic Company UI view models.
// These are deliberately POCO copies of the PoultryFarmAPI DTOs - PoultryWeb
// is a standalone project that doesn't reference PoultryFarmAPI, so models
// are duplicated here at the API boundary. Property names match the API
// JSON shape; System.Text.Json default web options (case-insensitive) handle
// the camelCase JSON the API emits.

using System.ComponentModel.DataAnnotations;

namespace PoultryWeb.Models.Generic
{
    // =========================================================================
    // Foundation
    // =========================================================================
    public class BusinessCategoryVm
    {
        public int BusinessCategoryId { get; set; }
        public string Name { get; set; } = string.Empty;
        public string? Description { get; set; }
        public int SortOrder { get; set; }
        public bool IsActive { get; set; }
    }

    public class GenericCompanyProfileVm
    {
        public int GenericCompanyProfileId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public int? BusinessCategoryId { get; set; }
        public string? BusinessCategoryNameSnapshot { get; set; }
        public string? BusinessCategoryName { get; set; }
        public string? BusinessDescription { get; set; }
        public string DefaultCurrency { get; set; } = "GHC";
        public decimal OpeningCashBalance { get; set; }
        public DateTime? BusinessStartDate { get; set; }
        public string? MainLocation { get; set; }
        public string? OwnerName { get; set; }
        public string? PhoneNumber { get; set; }
        public string? Notes { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    public class GenericCompanySetupRequestVm
    {
        [Required]
        public string FarmId { get; set; } = string.Empty;
        public int? BusinessCategoryId { get; set; }
        public string? BusinessDescription { get; set; }
        public string? DefaultCurrency { get; set; } = "GHC";
        [Range(0, double.MaxValue)]
        public decimal? OpeningCashBalance { get; set; }
        public DateTime? BusinessStartDate { get; set; }
        public string? MainLocation { get; set; }
        public string? OwnerName { get; set; }
        public string? PhoneNumber { get; set; }
        public string? Notes { get; set; }
    }

    public class GenericCashAccountVm
    {
        public int GenericCashAccountId { get; set; }
        public string AccountName { get; set; } = string.Empty;
        public string AccountType { get; set; } = string.Empty;
        public decimal OpeningBalance { get; set; }
        public decimal CurrentBalance { get; set; }
        public bool AllowNegativeBalance { get; set; }
        public bool IsActive { get; set; }
        public string? Notes { get; set; }
    }

    // =========================================================================
    // Catalog (Phase 2)
    // =========================================================================
    public class GenericProductVm
    {
        public int GenericProductId { get; set; }
        public int? GenericProductCategoryId { get; set; }
        public string? CategoryName { get; set; }
        public string ProductName { get; set; } = string.Empty;
        public string? SKU { get; set; }
        public string? Barcode { get; set; }
        public string? UnitOfMeasure { get; set; }
        public decimal CostPrice { get; set; }
        public decimal SellingPrice { get; set; }
        public decimal? WholesalePrice { get; set; }
        public decimal? RetailPrice { get; set; }
        public decimal OpeningStock { get; set; }
        public decimal CurrentStock { get; set; }
        public decimal MinimumStockAlert { get; set; }
        public bool TrackInventory { get; set; }
        public bool IsActive { get; set; }
        public string? Notes { get; set; }

        public bool IsLowStock => TrackInventory && CurrentStock <= MinimumStockAlert;
    }

    // =========================================================================
    // Customers + Suppliers
    // =========================================================================
    public class GenericCustomerVm
    {
        public int GenericCustomerId { get; set; }

        [Required]
        public string CustomerName { get; set; } = string.Empty;
        public string CustomerType { get; set; } = "Individual";
        public string? PhoneNumber { get; set; }
        public string? Email { get; set; }
        public string? Location { get; set; }
        public string? Address { get; set; }
        public decimal CreditLimit { get; set; }
        public int PaymentTermsDays { get; set; }
        public decimal OpeningBalance { get; set; }
        public decimal CurrentBalance { get; set; }
        public bool IsActive { get; set; } = true;
        public string? Notes { get; set; }

        public bool IsOverLimit => CreditLimit > 0 && CurrentBalance > CreditLimit;
    }

    public class GenericSupplierVm
    {
        public int GenericSupplierId { get; set; }

        [Required]
        public string SupplierName { get; set; } = string.Empty;
        public string SupplierType { get; set; } = "ProductSupplier";
        public string? PhoneNumber { get; set; }
        public string? Email { get; set; }
        public string? Location { get; set; }
        public string? Address { get; set; }
        public int PaymentTermsDays { get; set; }
        public decimal OpeningBalance { get; set; }
        public decimal CurrentBalance { get; set; }
        public bool IsActive { get; set; } = true;
        public string? Notes { get; set; }
    }

    // =========================================================================
    // Sales (Phase 3)
    // =========================================================================
    public class GenericSaleItemVm
    {
        public int GenericSaleItemId { get; set; }
        public string ItemType { get; set; } = "Product";
        public int? GenericProductId { get; set; }
        public int? GenericServiceId { get; set; }
        public string? Description { get; set; }
        public decimal Quantity { get; set; }
        public decimal UnitPrice { get; set; }
        public decimal DiscountAmount { get; set; }
        public decimal LineTotal { get; set; }
        public string? Notes { get; set; }
    }

    public class GenericSaleVm
    {
        public int GenericSaleId { get; set; }
        public DateTime SaleDate { get; set; }
        public int? GenericCustomerId { get; set; }
        public string? CustomerName { get; set; }
        public string SalesType { get; set; } = "WalkInSale";
        public string? SalesChannel { get; set; }
        public decimal SubtotalAmount { get; set; }
        public decimal DiscountAmount { get; set; }
        public decimal TaxAmount { get; set; }
        public decimal TotalAmount { get; set; }
        public decimal AmountPaid { get; set; }
        public decimal Balance { get; set; }
        public string PaymentStatus { get; set; } = "Unpaid";
        public string? PaymentMethod { get; set; }
        public int? GenericCashAccountId { get; set; }
        public string? ReceiptNumber { get; set; }
        public string Status { get; set; } = "Draft";
        public string? Notes { get; set; }
        public DateTime CreatedAt { get; set; }
        public List<GenericSaleItemVm> Items { get; set; } = new();
    }

    public class GenericSaleCreateVm
    {
        public DateTime? SaleDate { get; set; }
        public int? GenericCustomerId { get; set; }

        [Required]
        public string SalesType { get; set; } = "WalkInSale";
        public string? SalesChannel { get; set; }

        [Range(0, double.MaxValue)]
        public decimal HeaderDiscountAmount { get; set; }

        [Range(0, double.MaxValue)]
        public decimal TaxAmount { get; set; }

        [Range(0, double.MaxValue)]
        public decimal AmountPaid { get; set; }

        public string? PaymentMethod { get; set; }
        public int? GenericCashAccountId { get; set; }
        public string? ReceiptNumber { get; set; }
        public string? Notes { get; set; }

        public List<GenericSaleItemVm> Items { get; set; } = new();
    }

    // =========================================================================
    // Purchases + Expenses (Phase 4)
    // =========================================================================
    public class GenericPurchaseVm
    {
        public int GenericPurchaseId { get; set; }
        public int? GenericSupplierId { get; set; }
        public string? SupplierName { get; set; }
        public DateTime PurchaseDate { get; set; }
        public decimal SubtotalAmount { get; set; }
        public decimal DiscountAmount { get; set; }
        public decimal TaxAmount { get; set; }
        public decimal TotalAmount { get; set; }
        public decimal AmountPaid { get; set; }
        public decimal Balance { get; set; }
        public string PaymentStatus { get; set; } = "Unpaid";
        public string? PaymentMethod { get; set; }
        public string? InvoiceNumber { get; set; }
        public string Status { get; set; } = "Draft";
        public string? Notes { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    public class GenericExpenseVm
    {
        public int GenericExpenseId { get; set; }
        public DateTime ExpenseDate { get; set; }
        public int GenericExpenseCategoryId { get; set; }
        public string? CategoryName { get; set; }
        public int? GenericSupplierId { get; set; }
        public string? SupplierName { get; set; }
        public string? Description { get; set; }
        public decimal Amount { get; set; }
        public string? PaidTo { get; set; }
        public string PaymentMethod { get; set; } = "Cash";
        public string Status { get; set; } = "Draft";
        public string? Notes { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    // =========================================================================
    // Daily Closing (Phase 5)
    // =========================================================================
    public class GenericDailyClosingVm
    {
        public int GenericDailyClosingId { get; set; }
        public DateTime ClosingDate { get; set; }
        public decimal OpeningCash { get; set; }
        public decimal TotalSales { get; set; }
        public decimal TotalExpenses { get; set; }
        public decimal TotalCustomerPayments { get; set; }
        public decimal TotalSupplierPayments { get; set; }
        public decimal TotalPurchasesPaid { get; set; }
        public decimal TotalCashIn { get; set; }
        public decimal TotalCashOut { get; set; }
        public decimal ExpectedCash { get; set; }
        public decimal ActualCashCounted { get; set; }
        public decimal CashDifference { get; set; }
        public decimal CreditSales { get; set; }
        public decimal CustomerDebtTotal { get; set; }
        public decimal SupplierDebtTotal { get; set; }
        public int InventoryAdjustmentsCount { get; set; }
        public string? ManagerNotes { get; set; }
        public string? DifferenceReason { get; set; }
        public string Status { get; set; } = "Draft";
        public DateTime CreatedAt { get; set; }
    }

    public class GenericDailyClosingCreateVm
    {
        [Required]
        public DateTime ClosingDate { get; set; } = DateTime.Today;
        public decimal? OpeningCash { get; set; }

        [Range(0, double.MaxValue)]
        public decimal ActualCashCounted { get; set; }

        public string? ManagerNotes { get; set; }
        public string? DifferenceReason { get; set; }
    }

    // =========================================================================
    // Dashboard
    // =========================================================================
    public class GenericDashboardVm
    {
        public GenericDashboardTodayVm Today { get; set; } = new();
        public GenericDashboardWeekVm Week { get; set; } = new();
        public List<GenericDashboardCashAccountVm> CashAccounts { get; set; } = new();
        public GenericDashboardAlertsVm Alerts { get; set; } = new();
    }

    public class GenericDashboardTodayVm
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

    public class GenericDashboardWeekVm
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

    public class GenericDashboardCashAccountVm
    {
        public int GenericCashAccountId { get; set; }
        public string AccountName { get; set; } = string.Empty;
        public string AccountType { get; set; } = string.Empty;
        public decimal CurrentBalance { get; set; }
        public bool IsActive { get; set; }
    }

    public class GenericDashboardAlertsVm
    {
        public int LowStockCount { get; set; }
        public int DraftSalesCount { get; set; }
        public int DraftExpensesCount { get; set; }
        public int CustomersOwingCount { get; set; }
        public int SuppliersOwedCount { get; set; }
        public int PendingClosingsCount { get; set; }
    }
}
