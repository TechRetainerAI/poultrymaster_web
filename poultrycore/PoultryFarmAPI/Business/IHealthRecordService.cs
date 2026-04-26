using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IHealthRecordService
    {
        Task<int> Insert(HealthRecordModel model);
        Task Update(HealthRecordModel model);
        Task<HealthRecordModel?> GetById(int id, string userId, string farmId);
        Task<List<HealthRecordModel>> GetAll(string userId, string farmId, int? flockId = null, int? houseId = null, int? itemId = null);
        Task Delete(int id, string userId, string farmId);
    }
}
