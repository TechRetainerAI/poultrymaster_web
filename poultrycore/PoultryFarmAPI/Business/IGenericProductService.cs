using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IGenericProductService
    {
        // Product categories
        Task<List<GenericProductCategoryModel>> GetCategoriesAsync(string farmId);
        Task<int> InsertCategoryAsync(GenericProductCategoryModel m);
        Task UpdateCategoryAsync(GenericProductCategoryModel m);
        Task DeleteCategoryAsync(int id, string farmId);

        // Products
        Task<List<GenericProductModel>> GetAllAsync(string farmId);
        Task<GenericProductModel?> GetByIdAsync(int id, string farmId);
        Task<int> InsertAsync(GenericProductModel m);
        Task UpdateAsync(GenericProductModel m);
        Task DeleteAsync(int id, string farmId);

        // Inventory reports
        Task<List<GenericProductLowStockRowModel>> GetLowStockAsync(string farmId);
        Task ReconcileStockAsync(string farmId);
    }
}
