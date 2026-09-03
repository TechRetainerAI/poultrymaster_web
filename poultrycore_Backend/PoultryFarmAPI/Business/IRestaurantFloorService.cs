using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IRestaurantFloorService
    {
        // Floors
        Task<List<RestaurantFloorModel>> ListFloorsAsync(string farmId);
        Task<int> InsertFloorAsync(RestaurantFloorModel m);
        Task UpdateFloorAsync(RestaurantFloorModel m);
        Task DeleteFloorAsync(int id, string farmId);

        // Tables
        Task<List<RestaurantTableModel>> ListTablesAsync(string farmId, int? floorId = null, string? status = null);
        Task<RestaurantTableModel?> GetTableAsync(int id, string farmId);
        Task<int> InsertTableAsync(RestaurantTableModel m);
        Task UpdateTableAsync(RestaurantTableModel m);
        Task DeleteTableAsync(int id, string farmId);
        Task UpdateTableStatusAsync(int id, string farmId, string status, int? currentOrderId = null);
        Task UpdateTablePositionAsync(int id, string farmId, int positionX, int positionY);
    }
}
