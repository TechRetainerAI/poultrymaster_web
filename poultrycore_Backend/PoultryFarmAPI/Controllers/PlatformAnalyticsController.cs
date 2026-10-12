// PROMPT 4: onboarding/activation, feature adoption and retention analytics
// for the Admin app. Same cross-tenant gate as the rest of the platform-admin
// surface (SystemAdmin / PlatformOwner, enforced server-side).

using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/PlatformAnalytics")]
    [Authorize(Roles = "SystemAdmin,PlatformOwner,CustomerSuccess")]
    public class PlatformAnalyticsController : ControllerBase
    {
        private readonly IPlatformAnalyticsService _svc;

        public PlatformAnalyticsController(IPlatformAnalyticsService svc) => _svc = svc;

        /// <summary>Per-company onboarding rows (setup %, missing milestones, activation).</summary>
        [HttpGet("onboarding")]
        public async Task<IActionResult> Onboarding(
            [FromQuery] string? companyFamily, [FromQuery] string? template, [FromQuery] string? country)
            => Ok(await _svc.GetOnboardingAsync(companyFamily, template, country));

        /// <summary>One company's milestone checklist (explains the setup %).</summary>
        [HttpGet("milestones/{companyId}")]
        public async Task<IActionResult> Milestones(string companyId)
            => Ok(await _svc.GetMilestonesAsync(companyId));

        /// <summary>Activation funnel. month = signup month (yyyy-MM).</summary>
        [HttpGet("funnel")]
        public async Task<IActionResult> Funnel(
            [FromQuery] string? month, [FromQuery] string? companyFamily,
            [FromQuery] string? template, [FromQuery] string? country)
            => Ok(await _svc.GetFunnelAsync(month, companyFamily, template, country));

        /// <summary>Feature adoption matrix (percent of applicable companies per vertical).</summary>
        [HttpGet("feature-adoption")]
        public async Task<IActionResult> FeatureAdoption([FromQuery] int? days)
            => Ok(await _svc.GetFeatureAdoptionAsync(days));

        /// <summary>Feature first/last use + usage depth (optionally one company).</summary>
        [HttpGet("feature-usage")]
        public async Task<IActionResult> FeatureUsage([FromQuery] string? companyId)
            => Ok(await _svc.GetFeatureUsageAsync(companyId));

        /// <summary>Retention cohorts. scope=org|company; cohortBy=signupMonth|signupWeek|activationMonth.
        /// Retained at Day N = meaningful activity within D1 [1,7) D7 [7,30) D30 [30,60) D60 [60,90) D90 [90,120).</summary>
        [HttpGet("retention")]
        public async Task<IActionResult> Retention(
            [FromQuery] string scope = "org", [FromQuery] string cohortBy = "signupMonth",
            [FromQuery] string? companyFamily = null, [FromQuery] string? template = null,
            [FromQuery] string? country = null)
            => Ok(await _svc.GetRetentionAsync(scope, cohortBy, companyFamily, template, country));
    }
}
