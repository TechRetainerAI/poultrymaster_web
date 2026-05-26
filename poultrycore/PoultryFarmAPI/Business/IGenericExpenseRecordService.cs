using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    // Named "ExpenseRecord" to avoid colliding with the legacy poultry
    // IExpenseService that already exists in this project.
    public interface IGenericExpenseRecordService
    {
        Task<List<GenericExpenseModel>> GetAllAsync(string farmId, string? status, DateTime? fromDate, DateTime? toDate);
        Task<GenericExpenseModel?> GetByIdAsync(int id, string farmId);
        Task<int> InsertAsync(GenericExpenseModel m);
        Task ApproveAsync(int id, string farmId, string? approvedBy);
        Task RejectAsync(int id, string farmId, string rejectionReason, string? approvedBy);
    }
}
