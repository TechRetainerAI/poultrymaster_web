using PoultryWeb.Models;

namespace PoultryWeb.Business
{
    public interface ISaleWebApiService
    {
        Task<List<SaleModel>> GetAllAsync();
        Task<SaleModel?> GetByIdAsync(int saleId);
        Task<SaleModel?> CreateAsync(SaleModel model);
        Task UpdateAsync(int saleId, SaleModel model);
        Task DeleteAsync(int saleId);

        // Optional, if using ByFlock
        Task<List<SaleModel>> GetByFlockAsync(int flockId);
    }
}
