using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // Water Customer Balances and Supplier Balances -- the payment allocation
    // control pages (migration 227). The poultry twin is
    // PoultryBalancesController; the route shapes are identical on purpose,
    // because lib/api/balances.ts is one client for all three modules and only
    // swaps the prefix.
    //
    // These are working pages, not reports: they summarise what is owed AND take
    // the payment. A payment posted here writes back to the sale or purchase it
    // was applied to, which is the whole reason the feature exists.
    //
    // The existing per-document endpoints (api/Water/payments and the raw
    // material pay-balance route) are untouched and keep working -- they now go
    // through the same SQL with a single allocation, so both routes produce
    // identical records.
    //
    // The statement routes deliberately sit at api/Water/customers/{id}/statement
    // and api/Water/suppliers/{id}/statement -- the shared client builds those
    // paths -- and neither WaterCustomerController nor the suppliers controller
    // defines a {id}/statement template, so there is no route collision.
    //
    // AuditLogActionFilter is registered globally, so every write below is
    // audited without any code here.
    // Authentication is REQUIRED here. These endpoints take money in, allocate
    // it across a customer's sales and reverse it again, and until this
    // attribute was added they were reachable with no token at all -- the
    // frontend's usePermissions() gate was the only thing in front of them,
    // which is exactly the "frontend hiding alone is not enough" case.
    //
    // [Authorize] is authentication only. WHICH user may do WHAT is the job of
    // IamEnforcementFilter, which runs globally in shadow mode by default
    // (Iam:Enforced); a [RequirePermission] here would enforce immediately and
    // could lock out staff whose roles have not been granted yet.
    [Authorize]
    [ApiController]
    [Route("api/Water")]
    public class WaterBalancesController : ControllerBase
    {
        private readonly IWaterBalanceService _svc;
        public WaterBalancesController(IWaterBalanceService svc) => _svc = svc;

        private static BalanceQuery BuildQuery(string farmId, DateTime? from, DateTime? to,
            int? partyId, string? status, decimal? minBalance, string? search) => new()
        {
            FarmId = farmId,
            From = from,
            To = to,
            PartyId = partyId,
            Status = status,
            MinBalance = minBalance,
            Search = search,
        };

        // ------------------------------------------------------ customer balances

        [HttpGet("customer-balances")]
        public async Task<ActionResult<IEnumerable<PartyBalanceRow>>> GetCustomerBalances(
            [FromQuery] string farmId, [FromQuery] DateTime? from, [FromQuery] DateTime? to,
            [FromQuery] int? customerId, [FromQuery] string? status,
            [FromQuery] decimal? minBalance, [FromQuery] string? search)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetCustomerBalances(
                BuildQuery(farmId, from, to, customerId, status, minBalance, search)));
        }

        [HttpGet("customer-balances/summary")]
        public async Task<ActionResult<BalanceSummary>> GetCustomerSummary([FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetCustomerSummary(farmId));
        }

        [HttpGet("customer-balances/{customerId:int}/open-sales")]
        public async Task<ActionResult<IEnumerable<OpenDocumentRow>>> GetOpenSales(
            int customerId, [FromQuery] string farmId,
            [FromQuery] DateTime? from, [FromQuery] DateTime? to, [FromQuery] string? status)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetOpenSales(farmId, customerId, from, to, status));
        }

        [HttpPost("customer-payments")]
        public async Task<ActionResult> RecordCustomerPayment([FromBody] RecordPaymentRequest r)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(r.FarmId)) return BadRequest("Company ID is required.");
            if (r.PartyId is null or 0) return BadRequest("A customer is required to receive a payment.");
            if (r.Allocations.Count == 0) return BadRequest("Select at least one sale to apply this payment to.");

            var groupId = await _svc.RecordCustomerPayment(r);
            return Ok(new { paymentId = groupId });
        }

        [HttpPost("customer-payments/{paymentId:guid}/reverse")]
        public async Task<ActionResult> ReverseCustomerPayment(Guid paymentId, [FromBody] ReversePaymentRequest r)
        {
            if (string.IsNullOrWhiteSpace(r.FarmId)) return BadRequest("Company ID is required.");
            var count = await _svc.ReverseCustomerPayment(r.FarmId, paymentId, r.Reason, r.ReversedBy);
            return Ok(new { reversedAllocations = count });
        }

        // NOTE: this is api/Water/customer-payments, NOT the legacy
        // api/Water/payments (WaterPaymentController), which lists the raw
        // per-sale rows. Both read waterpayments; this one groups them the way
        // the payment was actually made.
        [HttpGet("customer-payments")]
        public async Task<ActionResult<IEnumerable<PaymentHistoryRow>>> GetCustomerPayments(
            [FromQuery] string farmId, [FromQuery] int? customerId, [FromQuery] int? saleId,
            [FromQuery] DateTime? from, [FromQuery] DateTime? to)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetCustomerPayments(farmId, customerId, saleId, from, to));
        }

        [HttpGet("customer-payments/{paymentId:guid}")]
        public async Task<ActionResult> GetCustomerPayment(Guid paymentId, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var payments = await _svc.GetCustomerPayments(farmId, null, null, null, null);
            var header = payments.FirstOrDefault(p =>
                string.Equals(p.PaymentId, paymentId.ToString(), StringComparison.OrdinalIgnoreCase));
            if (header is null) return NotFound();
            return Ok(new
            {
                payment = header,
                allocations = await _svc.GetCustomerPaymentAllocations(farmId, paymentId),
            });
        }

        [HttpGet("customers/{customerId:int}/statement")]
        public async Task<ActionResult<IEnumerable<StatementLine>>> GetCustomerStatement(
            int customerId, [FromQuery] string farmId,
            [FromQuery] DateTime? from, [FromQuery] DateTime? to)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetCustomerStatement(farmId, customerId, from, to));
        }

        // ------------------------------------------------------ supplier balances

        [HttpGet("supplier-balances")]
        public async Task<ActionResult<IEnumerable<PartyBalanceRow>>> GetSupplierBalances(
            [FromQuery] string farmId, [FromQuery] DateTime? from, [FromQuery] DateTime? to,
            [FromQuery] int? supplierId, [FromQuery] string? status,
            [FromQuery] decimal? minBalance, [FromQuery] string? search)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetSupplierBalances(
                BuildQuery(farmId, from, to, supplierId, status, minBalance, search)));
        }

        [HttpGet("supplier-balances/summary")]
        public async Task<ActionResult<BalanceSummary>> GetSupplierSummary([FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetSupplierSummary(farmId));
        }

        [HttpGet("supplier-balances/{supplierId:int}/open-purchases")]
        public async Task<ActionResult<IEnumerable<OpenDocumentRow>>> GetOpenPurchases(
            int supplierId, [FromQuery] string farmId,
            [FromQuery] DateTime? from, [FromQuery] DateTime? to, [FromQuery] string? status)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetOpenPurchases(farmId, supplierId, from, to, status));
        }

        [HttpPost("supplier-payments")]
        public async Task<ActionResult> RecordSupplierPayment([FromBody] RecordPaymentRequest r)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(r.FarmId)) return BadRequest("Company ID is required.");
            if (r.Allocations.Count == 0) return BadRequest("Select at least one purchase to apply this payment to.");

            var id = await _svc.RecordSupplierPayment(r);
            return Ok(new { paymentId = id });
        }

        [HttpPost("supplier-payments/{paymentId:int}/reverse")]
        public async Task<ActionResult> ReverseSupplierPayment(int paymentId, [FromBody] ReversePaymentRequest r)
        {
            if (string.IsNullOrWhiteSpace(r.FarmId)) return BadRequest("Company ID is required.");
            var count = await _svc.ReverseSupplierPayment(r.FarmId, paymentId, r.Reason, r.ReversedBy);
            return Ok(new { reversedAllocations = count });
        }

        [HttpGet("supplier-payments")]
        public async Task<ActionResult<IEnumerable<PaymentHistoryRow>>> GetSupplierPayments(
            [FromQuery] string farmId, [FromQuery] int? supplierId,
            [FromQuery] string? documentType, [FromQuery] int? documentId,
            [FromQuery] DateTime? from, [FromQuery] DateTime? to)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetSupplierPayments(farmId, supplierId, documentType, documentId, from, to));
        }

        [HttpGet("supplier-payments/{paymentId:int}")]
        public async Task<ActionResult> GetSupplierPayment(int paymentId, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var payments = await _svc.GetSupplierPayments(farmId, null, null, null, null, null);
            var header = payments.FirstOrDefault(p => p.PaymentId == paymentId.ToString());
            if (header is null) return NotFound();
            return Ok(new
            {
                payment = header,
                allocations = await _svc.GetSupplierPaymentAllocations(farmId, paymentId),
            });
        }

        [HttpGet("suppliers/{supplierId:int}/statement")]
        public async Task<ActionResult<IEnumerable<StatementLine>>> GetSupplierStatement(
            int supplierId, [FromQuery] string farmId,
            [FromQuery] DateTime? from, [FromQuery] DateTime? to)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetSupplierStatement(farmId, supplierId, from, to));
        }

        // ----------------------------------------------------------------- audit

        /// <summary>
        /// Documents whose allocations disagree with their amountpaid. Should
        /// always return an empty list; a non-empty one means a payment path has
        /// drifted and the balances on screen can no longer be trusted.
        ///
        /// One known exception on water: purchases that were part-paid BEFORE
        /// migration 227 have no allocation rows to reconstruct from, so they
        /// report a one-time opening difference. See the note at the end of 227.
        /// </summary>
        [HttpGet("balances/audit")]
        public async Task<ActionResult<IEnumerable<BalanceAuditRow>>> Audit([FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.Audit(farmId));
        }
    }
}
