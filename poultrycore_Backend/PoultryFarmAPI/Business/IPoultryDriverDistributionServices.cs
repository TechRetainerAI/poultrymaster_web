using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    // One service surface for the whole Poultry Driver Distribution module
    // (masters, vehicle loadings, driver returns + reconciliation, shortages,
    // delivery expenses and the two reports). SPs: migrations 139 + 140.
    public interface IPoultryDriverDistributionService
    {
        // ---- Drivers ----
        Task<List<PoultryDriverModel>> GetDriversAsync(string farmId);
        Task<PoultryDriverModel?> GetDriverAsync(int id, string farmId);
        Task<int> InsertDriverAsync(PoultryDriverModel m);
        Task UpdateDriverAsync(PoultryDriverModel m);
        Task DeleteDriverAsync(int id, string farmId);
        Task<List<PoultryDriverModel>> ListDriversForFarmAsync(string farmId);
        Task<PoultryDriverModel?> UpsertDriverForEmployeeAsync(PoultryDriverFromEmployeeRequest req);

        // ---- Vehicles ----
        Task<List<PoultryVehicleModel>> GetVehiclesAsync(string farmId);
        Task<PoultryVehicleModel?> GetVehicleAsync(int id, string farmId);
        Task<int> InsertVehicleAsync(PoultryVehicleModel m);
        Task UpdateVehicleAsync(PoultryVehicleModel m);
        Task DeleteVehicleAsync(int id, string farmId);

        // ---- Routes ----
        Task<List<PoultryRouteModel>> GetRoutesAsync(string farmId);
        Task<PoultryRouteModel?> GetRouteAsync(int id, string farmId);
        Task<int> InsertRouteAsync(PoultryRouteModel m);
        Task UpdateRouteAsync(PoultryRouteModel m);
        Task DeleteRouteAsync(int id, string farmId);

        // ---- Vehicle Loadings ----
        Task<List<PoultryVehicleLoadingModel>> GetLoadingsAsync(string farmId, string? status, DateTime? fromDate, DateTime? toDate);
        Task<PoultryVehicleLoadingModel?> GetLoadingAsync(int id, string farmId);
        Task<List<PoultryVehicleLoadingItemModel>> GetLoadingItemsAsync(int loadingId, string farmId);
        Task<int> InsertLoadingAsync(PoultryVehicleLoadingCreateRequest req);
        Task ApproveLoadingAsync(int id, string farmId, string? approvedBy);
        Task CancelLoadingAsync(int id, string farmId);
        Task VoidLoadingAsync(int id, string farmId);
        Task<int> ReloadLoadingAsync(int id, string farmId, string? createdBy);

        // ---- Driver Returns ----
        Task<List<PoultryDriverReturnModel>> GetReturnsAsync(string farmId, string? status, DateTime? fromDate, DateTime? toDate);
        Task<PoultryDriverReturnModel?> GetReturnAsync(int id, string farmId);
        Task<List<PoultryDriverReturnItemModel>> GetReturnItemsAsync(int returnId, string farmId);
        Task<List<PoultryDriverReturnCustomerSaleRow>> GetReturnCustomerSalesAsync(int returnId, string farmId);
        Task<List<PoultryDriverDeliveryExpenseModel>> GetReturnExpensesAsync(int returnId, string farmId);
        Task<int> InsertReturnAsync(PoultryDriverReturnCreateRequest req);
        Task ApproveReturnAsync(int id, string farmId, string? approvedBy);
        Task ApproveReconcileReturnAsync(PoultryDriverReturnCreateRequest req);
        Task CancelReturnAsync(int id, string farmId);
        Task UncancelReturnAsync(int id, string farmId);
        Task ReverseReturnAsync(int id, string farmId);
        Task DeleteReturnAsync(int id, string farmId);
        Task UpdateReturnPostingModeAsync(int id, string farmId, string salesPostingMode);

        // ---- Delivery Expenses ----
        Task<List<PoultryDriverDeliveryExpenseModel>> ListDeliveryExpensesAsync(string farmId, DateTime? fromDate, DateTime? toDate);

        // ---- Shortages ----
        Task<List<PoultryDriverShortageModel>> GetShortagesAsync(string farmId, string? status);
        Task ResolveShortageAsync(int id, PoultryDriverShortageResolveRequest req);

        // ---- Reports ----
        Task<List<PoultryDriverReconciliationRow>> GetDriverReconciliationAsync(string farmId, DateTime? fromDate, DateTime? toDate);
        Task<PoultryDriverCollectionReport> GetDriverCollectionAsync(string farmId, DateTime? fromDate, DateTime? toDate, int? poultryDriverId);
    }
}
