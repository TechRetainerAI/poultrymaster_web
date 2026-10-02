// Hotel Sales, Payments, Customer Balances, Supplier Balances and Supplier
// Payments (migration 332).
//
//   /api/Hotel/balances/customer-balances ...  \
//   /api/Hotel/balances/customer-payments ...   |  the SAME contract PoultryBalancesController
//   /api/Hotel/balances/supplier-balances ...   }  answers (lib/api/balances.ts, module "hotel"),
//   /api/Hotel/balances/supplier-payments ...   |  so components/balances and components/payments
//   /api/Hotel/balances/{customers|suppliers}/{id}/statement, /audit  /  work unchanged.
//   /api/Hotel/sales, /api/Hotel/sales/{bookingId}/bill-to   the Sales page.
//
// Under /balances because /api/Hotel/customer-payments and /supplier-payments
// already exist (the Draft/Approve documents of 319/321) -- Generic's reason too.
// Every action checks the caller's JWT company; the acting user comes from the
// token, never the body; refusals come back as 400 with the database's sentence.

using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Filters;
using PoultryFarmAPIWeb.Helpers;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    public class HotelSaleBillToRequest { public string FarmId { get; set; } = ""; public int HotelCustomerId { get; set; } }

    [ApiController][Authorize][Route("api/Hotel")][HotelBusinessRuleFilter]
    public class HotelBalancesController : ControllerBase
    {
        private readonly IHotelBalanceService _svc;
        public HotelBalancesController(IHotelBalanceService svc) { _svc = svc; }

        private string By => HotelAuthHelper.GetUserName(User);
        private IActionResult? Deny(string? farmId) =>
            string.IsNullOrWhiteSpace(farmId) ? BadRequest(new { message = "Company ID is required." }) : HotelAuthHelper.VerifyFarmOwnership(User, farmId);

        // ---- Sales ------------------------------------------------------------
        [HttpGet("sales")]
        public async Task<IActionResult> Sales([FromQuery] string farmId, [FromQuery] DateTime? from, [FromQuery] DateTime? to)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.SalesAsync(farmId, from, to)); }

        /// <summary>Bills a checked-out stay's balance to a corporate account.</summary>
        [HttpPost("sales/{bookingId:int}/bill-to")]
        public async Task<IActionResult> BillTo(int bookingId, [FromBody] HotelSaleBillToRequest r)
        {
            var d = Deny(r.FarmId); if (d != null) return d;
            return Ok(new { hotelInvoiceId = await _svc.BillToAccountAsync(r.FarmId, bookingId, r.HotelCustomerId, By) });
        }

        /// <summary>Sales → Delete on a stay (refused once anything was paid).</summary>
        [HttpDelete("sales/{bookingId:int}")]
        public async Task<IActionResult> DeleteStay(int bookingId, [FromQuery] string farmId)
        {
            var d = Deny(farmId); if (d != null) return d;
            var refusal = await _svc.DeleteStayAsync(farmId, bookingId);
            return refusal == null ? NoContent() : BadRequest(new { message = refusal });
        }

        // ---- Balances (both sides) -------------------------------------------
        [HttpGet("balances/customer-balances")]
        public Task<IActionResult> CustomerBalances([FromQuery] string farmId, [FromQuery] DateTime? from, [FromQuery] DateTime? to,
            [FromQuery] int? customerId, [FromQuery] string? status, [FromQuery] decimal? minBalance, [FromQuery] string? search)
            => Balances("customer", farmId, from, to, customerId, status, minBalance, search);

        [HttpGet("balances/supplier-balances")]
        public Task<IActionResult> SupplierBalances([FromQuery] string farmId, [FromQuery] DateTime? from, [FromQuery] DateTime? to,
            [FromQuery] int? supplierId, [FromQuery] string? status, [FromQuery] decimal? minBalance, [FromQuery] string? search)
            => Balances("supplier", farmId, from, to, supplierId, status, minBalance, search);

        private async Task<IActionResult> Balances(string side, string farmId, DateTime? from, DateTime? to, int? partyId,
            string? status, decimal? minBalance, string? search)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.BalancesAsync(side, farmId, from, to, partyId, status, minBalance, search)); }

        [HttpGet("balances/customer-balances/summary")]
        public async Task<IActionResult> CustomerSummary([FromQuery] string farmId)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.SummaryAsync("customer", farmId)); }

        [HttpGet("balances/supplier-balances/summary")]
        public async Task<IActionResult> SupplierSummary([FromQuery] string farmId)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.SummaryAsync("supplier", farmId)); }

        [HttpGet("balances/customer-balances/{partyId:int}/open-sales")]
        public async Task<IActionResult> OpenSales(int partyId, [FromQuery] string farmId, [FromQuery] DateTime? from, [FromQuery] DateTime? to, [FromQuery] string? status)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.OpenDocumentsAsync("customer", farmId, partyId, from, to, status)); }

        [HttpGet("balances/supplier-balances/{supplierId:int}/open-purchases")]
        public async Task<IActionResult> OpenPurchases(int supplierId, [FromQuery] string farmId, [FromQuery] DateTime? from, [FromQuery] DateTime? to, [FromQuery] string? status)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.OpenDocumentsAsync("supplier", farmId, supplierId, from, to, status)); }

        // ---- Payments ---------------------------------------------------------
        [HttpPost("balances/customer-payments")]
        public Task<IActionResult> RecordCustomer([FromBody] RecordPaymentRequest r) => Record("customer", r);

        [HttpPost("balances/supplier-payments")]
        public Task<IActionResult> RecordSupplier([FromBody] RecordPaymentRequest r) => Record("supplier", r);

        private async Task<IActionResult> Record(string side, RecordPaymentRequest r)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var d = Deny(r.FarmId); if (d != null) return d;
            if (r.PartyId is null or 0)
                return BadRequest(new { message = side == "customer" ? "A customer is required to receive a payment." : "Choose the supplier this payment is for." });
            if (r.Allocations.Count == 0)
                return BadRequest(new { message = side == "customer" ? "Select at least one sale to apply this payment to." : "Select at least one purchase to apply this payment to." });
            return Ok(new { paymentId = await _svc.RecordAsync(side, r, By) });
        }

        /// <summary>Append-only: the money comes back through a new ledger row dated today. A reason is required.</summary>
        [HttpPost("balances/customer-payments/{paymentId}/reverse")]
        public Task<IActionResult> ReverseCustomer(string paymentId, [FromBody] ReversePaymentRequest r) => Reverse("customer", paymentId, r);

        [HttpPost("balances/supplier-payments/{paymentId}/reverse")]
        public Task<IActionResult> ReverseSupplier(string paymentId, [FromBody] ReversePaymentRequest r) => Reverse("supplier", paymentId, r);

        private async Task<IActionResult> Reverse(string side, string paymentId, ReversePaymentRequest r)
        {
            var d = Deny(r.FarmId); if (d != null) return d;
            if (string.IsNullOrWhiteSpace(r.Reason)) return BadRequest(new { message = "A reason is required to reverse a payment." });
            if (side == "customer" ? !Guid.TryParse(paymentId, out _) : !int.TryParse(paymentId, out _))
                return NotFound(new { message = "Payment not found for this company." });
            return Ok(new { reversedAllocations = await _svc.ReverseAsync(side, r.FarmId, paymentId, r.Reason, By) });
        }

        [HttpGet("balances/customer-payments")]
        public async Task<IActionResult> CustomerPayments([FromQuery] string farmId, [FromQuery] int? customerId, [FromQuery] int? saleId,
            [FromQuery] DateTime? from, [FromQuery] DateTime? to)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.HistoryAsync("customer", farmId, customerId, null, saleId, from, to)); }

        [HttpGet("balances/supplier-payments")]
        public async Task<IActionResult> SupplierPayments([FromQuery] string farmId, [FromQuery] int? supplierId, [FromQuery] string? documentType,
            [FromQuery] int? documentId, [FromQuery] DateTime? from, [FromQuery] DateTime? to)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.HistoryAsync("supplier", farmId, supplierId, documentType, documentId, from, to)); }

        [HttpGet("balances/customer-payments/{paymentId}")]
        public Task<IActionResult> CustomerPayment(string paymentId, [FromQuery] string farmId) => Payment("customer", paymentId, farmId);

        [HttpGet("balances/supplier-payments/{paymentId}")]
        public Task<IActionResult> SupplierPayment(string paymentId, [FromQuery] string farmId) => Payment("supplier", paymentId, farmId);

        private async Task<IActionResult> Payment(string side, string paymentId, string farmId)
        {
            var d = Deny(farmId); if (d != null) return d;
            var header = (await _svc.HistoryAsync(side, farmId, null, null, null, null, null))
                .FirstOrDefault(p => string.Equals(p.PaymentId, paymentId, StringComparison.OrdinalIgnoreCase));
            if (header == null) return NotFound(new { message = "Payment not found." });
            return Ok(new { payment = header, allocations = await _svc.AllocationsAsync(side, farmId, paymentId) });
        }

        // ---- Statements & audit ---------------------------------------------
        [HttpGet("balances/customers/{partyId:int}/statement")]
        public async Task<IActionResult> CustomerStatement(int partyId, [FromQuery] string farmId, [FromQuery] DateTime? from, [FromQuery] DateTime? to)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.StatementAsync("customer", farmId, partyId, from, to)); }

        [HttpGet("balances/suppliers/{supplierId:int}/statement")]
        public async Task<IActionResult> SupplierStatement(int supplierId, [FromQuery] string farmId, [FromQuery] DateTime? from, [FromQuery] DateTime? to)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.StatementAsync("supplier", farmId, supplierId, from, to)); }

        /// <summary>Documents whose allocations disagree with their payments. Empty when healthy.</summary>
        [HttpGet("balances/audit")]
        public async Task<IActionResult> Audit([FromQuery] string farmId)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.AuditAsync(farmId)); }
    }
}
