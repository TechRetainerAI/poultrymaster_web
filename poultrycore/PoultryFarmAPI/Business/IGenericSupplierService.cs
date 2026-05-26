using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IGenericSupplierService
    {
        // Suppliers
        Task<List<GenericSupplierModel>> GetAllAsync(string farmId);
        Task<GenericSupplierModel?> GetByIdAsync(int id, string farmId);
        Task<int>  InsertAsync(GenericSupplierModel m);
        Task UpdateAsync(GenericSupplierModel m);
        Task DeleteAsync(int id, string farmId);
        Task<List<GenericSupplierOwedRowModel>> GetOwedToThemAsync(string farmId);

        // Ledger
        Task<List<GenericSupplierLedgerEntryModel>> GetLedgerAsync(int supplierId, string farmId);

        // Payments
        Task<List<GenericSupplierPaymentModel>> GetPaymentsAsync(string farmId, string? status);
        Task<GenericSupplierPaymentModel?> GetPaymentByIdAsync(int id, string farmId);
        Task<int>  InsertPaymentAsync(GenericSupplierPaymentModel m);
        Task ApprovePaymentAsync(int id, string farmId, string? approvedBy);
        Task CancelPaymentAsync(int id, string farmId);
    }
}
