using PoultryWeb.Models;

namespace PoultryWeb.Business
{
    public interface IProductionRecordWebApiService
    {
        Task<List<ProductionRecordViewModel>> GetAllAsync();
        Task<ProductionRecordViewModel?> GetByIdAsync(int id);
        Task<ProductionRecordViewModel?> CreateAsync(ProductionRecordViewModel model);
        Task UpdateAsync(int id, ProductionRecordViewModel model);
        Task DeleteAsync(int id);
    }
}
