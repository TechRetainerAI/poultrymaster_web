using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface ISaleService
    {
        Task<int> Insert(SaleModel model);
        Task Update(SaleModel model);
        Task<SaleModel?> GetById(int saleId, string userId, string farmId);
        Task<List<SaleModel>> GetAll(string userId, string farmId);
        Task Delete(int saleId, string userId, string farmId);

        // Optional
        Task<List<SaleModel>> GetByFlock(int flockId, string userId, string farmId);

        /// <summary>One sale entry of several egg classes / products (migration 343), atomically.</summary>
        Task<SaleGroupResult> CreateGroup(SaleGroupRequest request);
        Task<string> EnsureGroup(int saleId, string farmId, string? userId);

        // 351: a posted sale is reversed, never edited or deleted.
        Task<string> GetReversalPreview(int saleId, string farmId);
        Task<string?> GetReversal(int saleId, string farmId);
        Task<int> Reverse(int saleId, SaleReverseRequest request);
        Task LinkCorrectionAsync(string farmId, int newSaleId, int correctsSaleId, string? by);
    }

}
