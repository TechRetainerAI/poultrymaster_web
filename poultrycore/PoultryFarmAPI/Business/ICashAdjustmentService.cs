using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface ICashAdjustmentService
    {
        Task<List<CashAdjustmentModel>> GetAllAsync(string farmId);
        Task<CashAdjustmentModel?> GetByIdAsync(int adjustmentId, string farmId);
        Task<int> InsertAsync(CashAdjustmentModel model);
        Task UpdateAsync(CashAdjustmentModel model);
        Task DeleteAsync(int adjustmentId, string farmId);
    }
}
