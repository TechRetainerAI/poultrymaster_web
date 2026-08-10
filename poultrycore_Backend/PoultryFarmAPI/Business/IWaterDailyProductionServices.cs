using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    // Water Daily Production (migration 193) — the day-level production record
    // that allocates across machines and posts into real WaterProductionBatches.
    public interface IWaterDailyProductionService
    {
        Task<List<WaterDailyProductionModel>> GetAllAsync(string farmId, string? status, DateTime? fromDate, DateTime? toDate);
        Task<WaterDailyProductionModel?> GetByIdAsync(int id, string farmId);
        Task<int> InsertAsync(WaterDailyProductionModel m);
        Task UpdateAsync(WaterDailyProductionModel m);
        Task DeleteAsync(int id, string farmId, string? userId);
        Task SetStatusAsync(int id, string farmId, string status, string? updatedBy);
        Task SaveAllocationAsync(int id, string farmId, string? updatedBy, string? status,
                                 List<WaterDailyProductionAllocationModel> allocations);
        Task DeleteAllocationAsync(int id, string farmId, string? updatedBy);
        Task PostAsync(int id, string farmId, string? postedBy);
        Task ReverseAsync(int id, string farmId, string? reversedBy);
    }
}
