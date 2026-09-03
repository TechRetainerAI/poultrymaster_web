using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IRestaurantOnlineOrderService
    {
        // Settings
        Task<RestaurantOnlineOrderingSettingsModel?> GetSettingsAsync(string farmId);
        Task UpsertSettingsAsync(RestaurantOnlineOrderingSettingsModel m);
        Task ToggleAcceptingOrdersAsync(string farmId, bool accepting, string? reason);

        // QR Codes
        Task<List<RestaurantQrCodeModel>> ListQrCodesAsync(string farmId);
        Task<(int id, string token)> GenerateQrCodeAsync(string farmId, int tableId, string tableNumber);
        Task DeleteQrCodeAsync(int id, string farmId);
        Task<RestaurantQrCodeModel?> ScanQrCodeAsync(string token);

        // Promo Codes
        Task<List<RestaurantPromoCodeModel>> ListPromoCodesAsync(string farmId);
        Task<int> InsertPromoCodeAsync(RestaurantPromoCodeModel m);
        Task UpdatePromoCodeAsync(RestaurantPromoCodeModel m);
        Task DeletePromoCodeAsync(int id, string farmId);
        Task<PromoValidationResult> ValidatePromoCodeAsync(string farmId, string code, decimal orderAmount, string? channel);

        // Delivery Addresses
        Task<List<RestaurantDeliveryAddressModel>> ListDeliveryAddressesAsync(string farmId, string? phone, string? email);
        Task<int> InsertDeliveryAddressAsync(RestaurantDeliveryAddressModel m);
        Task DeleteDeliveryAddressAsync(int id, string farmId);

        // Public Menu (no auth)
        Task<List<PublicMenuItemModel>> GetPublicMenuAsync(string farmId);
        Task<List<PublicCategoryModel>> GetPublicCategoriesAsync(string farmId);

        // Online Order Placement
        Task<(int orderId, string orderNumber, string trackingToken)> PlaceOnlineOrderAsync(OnlineOrderCreateRequest req);
        Task<OrderTrackingModel?> TrackOrderAsync(string trackingToken);
        Task<ThrottleCheckResult> CheckThrottleAsync(string farmId);
    }
}
