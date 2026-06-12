using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IGenericDailyClosingService
    {
        Task<List<GenericDailyClosingModel>> GetAllAsync(string farmId, DateTime? fromDate, DateTime? toDate, string? status, int? branchId);
        Task<GenericDailyClosingModel?> GetByIdAsync(int id, string farmId);
        Task<int> InsertAsync(string farmId, GenericDailyClosingCreateRequest req, string? createdBy);
        Task<GenericDailyClosingModel?> SubmitAsync(int id, string farmId, GenericDailyClosingSubmitRequest req, string? submittedBy);
        Task ApproveAsync(int id, string farmId, string? approvedBy);
        Task RejectAsync(int id, string farmId, string rejectionReason, string? approvedBy);
    }
}
