using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    /// <summary>
    /// Per-farm custom values for the Hotel dropdowns that offer "Other".
    /// Backed by hotelcustomoptions — see Migrations/300, which also records why
    /// these cannot live in the global hotel lookup tables.
    /// </summary>
    public interface IHotelCustomOptionService
    {
        string GetConnectionString();

        /// <summary>One list, e.g. listkey "MaintenanceAsset".</summary>
        Task<List<HotelCustomOptionModel>> ListAsync(string farmId, string listKey);

        /// <summary>Every list this farm has, for pages that render several dropdowns.</summary>
        Task<List<HotelCustomOptionModel>> ListAllAsync(string farmId);

        /// <summary>Idempotent: an existing value comes back rather than erroring.</summary>
        Task<HotelCustomOptionModel?> InsertAsync(string farmId, string listKey, string value, string? createdBy);

        /// <summary>Soft delete. Returns false when the row is absent or belongs to another farm.</summary>
        Task<bool> DeleteAsync(string farmId, int customOptionId);
    }
}
