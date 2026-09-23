using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IHotelCustomerService
    {
        Task<List<HotelCustomerModel>> GetAllAsync(string farmId);
        Task<HotelCustomerModel?> GetByIdAsync(int id, string farmId);
        Task<int> InsertAsync(HotelCustomerModel m, string? createdBy);
        Task UpdateAsync(HotelCustomerModel m);
        Task DeleteAsync(int id, string farmId);
        Task<List<HotelCustomerOwedRowModel>> GetOwedAsync(string farmId);
        Task<HotelCustomerBalanceSummaryModel> GetBalanceSummaryAsync(string farmId);
        Task<List<HotelCustomerLedgerEntryModel>> GetLedgerAsync(int customerId, string farmId);
        Task PostInvoiceAsync(string farmId, int customerId, int invoiceId, decimal amount, string? description, string? createdBy);
        Task PostAdjustmentAsync(string farmId, int customerId, decimal amount, string? description, string? createdBy);
        Task<List<HotelCustomerPaymentModel>> GetPaymentsAsync(string farmId, string? status);
        Task<HotelCustomerPaymentModel?> GetPaymentByIdAsync(int id, string farmId);
        Task<int> InsertPaymentAsync(HotelCustomerPaymentModel m, string? createdBy);
        Task ApprovePaymentAsync(int id, string farmId, string? approvedBy);
        Task CancelPaymentAsync(int id, string farmId);
    }
}
