using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IFeedInventoryAdjustmentService
    {
        Task<List<FeedInventoryAdjustmentModel>> GetAllAsync(string farmId);
        Task<FeedInventoryAdjustmentModel?> GetByIdAsync(int adjustmentId, string farmId);
        Task<int> InsertAsync(FeedInventoryAdjustmentModel model);
        Task UpdateAsync(FeedInventoryAdjustmentModel model);
        Task DeleteAsync(int adjustmentId, string farmId);
    }
}
