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
        Task<(int id, string token)> GenerateQrCodeAsync(string farmId, int? tableId, string? tableNumber, string codeType = "Table");
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

        // --- QR self-ordering (migration 248) --------------------------------
        /// <summary>Per-table rate limit for one QR code.</summary>
        Task<ThrottleCheckResult> CheckQrThrottleAsync(int qrCodeId, string farmId);
        /// <summary>Guest orders awaiting staff confirmation, oldest first.</summary>
        Task<List<PendingOnlineOrderModel>> ListPendingOnlineOrdersAsync(string farmId);
        /// <summary>Confirm a guest order so the kitchen can see it.</summary>
        Task<(bool ok, string message)> AcceptOnlineOrderAsync(int orderId, string farmId, string confirmedBy);
        /// <summary>Reject a guest order; cancels the order and all its items.</summary>
        Task<(bool ok, string message)> RejectOnlineOrderAsync(int orderId, string farmId, string? reason, string by);
    }
}
