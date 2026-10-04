// Flock anomaly alerts (migration 338).
//
// PERMISSIONS: the route maps to poultry.health in IamPermissionMap -- a flock
// dying, laying less or eating differently is flock health. GET = view (see
// alerts and why they fired); POST acknowledge / notes / resolve / scan =
// create; PUT settings = edit (change thresholds). No segment here is named
// approve/reverse/post, so nothing resolves to a key no role holds.
//
// Detection is system work, not a user action: GET with refresh=true (the
// default) re-runs the idempotent scan for yesterday + today on the company's
// calendar before listing, so anyone who may SEE alerts sees current ones.

using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Npgsql;
using PoultryFarmAPIWeb.Business;

namespace PoultryFarmAPIWeb.Controllers
{
    [Authorize]
    [ApiController]
    [Route("api/Poultry/flock-alerts")]
    public class PoultryFlockAlertsController : ControllerBase
    {
        private readonly IPoultryFlockAnomalyService _svc;
        public PoultryFlockAlertsController(IPoultryFlockAnomalyService svc) => _svc = svc;

        public class AlertActionBody
        {
            public string FarmId { get; set; } = string.Empty;
            public string? Note { get; set; }
        }

        public class ScanBody
        {
            public string FarmId { get; set; } = string.Empty;
            public DateTime? From { get; set; }
            public DateTime? To { get; set; }
        }

        public class ResetBody
        {
            public string FarmId { get; set; } = string.Empty;
            public string SignalKey { get; set; } = string.Empty;
        }

        private string? Actor => User.FindFirst(ClaimTypes.Name)?.Value ?? User.FindFirst(ClaimTypes.NameIdentifier)?.Value;

        /// <summary>
        /// Alerts, most urgent first. status: active (default: Open + Acknowledged) | all | Open |
        /// Acknowledged | Resolved | Cleared.
        /// </summary>
        [HttpGet]
        public async Task<ActionResult<IEnumerable<FlockAlert>>> List(
            [FromQuery] string farmId, [FromQuery] string? status, [FromQuery] DateTime? from, [FromQuery] DateTime? to,
            [FromQuery] int? flockId, [FromQuery] bool refresh = true)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            if (refresh) await _svc.ScanAsync(farmId, null, null, "system");
            return Ok(await _svc.ListAsync(farmId, status, from, to, flockId, null));
        }

        /// <summary>One alert with its full, append-only history.</summary>
        [HttpGet("{alertId:int}")]
        public async Task<IActionResult> Get(int alertId, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var alert = (await _svc.ListAsync(farmId, "all", null, null, null, alertId)).FirstOrDefault();
            if (alert is null) return NotFound(new { message = "Alert not found." });
            return Ok(new { alert, events = await _svc.GetEventsAsync(farmId, alertId) });
        }

        /// <summary>
        /// Every enabled signal for every flock with a record on the date -- including the ones
        /// that did NOT fire, and why. Read-only; the structured evidence a future assistant reads.
        /// </summary>
        [HttpGet("evaluation")]
        public async Task<ActionResult<IEnumerable<FlockSignalEvaluation>>> Evaluate([FromQuery] string farmId, [FromQuery] DateTime? date)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.EvaluateAsync(farmId, date));
        }

        /// <summary>Re-check a date range (e.g. after back-dated corrections). At most 93 days; never past today.</summary>
        [HttpPost("scan")]
        public async Task<IActionResult> Scan([FromBody] ScanBody body)
        {
            if (string.IsNullOrWhiteSpace(body.FarmId)) return BadRequest("Company ID is required.");
            return await Guarded(async () => Ok(await _svc.ScanAsync(body.FarmId, body.From, body.To, Actor)));
        }

        [HttpPost("{alertId:int}/acknowledge")]
        public Task<IActionResult> Acknowledge(int alertId, [FromBody] AlertActionBody body)
            => Act(body, () => _svc.AcknowledgeAsync(body.FarmId, alertId, body.Note, Actor));

        [HttpPost("{alertId:int}/notes")]
        public Task<IActionResult> AddNote(int alertId, [FromBody] AlertActionBody body)
            => Act(body, () => _svc.AddNoteAsync(body.FarmId, alertId, body.Note ?? string.Empty, Actor));

        [HttpPost("{alertId:int}/resolve")]
        public Task<IActionResult> Resolve(int alertId, [FromBody] AlertActionBody body)
            => Act(body, () => _svc.ResolveAsync(body.FarmId, alertId, body.Note ?? string.Empty, Actor));

        [HttpGet("settings")]
        public async Task<ActionResult<IEnumerable<FlockAnomalySignalSetting>>> GetSettings([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetSettingsAsync(farmId));

        /// <summary>Save one signal's configuration for the company.</summary>
        [HttpPut("settings")]
        public async Task<IActionResult> SetSetting([FromBody] FlockAnomalySignalSetting body)
        {
            if (string.IsNullOrWhiteSpace(body.FarmId)) return BadRequest("Company ID is required.");
            return await Guarded(async () => { await _svc.SetSettingAsync(body, Actor); return NoContent(); });
        }

        /// <summary>Put one signal back to the built-in defaults. Alert history is untouched.</summary>
        [HttpPut("settings/reset")]
        public async Task<IActionResult> ResetSetting([FromBody] ResetBody body)
        {
            if (string.IsNullOrWhiteSpace(body.FarmId)) return BadRequest("Company ID is required.");
            return await Guarded(async () => { await _svc.ResetSettingAsync(body.FarmId, body.SignalKey); return NoContent(); });
        }

        private async Task<IActionResult> Act(AlertActionBody body, Func<Task> action)
        {
            if (string.IsNullOrWhiteSpace(body.FarmId)) return BadRequest("Company ID is required.");
            return await Guarded(async () => { await action(); return NoContent(); });
        }

        private async Task<IActionResult> Guarded(Func<Task<IActionResult>> action)
        {
            try
            {
                return await action();
            }
            catch (PostgresException ex) when (ex.SqlState == "P0002")
            {
                return NotFound(new { message = ex.MessageText });
            }
            catch (PostgresException ex) when (ex.SqlState is "P0001" or "23514")
            {
                return BadRequest(new { message = ex.SqlState == "P0001" ? ex.MessageText
                    : "Those settings are not valid: Critical must be above Warning, Information below Warning, and the baseline 3–90 days." });
            }
        }
    }
}
