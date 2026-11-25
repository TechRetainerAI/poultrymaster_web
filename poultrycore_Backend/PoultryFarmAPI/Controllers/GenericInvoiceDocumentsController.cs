using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Filters;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // =========================================================================
    // Invoice Documents — formal billing records linked to posted Sales.
    //
    // Gated on EnableInvoices (independent of EnableSubscriptions).
    // Migration 494.
    // =========================================================================

    [ApiController]
    [Route("api/generic-company/{farmId}/invoice-documents")]
    [RequireCompanyType("Generic")]
    [RequireGenericModule("EnableInvoices")]
    public class GenericInvoiceDocumentsController : ControllerBase
    {
        private readonly IGenericInvoiceDocumentService _svc;
        private readonly IGenericCompanyService _companies;

        public GenericInvoiceDocumentsController(
            IGenericInvoiceDocumentService svc, IGenericCompanyService companies)
        {
            _svc = svc;
            _companies = companies;
        }

        // ---- Settings ----

        [HttpGet("settings")]
        public async Task<ActionResult<InvoiceSettingsDto>> GetSettings(string farmId)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _svc.GetSettings(farmId));
        }

        [HttpPut("settings")]
        public async Task<ActionResult<InvoiceSettingsDto>> SaveSettings(
            string farmId, [FromBody] InvoiceSettingsDto dto)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            dto.FarmId = farmId;
            await _svc.SaveSettings(dto);
            return Ok(await _svc.GetSettings(farmId));
        }

        // ---- Generate ----

        [HttpPost("generate")]
        public async Task<ActionResult<InvoiceDocumentDetail>> Generate(
            string farmId, [FromBody] GenerateInvoiceDocumentRequest req)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            req.FarmId = farmId;
            var docId = await _svc.Generate(req);
            var doc = await _svc.Get(farmId, docId);
            return Ok(doc);
        }

        // ---- Get single ----

        [HttpGet("{docId:int}")]
        public async Task<ActionResult<InvoiceDocumentDetail>> Get(string farmId, int docId)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            var doc = await _svc.Get(farmId, docId);
            if (doc == null) return NotFound();
            return Ok(doc);
        }

        [HttpGet("by-sale/{saleId:int}")]
        public async Task<ActionResult<InvoiceSaleLookup>> GetBySale(string farmId, int saleId)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            var lookup = await _svc.GetBySale(farmId, saleId);
            if (lookup == null) return NotFound();
            return Ok(lookup);
        }

        // ---- List ----

        [HttpGet]
        public async Task<ActionResult<List<InvoiceDocumentRow>>> GetAll(
            string farmId,
            [FromQuery] string? documentStatus = null,
            [FromQuery] string? paymentStatus = null,
            [FromQuery] int? customerId = null,
            [FromQuery] int? projectId = null,
            [FromQuery] DateTime? from = null,
            [FromQuery] DateTime? to = null,
            [FromQuery] bool overdueOnly = false)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _svc.GetAll(farmId, documentStatus, paymentStatus,
                customerId, projectId, from, to, overdueOnly));
        }

        // ---- Lifecycle ----

        [HttpPost("{docId:int}/issue")]
        public async Task<ActionResult> Issue(
            string farmId, int docId, [FromBody] IssueInvoiceRequest req)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            await _svc.Issue(farmId, docId, req.IssuedBy ?? "system");
            return Ok(new { message = "Invoice issued." });
        }

        [HttpPost("{docId:int}/void")]
        public async Task<ActionResult> Void(
            string farmId, int docId, [FromBody] VoidInvoiceRequest req)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            await _svc.Void(farmId, docId, req.Reason, req.VoidedBy ?? "system");
            return Ok(new { message = "Invoice voided." });
        }

        [HttpPut("{docId:int}/draft")]
        public async Task<ActionResult<InvoiceDocumentDetail>> UpdateDraft(
            string farmId, int docId, [FromBody] UpdateDraftInvoiceRequest req)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            req.FarmId = farmId;
            await _svc.UpdateDraft(farmId, docId, req);
            var doc = await _svc.Get(farmId, docId);
            return Ok(doc);
        }

        // ---- Supporting data ----

        [HttpGet("{docId:int}/history")]
        public async Task<ActionResult<List<InvoiceHistoryRow>>> GetHistory(string farmId, int docId)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _svc.GetHistory(farmId, docId));
        }

        [HttpGet("sale-lines/{saleId:int}")]
        public async Task<ActionResult<List<InvoiceSaleLineRow>>> GetSaleLines(string farmId, int saleId)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _svc.GetSaleLines(farmId, saleId));
        }

        // ---- Reconciliation ----

        [HttpGet("reconcile")]
        public async Task<ActionResult<object>> Reconcile(string farmId)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            var issues = await _svc.Reconcile(farmId);
            return Ok(new
            {
                healthy = issues.Count == 0,
                errorCount = issues.Count(i => i.Severity == "error"),
                warningCount = issues.Count(i => i.Severity == "warning"),
                issues,
            });
        }
    }
}
