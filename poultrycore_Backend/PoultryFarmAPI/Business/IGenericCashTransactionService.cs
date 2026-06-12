using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IGenericCashTransactionService
    {
        Task<List<GenericCashTransactionModel>> GetByAccountAsync(int accountId, string farmId, DateTime? fromDate, DateTime? toDate);
        Task<List<GenericCashTransactionModel>> GetByFarmAsync(string farmId, DateTime? fromDate, DateTime? toDate);
        Task<long> InsertAdjustmentAsync(string farmId, GenericCashAdjustmentRequest req, string? createdBy, string? approvedBy);

        // Posts an equal-and-opposite transaction for an Approved transaction,
        // links it via ReversalOfTransactionId and marks the original Reversed.
        Task<long> ReverseAsync(long transactionId, string farmId, string? reversedBy, string? reason);

        // Posts a typed money-in / money-out movement (owner/loan/refund/other).
        Task<long> PostMovementAsync(string farmId, string direction, GenericCashMovementRequest req, string? createdBy, string? approvedBy);

        // Reconcile an account against an actual count; posts the difference.
        Task<int> CreateReconciliationAsync(string farmId, GenericCashReconciliationRequest req, string? requestedBy, string? approvedBy);
        Task<List<GenericCashReconciliationModel>> GetReconciliationsByAccountAsync(int accountId, string farmId);

        // Company default cash-account mappings.
        Task UpsertDefaultAsync(string farmId, string defaultKey, int accountId);
        Task<List<GenericCashAccountDefaultModel>> GetDefaultsAsync(string farmId);

        // Post a multi-method payment allocation set for one source.
        Task<int> PostAllocationsAsync(string farmId, GenericCashAllocationsRequest req, string? createdBy, string? approvedBy);

        // Account details header + ledger-vs-balance report.
        Task<GenericCashAccountDetailsModel?> GetAccountDetailsAsync(int accountId, string farmId);
        Task<List<GenericCashLedgerReportRow>> GetLedgerReportAsync(string farmId);
    }
}
