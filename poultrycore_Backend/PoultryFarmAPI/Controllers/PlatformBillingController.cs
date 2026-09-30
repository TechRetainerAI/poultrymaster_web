// Business Office → Subscription & Billing (migration 329).
//
// The caller passes userId on the query string like the rest of this API.
// Ownership is enforced by construction: every query runs through the
// caller's own billing account and their userfarms Owner rows, so a farmid
// or invoice id belonging to someone else never resolves (spec Part 31).
//
// Route segment "PlatformBilling" is deliberate: the frontend proxy routes
// by exact first path segment and must not collide with the segments it
// sends to the Login API (see UserQuickLinkController's note).

using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/PlatformBilling")]
    public class PlatformBillingController : ControllerBase
    {
        private readonly IPlatformBillingService _svc;
        public PlatformBillingController(IPlatformBillingService svc) => _svc = svc;

        /// <summary>
        /// The whole billing dashboard in one read: account (market, currency,
        /// trial), one row per company with its evaluated metric/tier/price,
        /// and the consolidated bill preview. Companies whose profile has no
        /// configured price come back PricingNotConfigured — shown, never
        /// charged (spec Part 39).
        /// </summary>
        [HttpGet("summary")]
        public async Task<ActionResult<BillingSummaryModel>> Summary([FromQuery] string userId)
        {
            if (string.IsNullOrWhiteSpace(userId)) return BadRequest("userId is required.");
            return Ok(await _svc.GetSummaryAsync(userId));
        }

        [HttpGet("invoices")]
        public async Task<ActionResult<List<PlatformInvoiceModel>>> Invoices([FromQuery] string userId)
        {
            if (string.IsNullOrWhiteSpace(userId)) return BadRequest("userId is required.");
            return Ok(await _svc.GetInvoicesAsync(userId));
        }

        [HttpGet("payments")]
        public async Task<ActionResult<List<PlatformPaymentModel>>> Payments([FromQuery] string userId)
        {
            if (string.IsNullOrWhiteSpace(userId)) return BadRequest("userId is required.");
            return Ok(await _svc.GetPaymentsAsync(userId));
        }

        /// <summary>"Why this price?" from the stored evaluation snapshot (spec 22.5).</summary>
        [HttpGet("explain")]
        public async Task<ActionResult<PricingExplainModel>> Explain(
            [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(userId)) return BadRequest("userId is required.");
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var m = await _svc.ExplainAsync(userId, farmId);
            return m is null ? NotFound("No billing evaluation exists for this company yet.") : Ok(m);
        }

        /// <summary>
        /// Generate (or reuse) this period's consolidated invoice and start a
        /// provider checkout for its balance. Amount and currency are computed
        /// server-side from the invoice — nothing from the browser is trusted.
        /// </summary>
        [HttpPost("checkout")]
        public async Task<ActionResult<StartCheckoutResponse>> Checkout([FromBody] StartCheckoutRequest req)
        {
            var res = await _svc.StartCheckoutAsync(req);
            return res.Success ? Ok(res) : BadRequest(res);
        }

        /// <summary>
        /// Settle by authoritative provider verification after the browser
        /// returns. Idempotent with the webhook: whichever arrives second
        /// becomes a no-op (spec 13.3/13.4).
        /// </summary>
        [HttpGet("verify")]
        public async Task<IActionResult> Verify([FromQuery] string userId, [FromQuery] string reference)
        {
            if (string.IsNullOrWhiteSpace(userId)) return BadRequest("userId is required.");
            if (string.IsNullOrWhiteSpace(reference)) return BadRequest("reference is required.");
            var (ok, message) = await _svc.VerifyAndSettleAsync(userId, reference);
            return ok ? Ok(new { ok, message }) : BadRequest(new { ok, message });
        }

        // -------- Market change: a controlled request flow (spec 3.7/46) ----

        /// <summary>What the bill would look like in another market — nothing persisted.</summary>
        [HttpGet("market-preview")]
        public async Task<ActionResult<MarketChangePreviewModel>> MarketPreview(
            [FromQuery] string userId, [FromQuery] string marketCode)
        {
            if (string.IsNullOrWhiteSpace(userId)) return BadRequest("userId is required.");
            var m = await _svc.PreviewMarketAsync(userId, marketCode);
            return m is null ? NotFound($"Unknown market {marketCode}.") : Ok(m);
        }

        [HttpPost("market-change")]
        public async Task<IActionResult> RequestMarketChange([FromBody] MarketChangeRequestBody req)
        {
            if (string.IsNullOrWhiteSpace(req?.UserId)) return BadRequest("userId is required.");
            var (ok, message) = await _svc.RequestMarketChangeAsync(req.UserId, req.MarketCode ?? "", req.Reason);
            return ok ? Ok(new { ok, message }) : BadRequest(new { ok, message });
        }

        [HttpDelete("market-change")]
        public async Task<IActionResult> CancelMarketChange([FromQuery] string userId)
        {
            if (string.IsNullOrWhiteSpace(userId)) return BadRequest("userId is required.");
            var (ok, message) = await _svc.CancelMarketChangeAsync(userId);
            return ok ? Ok(new { ok, message }) : BadRequest(new { ok, message });
        }

        // -------- Cycle & cancellation (spec 11.3 / 21) ---------------------

        [HttpPost("billing-cycle")]
        public async Task<IActionResult> SetCycle([FromBody] BillingCycleBody req)
        {
            if (string.IsNullOrWhiteSpace(req?.UserId)) return BadRequest("userId is required.");
            var (ok, message) = await _svc.SetBillingCycleAsync(req.UserId, req.Cycle ?? "");
            return ok ? Ok(new { ok, message }) : BadRequest(new { ok, message });
        }

        [HttpPost("cancel")]
        public async Task<IActionResult> Cancel([FromBody] CancelBody req)
        {
            if (string.IsNullOrWhiteSpace(req?.UserId)) return BadRequest("userId is required.");
            var (ok, message) = await _svc.CancelAtPeriodEndAsync(req.UserId, req.Reason);
            return ok ? Ok(new { ok, message }) : BadRequest(new { ok, message });
        }

        [HttpPost("reactivate")]
        public async Task<IActionResult> Reactivate([FromBody] CancelBody req)
        {
            if (string.IsNullOrWhiteSpace(req?.UserId)) return BadRequest("userId is required.");
            var (ok, message) = await _svc.ReactivateAsync(req.UserId);
            return ok ? Ok(new { ok, message }) : BadRequest(new { ok, message });
        }

        // -------- Company-level Plan & Usage + entitlements (23/17) ---------

        [HttpGet("plan-usage")]
        public async Task<ActionResult<PlanUsageModel>> PlanUsage(
            [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(userId)) return BadRequest("userId is required.");
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var m = await _svc.GetPlanUsageAsync(userId, farmId);
            return m is null ? NotFound("No plan information exists for this company yet.") : Ok(m);
        }

        [HttpGet("entitlements")]
        public async Task<ActionResult<List<EntitlementModel>>> Entitlements(
            [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(userId)) return BadRequest("userId is required.");
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetEntitlementsAsync(userId, farmId));
        }
    }

    public class MarketChangeRequestBody
    {
        public string UserId { get; set; } = string.Empty;
        public string? MarketCode { get; set; }
        public string? Reason { get; set; }
    }

    public class BillingCycleBody
    {
        public string UserId { get; set; } = string.Empty;
        public string? Cycle { get; set; }
    }

    public class CancelBody
    {
        public string UserId { get; set; } = string.Empty;
        public string? Reason { get; set; }
    }

    /// <summary>
    /// Provider webhooks. Unauthenticated by necessity; authenticity comes
    /// from the HMAC signature over the raw body, and duplicates die on the
    /// event store's unique payload hash (spec Part 13).
    /// </summary>
    [ApiController]
    [Route("api/PlatformBillingWebhook")]
    public class PlatformBillingWebhookController : ControllerBase
    {
        private readonly IPlatformBillingService _svc;
        public PlatformBillingWebhookController(IPlatformBillingService svc) => _svc = svc;

        [HttpPost("paystack")]
        public async Task<IActionResult> Paystack()
        {
            using var reader = new StreamReader(Request.Body);
            var payload = await reader.ReadToEndAsync();
            var signature = Request.Headers["x-paystack-signature"].ToString();
            var (ok, message) = await _svc.ProcessPaystackWebhookAsync(payload, signature);
            // Always 200 on verified deliveries so the provider stops retrying;
            // 400 only for bad signatures, which are not the provider.
            return ok ? Ok(new { message }) : BadRequest(new { message });
        }
    }
}
