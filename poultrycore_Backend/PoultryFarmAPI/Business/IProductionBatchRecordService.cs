using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IProductionBatchRecordService
    {
        Task<int> Insert(ProductionBatchRecordModel model);
        Task Update(ProductionBatchRecordModel model);
        Task<ProductionBatchRecordModel?> GetById(int id, string farmId);
        Task<List<ProductionBatchRecordModel>> GetAll(string userId, string farmId);
        Task Delete(int id, string userId, string farmId);
        Task SetStatus(int id, string farmId, string status, string? updatedBy);
        Task SaveAllocation(int id, string farmId, string? updatedBy, string? status, List<ProductionBatchAllocationModel> allocations);
        Task Post(int id, string farmId, string postedBy);
        Task Reverse(int id, string farmId, string reversedBy);
    }
}
