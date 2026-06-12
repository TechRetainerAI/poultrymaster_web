using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IEggInventoryAdjustmentService
    {
        Task<List<EggInventoryAdjustmentModel>> GetAllAsync(string farmId);
        Task<EggInventoryAdjustmentModel?> GetByIdAsync(int adjustmentId, string farmId);
        Task<int> InsertAsync(EggInventoryAdjustmentModel model);
        Task UpdateAsync(EggInventoryAdjustmentModel model);
        Task DeleteAsync(int adjustmentId, string farmId);
    }
}
