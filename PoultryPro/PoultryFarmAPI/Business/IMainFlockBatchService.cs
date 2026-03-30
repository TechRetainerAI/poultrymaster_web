using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    // Defines the contract for all business operations related to MainFlockBatch.
    public interface IMainFlockBatchService
    {
        // Inserts a new batch record and returns the new BatchId.
        Task<int> Insert(MainFlockBatchModel model);

        // Updates an existing batch record.
        Task Update(MainFlockBatchModel model);

        // Retrieves a single batch record by its primary key and security parameters.
        Task<MainFlockBatchModel?> GetById(int batchId, string userId, string farmId);

        // Retrieves all batch records for a specific User and Farm.
        Task<List<MainFlockBatchModel>> GetAll(string userId, string farmId);

        // Deletes a single batch record.
        Task Delete(int batchId, string userId, string farmId);
    }
}
