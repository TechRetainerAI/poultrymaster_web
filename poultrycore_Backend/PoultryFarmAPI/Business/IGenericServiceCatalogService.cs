using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    // Named "ServiceCatalog" rather than "Service" to avoid the awkward
    // GenericServiceService class name.
    public interface IGenericServiceCatalogService
    {
        Task<List<GenericServiceCategoryModel>> GetCategoriesAsync(string farmId);
        Task<int>  InsertCategoryAsync(GenericServiceCategoryModel m);
        Task UpdateCategoryAsync(GenericServiceCategoryModel m);
        Task DeleteCategoryAsync(int id, string farmId);

        Task<List<GenericServiceModel>> GetAllAsync(string farmId);
        Task<GenericServiceModel?> GetByIdAsync(int id, string farmId);
        Task<int>  InsertAsync(GenericServiceModel m);
        Task UpdateAsync(GenericServiceModel m);
        Task DeleteAsync(int id, string farmId);
        Task ArchiveAsync(int id, string farmId, string? archivedBy);
        Task SetActiveAsync(int id, string farmId, bool isActive, string? updatedBy);
        Task<bool> HasPostedSalesAsync(int id, string farmId);
    }
}
