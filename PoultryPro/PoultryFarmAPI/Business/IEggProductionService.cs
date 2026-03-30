using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IEggProductionService
    {
        Task<int> Insert(EggProductionModel model);
        Task Update(EggProductionModel model);
        Task<EggProductionModel?> GetById(int productionId, string userId, string farmId);
        Task<List<EggProductionModel>> GetAll(string userId, string farmId);
        Task<List<EggProductionModel>> GetByFlockId(int flockId, string userId, string farmId);
        Task Delete(int productionId, string userId, string farmId);
    }

}
