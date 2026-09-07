using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    /// <summary>
    /// Generic Customer Balances -- the payment allocation control page
    /// (migration 244, the one migration 222 promised and nobody wrote).
    ///
    /// Why the extra /balances segment
    /// -------------------------------
    /// api/generic-company/{farmId}/customer-payments ALREADY EXISTS on
    /// GenericCustomerController and means something different: a
    /// GenericCustomerPaymentModel document with a Draft/Approved/Cancelled
    /// lifecycle. Mounting these endpoints on the same routes would be an
    /// ambiguous-route exception at startup, and quietly changing that
    /// controller's response shape would break the existing page. So the balance
    /// endpoints live one segment down, and lib/api/balances.ts points the
    /// generic module at that prefix.
    ///
    /// Customer side only. GenericExpenses has no AmountPaid/Balance columns at
    /// all, so the supplier mirror needs its own migration first.
    /// </summary>
    [ApiController]
    [Route("api/generic-company/{farmId}/balances")]
    public class GenericBalancesController : ControllerBase
    {
        private readonly IGenericBalanceService _svc;
        private readonly IGenericCompanyService _companies;

        public GenericBalancesController(IGenericBalanceService svc, IGenericCompanyService companies)
        {
            _svc = svc;
            _companies = companies;
        }

        // ------------------------------------------------------ customer balances

        [HttpGet("customer-balances")]
        public async Task<ActionResult<IEnumerable<PartyBalanceRow>>> GetCustomerBalances(
            string farmId, [FromQuery] DateTime? from, [FromQuery] DateTime? to,
            [FromQuery] int? customerId, [FromQuery] string? status,
            [FromQuery] decimal? minBalance, [FromQuery] string? search)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            return Ok(await _svc.GetCustomerBalances(new BalanceQuery
            {
                FarmId = farmId,
                From = from,
                To = to,
                PartyId = customerId,
                Status = status,
                MinBalance = minBalance,
                Search = search,
            }));
        }

        [HttpGet("customer-balances/summary")]
        public async Task<ActionResult<BalanceSummary>> GetCustomerSummary(string farmId)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _svc.GetCustomerSummary(farmId));
        }

        /// <summary>
        /// The approved invoices behind a customer's balance. Named open-sales to
        /// match the poultry and water routes -- for a Generic subscription
        /// business every one of them is an invoice, but the shape is identical.
        /// </summary>
        [HttpGet("customer-balances/{customerId:int}/open-sales")]
        public async Task<ActionResult<IEnumerable<OpenDocumentRow>>> GetOpenInvoices(
            string farmId, int customerId,
            [FromQuery] DateTime? from, [FromQuery] DateTime? to, [FromQuery] string? status)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _svc.GetOpenInvoices(farmId, customerId, from, to, status));
        }

        // -------------------------------------------------------------- payments

        [HttpGet("customer-payments")]
        public async Task<ActionResult<IEnumerable<PaymentHistoryRow>>> GetPayments(
            string farmId, [FromQuery] int? customerId, [FromQuery] int? saleId,
            [FromQuery] DateTime? from, [FromQuery] DateTime? to)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _svc.GetCustomerPayments(farmId, customerId, saleId, from, to));
        }

        [HttpGet("customer-payments/{paymentId:int}")]
        public async Task<ActionResult> GetPayment(string farmId, int paymentId)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            var payments = await _svc.GetCustomerPayments(farmId, null, null, null, null);
            var payment = payments.FirstOrDefault(p => p.PaymentId == paymentId.ToString());
            if (payment is null) return NotFound();

            var allocations = await _svc.GetCustomerPaymentAllocations(farmId, paymentId);
            return Ok(new { payment, allocations });
        }

        /// <summary>
        /// One payment, N allocations, one cash movement -- and one SQL function
        /// call, so it either lands completely or not at all.
        /// </summary>
        [HttpPost("customer-payments")]
        public async Task<ActionResult> RecordPayment(string farmId, [FromBody] RecordPaymentRequest r)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            r.FarmId = farmId;
            if (r.PartyId is null or 0) return BadRequest("A customer is required to receive a payment.");
            if (r.Allocations.Count == 0) return BadRequest("Select at least one invoice to apply this payment to.");

            var paymentId = await _svc.RecordCustomerPayment(r);
            return Ok(new { paymentId });
        }

        /// <summary>
        /// Append-only: the payment and its allocations are marked Reversed and
        /// every row is kept. Nothing is deleted, so the history stays readable.
        /// </summary>
        [HttpPost("customer-payments/{paymentId:int}/reverse")]
        public async Task<IActionResult> ReversePayment(
            string farmId, int paymentId, [FromBody] ReversePaymentRequest r)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            r.FarmId = farmId;
            await _svc.ReverseCustomerPayment(farmId, paymentId, r.Reason, r.ReversedBy);
            return NoContent();
        }

        // ------------------------------------------------------------ statements

        [HttpGet("customers/{customerId:int}/statement")]
        public async Task<ActionResult<IEnumerable<StatementLine>>> GetStatement(
            string farmId, int customerId, [FromQuery] DateTime? from, [FromQuery] DateTime? to)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _svc.GetCustomerStatement(farmId, customerId, from, to));
        }

        // ----------------------------------------------------------------- audit

        /// <summary>
        /// Returns NOTHING when the books are healthy. Any row means an invoice's
        /// AmountPaid disagrees with the allocations posted against it.
        /// </summary>
        [HttpGet("audit")]
        public async Task<ActionResult<IEnumerable<BalanceAuditRow>>> Audit(string farmId)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _svc.Audit(farmId));
        }
    }
}
