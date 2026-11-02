using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IProductionRecordService
    {
        Task<int> Insert(ProductionRecordModel model);
        Task Update(ProductionRecordModel model);
        /// <summary>389: a feed-only (FeedUsage) record saved from the production form becomes production.</summary>
        Task MarkRecorded(int recordId, string farmId);
        Task<ProductionRecordModel?> GetById(int recordId, string userId, string farmId);
        Task<List<ProductionRecordModel>> GetAll(string userId, string farmId);
        Task Delete(int recordId, string userId, string farmId);
    }
}
