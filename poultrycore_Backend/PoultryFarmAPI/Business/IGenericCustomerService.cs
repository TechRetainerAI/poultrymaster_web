using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IGenericCustomerService
    {
        // Customers
        Task<List<GenericCustomerModel>> GetAllAsync(string farmId);
        Task<GenericCustomerModel?> GetByIdAsync(int id, string farmId);
        Task<int>  InsertAsync(GenericCustomerModel m);
        Task UpdateAsync(GenericCustomerModel m);
        Task DeleteAsync(int id, string farmId);
        Task<List<GenericCustomerOwingRowModel>> GetOwingMoneyAsync(string farmId);

        // Ledger
        Task<List<GenericCustomerLedgerEntryModel>> GetLedgerAsync(int customerId, string farmId);

        // Payments
        Task<List<GenericCustomerPaymentModel>> GetPaymentsAsync(string farmId, string? status);
        Task<GenericCustomerPaymentModel?> GetPaymentByIdAsync(int id, string farmId);
        Task<int>  InsertPaymentAsync(GenericCustomerPaymentModel m);
        Task ApprovePaymentAsync(int id, string farmId, string? approvedBy);
        Task CancelPaymentAsync(int id, string farmId);
    }
}
