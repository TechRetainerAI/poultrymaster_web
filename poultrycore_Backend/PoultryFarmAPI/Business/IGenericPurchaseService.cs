using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IGenericPurchaseService
    {
        Task<List<GenericPurchaseModel>> GetAllAsync(string farmId, string? status);
        Task<GenericPurchaseModel?> GetByIdAsync(int id, string farmId);
        Task<int> InsertAsync(string farmId, GenericPurchaseCreateRequest req, string? createdBy);

        Task ApproveAsync(int id, string farmId, string? approvedBy);
        Task CancelAsync(int id, string farmId, string? cancelledBy, string? reason);
    }
}
