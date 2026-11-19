using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IGenericProductionRecordService
    {
        Task<List<GenericProductionRecordModel>> GetAllAsync(string farmId, string? status = null);
        Task<int> InsertAsync(GenericProductionRecordModel model);
        Task ReverseAsync(int id, string farmId, string reason, string? reversedBy);
    }
}
