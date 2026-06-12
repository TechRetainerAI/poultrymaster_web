using PoultryFarmAPIWeb.Models;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace PoultryFarmAPIWeb.Business
{
    public interface IBirdFlockService
    {
        Task<int> CreateFlock(FlockModel model);
        Task UpdateFlock(FlockModel model);
        FlockModel GetFlockById(int flockId, string userId, string farmId);
        List<FlockModel> GetAllFlocks(string userId, string farmId);
        Task DeleteFlock(int flockId, string userId, string farmId);
        Task<int> GetTotalFlockQuantityForBatch(int batchId, string userId, string farmId, int? flockIdToExclude = null);
    }
}
