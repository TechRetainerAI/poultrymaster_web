using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    /// <summary>
    /// Customer Balances for the Generic company (migration 244).
    ///
    /// Both sides. The customer half came with 244; the supplier half with 248,
    /// which gave GenericExpenses the AmountPaid/DueDate/PaymentStatus columns it
    /// had never had and joined it to GenericPurchases behind one payables union.
    /// </summary>
    public interface IGenericBalanceService
    {
        Task<List<PartyBalanceRow>> GetCustomerBalances(BalanceQuery q);
        Task<BalanceSummary> GetCustomerSummary(string farmId);
        Task<List<OpenDocumentRow>> GetOpenInvoices(string farmId, int customerId, DateTime? from, DateTime? to, string? status);
        Task<int> RecordCustomerPayment(RecordPaymentRequest r);
        Task<int> ReverseCustomerPayment(string farmId, int paymentId, string? reason, string? reversedBy);
        Task<List<PaymentHistoryRow>> GetCustomerPayments(string farmId, int? customerId, int? saleId, DateTime? from, DateTime? to);
        Task<List<PaymentAllocationRow>> GetCustomerPaymentAllocations(string farmId, int paymentId);
        Task<List<StatementLine>> GetCustomerStatement(string farmId, int customerId, DateTime? from, DateTime? to);
        // Supplier side (migration 248). genericexpenses gained amountpaid/duedate/
        // paymentstatus, and genericpurchases already had them, so both are now
        // payable documents behind one fngenericpayables union.
        Task<List<PartyBalanceRow>> GetSupplierBalances(BalanceQuery q);
        Task<BalanceSummary> GetSupplierSummary(string farmId);
        Task<List<OpenDocumentRow>> GetOpenBills(string farmId, int supplierId, DateTime? from, DateTime? to, string? status);
        Task<int> RecordSupplierPayment(RecordPaymentRequest r);
        Task<int> ReverseSupplierPayment(string farmId, int paymentId, string? reason, string? reversedBy);
        Task<List<PaymentHistoryRow>> GetSupplierPayments(string farmId, int? supplierId, string? documentType, int? documentId, DateTime? from, DateTime? to);
        Task<List<PaymentAllocationRow>> GetSupplierPaymentAllocations(string farmId, int paymentId);
        Task<List<StatementLine>> GetSupplierStatement(string farmId, int supplierId, DateTime? from, DateTime? to);

        Task<List<BalanceAuditRow>> Audit(string farmId);
    }
}
