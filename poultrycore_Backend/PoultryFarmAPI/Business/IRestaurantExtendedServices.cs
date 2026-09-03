using PoultryFarmAPIWeb.Models;
namespace PoultryFarmAPIWeb.Business
{
    public interface IRestaurantLoyaltyService
    {
        Task<LoyaltySettingsModel?> GetSettingsAsync(string farmId);
        Task UpsertSettingsAsync(LoyaltySettingsModel m);
        Task<List<LoyaltyAccountModel>> ListAccountsAsync(string farmId, string? tier = null);
        Task<int> CreateAccountAsync(string farmId, int? customerId, string customerName, string? customerPhone);
        Task EarnPointsAsync(int accountId, string farmId, int points, string description, int? orderId = null);
        Task<bool> RedeemPointsAsync(int accountId, string farmId, int points, string description);
        Task<List<PointTransactionModel>> GetTransactionsAsync(int accountId, string farmId);
        Task<LoyaltyStatsModel> GetStatsAsync(string farmId);
    }
    public interface IRestaurantNotificationService
    {
        Task<List<NotificationModel>> ListAsync(string farmId, bool unreadOnly = false);
        Task<int> CreateAsync(string farmId, string type, string title, string message, string severity, string? targetRole = null, int? relatedId = null, string? relatedType = null);
        Task MarkReadAsync(int id, string farmId);
        Task MarkAllReadAsync(string farmId);
        Task<NotificationSettingsModel?> GetSettingsAsync(string farmId);
        Task UpsertSettingsAsync(NotificationSettingsModel m);
    }
    public interface IRestaurantEventService
    {
        Task<List<EventModel>> ListAsync(string farmId, string? status = null);
        Task<int> InsertAsync(EventModel m);
        Task UpdateStatusAsync(int id, string farmId, string status);
        Task DeleteAsync(int id, string farmId);
    }
    public interface IRestaurantGiftCardService
    {
        Task<List<GiftCardModel>> ListAsync(string farmId, string? status = null);
        Task<(int id, string cardNumber)> CreateAsync(string farmId, string cardType, decimal amount, string? purchaserName, string? purchaserPhone, string? recipientName, string? recipientEmail, string? message, DateTime? expiryDate);
        Task<GiftCardRedeemResult> RedeemAsync(string cardNumber, string farmId, decimal amount, int? orderId = null, string? processedBy = null);
        Task ReloadAsync(string cardNumber, string farmId, decimal amount, string? processedBy = null);
        Task<GiftCardModel?> CheckBalanceAsync(string cardNumber);
        Task<List<GiftCardTxModel>> GetTransactionsAsync(int giftCardId, string farmId);
        Task<GiftCardStatsModel> GetStatsAsync(string farmId);
    }
    public interface IRestaurantExpenseService
    {
        Task<List<ExpenseCategoryModel>> ListCategoriesAsync(string farmId);
        Task<int> InsertCategoryAsync(string farmId, string name);
        Task DeleteCategoryAsync(int id, string farmId);
        Task<List<RestaurantExpenseModel>> ListExpensesAsync(string farmId, DateTime? from = null, DateTime? to = null);
        Task<int> InsertExpenseAsync(RestaurantExpenseModel m);
        Task DeleteExpenseAsync(int id, string farmId);
        Task<ReceiptTemplateModel?> GetReceiptTemplateAsync(string farmId);
        Task UpsertReceiptTemplateAsync(ReceiptTemplateModel m);
    }
    public interface IRestaurantStaffService
    {
        Task<List<RestaurantStaffModel>> ListAsync(string farmId, string? role = null);
        Task<RestaurantStaffModel?> GetByIdAsync(int id, string farmId);
        Task<int> InsertAsync(RestaurantStaffModel m);
        Task UpdateAsync(RestaurantStaffModel m);
        Task DeleteAsync(int id, string farmId);
    }
}
