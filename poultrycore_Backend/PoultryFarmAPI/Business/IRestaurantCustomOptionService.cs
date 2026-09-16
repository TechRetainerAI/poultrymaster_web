using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    /// <summary>
    /// Per-farm custom values for the Restaurant dropdowns that offer "Other".
    /// Backed by restaurantcustomoptions — see Migrations/291.
    /// </summary>
    public interface IRestaurantCustomOptionService
    {
        string GetConnectionString();

        /// <summary>One list, e.g. listkey "WasteReason".</summary>
        Task<List<RestaurantCustomOptionModel>> ListAsync(string farmId, string listKey);

        /// <summary>Every list this farm has, for pages that render several dropdowns.</summary>
        Task<List<RestaurantCustomOptionModel>> ListAllAsync(string farmId);

        /// <summary>Idempotent: an existing value comes back rather than erroring.</summary>
        Task<RestaurantCustomOptionModel?> InsertAsync(string farmId, string listKey, string value, string? createdBy);

        /// <summary>Soft delete. Returns false when the row is absent or belongs to another farm.</summary>
        Task<bool> DeleteAsync(string farmId, int customOptionId);
    }
}
