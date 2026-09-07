using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    /// <summary>
    /// Customer Balances for the Generic company (migration 244).
    ///
    /// Customer side only. The supplier mirror is deliberately not here:
    /// GenericExpenses has no AmountPaid/Balance columns at all, so Generic
    /// payables need their own migration (the 238-equivalent) before a service
    /// can be written over them.
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
        Task<List<BalanceAuditRow>> Audit(string farmId);
    }
}
