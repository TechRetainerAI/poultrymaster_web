using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // Business templates, service plans, subscriptions and billing runs for the
    // Generic company (migrations 242-243).
    //
    // Every action opens with GenericFarmGuard.EnsureAsync, the same guard the
    // rest of the Generic tree uses: a wrong company type gets a 409 rather than
    // a confusing SQL error.
    //
    // AuditLogActionFilter is registered globally, so every write below is
    // audited without code here -- but its farmId cascade reads the query string
    // or the body, NOT the {farmId} route segment, which is why the request
    // bodies carry FarmId and the actions stamp it from the route.

    // =========================================================================
    // Business template + module visibility.
    // =========================================================================
    [ApiController]
    [Route("api/generic-company/{farmId}")]
    public class GenericBusinessTemplateController : ControllerBase
    {
        private readonly IGenericBusinessTemplateService _svc;
        private readonly IGenericCompanyService _companies;

        public GenericBusinessTemplateController(
            IGenericBusinessTemplateService svc, IGenericCompanyService companies)
        {
            _svc = svc;
            _companies = companies;
        }

        /// <summary>
        /// Which template this company is on. Drives the labels the frontend
        /// shows -- "Member", "Student", "Fee Note" -- and returns nulls rather
        /// than 404 for a company that has never been templated.
        /// </summary>
        [HttpGet("business-template")]
        public async Task<ActionResult<GenericBusinessTemplateInfo>> GetTemplate(string farmId)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _svc.GetTemplate(farmId));
        }

        /// <summary>
        /// Which modules this company shows. Never 404s: a company with no
        /// settings row gets the synthesised default, which is everything on.
        /// </summary>
        [HttpGet("module-settings")]
        public async Task<ActionResult<GenericModuleSettings>> GetModuleSettings(string farmId)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _svc.GetModuleSettings(farmId));
        }

        [HttpPut("module-settings")]
        public async Task<ActionResult<GenericModuleSettings>> SaveModuleSettings(
            string farmId, [FromBody] GenericModuleSettings s)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            s.FarmId = farmId;
            return Ok(await _svc.SaveModuleSettings(s));
        }

        /// <summary>
        /// Applies a business + industry template: stamps the profile and seeds
        /// this industry's categories, cash accounts and starter plans. Safe to
        /// call again -- every seed is ON CONFLICT DO NOTHING.
        /// </summary>
        [HttpPost("business-template")]
        public async Task<IActionResult> ApplyTemplate(
            string farmId, [FromBody] ApplyBusinessTemplateRequest r)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            r.FarmId = farmId;
            await _svc.ApplyTemplate(r);
            return Ok(await _svc.GetModuleSettings(farmId));
        }
    }

    // =========================================================================
    // Service plans and subscriptions.
    // =========================================================================
    [ApiController]
    [Route("api/generic-company/{farmId}")]
    public class GenericSubscriptionsController : ControllerBase
    {
        private readonly IGenericSubscriptionService _svc;
        private readonly IGenericCompanyService _companies;

        public GenericSubscriptionsController(
            IGenericSubscriptionService svc, IGenericCompanyService companies)
        {
            _svc = svc;
            _companies = companies;
        }

        // ------------------------------------------------------------- plans

        [HttpGet("service-plans")]
        public async Task<ActionResult<IEnumerable<GenericServicePlanRow>>> GetPlans(
            string farmId, [FromQuery] bool activeOnly = false)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _svc.GetPlans(farmId, activeOnly));
        }

        /// <summary>
        /// Sets a service's plan type and billing frequency. Creating or renaming
        /// the service itself still goes through the service-catalogue endpoints.
        /// </summary>
        [HttpPut("service-plans/{serviceId:int}")]
        public async Task<IActionResult> SetPlan(
            string farmId, int serviceId, [FromBody] SetServicePlanRequest r)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            r.FarmId = farmId;
            await _svc.SetPlan(serviceId, r);
            return NoContent();
        }

        // ----------------------------------------------------- subscriptions

        [HttpGet("subscriptions")]
        public async Task<ActionResult<IEnumerable<GenericSubscriptionRow>>> GetAll(
            string farmId, [FromQuery] string? status)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _svc.GetAll(farmId, status));
        }

        [HttpPost("subscriptions")]
        public async Task<ActionResult> Create(string farmId, [FromBody] CreateSubscriptionRequest r)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            r.FarmId = farmId;
            var id = await _svc.Create(r);
            return Ok(new { genericSubscriptionId = id });
        }

        /// <summary>
        /// Pause, resume, suspend, cancel or expire. Cancelling needs a reason;
        /// the SP rejects a blank one rather than this layer guessing.
        /// </summary>
        [HttpPost("subscriptions/{subscriptionId:int}/status")]
        public async Task<IActionResult> SetStatus(
            string farmId, int subscriptionId, [FromBody] SetSubscriptionStatusRequest r)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            r.FarmId = farmId;
            await _svc.SetStatus(subscriptionId, r);
            return NoContent();
        }
    }

    // =========================================================================
    // Billing runs.
    // =========================================================================
    [ApiController]
    [Route("api/generic-company/{farmId}/billing-runs")]
    public class GenericBillingRunsController : ControllerBase
    {
        private readonly IGenericBillingService _svc;
        private readonly IGenericCompanyService _companies;

        public GenericBillingRunsController(
            IGenericBillingService svc, IGenericCompanyService companies)
        {
            _svc = svc;
            _companies = companies;
        }

        [HttpGet]
        public async Task<ActionResult<IEnumerable<BillingRunRow>>> GetRuns(string farmId)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _svc.GetRuns(farmId));
        }

        /// <summary>
        /// What generating right now would raise. Reads nothing into the books --
        /// preview and generate share the same selection in SQL, so what is shown
        /// here is exactly what generate will bill.
        /// </summary>
        [HttpGet("preview")]
        public async Task<ActionResult<IEnumerable<BillingPreviewRow>>> Preview(
            string farmId, [FromQuery] DateTime? asOf)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _svc.Preview(farmId, asOf));
        }

        /// <summary>
        /// Raises one DRAFT invoice per unbilled period. Draft on purpose:
        /// approving an invoice is what makes it a receivable, and that stays a
        /// human decision. Running it twice bills nobody twice.
        /// </summary>
        [HttpPost("generate")]
        public async Task<ActionResult> Generate(string farmId, [FromBody] GenerateBillingRequest r)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            r.FarmId = farmId;
            var runId = await _svc.Generate(r);
            var runs = await _svc.GetRuns(farmId);
            return Ok(runs.FirstOrDefault(x => x.GenericBillingRunId == runId)
                      ?? new BillingRunRow { GenericBillingRunId = runId });
        }
    }

    // =========================================================================
    // Invoices.
    // =========================================================================
    /// <summary>
    /// The Invoices list: genericsales read through an invoice lens, so an
    /// invoice a billing run raised and a counter sale that is still owed appear
    /// in the same place. Creating, approving and cancelling still belong to the
    /// Sales controller -- an invoice IS a sale, and one lifecycle is enough.
    /// </summary>
    [ApiController]
    [Route("api/generic-company/{farmId}/invoices")]
    public class GenericInvoicesController : ControllerBase
    {
        private readonly IGenericBillingService _svc;
        private readonly IGenericCompanyService _companies;

        public GenericInvoicesController(IGenericBillingService svc, IGenericCompanyService companies)
        {
            _svc = svc;
            _companies = companies;
        }

        [HttpGet]
        public async Task<ActionResult<IEnumerable<GenericInvoiceRow>>> GetInvoices(
            string farmId, [FromQuery] string? status, [FromQuery] bool subscriptionOnly = false,
            [FromQuery] DateTime? from = null, [FromQuery] DateTime? to = null)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _svc.GetInvoices(farmId, status, subscriptionOnly, from, to));
        }
    }
}
