using PoultryWeb.Models.Generic;

namespace PoultryWeb.Business.Generic
{
    public interface IGenericApiClient
    {
        // Foundation
        Task<List<BusinessCategoryVm>> GetBusinessCategoriesAsync();
        Task<GenericCompanyProfileVm?> GetProfileAsync();
        Task<GenericCompanyProfileVm?> SetupAsync(GenericCompanySetupRequestVm req);

        // Catalog
        Task<List<GenericProductVm>> GetProductsAsync();
        Task<List<GenericCashAccountVm>> GetCashAccountsAsync();

        // Customers + Suppliers
        Task<List<GenericCustomerVm>> GetCustomersAsync();
        Task<GenericCustomerVm?> CreateCustomerAsync(GenericCustomerVm m);
        Task<List<GenericSupplierVm>> GetSuppliersAsync();
        Task<GenericSupplierVm?> CreateSupplierAsync(GenericSupplierVm m);

        // Sales
        Task<List<GenericSaleVm>> GetSalesAsync(string? status);
        Task<GenericSaleVm?> GetSaleAsync(int id);
        Task<int> CreateSaleAsync(GenericSaleCreateVm req);
        Task ApproveSaleAsync(int id);
        Task CancelSaleAsync(int id, string? reason);

        // Purchases + Expenses (read-only in Part 1)
        Task<List<GenericPurchaseVm>> GetPurchasesAsync(string? status);
        Task ApprovePurchaseAsync(int id);
        Task<List<GenericExpenseVm>> GetExpensesAsync(string? status);
        Task ApproveExpenseAsync(int id);

        // Daily Closings
        Task<List<GenericDailyClosingVm>> GetDailyClosingsAsync();
        Task<int> CreateDailyClosingAsync(GenericDailyClosingCreateVm req);
        Task SubmitDailyClosingAsync(int id);
        Task ApproveDailyClosingAsync(int id);

        // Dashboard
        Task<GenericDashboardVm> GetDashboardAsync();
    }
}
