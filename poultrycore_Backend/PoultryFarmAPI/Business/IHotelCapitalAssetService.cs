using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IHotelCapitalAssetService
    {
        Task<List<HotelAssetCategoryModel>> GetCategoriesAsync(string farmId);
        Task<int> UpsertCategoryAsync(string farmId, HotelAssetCategoryModel m);
        Task<List<HotelCapitalAssetModel>> GetAllAsync(string farmId, string? status, int? categoryId);
        Task<HotelCapitalAssetModel?> GetByIdAsync(int id, string farmId);
        Task<HotelCapitalAssetSummaryModel> GetSummaryAsync(string farmId);
        Task<int> CreateAsync(HotelCapitalAssetCreateRequest req, string? createdBy);
        Task UpdateAsync(int id, HotelCapitalAssetUpdateRequest req);
        Task ActivateAsync(int id, string farmId);
        Task<int> AddCostAsync(int assetId, string farmId, decimal amount, string? description, DateTime? costDate, string? createdBy);
        Task ReverseCostAsync(int costId, int assetId, string farmId, string? reason, string? by);
        Task DisposeAsync(int id, string farmId, DateTime? disposalDate, string? reason, string? by);
        Task ReverseAsync(int id, string farmId, string? reason, string? by);
        Task<List<HotelCapitalAssetCostModel>> GetCostsAsync(int assetId, string farmId);
        Task<List<HotelAssetDepreciationModel>> GetDepreciationAsync(string farmId, int? assetId);
        Task<HotelDepreciationRunResult> GenerateDepreciationAsync(string farmId, DateTime? throughDate, int? assetId, string? createdBy);
        Task ReverseDepreciationAsync(int entryId, string farmId, string? reason, string? by);
    }
}
