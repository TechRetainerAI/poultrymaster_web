using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IRestaurantDeliveryService
    {
        // Drivers
        Task<List<RestaurantDriverModel>> ListDriversAsync(string farmId, string? status = null);
        Task<int> InsertDriverAsync(RestaurantDriverModel m);
        Task UpdateDriverAsync(RestaurantDriverModel m);
        Task DeleteDriverAsync(int id, string farmId);
        Task UpdateDriverStatusAsync(int id, string farmId, string status);
        Task UpdateDriverLocationAsync(int id, string farmId, decimal lat, decimal lng);
        Task<DriverStatsModel> GetDriverStatsAsync(int driverId, string farmId, DateTime? fromDate = null, DateTime? toDate = null);

        // Delivery Zones
        Task<List<RestaurantDeliveryZoneModel>> ListZonesAsync(string farmId);
        Task<int> InsertZoneAsync(RestaurantDeliveryZoneModel m);
        Task UpdateZoneAsync(RestaurantDeliveryZoneModel m);
        Task DeleteZoneAsync(int id, string farmId);

        // Assignments
        Task<List<RestaurantDeliveryAssignmentModel>> ListAssignmentsAsync(string farmId, string? status = null, int? driverId = null, DateTime? fromDate = null, DateTime? toDate = null);
        Task<int> CreateAssignmentAsync(string farmId, int orderId, string orderNumber, int driverId, string? deliveryAddress, string? deliveryNotes, int? zoneId, decimal deliveryFee, int? estimatedMins);
        Task UpdateAssignmentStatusAsync(int id, string farmId, string status, string? failReason = null);
        Task RateAssignmentAsync(int id, string farmId, int rating);
        Task AddProofAsync(int id, string farmId, string proofType, string proofData);

        // Third-Party Platforms
        Task<List<RestaurantThirdPartyPlatformModel>> ListPlatformsAsync(string farmId);
        Task<int> InsertPlatformAsync(RestaurantThirdPartyPlatformModel m);
        Task UpdatePlatformAsync(RestaurantThirdPartyPlatformModel m);
        Task DeletePlatformAsync(int id, string farmId);

        // Third-Party Orders
        Task<List<RestaurantThirdPartyOrderModel>> ListThirdPartyOrdersAsync(string farmId, string? status = null, int? platformId = null);
        Task<int> InsertThirdPartyOrderAsync(RestaurantThirdPartyOrderModel m, decimal commissionRate);
        Task UpdateThirdPartyOrderStatusAsync(int id, string farmId, string status, string? rejectReason = null);

        // Stats
        Task<DeliveryStatsModel> GetDeliveryStatsAsync(string farmId, DateTime? date = null);
    }
}
