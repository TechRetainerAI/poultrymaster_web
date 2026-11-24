using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IGenericSaleService
    {
        Task<List<GenericSaleModel>> GetAllAsync(string farmId, string? status);
        Task<GenericSaleModel?> GetByIdAsync(int id, string farmId);
        Task<int> InsertAsync(string farmId, GenericSaleCreateRequest req, string? createdBy);

        Task ApproveAsync(int id, string farmId, string? approvedBy);
        Task CancelAsync(int id, string farmId, string? cancelledBy, string? reason);
        Task RefundAsync(int id, string farmId, string? refundedBy, string? reason);
        // 483: the sale reversal model (Poultry 351 / Water 458)
        Task<string> GetReversalPreviewAsync(int id, string farmId);
        Task<string?> GetReversalAsync(int id, string farmId);
        Task<int> ReverseAsync(int id, string farmId, SaleReverseRequest req, string? reversedBy);
    }
}
