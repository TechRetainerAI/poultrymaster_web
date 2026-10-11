// PROMPT 7: platform operations API with ROLE SEPARATION. The all-powerful
// roles (SystemAdmin, PlatformOwner) see everything; the scoped admin roles
// only their own surface:
//   TechnicalSupport — errors, releases, system health
//   SecurityAdmin    — security events
//   CustomerSuccess  — briefs (plus the health/CRM surfaces they already have)
// Feature-flag ADMINISTRATION stays SystemAdmin/PlatformOwner only (flags gate
// product rollout, so changing them is a platform-level power); flag EVALUATION
// is available to any authenticated app user.
// Exports are SystemAdmin/PlatformOwner only and every export is written to the
// audit trail explicitly (GET requests bypass the global audit filter).

using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/PlatformOps")]
    public class PlatformOpsController : ControllerBase
    {
        private readonly IPlatformOpsService _svc;
        private readonly IPlatformBriefService _briefs;
        private readonly IAuditLogService _audit;

        public PlatformOpsController(IPlatformOpsService svc, IPlatformBriefService briefs, IAuditLogService audit)
        {
            _svc = svc;
            _briefs = briefs;
            _audit = audit;
        }

        private string Actor =>
            User.FindFirst(ClaimTypes.Name)?.Value
            ?? User.FindFirst(ClaimTypes.NameIdentifier)?.Value
            ?? "platform-admin";

        // ---------------- error intelligence ----------------
        [HttpGet("errors")]
        [Authorize(Roles = "SystemAdmin,PlatformOwner,TechnicalSupport")]
        public async Task<IActionResult> Errors([FromQuery] int hours = 24)
            => Ok(await _svc.GetErrorDashboardAsync(hours));

        [HttpGet("errors/company/{companyId}")]
        [Authorize(Roles = "SystemAdmin,PlatformOwner,TechnicalSupport,CustomerSuccess")]
        public async Task<IActionResult> CompanyErrors(string companyId)
            => Ok(await _svc.GetCompanyErrorsAsync(companyId));

        // ---------------- security ----------------
        [HttpGet("security-events")]
        [Authorize(Roles = "SystemAdmin,PlatformOwner,SecurityAdmin")]
        public async Task<IActionResult> SecurityEvents([FromQuery] bool refresh = true)
            => Ok(await _svc.GetSecurityEventsAsync(refresh));

        // ---------------- feature flags ----------------
        [HttpGet("flags")]
        [Authorize(Roles = "SystemAdmin,PlatformOwner")]
        public async Task<IActionResult> Flags() => Ok(await _svc.GetFlagsAsync());

        [HttpPost("flags")]
        [Authorize(Roles = "SystemAdmin,PlatformOwner")]
        public async Task<IActionResult> CreateFlag([FromBody] FeatureFlagRequest req)
        {
            try { return Ok(await _svc.CreateFlagAsync(req, Actor)); }
            catch (ArgumentException ex) { return BadRequest(new { message = ex.Message }); }
        }

        [HttpPost("flags/{flagKey}/enabled")]
        [Authorize(Roles = "SystemAdmin,PlatformOwner")]
        public async Task<IActionResult> SetFlagEnabled(string flagKey, [FromBody] FlagRuleRequest req)
        {
            var flag = await _svc.SetFlagEnabledAsync(flagKey, req.Enabled, Actor, req.Reason);
            return flag is null ? NotFound(new { message = "Flag not found." }) : Ok(flag);
        }

        [HttpPost("flags/{flagKey}/rules")]
        [Authorize(Roles = "SystemAdmin,PlatformOwner")]
        public async Task<IActionResult> SetRule(string flagKey, [FromBody] FlagRuleRequest req)
        {
            try
            {
                var flag = await _svc.SetRuleAsync(flagKey, req, Actor);
                return flag is null ? NotFound(new { message = "Flag not found." }) : Ok(flag);
            }
            catch (ArgumentException ex) { return BadRequest(new { message = ex.Message }); }
        }

        [HttpDelete("flags/{flagKey}/rules")]
        [Authorize(Roles = "SystemAdmin,PlatformOwner")]
        public async Task<IActionResult> RemoveRule(string flagKey,
            [FromQuery] string scopeType, [FromQuery] string scopeValue = "", [FromQuery] string? reason = null)
        {
            var flag = await _svc.RemoveRuleAsync(flagKey, scopeType, scopeValue, Actor, reason);
            return flag is null ? NotFound(new { message = "Flag or rule not found." }) : Ok(flag);
        }

        [HttpGet("flags/audit")]
        [Authorize(Roles = "SystemAdmin,PlatformOwner,SecurityAdmin")]
        public async Task<IActionResult> FlagAudit([FromQuery] string? flagKey)
            => Ok(await _svc.GetFlagAuditAsync(flagKey));

        /// <summary>Flag evaluation for the product apps: any authenticated user may
        /// ask about a flag for their own context (no cross-tenant data returned —
        /// the answer is only on/off + which scope matched).</summary>
        [HttpGet("flags/{flagKey}/evaluate")]
        [Authorize]
        public async Task<IActionResult> EvaluateFlag(string flagKey, [FromQuery] string? companyId)
        {
            var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            return Ok(await _svc.EvaluateFlagAsync(flagKey, userId, companyId));
        }

        // ---------------- releases + system health ----------------
        [HttpGet("releases")]
        [Authorize(Roles = "SystemAdmin,PlatformOwner,TechnicalSupport")]
        public async Task<IActionResult> Releases() => Ok(await _svc.GetReleasesAsync());

        [HttpGet("system-health")]
        [Authorize(Roles = "SystemAdmin,PlatformOwner,TechnicalSupport")]
        public async Task<IActionResult> SystemHealth() => Ok(await _svc.GetSystemHealthAsync());

        // ---------------- briefs ----------------
        [HttpGet("briefs/{briefType}")]
        [Authorize(Roles = "SystemAdmin,PlatformOwner,CustomerSuccess,BillingAdmin")]
        public async Task<IActionResult> LatestBrief(string briefType)
        {
            var brief = await _briefs.GetLatestAsync(briefType);
            return brief is null ? NotFound(new { message = "No brief generated yet." }) : Ok(brief);
        }

        [HttpPost("briefs/{briefType}/generate")]
        [Authorize(Roles = "SystemAdmin,PlatformOwner,CustomerSuccess,BillingAdmin")]
        public async Task<IActionResult> GenerateBrief(string briefType)
            => Ok(await _briefs.GenerateAsync(briefType, Actor));

        // ---------------- audited export ----------------
        [HttpGet("export")]
        [Authorize(Roles = "SystemAdmin,PlatformOwner")]
        public async Task<IActionResult> Export([FromQuery] string dataset = "organizations")
        {
            string csv;
            try { csv = await _svc.ExportCsvAsync(dataset); }
            catch (ArgumentException ex) { return BadRequest(new { message = ex.Message }); }

            // GETs bypass the global audit filter — exports are logged explicitly.
            try
            {
                await _audit.InsertAsync(new AuditLogModel
                {
                    UserId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value ?? "unknown",
                    UserName = Actor,
                    Action = "EXPORT",
                    Resource = "PlatformOps",
                    Details = $"Exported analytics dataset '{dataset}' as CSV",
                    Timestamp = DateTime.UtcNow,
                    Status = "Success",
                    FarmId = "Platform",
                });
            }
            catch { /* export must not fail because auditing hiccuped; filter logs remain */ }

            return File(System.Text.Encoding.UTF8.GetBytes(csv), "text/csv",
                $"visibilitycore-{dataset}-{DateTime.UtcNow:yyyyMMdd}.csv");
        }
    }
}
