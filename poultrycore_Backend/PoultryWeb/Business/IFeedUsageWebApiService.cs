using PoultryWeb.Models;

namespace PoultryWeb.Business
{
    public interface IFeedUsageWebApiService
    {
        Task<List<FeedUsageModel>> GetAllAsync();
        Task<FeedUsageModel?> GetByIdAsync(int feedUsageId);
        Task<FeedUsageModel?> CreateAsync(FeedUsageModel model);
        Task UpdateAsync(int feedUsageId, FeedUsageModel model);
        Task DeleteAsync(int feedUsageId);
    }
}
