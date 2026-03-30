using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IProductionRecordService
    {
        Task<int> Insert(ProductionRecordModel model);
        Task Update(ProductionRecordModel model);
        Task<ProductionRecordModel?> GetById(int recordId, string userId, string farmId);
        Task<List<ProductionRecordModel>> GetAll(string userId, string farmId);
        Task Delete(int recordId, string userId, string farmId);
    }
}
