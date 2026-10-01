// Restaurant pay-later orders, Customer Balances and Payments (migration 333).
//
//   POST /api/Restaurant/orders/{id}/pay-later           mark Pay later + complete the order
//   /api/Restaurant/customer-balances ...               \
//   /api/Restaurant/customer-payments ...                } the SAME contract PoultryBalancesController
//   /api/Restaurant/customers/{id}/statement, /balances/audit  answers (lib/api/balances.ts, "restaurant")
//
// Every action checks the caller's JWT company against farmId; the acting user
// comes from the token (a createdBy / reversedBy in the body is ignored);
// refusals come back as 400 with the database's own sentence.

using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Filters;
using PoultryFarmAPIWeb.Helpers;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    public class RestaurantPayLaterRequest
    {
        public string FarmId { get; set; } = string.Empty;
        /// <summary>The saved customer; defaults to the order's own link.</summary>
        public int? CustomerId { get; set; }
        public DateTime? DueDate { get; set; }
        public string? Notes { get; set; }
    }

    [ApiController]
    [Authorize]
    [RestaurantBusinessRuleFilter]
    [Route("api/Restaurant")]
    public class RestaurantCustomerBalancesController : ControllerBase
    {
        private readonly IRestaurantCustomerBalanceService _svc;
        private readonly IRestaurantOrderService _orders;
        public RestaurantCustomerBalancesController(IRestaurantCustomerBalanceService svc, IRestaurantOrderService orders)
        { _svc = svc; _orders = orders; }

        private string Me => HotelAuthHelper.GetUserName(User);
        private IActionResult? Deny(string? farmId) =>
            string.IsNullOrWhiteSpace(farmId) ? BadRequest(new { message = "Company ID is required." }) : HotelAuthHelper.VerifyFarmOwnership(User, farmId);

        /// <summary>Marks the order Pay later for a saved customer, then completes it through the normal
        /// status path (stock deduction included). Walk-ins are refused by the database.</summary>
        [HttpPost("orders/{id:int}/pay-later")]
        public async Task<IActionResult> PayLater(int id, [FromBody] RestaurantPayLaterRequest r)
        {
            var d = Deny(r.FarmId); if (d != null) return d;
            await _svc.MarkPayLaterAsync(r.FarmId, id, r.CustomerId, r.DueDate, r.Notes, Me);
            await _orders.UpdateOrderStatusAsync(id, r.FarmId, "Completed");
            return Ok(new { orderId = id, status = "Completed" });
        }

        [HttpGet("customer-balances")]
        public async Task<IActionResult> Balances([FromQuery] string farmId, [FromQuery] DateTime? from, [FromQuery] DateTime? to,
            [FromQuery] int? customerId, [FromQuery] string? status, [FromQuery] decimal? minBalance, [FromQuery] string? search)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.BalancesAsync(farmId, from, to, customerId, status, minBalance, search)); }

        [HttpGet("customer-balances/summary")]
        public async Task<IActionResult> Summary([FromQuery] string farmId)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.SummaryAsync(farmId)); }

        [HttpGet("customer-balances/{customerId:int}/open-sales")]
        public async Task<IActionResult> OpenSales(int customerId, [FromQuery] string farmId, [FromQuery] DateTime? from,
            [FromQuery] DateTime? to, [FromQuery] string? status)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.OpenOrdersAsync(farmId, customerId, from, to, status)); }

        /// <summary>One cash-in to the chosen account; allocations must add up to the amount.</summary>
        [HttpPost("customer-payments")]
        public async Task<IActionResult> Record([FromBody] RecordPaymentRequest r)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var d = Deny(r.FarmId); if (d != null) return d;
            if (r.PartyId is null or 0) return BadRequest(new { message = "A customer is required to receive a payment." });
            if (r.Allocations.Count == 0) return BadRequest(new { message = "Select at least one sale to apply this payment to." });
            return Ok(new { paymentId = "CP-" + await _svc.RecordAsync(r, Me) });
        }

        /// <summary>Append-only: the money goes back out through a new ledger row dated today. A reason is required.</summary>
        [HttpPost("customer-payments/{paymentId}/reverse")]
        public async Task<IActionResult> Reverse(string paymentId, [FromBody] ReversePaymentRequest r)
        {
            var d = Deny(r.FarmId); if (d != null) return d;
            if (string.IsNullOrWhiteSpace(r.Reason)) return BadRequest(new { message = "A reason is required to reverse a payment." });
            return Ok(new { reversedAllocations = await _svc.ReverseAsync(r.FarmId, paymentId, r.Reason, Me) });
        }

        [HttpGet("customer-payments")]
        public async Task<IActionResult> History([FromQuery] string farmId, [FromQuery] int? customerId, [FromQuery] int? saleId,
            [FromQuery] DateTime? from, [FromQuery] DateTime? to)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.HistoryAsync(farmId, customerId, saleId, from, to)); }

        [HttpGet("customer-payments/{paymentId}")]
        public async Task<IActionResult> Get(string paymentId, [FromQuery] string farmId)
        {
            var d = Deny(farmId); if (d != null) return d;
            var header = (await _svc.HistoryAsync(farmId, null, null, null, null))
                .FirstOrDefault(p => string.Equals(p.PaymentId, paymentId, StringComparison.OrdinalIgnoreCase));
            if (header == null) return NotFound(new { message = "Payment not found." });
            return Ok(new { payment = header, allocations = await _svc.AllocationsAsync(farmId, paymentId) });
        }

        [HttpGet("customers/{customerId:int}/statement")]
        public async Task<IActionResult> Statement(int customerId, [FromQuery] string farmId, [FromQuery] DateTime? from, [FromQuery] DateTime? to)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.StatementAsync(farmId, customerId, from, to)); }

        /// <summary>Pay-later orders whose paid amount disagrees with their payments. Empty when healthy.</summary>
        [HttpGet("balances/audit")]
        public async Task<IActionResult> Audit([FromQuery] string farmId)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.AuditAsync(farmId)); }
    }
}
