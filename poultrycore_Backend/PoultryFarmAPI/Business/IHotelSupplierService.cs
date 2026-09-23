using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IHotelSupplierService
    {
        Task<List<HotelSupplierModel>> GetAllAsync(string farmId);
        Task<HotelSupplierModel?> GetByIdAsync(int id, string farmId);
        Task<int> InsertAsync(HotelSupplierModel m, string? createdBy);
        Task UpdateAsync(HotelSupplierModel m);
        Task DeleteAsync(int id, string farmId);
        Task<List<HotelSupplierModel>> GetOwedAsync(string farmId);
        Task<HotelSupplierBalanceSummaryModel> GetBalanceSummaryAsync(string farmId);
        Task<List<HotelSupplierLedgerEntryModel>> GetLedgerAsync(int supplierId, string farmId);
        Task PostExpenseAsync(string farmId, int supplierId, int expenseId, decimal amount, string? description, string? createdBy);
        Task PostAdjustmentAsync(string farmId, int supplierId, decimal amount, string? description, string? createdBy);
        Task<List<HotelSupplierPaymentModel>> GetPaymentsAsync(string farmId, string? status);
        Task<int> InsertPaymentAsync(HotelSupplierPaymentModel m, string? createdBy);
        Task ApprovePaymentAsync(int id, string farmId, string? approvedBy);
        Task CancelPaymentAsync(int id, string farmId);
    }
}
