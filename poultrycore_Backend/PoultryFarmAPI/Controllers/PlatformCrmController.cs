// PROMPT 5: Customer Success CRM API behind Organization/Company 360.
// SystemAdmin/PlatformOwner only (server-side; customers can never read these),
// every mutating call also lands in auditlogs via the global filter.
//
// VIEW-AS-CUSTOMER (spec section 12): write-capable impersonation is NOT
// implemented. The customer-facing app cannot currently guarantee the required
// safeguards (support banner, enforced read-only mode, scoped short-lived
// session), so per the spec's own fallback the admin 360 pages ARE the
// read-only support context: they show usage, setup, billing and operational
// summaries without ever exposing passwords, tokens or payment credentials.

using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/PlatformCrm")]
    [Authorize(Roles = "SystemAdmin,PlatformOwner,CustomerSuccess")]
    public class PlatformCrmController : ControllerBase
    {
        private readonly ICustomerCrmService _svc;

        public PlatformCrmController(ICustomerCrmService svc) => _svc = svc;

        private string Actor =>
            User.FindFirst(ClaimTypes.Name)?.Value
            ?? User.FindFirst(ClaimTypes.NameIdentifier)?.Value
            ?? "platform-admin";

        /// <summary>Combined significant-event timeline for an organization (optionally one company).</summary>
        [HttpGet("timeline")]
        public async Task<IActionResult> Timeline(
            [FromQuery] string organizationId, [FromQuery] string? companyId, [FromQuery] int limit = 100)
        {
            if (string.IsNullOrWhiteSpace(organizationId))
                return BadRequest(new { message = "organizationId is required." });
            return Ok(await _svc.GetTimelineAsync(organizationId, companyId, limit));
        }

        [HttpGet("notes")]
        public async Task<IActionResult> Notes(
            [FromQuery] string? organizationId, [FromQuery] string? companyId, [FromQuery] string? category,
            [FromQuery] string? assignee, [FromQuery] string? contactType,
            [FromQuery] DateTime? followUpFrom, [FromQuery] DateTime? followUpTo)
            => Ok(await _svc.GetNotesAsync(organizationId, companyId, category, assignee, contactType, followUpFrom, followUpTo));

        [HttpPost("notes")]
        public async Task<IActionResult> AddNote([FromBody] CrmNoteRequest req)
        {
            try { return Ok(await _svc.AddNoteAsync(req, Actor)); }
            catch (ArgumentException ex) { return BadRequest(new { message = ex.Message }); }
        }

        [HttpPost("notes/{id:long}/outcome")]
        public async Task<IActionResult> SetOutcome(long id, [FromBody] AttentionActionRequest req)
        {
            if (string.IsNullOrWhiteSpace(req?.Note))
                return BadRequest(new { message = "Outcome text is required." });
            var note = await _svc.SetNoteOutcomeAsync(id, req.Note, Actor);
            return note is null ? NotFound(new { message = "Note not found." }) : Ok(note);
        }

        [HttpGet("feedback")]
        public async Task<IActionResult> Feedback([FromQuery] string? organizationId, [FromQuery] string? status)
            => Ok(await _svc.GetFeedbackAsync(organizationId, status));

        [HttpPost("feedback")]
        public async Task<IActionResult> AddFeedback([FromBody] ProductFeedbackRequest req)
        {
            try { return Ok(await _svc.AddFeedbackAsync(req, Actor)); }
            catch (ArgumentException ex) { return BadRequest(new { message = ex.Message }); }
        }

        [HttpPost("feedback/{id:long}/status")]
        public async Task<IActionResult> SetFeedbackStatus(long id, [FromBody] AttentionActionRequest req)
        {
            if (string.IsNullOrWhiteSpace(req?.Note))
                return BadRequest(new { message = "Status is required." });
            var fb = await _svc.SetFeedbackStatusAsync(id, req.Note.Trim());
            return fb is null ? NotFound(new { message = "Feedback not found." }) : Ok(fb);
        }

        [HttpGet("cancellation-reasons")]
        public async Task<IActionResult> CancellationReasons([FromQuery] string? organizationId)
            => Ok(await _svc.GetCancellationReasonsAsync(organizationId));

        [HttpPost("cancellation-reasons")]
        public async Task<IActionResult> AddCancellationReason([FromBody] CancellationReasonRequest req)
        {
            try { return Ok(await _svc.AddCancellationReasonAsync(req, Actor)); }
            catch (ArgumentException ex) { return BadRequest(new { message = ex.Message }); }
        }

        /// <summary>Concise vertical-specific support context (adapter per family).</summary>
        [HttpGet("vertical-summary/{companyId}")]
        public async Task<IActionResult> VerticalSummary(string companyId)
            => Ok(await _svc.GetVerticalSummaryAsync(companyId));

        /// <summary>Organization activity rollup: 7/30/90-day windows + top categories + next billing.</summary>
        [HttpGet("organization-activity/{organizationId}")]
        public async Task<IActionResult> OrganizationActivity(string organizationId)
            => Ok(await _svc.GetOrgActivitySummaryAsync(organizationId));
    }
}
