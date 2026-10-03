using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Security.Claims;
using System.Threading.Tasks;

namespace PoultryFarmAPIWeb.Controllers
{
    /// <summary>
    /// End-of-flock closeout (migration 338).
    ///
    /// <para>
    /// Permissions come from IamPermissionMap's "flock-closeout" entry, so they
    /// switch on with Iam:Enforced like every other route rather than biting the
    /// moment this deploys (which an explicit [RequirePermission] would):
    /// </para>
    /// <list type="bullet">
    /// <item>GET  .../context, .../history, lifetime  → poultry.flock-closeout.view</item>
    /// <item>POST api/flock-closeout/{flockId}          → poultry.flock-closeout.create (close)</item>
    /// <item>POST api/flock-closeout/{flockId}/reverse  → poultry.flock-closeout.approve (reopen)
    ///   -- "reverse" is one of ResolveAction's approve segments, and it is what a
    ///   reopen does to the closeout.</item>
    /// </list>
    /// <para>farmId travels in the query string on every route, because that is
    /// where the IAM filter reads the company from.</para>
    /// </summary>
    [ApiController]
    [Route("api/flock-closeout")]
    public class FlockCloseoutController : ControllerBase
    {
        private readonly IFlockCloseoutService _closeout;
        private readonly IAuditLogService _auditLog;
        private readonly ILogger<FlockCloseoutController> _logger;

        public FlockCloseoutController(
            IFlockCloseoutService closeout,
            IAuditLogService auditLog,
            ILogger<FlockCloseoutController> logger)
        {
            _closeout = closeout;
            _auditLog = auditLog;
            _logger = logger;
        }

        // GET api/flock-closeout/{flockId}/context?userId=&farmId=
        [HttpGet("{flockId:int}/context")]
        public async Task<ActionResult<FlockCloseoutContext>> GetContext(
            int flockId, [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId)) return BadRequest("UserId is required.");
            if (string.IsNullOrEmpty(farmId)) return BadRequest("FarmId is required.");

            var context = await _closeout.GetContextAsync(flockId, userId, farmId);
            if (context == null) return NotFound(new { message = "Flock not found on this farm." });
            return Ok(context);
        }

        // GET api/flock-closeout/{flockId}/history?farmId=
        [HttpGet("{flockId:int}/history")]
        public async Task<ActionResult<List<FlockCloseoutRecord>>> GetHistory(int flockId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(farmId)) return BadRequest("FarmId is required.");
            return Ok(await _closeout.GetHistoryAsync(flockId, farmId));
        }

        // GET api/flock-closeout/lifetime?farmId=&flockId=&closedOnly=
        [HttpGet("lifetime")]
        public async Task<ActionResult<List<FlockLifetimeSummary>>> GetLifetime(
            [FromQuery] string farmId, [FromQuery] int? flockId, [FromQuery] bool closedOnly = false)
        {
            if (string.IsNullOrEmpty(farmId)) return BadRequest("FarmId is required.");
            return Ok(await _closeout.GetLifetimeSummaryAsync(farmId, flockId, closedOnly));
        }

        // POST api/flock-closeout/{flockId}?farmId=
        [HttpPost("{flockId:int}")]
        public async Task<ActionResult<FlockCloseoutResult>> Close(int flockId, [FromBody] FlockCloseoutRequest request)
        {
            if (request == null) return BadRequest("A request body is required.");
            if (string.IsNullOrEmpty(request.UserId)) return BadRequest("UserId is required.");
            if (string.IsNullOrEmpty(request.FarmId)) return BadRequest("FarmId is required.");

            FlockCloseoutResult result;
            try
            {
                result = await _closeout.CloseAsync(flockId, request);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Closeout of flock {FlockId} failed.", flockId);
                return StatusCode(500, new FlockCloseoutResult { Success = false, Message = "The flock could not be closed. " + ex.Message });
            }

            if (!result.Success) return BadRequest(result);

            await WriteAuditAsync(request.UserId, request.FarmId, flockId, "CLOSE",
                $"Closed flock (ID: {flockId}) -- {request.Reason.Trim()}",
                new
                {
                    result.CloseoutId,
                    closedDate = request.ClosedDate.Date,
                    reason = request.Reason.Trim(),
                    sold = request.Sales?.Sum(s => s.Quantity) ?? 0,
                    culled = request.Culls?.Sum(c => c.Quantity) ?? 0,
                    transferred = request.Transfers?.Sum(t => t.Quantity) ?? 0,
                    result.SaleIds,
                    result.ReleasedHouseId,
                    result.Warnings,
                });

            return Ok(result);
        }

        // POST api/flock-closeout/{flockId}/reverse?farmId=
        [HttpPost("{flockId:int}/reverse")]
        public async Task<ActionResult<FlockReopenResult>> Reopen(int flockId, [FromBody] FlockReopenRequest request)
        {
            if (request == null) return BadRequest("A request body is required.");
            if (string.IsNullOrEmpty(request.UserId)) return BadRequest("UserId is required.");
            if (string.IsNullOrEmpty(request.FarmId)) return BadRequest("FarmId is required.");

            var result = await _closeout.ReopenAsync(flockId, request);
            if (!result.Success) return BadRequest(result);

            await WriteAuditAsync(request.UserId, request.FarmId, flockId, "REOPEN",
                $"Reopened flock (ID: {flockId}) -- {request.Reason.Trim()}",
                new { result.CloseoutId, reason = request.Reason.Trim(), request.ReverseSales, result.Warnings });

            return Ok(result);
        }

        /// <summary>
        /// A dedicated audit row on top of the request-level one the global
        /// AuditLogActionFilter writes, so a close or reopen is findable by the
        /// flock it happened to and says what was done in words.
        /// </summary>
        private async Task WriteAuditAsync(string userId, string farmId, int flockId, string action, string details, object data)
        {
            var userName = User?.FindFirst(ClaimTypes.Name)?.Value
                           ?? User?.Identity?.Name
                           ?? Request.Headers["X-Username"].FirstOrDefault()
                           ?? userId;
            try
            {
                await _auditLog.InsertAsync(new AuditLogModel
                {
                    UserId = userId,
                    UserName = userName,
                    FarmId = farmId,
                    Action = action,
                    Resource = "Flock",
                    ResourceId = flockId.ToString(),
                    Details = details,
                    Data = System.Text.Json.JsonSerializer.Serialize(data),
                    IpAddress = HttpContext.Connection.RemoteIpAddress?.ToString(),
                    UserAgent = Request.Headers["User-Agent"].FirstOrDefault(),
                    Timestamp = DateTime.UtcNow,
                    Status = "Success",
                });
            }
            catch (Exception ex)
            {
                // The flock is closed/reopened and committed; the closeout row is
                // its own audit trail. Losing this extra row is logged, not fatal.
                _logger.LogError(ex, "Could not write {Action} audit row for flock {FlockId}.", action, flockId);
            }
        }
    }
}
