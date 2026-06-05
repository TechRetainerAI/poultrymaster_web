using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IGenericCashTransactionService
    {
        Task<List<GenericCashTransactionModel>> GetByAccountAsync(int accountId, string farmId, DateTime? fromDate, DateTime? toDate);
        Task<List<GenericCashTransactionModel>> GetByFarmAsync(string farmId, DateTime? fromDate, DateTime? toDate);
        Task<long> InsertAdjustmentAsync(string farmId, GenericCashAdjustmentRequest req, string? createdBy, string? approvedBy);
    }
}
