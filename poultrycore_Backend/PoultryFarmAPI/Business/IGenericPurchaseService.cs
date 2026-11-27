using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IGenericPurchaseService
    {
        Task<List<GenericPurchaseModel>> GetAllAsync(string farmId, string? status);
        Task<GenericPurchaseModel?> GetByIdAsync(int id, string farmId);
        Task<int> InsertAsync(string farmId, GenericPurchaseCreateRequest req, string? createdBy);

        Task UpdateAsync(int id, string farmId, GenericPurchaseCreateRequest req);
        Task ApproveAsync(int id, string farmId, string? approvedBy);
        Task CancelAsync(int id, string farmId, string? cancelledBy, string? reason);

        // 500: reversal (preview -> reverse -> record)
        Task<string> GetReversalPreviewAsync(int id, string farmId);
        Task<string?> GetReversalAsync(int id, string farmId);
        Task<int> ReverseAsync(int id, string farmId, GenericPurchaseReverseRequest req, string? reversedBy);
    }
}
