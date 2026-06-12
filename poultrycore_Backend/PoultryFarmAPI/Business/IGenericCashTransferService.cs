using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IGenericCashTransferService
    {
        Task<List<GenericCashTransferModel>> GetAllAsync(string farmId, string? status);
        Task<GenericCashTransferModel?> GetByIdAsync(int id, string farmId);
        Task<int> InsertAsync(GenericCashTransferModel m);
        Task ApproveAsync(int id, string farmId, string? approvedBy);
        Task CancelAsync(int id, string farmId);
    }
}
