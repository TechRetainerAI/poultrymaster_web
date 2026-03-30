using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface ISaleService
    {
        Task<int> Insert(SaleModel model);
        Task Update(SaleModel model);
        Task<SaleModel?> GetById(int saleId, string userId, string farmId);
        Task<List<SaleModel>> GetAll(string userId, string farmId);
        Task Delete(int saleId, string userId, string farmId);

        // Optional
        Task<List<SaleModel>> GetByFlock(int flockId, string userId, string farmId);
    }

}
