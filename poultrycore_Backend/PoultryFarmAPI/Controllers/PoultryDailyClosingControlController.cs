// Daily Farm Closing / management control (migration 333).
//
// Same route prefix as the existing PoultryDailyClosingController, so the IAM
// map's "poultry/daily-closings" -> poultry.daily-closing entry covers these
// endpoints too; the literal segments here never collide with its {id:int}
// routes. The existing Draft -> Submitted -> Approved endpoints are unchanged
// and Approve now runs the same guarded close in SQL.
//
// PERMISSIONS
// The route map turns every POST into .create. Closing a day (and reopening
// one, and loosening the closing policy) is the approve right -- the catalog
// seed describes poultry.daily-closing.approve as "Approve locks the day" -- so
// those are checked explicitly here, and only once Iam:Enforced is on, the
// same posture as PoultryFarmSetupController. In shadow mode the route map's
// own check still applies and logs.

using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Npgsql;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [Authorize]
    [ApiController]
    [Route("api/Poultry/daily-closings")]
    public class PoultryDailyClosingControlController : ControllerBase
    {
        public const string CloseRight = "poultry.daily-closing.approve";

        private readonly IPoultryDailyClosingControlService _svc;
        private readonly IIamService _iam;
        private readonly IConfiguration _config;

        public PoultryDailyClosingControlController(
            IPoultryDailyClosingControlService svc, IIamService iam, IConfiguration config)
        {
            _svc = svc;
            _iam = iam;
            _config = config;
        }

        /// <summary>
        /// The Daily Closing page for one date: live sections + checklist, the
        /// closing row, the state at closing, and the history. businessDate
        /// defaults to the company's today; a future date is a 400.
        /// </summary>
        [HttpGet("day")]
        public async Task<ActionResult<PoultryClosingDayView>> GetDay([FromQuery] string farmId, [FromQuery] DateTime? businessDate)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            try
            {
                return Ok(await _svc.GetDayAsync(farmId, businessDate));
            }
            catch (PostgresException ex) when (ex.SqlState == "P0001")
            {
                return BadRequest(new { message = ex.MessageText });
            }
        }

        /// <summary>
        /// Close Business Day. Creates the closing if none exists, refuses while
        /// any check is Blocking (409, with the blockers in the message), and
        /// refuses a day that is already closed (409).
        /// </summary>
        [HttpPost("close")]
        public async Task<ActionResult<PoultryCloseDayResult>> Close([FromBody] PoultryCloseDayRequest req)
        {
            if (string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required.");
            var denied = await RequireCloseRightAsync(this, _iam, _config, req.FarmId, "close a business day");
            if (denied is not null) return denied;

            try
            {
                return Ok(await _svc.CloseAsync(req.FarmId, req.BusinessDate, Actor(User), req.Notes));
            }
            catch (PostgresException ex) when (ex.SqlState is "P0002" or "P0003")
            {
                return Conflict(new { message = ex.MessageText, code = ex.SqlState == "P0002" ? "AlreadyClosed" : "Blocked" });
            }
            catch (PostgresException ex) when (ex.SqlState == "P0001")
            {
                return BadRequest(new { message = ex.MessageText });
            }
        }

        /// <summary>Previous closings, newest first, with figures as they were closed.</summary>
        [HttpGet("history")]
        public async Task<ActionResult<IEnumerable<PoultryClosingHistoryRow>>> GetHistory(
            [FromQuery] string farmId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetHistoryAsync(farmId, fromDate, toDate));

        /// <summary>The snapshot a particular past close stored (history entry).</summary>
        [HttpGet("events/{eventId:long}/snapshot")]
        public async Task<IActionResult> GetEventSnapshot(long eventId, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var snap = await _svc.GetEventSnapshotAsync(farmId, eventId);
            return snap is null ? NotFound() : Ok(snap.Value);
        }

        [HttpGet("policy")]
        public async Task<ActionResult<PoultryClosingPolicy>> GetPolicy([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetPolicyAsync(farmId));

        /// <summary>
        /// Which checks block a close. Loosening this is as consequential as
        /// closing itself, so it needs the same right.
        /// </summary>
        [HttpPut("policy")]
        public async Task<IActionResult> SetPolicy([FromBody] PoultryClosingPolicy body)
        {
            if (string.IsNullOrWhiteSpace(body.FarmId)) return BadRequest("Company ID is required.");
            var denied = await RequireCloseRightAsync(this, _iam, _config, body.FarmId, "change the closing policy");
            if (denied is not null) return denied;
            try
            {
                await _svc.SetPolicyAsync(body, Actor(User));
            }
            catch (PostgresException ex) when (ex.SqlState is "23514" or "P0001")
            {
                return BadRequest(new { message = "Levels must be Blocking or Warning, and numbers cannot be negative." });
            }
            return NoContent();
        }

        // ---- shared with PoultryDailyClosingController.Reopen ----------------

        /// <summary>
        /// Null when allowed. Under Iam:Enforced the caller must hold
        /// poultry.daily-closing.approve for this company; otherwise nothing is
        /// added beyond the route map's own (shadow) check.
        /// </summary>
        public static async Task<ActionResult?> RequireCloseRightAsync(
            ControllerBase controller, IIamService iam, IConfiguration config, string farmId, string doing)
        {
            if (!config.GetValue("Iam:Enforced", false)) return null;
            var userId = controller.User?.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (!string.IsNullOrWhiteSpace(userId) && await iam.HasPermissionAsync(userId, farmId, CloseRight))
                return null;
            return controller.StatusCode(403, new
            {
                message = $"You do not have permission to {doing}.",
                requiredPermission = CloseRight,
            });
        }

        /// <summary>Who did it, as history should show it: the user name, else the id.</summary>
        public static string? Actor(ClaimsPrincipal? user)
            => user?.FindFirst(ClaimTypes.Name)?.Value
               ?? user?.FindFirst(ClaimTypes.NameIdentifier)?.Value;
    }

    // -------------------------------------------------------------------------
    // Module-neutral closing status: "Poultry Farm A -- Today: Closed". Business
    // Office can ask this of every company without knowing its type; each module
    // answers through its own IDailyClosingStatusProvider. Only poultry answers
    // today -- the others return NotSupported until they register a provider.
    // -------------------------------------------------------------------------
    [Authorize]
    [ApiController]
    [Route("api/DailyClosingStatus")]
    public class DailyClosingStatusController : ControllerBase
    {
        private readonly IEnumerable<IDailyClosingStatusProvider> _providers;
        private readonly IIamService _iam;

        public DailyClosingStatusController(IEnumerable<IDailyClosingStatusProvider> providers, IIamService iam)
        {
            _providers = providers;
            _iam = iam;
        }

        [HttpGet]
        public async Task<ActionResult<DailyClosingStatus>> Get([FromQuery] string farmId, [FromQuery] DateTime? businessDate)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var module = await _iam.GetModuleForFarmAsync(farmId);
            var provider = _providers.FirstOrDefault(p => string.Equals(p.Module, module, StringComparison.OrdinalIgnoreCase));
            if (provider is null)
                return Ok(new DailyClosingStatus { FarmId = farmId, Module = module ?? "unknown", ClosingStatus = "NotSupported" });
            try
            {
                return Ok(await provider.GetStatusAsync(farmId, businessDate));
            }
            catch (PostgresException ex) when (ex.SqlState == "P0001")
            {
                return BadRequest(new { message = ex.MessageText });
            }
        }
    }
}
