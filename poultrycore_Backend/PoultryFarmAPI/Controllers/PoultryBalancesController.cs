using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // Poultry Customer Balances and Supplier Balances -- the payment allocation
    // control pages (migrations 222-224).
    //
    // These are working pages, not reports: they summarise what is owed AND take
    // the payment. A payment posted here writes back to the sale or purchase it
    // was applied to, which is the whole reason the feature exists.
    //
    // The existing per-document endpoints (api/Poultry/payments and the two
    // pay-balance routes) are untouched and keep working -- they now go through
    // the same SQL with a single allocation, so both routes produce identical
    // records.
    //
    // AuditLogActionFilter is registered globally, so every write below is
    // audited without any code here.
    [ApiController]
    [Route("api/Poultry")]
    public class PoultryBalancesController : ControllerBase
    {
        private readonly IPoultryBalanceService _svc;
        public PoultryBalancesController(IPoultryBalanceService svc) => _svc = svc;

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
        /// </summary>
        [HttpGet("balances/audit")]
        public async Task<ActionResult<IEnumerable<BalanceAuditRow>>> Audit([FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.Audit(farmId));
        }
    }
}
