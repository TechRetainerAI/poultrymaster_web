using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IRestaurantSetupService
    {
        // Profile
        Task<RestaurantProfileModel?> GetProfileAsync(string farmId);
        Task<RestaurantProfileModel> UpsertProfileAsync(RestaurantProfileModel m);
    }
}
