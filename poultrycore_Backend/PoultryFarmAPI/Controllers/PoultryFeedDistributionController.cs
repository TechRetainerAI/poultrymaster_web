// Distribute Feed (migration 335).
//
// PERMISSIONS: the route maps to poultry.feed-usage in IamPermissionMap (view,
// create, edit and delete all exist for it). Reversal is a POST to
// {id}/reversal -- deliberately NOT a segment named "reverse", which the map
// would turn into poultry.feed-usage.approve, a key no role holds -- and under
// Iam:Enforced it is checked explicitly against poultry.feed-usage.delete,
// the right to take recorded feed usage away.

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
    [Route("api/Poultry/feed-distributions")]
    public class PoultryFeedDistributionController : ControllerBase
    {
        private readonly IPoultryFeedDistributionService _svc;
        private readonly IIamService _iam;
        private readonly IConfiguration _config;

        public PoultryFeedDistributionController(IPoultryFeedDistributionService svc, IIamService iam, IConfiguration config)
        {
            _svc = svc;
            _iam = iam;
            _config = config;
        }

        [HttpGet("availability")]
        public async Task<ActionResult<FeedDistributionAvailability>> GetAvailability([FromQuery] string farmId, [FromQuery] int itemId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var a = await _svc.GetAvailabilityAsync(farmId, itemId);
            return a is null ? NotFound(new { message = "Feed product not found." }) : Ok(a);
        }

        [HttpGet("candidates")]
        public async Task<ActionResult<IEnumerable<FeedDistributionCandidate>>> GetCandidates(
            [FromQuery] string farmId, [FromQuery] DateTime businessDate, [FromQuery] int itemId, [FromQuery] int avgDays = 7)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            try
            {
                return Ok(await _svc.GetCandidatesAsync(farmId, businessDate, itemId, avgDays));
            }
            catch (PostgresException ex) when (ex.SqlState == "P0001")
            {
                return BadRequest(new { message = ex.MessageText });
            }
        }

        [HttpGet]
        public async Task<ActionResult<IEnumerable<FeedDistribution>>> GetAll(
            [FromQuery] string farmId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetAllAsync(farmId, fromDate, toDate));

        [HttpGet("{id:int}/lines")]
        public async Task<ActionResult<IEnumerable<FeedDistributionLine>>> GetLines(int id, [FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetLinesAsync(id, farmId));

        /// <summary>
        /// Post Feed Distribution. All flocks or none: 409 when stock no longer
        /// covers it (re-checked under a lock), 400 when a flock cannot receive
        /// feed (no / duplicate production record) or any other refusal.
        /// </summary>
        [HttpPost]
        public async Task<ActionResult<object>> Post([FromBody] FeedDistributionPostRequest req)
        {
            if (string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required.");
            var by = Actor();
            if (by is null) return Unauthorized(new { message = "Sign in again to post feed." });
            try
            {
                var id = await _svc.PostAsync(req, by);
                return Ok(new { poultryFeedDistributionId = id });
            }
            catch (PostgresException ex) when (ex.SqlState == "P0003")
            {
                return Conflict(new { message = ex.MessageText, code = "InsufficientStock" });
            }
            catch (PostgresException ex) when (ex.SqlState is "P0004" or "P0001")
            {
                return BadRequest(new { message = ex.MessageText });
            }
        }

        [HttpPost("{id:int}/reversal")]
        public async Task<IActionResult> Reverse(int id, [FromBody] FeedDistributionReverseRequest req)
        {
            if (string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required.");
            if (string.IsNullOrWhiteSpace(req.Reason)) return BadRequest(new { message = "A reason is required to reverse a feed distribution." });
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

        [HttpPut("rate")]
        public async Task<IActionResult> SetRate([FromBody] FeedRateRequest req)
        {
            if (string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required.");
            try
            {
                await _svc.SetRateAsync(req.FarmId, req.ItemId, req.GramsPerBirdPerDay, req.RateUnit, Actor());
                return NoContent();
            }
            catch (PostgresException ex) when (ex.SqlState == "P0001")
            {
                return BadRequest(new { message = ex.MessageText });
            }
        }

        private string? Actor()
            => User.FindFirst(ClaimTypes.Name)?.Value ?? User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
    }
}
