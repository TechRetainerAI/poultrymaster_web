using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IRestaurantKdsService
    {
        // Stations
        Task<List<RestaurantKdsStationModel>> ListStationsAsync(string farmId);
        Task<int> InsertStationAsync(RestaurantKdsStationModel m);
        Task UpdateStationAsync(RestaurantKdsStationModel m);
        Task DeleteStationAsync(int id, string farmId);

        // Station-Item mappings
        Task<List<RestaurantKdsStationItemModel>> ListStationItemsAsync(int stationId, string farmId);
        Task<int> AssignItemToStationAsync(string farmId, int stationId, int menuItemId);
        Task UnassignItemFromStationAsync(int id, string farmId);
        Task SetItemStationAsync(string farmId, int menuItemId, int stationId);

        // KDS Queue
        Task<List<KdsQueueItemModel>> GetQueueAsync(string farmId, int? stationId = null, bool isExpo = false);
        Task<string> BumpItemAsync(int orderItemId, string farmId);
        Task<string> RecallItemAsync(int orderItemId, string farmId);
        Task BumpOrderAsync(int orderId, string farmId);

        // Stats
        Task<KdsStatsModel> GetStatsAsync(string farmId);
    }
}
