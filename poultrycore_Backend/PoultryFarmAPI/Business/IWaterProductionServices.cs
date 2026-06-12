using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IWaterBoreholeService
    {
        Task<List<WaterBoreholeModel>> GetAllAsync(string farmId);
        Task<WaterBoreholeModel?> GetByIdAsync(int id, string farmId);
        Task<int> InsertAsync(WaterBoreholeModel m);
        Task UpdateAsync(WaterBoreholeModel m);
        Task DeleteAsync(int id, string farmId);
    }

    public interface IWaterMachineService
    {
        Task<List<WaterMachineModel>> GetAllAsync(string farmId);
        Task<WaterMachineModel?> GetByIdAsync(int id, string farmId);
        Task<int> InsertAsync(WaterMachineModel m);
        Task UpdateAsync(WaterMachineModel m);
        Task DeleteAsync(int id, string farmId);
    }

    public interface IWaterProductionBatchService
    {
        Task<List<WaterProductionBatchModel>> GetAllAsync(string farmId, string? status, DateTime? fromDate, DateTime? toDate);
        Task<WaterProductionBatchModel?> GetByIdAsync(int id, string farmId);
        Task<int> InsertAsync(WaterProductionBatchModel m);
        Task UpdateAsync(WaterProductionBatchModel m);
        Task ApproveAsync(int id, string farmId, string? approvedBy);
        Task CancelAsync(int id, string farmId);
        Task ReopenAsync(int id, string farmId, string? reopenedBy);
        Task<List<WaterProductionMaterialUsageRow>> GetMaterialsUsedAsync(int batchId, string farmId);

        // Migration 067: read-side helpers used by the Details view.
        Task<List<WaterProductionLossModel>>          GetLinkedLossesAsync(int batchId, string farmId);
        Task<List<WaterProductionLinkedExpenseRow>>   GetLinkedExpensesAsync(int batchId, string farmId);
        Task<List<WaterProductionLinkedStockTxnRow>>  GetLinkedStockTxnsAsync(int batchId, string farmId);
    }

    // Migration 067: stand-alone loss list (Loss page).
    public interface IWaterProductionLossService
    {
        Task<List<WaterProductionLossModel>> GetAllAsync(string farmId, DateTime? fromDate, DateTime? toDate, string? status);
    }

    public interface IWaterProductionRecipeService
    {
        Task<WaterProductionRecipeModel?> GetByProductAsync(string farmId, int waterProductId);
        Task<int> UpsertAsync(string farmId, int waterProductId, WaterProductionRecipeUpsertRequest req, string? updatedBy);
        Task DeleteAsync(string farmId, int recipeId);
        Task<List<WaterProductionMaterialUsageRow>> GetUsageHistoryAsync(string farmId, int? rawMaterialItemId, DateTime? fromDate, DateTime? toDate);
    }

    public interface IWaterQualityTestService
    {
        Task<List<WaterQualityTestModel>> GetAllAsync(string farmId, int? boreholeId, int? batchId);
        Task<int> InsertAsync(WaterQualityTestModel m);
    }

    public interface IWaterDailyPumpingLogService
    {
        Task<List<WaterDailyPumpingLogModel>> GetAllAsync(string farmId, DateTime? fromDate, DateTime? toDate);
        Task<int> InsertAsync(WaterDailyPumpingLogModel m);
    }
}
