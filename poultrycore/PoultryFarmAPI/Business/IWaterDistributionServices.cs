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
    }

    public interface IWaterDriverReturnService
    {
        Task<List<WaterDriverReturnModel>> GetAllAsync(string farmId, string? status, DateTime? fromDate, DateTime? toDate);
        Task<WaterDriverReturnModel?> GetByIdAsync(int id, string farmId);
        Task<int> InsertAsync(WaterDriverReturnModel m);
        Task ApproveAsync(int id, string farmId, string? approvedBy);
        Task CancelAsync(int id, string farmId);
    }

    public interface IWaterDriverShortageService
    {
        Task<List<WaterDriverShortageModel>> GetAllAsync(string farmId, string? status);
        Task ResolveAsync(int id, string farmId, string newStatus, string? reason, string? approvedBy);
    }
}
