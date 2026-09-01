using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IRestaurantOrderService
    {
        // Orders
        Task<(int orderId, string orderNumber)> CreateOrderAsync(RestaurantOrderCreateRequest req);
        Task<List<RestaurantOrderModel>> ListOrdersAsync(string farmId, string? status = null, string? orderType = null, DateTime? fromDate = null, DateTime? toDate = null);
        Task<RestaurantOrderModel?> GetOrderAsync(int id, string farmId);
        Task UpdateOrderStatusAsync(int id, string farmId, string status, string? reason = null);
        Task RecalcOrderAsync(int orderId, string farmId, decimal taxRate, decimal serviceChargeRate);

        // Order Items
        Task<int> AddOrderItemAsync(RestaurantOrderItemCreateRequest req);
        Task<List<RestaurantOrderItemModel>> ListOrderItemsAsync(int orderId, string farmId);
        Task UpdateOrderItemStatusAsync(int id, string farmId, string status);
        Task CancelOrderItemAsync(int id, string farmId);

        // Order Item Modifiers
        Task<List<RestaurantOrderItemModifierModel>> ListOrderItemModifiersAsync(int orderItemId, string farmId);

        // Order Payments
        Task<int> AddPaymentAsync(string farmId, int orderId, string paymentMethod, decimal amount, decimal tipAmount, string? reference, string? processedBy);
        Task<List<RestaurantOrderPaymentModel>> ListPaymentsAsync(int orderId, string farmId);

        // Discounts
        Task<List<RestaurantDiscountModel>> ListDiscountsAsync(string farmId);
        Task<int> InsertDiscountAsync(RestaurantDiscountModel m);
        Task UpdateDiscountAsync(RestaurantDiscountModel m);
        Task DeleteDiscountAsync(int id, string farmId);

        // Order Discounts
        Task<int> ApplyDiscountToOrderAsync(string farmId, int orderId, int? discountId, string discountName, string discountType, decimal value, decimal appliedAmount);
        Task RemoveDiscountFromOrderAsync(int id, string farmId);
        Task<List<RestaurantOrderDiscountModel>> ListOrderDiscountsAsync(int orderId, string farmId);
    }
}
