using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    /// <summary>
    /// Invoice documents: formal billing records that reference authoritative
    /// posted Sales. Migration 494.
    /// </summary>
    public interface IGenericInvoiceDocumentService
    {
        // ---- Settings ----
        Task<InvoiceSettingsDto> GetSettings(string farmId);
        Task SaveSettings(InvoiceSettingsDto s);

        // ---- Invoice CRUD ----
        Task<int> Generate(GenerateInvoiceDocumentRequest r);
        Task<InvoiceDocumentDetail?> Get(string farmId, int docId);
        Task<InvoiceSaleLookup?> GetBySale(string farmId, int saleId);
        Task<List<InvoiceDocumentRow>> GetAll(
            string farmId, string? documentStatus, string? paymentStatus,
            int? customerId, int? projectId,
            DateTime? from, DateTime? to, bool overdueOnly);

        // ---- Lifecycle ----
        Task Issue(string farmId, int docId, string issuedBy);
        Task Void(string farmId, int docId, string reason, string voidedBy);
        Task UpdateDraft(string farmId, int docId, UpdateDraftInvoiceRequest r);

        // ---- Supporting data ----
        Task<List<InvoiceSaleLineRow>> GetSaleLines(string farmId, int saleId);
        Task<List<InvoiceHistoryRow>> GetHistory(string farmId, int docId);

        // ---- Reconciliation ----
        Task<List<InvoiceReconciliationRow>> Reconcile(string farmId);
    }
}
