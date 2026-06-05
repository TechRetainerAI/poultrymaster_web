using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IWaterDriverService
    {
        Task<List<WaterDriverModel>> GetAllAsync(string farmId);
        Task<WaterDriverModel?> GetByIdAsync(int id, string farmId);
        Task<int> InsertAsync(WaterDriverModel m);
        Task UpdateAsync(WaterDriverModel m);
        Task DeleteAsync(int id, string farmId);
    }

    public interface IWaterVehicleService
    {
        Task<List<WaterVehicleModel>> GetAllAsync(string farmId);
        Task<WaterVehicleModel?> GetByIdAsync(int id, string farmId);
        Task<int> InsertAsync(WaterVehicleModel m);
        Task UpdateAsync(WaterVehicleModel m);
        Task DeleteAsync(int id, string farmId);
    }

    public interface IWaterRouteService
    {
        Task<List<WaterRouteModel>> GetAllAsync(string farmId);
        Task<WaterRouteModel?> GetByIdAsync(int id, string farmId);
        Task<int> InsertAsync(WaterRouteModel m);
        Task UpdateAsync(WaterRouteModel m);
        Task DeleteAsync(int id, string farmId);
    }

    public interface IWaterVehicleLoadingService
    {
        Task<List<WaterVehicleLoadingModel>> GetAllAsync(string farmId, string? status, DateTime? fromDate, DateTime? toDate);
        Task<WaterVehicleLoadingModel?> GetByIdAsync(int id, string farmId);
        Task<int> InsertAsync(WaterVehicleLoadingModel m);
        Task ApproveAsync(int id, string farmId, string? approvedBy);
        Task CancelAsync(int id, string farmId);
        // Migration 064: multi-product loadings
        Task<List<WaterVehicleLoadingItemModel>> GetItemsAsync(int loadingId, string farmId);
        // Migration 065: void Draft or Loaded loadings (reverses stock for Loaded)
        Task VoidAsync(int id, string farmId, string? voidedBy, string? reason);
        // Migration 068: Reload / Edit Load (reverses old + applies new in one txn)
        Task ReloadAsync(int id, WaterVehicleLoadingReloadInput input, string farmId, string? updatedBy);
    }

    public interface IWaterDriverReturnService
    {
        Task<List<WaterDriverReturnModel>> GetAllAsync(string farmId, string? status, DateTime? fromDate, DateTime? toDate);
        Task<WaterDriverReturnModel?> GetByIdAsync(int id, string farmId);
        Task<int> InsertAsync(WaterDriverReturnModel m);
        Task ApproveAsync(int id, string farmId, string? approvedBy);
        Task CancelAsync(int id, string farmId);
        // Migration 071: Uncancel (Cancelled → Draft) so it can be re-reconciled.
        Task UncancelAsync(int id, string farmId);
        // Migration 072: admin-only hard delete of a Cancelled return.
        Task DeleteAsync(int id, string farmId);
        // Migration 064: per-product reconciliation + customer breakdown + expenses
        Task<List<WaterDriverReturnItemModel>> GetItemsAsync(int returnId, string farmId);
        Task<List<WaterDriverReturnCustomerSaleRow>> GetCustomerSalesAsync(int returnId, string farmId);
        Task<List<WaterDeliveryExpenseModel>> GetExpensesAsync(int returnId, string farmId);
        // Migration 085 — unified Expenses ledger: list ALL delivery expenses
        // on a farm (with optional date range) so /water-expenses can show
        // them alongside the regular WaterExpenses ledger.
        Task<List<WaterDeliveryExpenseModel>> ListAllDeliveryExpensesAsync(string farmId, DateTime? fromDate, DateTime? toDate);
        // Migration 068: Reverse Reconciliation (unwind sales/payments/stock)
        Task ReverseAsync(int id, string farmId, string? reversedBy, string? reason);
        // Migration 083: validate + approve in one shot using the row's
        // SalesPostingMode (defaults to 'Detailed' for legacy drafts).
        Task ApproveReconcileAsync(int id, string farmId, string? approvedBy);
        // Migration 083: set posting mode + primary customer on a Draft return.
        Task UpdatePostingModeAsync(int id, string farmId, string salesPostingMode, int? primaryCustomerId);
    }

    public interface IWaterDriverShortageService
    {
        Task<List<WaterDriverShortageModel>> GetAllAsync(string farmId, string? status);
        Task ResolveAsync(int id, string farmId, string newStatus, string? reason, string? approvedBy);
    }
}
