using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IGenericCompanyService
    {
        // Platform-wide lookup
        Task<List<BusinessCategoryModel>> GetBusinessCategoriesAsync();

        // Profile + setup
        Task<GenericCompanyProfileModel?> SetupAsync(GenericCompanySetupRequest req);
        Task<GenericCompanyProfileModel?> GetProfileAsync(string farmId);
        Task<GenericCompanyProfileModel?> UpdateProfileAsync(string farmId, GenericCompanyUpdateRequest req);

        // Per-Farm seed/CRUD - expense categories
        Task<List<GenericExpenseCategoryModel>> GetExpenseCategoriesAsync(string farmId);
        Task<int> InsertExpenseCategoryAsync(GenericExpenseCategoryModel m);
        Task UpdateExpenseCategoryAsync(GenericExpenseCategoryModel m);
        Task DeleteExpenseCategoryAsync(int id, string farmId);

        // Per-Farm seed/CRUD - cash accounts
        Task<List<GenericCashAccountModel>> GetCashAccountsAsync(string farmId);
        Task<int> InsertCashAccountAsync(GenericCashAccountModel m);
        Task UpdateCashAccountAsync(GenericCashAccountModel m);
        Task DeleteCashAccountAsync(int id, string farmId);

        // Read-only for Phase 1
        Task<List<GenericCustomerTypeModel>> GetCustomerTypesAsync(string farmId);
        Task<List<GenericSupplierTypeModel>> GetSupplierTypesAsync(string farmId);
        Task<List<GenericPaymentMethodModel>> GetPaymentMethodsAsync(string farmId);

        // Used by the controller's company-scope check.
        Task<string?> GetFarmTypeAsync(string farmId);
    }
}
