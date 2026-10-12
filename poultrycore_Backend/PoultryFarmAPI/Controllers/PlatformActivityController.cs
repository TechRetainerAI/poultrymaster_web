// PROMPT 1 (Platform Activity Foundation): reusable platform-admin analytics
// API over the normalized activity layer. These endpoints are deliberately
// UI-agnostic — the Admin app's current pages and the dashboards of prompts
// 2-7 all consume the same service.
//
// SECURITY: cross-tenant analytics, so the same JWT gate as the platform audit
// feed and PlatformFarms (SystemAdmin / PlatformOwner only), enforced
// server-side. A normal customer token is rejected by role, never by UI.

using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/PlatformActivity")]
    [Authorize(Roles = "SystemAdmin,PlatformOwner,CustomerSuccess,BillingAdmin,TechnicalSupport,SecurityAdmin")]
    public class PlatformActivityController : ControllerBase
    {
        private readonly IPlatformActivityService _svc;

        public PlatformActivityController(IPlatformActivityService svc) => _svc = svc;

        /// <summary>Platform-wide activity overview (counts, statuses, trend, breakdowns).</summary>
        [HttpGet("overview")]
        public async Task<IActionResult> Overview([FromQuery] int? days)
            => Ok(await _svc.GetOverviewAsync(days));

        /// <summary>All organizations with their companies rolled up (company data preserved).</summary>
        [HttpGet("organizations")]
        public async Task<IActionResult> Organizations()
            => Ok(await _svc.GetOrganizationSummariesAsync());

        /// <summary>One organization's activity summary.</summary>
        [HttpGet("organizations/{organizationId}")]
        public async Task<IActionResult> Organization(string organizationId)
        {
            var org = await _svc.GetOrganizationAsync(organizationId);
            return org is null ? NotFound(new { message = "Organization not found." }) : Ok(org);
        }

        /// <summary>One company's activity summary incl. category breakdown.</summary>
        [HttpGet("companies/{companyId}")]
        public async Task<IActionResult> Company(string companyId)
        {
            var company = await _svc.GetCompanyAsync(companyId);
            return company is null ? NotFound(new { message = "Company not found." }) : Ok(company);
        }

        /// <summary>Daily activity time series (platform-wide, per organization, per company, per family).</summary>
        [HttpGet("timeseries")]
        public async Task<IActionResult> TimeSeries(
            [FromQuery] string? organizationId, [FromQuery] string? companyId,
            [FromQuery] string? companyFamily, [FromQuery] int? days)
            => Ok(await _svc.GetTimeSeriesAsync(organizationId, companyId, companyFamily, days));

        /// <summary>Deterministic "Going Quiet" list: previously active companies whose
        /// recent meaningful activity dropped to ~zero. Explicitly NOT a churn verdict.</summary>
        [HttpGet("going-quiet")]
        public async Task<IActionResult> GoingQuiet()
            => Ok(await _svc.GetGoingQuietAsync());

        /// <summary>New organizations in the window (default: last 31 days).</summary>
        [HttpGet("new-customers")]
        public async Task<IActionResult> NewCustomers([FromQuery] int? days)
            => Ok(await _svc.GetNewCustomersAsync(days));

        /// <summary>Module adoption: meaningful activity per category per vertical.</summary>
        [HttpGet("module-adoption")]
        public async Task<IActionResult> ModuleAdoption([FromQuery] int? days)
            => Ok(await _svc.GetModuleAdoptionAsync(days));

        /// <summary>Activity category breakdown (platform-wide, per organization, or per company).</summary>
        [HttpGet("categories")]
        public async Task<IActionResult> Categories(
            [FromQuery] string? organizationId, [FromQuery] string? companyId, [FromQuery] int? days)
            => Ok(await _svc.GetCategoryBreakdownAsync(organizationId, companyId, days));

        /// <summary>Most recent meaningful activity across the platform (filterable).</summary>
        [HttpGet("recent")]
        public async Task<IActionResult> Recent(
            [FromQuery] int limit = 50, [FromQuery] string? companyFamily = null,
            [FromQuery] string? organizationId = null, [FromQuery] string? companyId = null)
            => Ok(await _svc.GetRecentMeaningfulAsync(limit, companyFamily, organizationId, companyId));
    }
}
