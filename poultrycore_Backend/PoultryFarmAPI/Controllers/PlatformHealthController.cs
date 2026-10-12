// PROMPT 3: Customer Success API — health sweep + Needs Attention queue and
// actions. Same cross-tenant gate as the rest of the platform-admin surface
// (SystemAdmin / PlatformOwner, enforced server-side). Every mutating call is
// also captured by the global audit filter.

using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/PlatformHealth")]
    [Authorize(Roles = "SystemAdmin,PlatformOwner,CustomerSuccess")]
    public class PlatformHealthController : ControllerBase
    {
        private readonly IPlatformHealthService _svc;

        public PlatformHealthController(IPlatformHealthService svc) => _svc = svc;

        private string Actor =>
            User.FindFirst(ClaimTypes.Name)?.Value
            ?? User.FindFirst(ClaimTypes.NameIdentifier)?.Value
            ?? "platform-admin";

        private string ActorId =>
            User.FindFirst(ClaimTypes.NameIdentifier)?.Value ?? Actor;

        /// <summary>Re-evaluates health for every organization/company, updates the
        /// attention queue (deduplicated) and auto-resolves cleared conditions.</summary>
        [HttpPost("evaluate")]
        public async Task<IActionResult> Evaluate() => Ok(await _svc.RunSweepAsync());

        /// <summary>The Needs Attention queue. status: omitted = live items
        /// (Open/Assigned/Contacted); or Open|Assigned|Contacted|Resolved|Dismissed|All.
        /// refresh=true (default) runs the sweep first so the queue is current.</summary>
        [HttpGet("queue")]
        public async Task<IActionResult> Queue([FromQuery] string? status, [FromQuery] bool refresh = true,
            [FromQuery] bool notes = true)
        {
            if (refresh) await _svc.RunSweepAsync();
            return Ok(await _svc.GetQueueAsync(status, notes));
        }

        [HttpPost("items/{id:long}/assign")]
        public async Task<IActionResult> Assign(long id, [FromBody] AttentionActionRequest? req)
        {
            var item = await _svc.AssignAsync(id, Actor,
                string.IsNullOrWhiteSpace(req?.UserId) ? ActorId : req!.UserId,
                string.IsNullOrWhiteSpace(req?.Name) ? Actor : req!.Name);
            return item is null ? NotFound(new { message = "Item not found or already closed." }) : Ok(item);
        }

        [HttpPost("items/{id:long}/contacted")]
        public async Task<IActionResult> Contacted(long id)
        {
            var item = await _svc.MarkContactedAsync(id, Actor);
            return item is null ? NotFound(new { message = "Item not found or already closed." }) : Ok(item);
        }

        [HttpPost("items/{id:long}/notes")]
        public async Task<IActionResult> AddNote(long id, [FromBody] AttentionActionRequest req)
        {
            if (string.IsNullOrWhiteSpace(req?.Note))
                return BadRequest(new { message = "Note text is required." });
            var item = await _svc.AddNoteAsync(id, Actor, req.Note.Trim());
            return item is null ? NotFound(new { message = "Item not found." }) : Ok(item);
        }

        [HttpPost("items/{id:long}/follow-up")]
        public async Task<IActionResult> FollowUp(long id, [FromBody] AttentionActionRequest req)
        {
            var item = await _svc.SetFollowUpAsync(id, Actor, req?.FollowUpAtUtc);
            return item is null ? NotFound(new { message = "Item not found." }) : Ok(item);
        }

        [HttpPost("items/{id:long}/resolve")]
        public async Task<IActionResult> Resolve(long id, [FromBody] AttentionActionRequest? req)
        {
            var item = await _svc.ResolveAsync(id, Actor, req?.Note?.Trim());
            return item is null ? NotFound(new { message = "Item not found or already closed." }) : Ok(item);
        }

        [HttpPost("items/{id:long}/dismiss")]
        public async Task<IActionResult> Dismiss(long id, [FromBody] AttentionActionRequest req)
        {
            if (string.IsNullOrWhiteSpace(req?.Note))
                return BadRequest(new { message = "A dismissal reason is required." });
            var item = await _svc.DismissAsync(id, Actor, req.Note.Trim());
            return item is null ? NotFound(new { message = "Item not found or already closed." }) : Ok(item);
        }
    }
}
