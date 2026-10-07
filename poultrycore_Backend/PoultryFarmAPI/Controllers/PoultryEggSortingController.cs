// Egg Sorting Workspace (migrations 341-343).
//
// PERMISSIONS: the route maps to poultry.egg-sorting in IamPermissionMap.
//   GET                              -> view
//   POST sessions (save / commit)    -> create   (no "post" segment on purpose:
//                                                 that would resolve to .approve)
//   PUT sessions/{id}, sizes, settings -> edit
//   DELETE sessions/{id} (discard)   -> delete
//   POST sessions/{id}/reversal      -> checked explicitly against .delete under
//                                       Iam:Enforced, the right to take sorted
//                                       stock back out.

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
    [Route("api/Poultry/egg-sorting")]
    public class PoultryEggSortingController : ControllerBase
    {
        private readonly IPoultryEggSortingService _svc;
        private readonly IIamService _iam;
        private readonly IConfiguration _config;

        public PoultryEggSortingController(IPoultryEggSortingService svc, IIamService iam, IConfiguration config)
        {
            _svc = svc;
            _iam = iam;
            _config = config;
        }

        [HttpGet("settings")]
        public async Task<ActionResult<EggSortingSettings>> GetSettings([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetSettingsAsync(farmId));

        [HttpPut("settings")]
        public async Task<IActionResult> SaveSettings([FromBody] EggSortingSettingsRequest req)
        {
            if (string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required.");
            return await Refusals(async () => { await _svc.SaveSettingsAsync(req, Actor()); return NoContent(); });
        }

        /// <summary>Unsorted + sizes with eggs on hand. ensure=true seeds the default sizes the first time.</summary>
        [HttpGet("classes")]
        public async Task<ActionResult<IEnumerable<EggClass>>> GetClasses(
            [FromQuery] string farmId, [FromQuery] bool includeInactive = false, [FromQuery] bool ensure = false)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetClassesAsync(farmId, includeInactive, ensure, Actor()));

        [HttpPut("sizes")]
        public async Task<IActionResult> SaveSize([FromBody] EggSizeSaveRequest req)
        {
            if (string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required.");
            return await Refusals(async () => Ok(new { eggSizeId = await _svc.SaveSizeAsync(req, Actor()) }));
        }

        /// <summary>Default selling price per crate for one size (344). Null clears it.</summary>
        [HttpPut("sizes/{id:int}/price")]
        public async Task<IActionResult> SetSizePrice(int id, [FromBody] EggSizePriceRequest req)
        {
            if (string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required.");
            return await Refusals(async () => { await _svc.SetSizePriceAsync(req.FarmId, id, req.PricePerCrate, Actor()); return NoContent(); });
        }

        /// <summary>
        /// Breakage / loss / stock-take against ONE egg class (344). Not sorting
        /// loss -- that stays on the sorting. Checked against .edit under
        /// enforcement: it changes stock without a sale or a sorting behind it.
        /// </summary>
        [HttpPost("adjustments")]
        public async Task<IActionResult> Adjust([FromBody] EggClassAdjustRequest req)
        {
            if (string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required.");
            if (string.IsNullOrWhiteSpace(req.Reason)) return BadRequest(new { message = "A reason is required for an egg adjustment." });
            var by = Actor();
            if (by is null) return Unauthorized(new { message = "Sign in again to adjust egg stock." });
            if (_config.GetValue("Iam:Enforced", false))
            {
                var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
                if (string.IsNullOrWhiteSpace(userId) || !await _iam.HasPermissionAsync(userId, req.FarmId, "poultry.egg-sorting.edit"))
                    return StatusCode(403, new { message = "You do not have permission to adjust egg stock.", requiredPermission = "poultry.egg-sorting.edit" });
            }
            return await Refusals(async () => Ok(new { transactionId = await _svc.AdjustClassAsync(req, by) }));
        }

        /// <summary>Audit trail: sortings, sizes, settings, sale classes, adjustments.</summary>
        [HttpGet("audit")]
        public async Task<ActionResult<IEnumerable<EggSortingAuditRow>>> GetAudit(
            [FromQuery] string farmId, [FromQuery] string? entity, [FromQuery] int? entityId, [FromQuery] int limit = 200)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetAuditAsync(farmId, entity, entityId, limit));

        [HttpGet("picks")]
        public async Task<ActionResult<IEnumerable<EggSortingPick>>> GetPicks(
            [FromQuery] string farmId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate,
            [FromQuery] int? flockId, [FromQuery] int[]? recordIds)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetPicksAsync(farmId, fromDate, toDate, flockId, recordIds));

        [HttpGet("summary")]
        public async Task<ActionResult<EggSortingSummary>> GetSummary([FromQuery] string farmId, [FromQuery] DateTime? date)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var s = await _svc.GetSummaryAsync(farmId, date);
            return s is null ? NotFound() : Ok(s);
        }

        [HttpGet("sessions")]
        public async Task<ActionResult<IEnumerable<EggSortingSession>>> GetSessions(
            [FromQuery] string farmId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate,
            [FromQuery] string? status, [FromQuery] int? recordId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetSessionsAsync(farmId, fromDate, toDate, status, recordId, null));

        [HttpGet("sessions/{id:int}")]
        public async Task<ActionResult<EggSortingSession>> GetSession(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var s = (await _svc.GetSessionsAsync(farmId, null, null, null, null, id)).FirstOrDefault();
            return s is null ? NotFound(new { message = "Sorting not found." }) : Ok(s);
        }

        /// <summary>New sorting: a draft, or (Post = true) posted in the same transaction.</summary>
        [HttpPost("sessions")]
        public Task<IActionResult> Create([FromBody] EggSortingSaveRequest req) => Save(req, null);

        /// <summary>Edit a draft; Post = true posts it.</summary>
        [HttpPut("sessions/{id:int}")]
        public Task<IActionResult> Update(int id, [FromBody] EggSortingSaveRequest req) => Save(req, id);

        private async Task<IActionResult> Save(EggSortingSaveRequest req, int? id)
        {
            if (string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required.");
            var by = Actor();
            if (by is null) return Unauthorized(new { message = "Sign in again to record sorting." });
            return await Refusals(async () =>
            {
                var sessionId = await _svc.SaveAsync(req, id, by);
                return Ok(new { sessionId });
            });
        }

        [HttpDelete("sessions/{id:int}")]
        public async Task<IActionResult> Discard(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return await Refusals(async () => { await _svc.DiscardAsync(farmId, id, Actor()); return NoContent(); });
        }

        [HttpPost("sessions/{id:int}/reversal")]
        public async Task<IActionResult> Reverse(int id, [FromBody] EggSortingReverseRequest req)
        {
            if (string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required.");
            if (string.IsNullOrWhiteSpace(req.Reason)) return BadRequest(new { message = "A reason is required to reverse a sorting." });
            var by = Actor();
            if (by is null) return Unauthorized(new { message = "Sign in again to reverse sorting." });

            if (_config.GetValue("Iam:Enforced", false))
            {
                var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
                if (string.IsNullOrWhiteSpace(userId) || !await _iam.HasPermissionAsync(userId, req.FarmId, "poultry.egg-sorting.delete"))
                    return StatusCode(403, new { message = "You do not have permission to reverse egg sorting.", requiredPermission = "poultry.egg-sorting.delete" });
            }

            return await Refusals(async () => { await _svc.ReverseAsync(req.FarmId, id, req.Reason.Trim(), by); return NoContent(); });
        }

        /// <summary>groupBy: productiondate | sortingdate | flock | batch | age | pick.</summary>
        [HttpGet("composition")]
        public async Task<ActionResult<IEnumerable<EggCompositionRow>>> GetComposition(
            [FromQuery] string farmId, [FromQuery] DateTime fromDate, [FromQuery] DateTime toDate,
            [FromQuery] string groupBy = "productiondate", [FromQuery] int? flockId = null)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetCompositionAsync(farmId, fromDate, toDate, groupBy, flockId));

        [HttpGet("carryover")]
        public async Task<ActionResult<IEnumerable<EggCarryoverRow>>> GetCarryover(
            [FromQuery] string farmId, [FromQuery] DateTime fromDate, [FromQuery] DateTime toDate, [FromQuery] int? flockId = null)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetCarryoverAsync(farmId, fromDate, toDate, flockId));

        /// <summary>Every egg-class movement with a running balance per class (Egg Tracker).</summary>
        [HttpGet("ledger")]
        public async Task<ActionResult<IEnumerable<EggLedgerRow>>> GetLedger(
            [FromQuery] string farmId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate, [FromQuery] int? productId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetLedgerAsync(farmId, fromDate, toDate, productId));

        /// <summary>Same-flock, same-day production records that predate the one-per-day rule.</summary>
        [HttpGet("production-duplicates")]
        public async Task<ActionResult<IEnumerable<ProductionDuplicateGroup>>> GetDuplicates([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetDuplicatesAsync(farmId));

        // P0003 not enough eggs / stock and P0006 reversal blocked are conflicts
        // with the current state; every other RAISE is a refusal to explain.
        private static async Task<IActionResult> Refusals(Func<Task<IActionResult>> action)
        {
            try
            {
                return await action();
            }
            catch (PostgresException ex) when (ex.SqlState == "P0003")
            {
                return new ConflictObjectResult(new { message = ex.MessageText, code = "NotEnoughEggs" });
            }
            catch (PostgresException ex) when (ex.SqlState == "P0006")
            {
                return new ConflictObjectResult(new { message = ex.MessageText, code = "ReversalBlocked" });
            }
            catch (PostgresException ex) when (ex.SqlState == "P0001")
            {
                return new BadRequestObjectResult(new { message = ex.MessageText });
            }
        }

        private string? Actor()
            => User.FindFirst(ClaimTypes.Name)?.Value ?? User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
    }
}
