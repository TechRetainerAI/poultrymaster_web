using PoultryFarmAPIWeb.Models;
namespace PoultryFarmAPIWeb.Business
{
    public interface IRestaurantCRMService
    {
        Task<List<RestaurantCustomerModel>> ListCustomersAsync(string farmId, string? segment = null, string? search = null);
        Task<int> InsertCustomerAsync(RestaurantCustomerModel m);
        Task UpdateCustomerAsync(RestaurantCustomerModel m);
        Task DeleteCustomerAsync(int id, string farmId);
        Task RecordVisitAsync(int id, string farmId, decimal orderAmount);
        Task<CustomerStatsModel> GetCustomerStatsAsync(string farmId);
        Task<List<RestaurantFeedbackModel>> ListFeedbackAsync(string farmId, string? status = null);
        Task<int> InsertFeedbackAsync(RestaurantFeedbackModel m);
        Task RespondToFeedbackAsync(int id, string farmId, string response, string respondedBy);
        Task<FeedbackStatsModel> GetFeedbackStatsAsync(string farmId);
        Task<List<RestaurantCampaignModel>> ListCampaignsAsync(string farmId);
        Task<int> InsertCampaignAsync(RestaurantCampaignModel m);
        Task DeleteCampaignAsync(int id, string farmId);
    }
}
