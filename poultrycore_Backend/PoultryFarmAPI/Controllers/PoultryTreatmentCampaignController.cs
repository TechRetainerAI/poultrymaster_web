// Treatment Campaigns (migration 339).
//
// PERMISSIONS: the route maps to poultry.health in IamPermissionMap, through
// the global IamEnforcementFilter (shadow mode logs, Iam:Enforced blocks).
// GET = view; POST create / record a day = create; PUT settings, completion and
// cancellation = edit. Reversal is a POST to days/{postId}/reversal --
// deliberately NOT a segment named "reverse" or "post", which the map would
// turn into poultry.health.approve, a key no role holds -- and under
// Iam:Enforced it is checked explicitly against poultry.health.delete, the
// right to take a recorded treatment away. Daily postings live under "days"
// for the same reason.

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
    [Route("api/Poultry/treatment-campaigns")]
    public class PoultryTreatmentCampaignController : ControllerBase
    {
        private readonly IPoultryTreatmentCampaignService _svc;
        private readonly IIamService _iam;
        private readonly IConfiguration _config;

        public PoultryTreatmentCampaignController(IPoultryTreatmentCampaignService svc, IIamService iam, IConfiguration config)
        {
            _svc = svc;
            _iam = iam;
            _config = config;
        }

        // ---- Products -------------------------------------------------------

        [HttpGet("products")]
        public async Task<ActionResult<IEnumerable<MedicationProduct>>> GetProducts([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetProductsAsync(farmId));

        /// <summary>The farm's own dose and withdrawal figures for a product. All null clears them.</summary>
        [HttpPut("products/{itemId:int}/settings")]
        public async Task<IActionResult> SetProductSettings(int itemId, [FromBody] MedicationProductSettingsRequest req)
        {
            if (string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required.");
            return await Refusals(async () => { await _svc.SetProductSettingsAsync(itemId, req, Actor()); return NoContent(); });
        }

        [HttpGet("flock-options")]
        public async Task<ActionResult<IEnumerable<TreatmentFlockOption>>> GetFlockOptions([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetFlockOptionsAsync(farmId));

        // ---- Campaigns ------------------------------------------------------

        [HttpGet]
        public async Task<ActionResult<IEnumerable<TreatmentCampaign>>> GetAll([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetAllAsync(farmId));

        [HttpGet("{id:int}")]
        public async Task<ActionResult<TreatmentCampaign>> GetOne(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var c = (await _svc.GetAllAsync(farmId, id)).FirstOrDefault();
            return c is null ? NotFound(new { message = "Treatment campaign not found." }) : Ok(c);
        }

        [HttpPost]
        public async Task<IActionResult> Create([FromBody] TreatmentCampaignCreateRequest req)
        {
            if (string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required.");
            var by = Actor();
            if (by is null) return Unauthorized(new { message = "Sign in again to create a campaign." });
            // 340: a campaign always carries its dose -- an amount and what it is per.
            if (req.DoseQuantity is not > 0 || !DoseBases.Contains(req.DoseBasis ?? string.Empty))
                return BadRequest(new { message = "A dose needs both an amount and what it is per (per bird, per 1,000 birds or per flock)." });
            return await Refusals(async () => Ok(new { poultryTreatmentCampaignId = await _svc.CreateAsync(req, by) }));
        }

        [HttpPut("{id:int}/completion")]
        public async Task<IActionResult> Complete(int id, [FromBody] TreatmentFarmRequest req)
        {
            if (string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required.");
            var by = Actor();
            if (by is null) return Unauthorized(new { message = "Sign in again." });
            return await Refusals(async () => { await _svc.CompleteAsync(id, req.FarmId, by); return NoContent(); });
        }

        /// <summary>Stops further treatment. Doses already posted stay -- those birds were treated.</summary>
        [HttpPut("{id:int}/cancellation")]
        public async Task<IActionResult> Cancel(int id, [FromBody] TreatmentReasonRequest req)
        {
            if (string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required.");
            if (string.IsNullOrWhiteSpace(req.Reason)) return BadRequest(new { message = "A reason is required to cancel a campaign." });
            var by = Actor();
            if (by is null) return Unauthorized(new { message = "Sign in again." });
            return await Refusals(async () => { await _svc.CancelAsync(id, req.FarmId, req.Reason.Trim(), by); return NoContent(); });
        }

        [HttpGet("{id:int}/flocks")]
        public async Task<ActionResult<IEnumerable<TreatmentCampaignFlock>>> GetFlocks(int id, [FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetFlocksAsync(id, farmId));

        // ---- Daily treatment ------------------------------------------------

        [HttpGet("{id:int}/day-grid")]
        public async Task<ActionResult<IEnumerable<TreatmentDayRow>>> GetDayGrid(int id, [FromQuery] string farmId, [FromQuery] DateTime date)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetDayGridAsync(id, farmId, date));

        [HttpGet("{id:int}/days")]
        public async Task<ActionResult<IEnumerable<TreatmentDayPosting>>> GetDays(int id, [FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetDaysAsync(id, farmId));

        [HttpGet("days/{postId:int}/lines")]
        public async Task<ActionResult<IEnumerable<TreatmentDayLine>>> GetDayLines(int postId, [FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetDayLinesAsync(postId, farmId));

        /// <summary>
        /// Record a day's treatment. All flocks or none: 409 when stock no longer
        /// covers it (re-checked under a lock) or the day is already recorded,
        /// 400 when a flock cannot be dosed or any other refusal.
        /// </summary>
        [HttpPost("{id:int}/days")]
        public async Task<IActionResult> PostDay(int id, [FromBody] TreatmentDayPostRequest req)
        {
            if (string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required.");
            var by = Actor();
            if (by is null) return Unauthorized(new { message = "Sign in again to record treatment." });
            return await Refusals(async () => Ok(new { poultryTreatmentCampaignPostId = await _svc.PostDayAsync(id, req, by) }));
        }

        [HttpPost("days/{postId:int}/reversal")]
        public async Task<IActionResult> ReverseDay(int postId, [FromBody] TreatmentReasonRequest req)
        {
            if (string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required.");
            if (string.IsNullOrWhiteSpace(req.Reason)) return BadRequest(new { message = "A reason is required to reverse a treatment posting." });
            var by = Actor();
            if (by is null) return Unauthorized(new { message = "Sign in again to reverse treatment." });

            if (_config.GetValue("Iam:Enforced", false))
            {
                var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
                if (string.IsNullOrWhiteSpace(userId) || !await _iam.HasPermissionAsync(userId, req.FarmId, "poultry.health.delete"))
                    return StatusCode(403, new { message = "You do not have permission to reverse a recorded treatment.", requiredPermission = "poultry.health.delete" });
            }

            return await Refusals(async () => { await _svc.ReverseDayAsync(postId, req.FarmId, req.Reason.Trim(), by); return NoContent(); });
        }

        // ---- A flock's own history -------------------------------------------

        [HttpGet("flocks/{flockId:int}/history")]
        public async Task<ActionResult<IEnumerable<FlockTreatmentHistoryRow>>> GetFlockHistory(int flockId, [FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetFlockHistoryAsync(farmId, flockId));

        // ---------------------------------------------------------------------

        /// <summary>The database's refusals as readable 4xx answers.</summary>
        private async Task<IActionResult> Refusals(Func<Task<IActionResult>> run)
        {
            try
            {
                return await run();
            }
            catch (PostgresException ex) when (ex.SqlState == "P0003")
            {
                return Conflict(new { message = ex.MessageText, code = "InsufficientStock" });
            }
            catch (PostgresException ex) when (ex.SqlState == "P0006" || ex.SqlState == "23505")
            {
                // 23505: the one-live-posting-per-day index caught a race the check missed.
                return Conflict(new { message = ex.SqlState == "P0006" ? ex.MessageText : "Treatment for this day was just recorded by someone else.", code = "AlreadyRecorded" });
            }
            catch (PostgresException ex) when (ex.SqlState is "P0001" or "P0004" or "P0005" or "23514")
            {
                return BadRequest(new { message = ex.MessageText });
            }
        }

        private static readonly string[] DoseBases = { "PerBird", "Per1000Birds", "PerFlock" };

        private string? Actor()
            => User.FindFirst(ClaimTypes.Name)?.Value ?? User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
    }
}
