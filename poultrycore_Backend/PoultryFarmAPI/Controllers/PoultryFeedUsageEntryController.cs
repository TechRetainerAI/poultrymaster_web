// Feed Usage from stock (migration 389).
//
// PERMISSIONS: the route maps to poultry.feed-usage in IamPermissionMap, like
// the old /FeedUsage endpoints and Distribute Feed. Reversal is a POST to
// {id}/reversal (not "reverse", which the map would turn into .approve) and
// under Iam:Enforced is checked explicitly against poultry.feed-usage.delete.

using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Filters;
using Npgsql;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [Authorize]
    [ApiController]
    [Route("api/Poultry/feed-usage-entries")]
    [RequireCompanyType("Poultry")]
    public class PoultryFeedUsageEntryController : ControllerBase
    {
        private readonly IPoultryFeedUsageEntryService _svc;
        private readonly IIamService _iam;
        private readonly IConfiguration _config;

        public PoultryFeedUsageEntryController(IPoultryFeedUsageEntryService svc, IIamService iam, IConfiguration config)
        {
            _svc = svc;
            _iam = iam;
            _config = config;
        }

        [HttpGet("candidates")]
        public async Task<ActionResult<IEnumerable<FeedUsageCandidate>>> GetCandidates([FromQuery] string farmId, [FromQuery] DateTime businessDate)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            try
            {
                return Ok(await _svc.GetCandidatesAsync(farmId, businessDate));
            }
            catch (PostgresException ex) when (ex.SqlState == "P0001")
            {
                return BadRequest(new { message = ex.MessageText });
            }
        }

        [HttpGet]
        public async Task<ActionResult<IEnumerable<FeedUsageEntry>>> GetAll(
            [FromQuery] string farmId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetAllAsync(farmId, fromDate, toDate));

        [HttpGet("{id:int}/lines")]
        public async Task<ActionResult<IEnumerable<FeedUsageEntryLine>>> GetLines(int id, [FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetLinesAsync(id, farmId));

        /// <summary>Every feed line on the farm's production records, whichever screen entered it.</summary>
        [HttpGet("log")]
        public async Task<ActionResult<IEnumerable<FeedUsageLogRow>>> GetLog(
            [FromQuery] string farmId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetLogAsync(farmId, fromDate, toDate));

        /// <summary>
        /// Record feed usage. All or nothing: 409 when stock no longer covers it
        /// (re-checked under a lock), 400 for any other refusal.
        /// </summary>
        [HttpPost]
        public async Task<ActionResult<object>> Post([FromBody] FeedUsagePostRequest req)
        {
            if (string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required.");
            var by = Actor();
            if (by is null) return Unauthorized(new { message = "Sign in again to record feed." });
            try
            {
                var id = await _svc.PostAsync(req, by);
                return Ok(new { poultryFeedUsageEntryId = id });
            }
            catch (PostgresException ex) when (ex.SqlState == "P0003")
            {
                return Conflict(new { message = ex.MessageText, code = "InsufficientStock" });
            }
            catch (PostgresException ex) when (ex.SqlState is "P0004" or "P0001" or "P0010")
            {
                return BadRequest(new { message = ex.MessageText });
            }
        }

        [HttpPost("{id:int}/reversal")]
        public async Task<IActionResult> Reverse(int id, [FromBody] FeedUsageReverseRequest req)
        {
            if (string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required.");
            if (string.IsNullOrWhiteSpace(req.Reason)) return BadRequest(new { message = "A reason is required to reverse feed usage." });
            var by = Actor();
            if (by is null) return Unauthorized(new { message = "Sign in again to reverse feed." });

            if (_config.GetValue("Iam:Enforced", false))
            {
                var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
                if (string.IsNullOrWhiteSpace(userId) || !await _iam.HasPermissionAsync(userId, req.FarmId, "poultry.feed-usage.delete"))
                    return StatusCode(403, new { message = "You do not have permission to reverse feed usage.", requiredPermission = "poultry.feed-usage.delete" });
            }

            try
            {
                await _svc.ReverseAsync(id, req.FarmId, req.Reason.Trim(), by);
                return NoContent();
            }
            catch (PostgresException ex) when (ex.SqlState is "P0005" or "P0001")
            {
                return BadRequest(new { message = ex.MessageText });
            }
        }

        private string? Actor()
            => User.FindFirst(ClaimTypes.Name)?.Value ?? User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
    }
}
