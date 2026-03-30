using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IFeedUsageService
    {
        Task<int> Insert(FeedUsageModel model);
        Task Update(FeedUsageModel model);
        Task<FeedUsageModel?> GetById(int feedUsageId, string userId, string farmId);
        Task<List<FeedUsageModel>> GetAll(string userId, string farmId);
        Task Delete(int feedUsageId, string userId, string farmId);

        // Optional
        // Task<List<FeedUsageModel>> GetByFlockId(int flockId, string userId, string farmId);
    }

}
