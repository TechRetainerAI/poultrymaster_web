using System.Data.SqlClient;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class AuditLogsController : ControllerBase
    {
        private readonly IAuditLogService _service;
        private readonly ILogger<AuditLogsController> _logger;

        public AuditLogsController(IAuditLogService service, ILogger<AuditLogsController> logger)
        {
            _service = service;
            _logger = logger;
        }

        [HttpGet]
        public async Task<ActionResult<IEnumerable<AuditLogModel>>> GetAll(
            [FromQuery] string? userId,
            [FromQuery] string? farmId,
            [FromQuery] string? status,
            [FromQuery] DateTime? startDate,
            [FromQuery] DateTime? endDate,
            [FromQuery] int page = 1,
            [FromQuery] int pageSize = 200)
        {
            // Require farmId to ensure farm-scoped filtering
            if (string.IsNullOrEmpty(farmId))
            {
                return BadRequest("FarmId is required to retrieve farm-scoped audit logs.");
            }

            try
            {
                var logs = await _service.GetAllAsync(userId, farmId, status, startDate, endDate, page, pageSize);
                return Ok(logs);
            }
            catch (SqlException ex)
            {
                _logger.LogError(ex, "AuditLogs GetAll failed (SQL {Number})", ex.Number);
                return StatusCode(500, new
                {
                    message = "Audit log query failed. Ensure dbo.AuditLogs exists with FarmId (run Migrations/007_AddAuditLogsFarmId.sql). On case-sensitive SQL Server, run 008_RenameLegacyAuditlogsToAuditLogs.sql if needed.",
                    sqlNumber = ex.Number,
                    sqlMessage = ex.Message,
                });
            }
            catch (InvalidOperationException ex)
            {
                _logger.LogError(ex, "AuditLogs GetAll failed (configuration)");
                return StatusCode(500, new { message = ex.Message });
            }
        }

        /// <summary>
        /// Cross-farm recent activity from PoultryMaster (dbo.AuditLogs). Same roles as Login API <c>api/System/farms</c>.
        /// Must be registered before the <c>{id}</c> route so <c>platform</c> is not treated as an id.
        /// </summary>
        [HttpGet("platform")]
        [Authorize(Roles = "SystemAdmin,PlatformOwner")]
        public async Task<ActionResult<IEnumerable<AuditLogModel>>> GetPlatform([FromQuery] int take = 400)
        {
            try
            {
                var logs = await _service.GetPlatformRecentAsync(take);
                return Ok(logs);
            }
            catch (SqlException ex)
            {
                _logger.LogError(ex, "AuditLogs GetPlatform failed (SQL {Number})", ex.Number);
                return StatusCode(500, new
                {
                    message = "Platform audit query failed.",
                    sqlNumber = ex.Number,
                    sqlMessage = ex.Message,
                });
            }
            catch (InvalidOperationException ex)
            {
                _logger.LogError(ex, "AuditLogs GetPlatform failed (configuration)");
                return StatusCode(500, new { message = ex.Message });
            }
        }

        [HttpGet("{id}")]
        public async Task<ActionResult<AuditLogModel>> GetById(string id)
        {
            try
            {
                var log = await _service.GetByIdAsync(id);
                if (log == null) return NotFound();
                return Ok(log);
            }
            catch (SqlException ex)
            {
                _logger.LogError(ex, "AuditLogs GetById failed (SQL {Number})", ex.Number);
                return StatusCode(500, new { message = "Audit log query failed.", sqlNumber = ex.Number, sqlMessage = ex.Message });
            }
            catch (InvalidOperationException ex)
            {
                _logger.LogError(ex, "AuditLogs GetById failed (configuration)");
                return StatusCode(500, new { message = ex.Message });
            }
        }

        [HttpPost]
        public async Task<ActionResult<AuditLogModel>> Create([FromBody] AuditLogModel model)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);

            if (string.IsNullOrEmpty(model.UserId) || string.IsNullOrEmpty(model.FarmId))
                return BadRequest("UserId and FarmId are required.");

            model.Timestamp = model.Timestamp == default ? DateTime.UtcNow : model.Timestamp;
            model.Status = string.IsNullOrEmpty(model.Status) ? "Success" : model.Status;

            try
            {
                var id = await _service.InsertAsync(model);
                var createdLog = await _service.GetByIdAsync(id);

                if (createdLog == null)
                    return StatusCode(500, "Log was created but could not be retrieved.");

                return CreatedAtAction(nameof(GetById), new { id }, createdLog);
            }
            catch (SqlException ex)
            {
                _logger.LogError(ex, "AuditLogs Create failed (SQL {Number})", ex.Number);
                return StatusCode(500, new { message = "Audit log insert failed.", sqlNumber = ex.Number, sqlMessage = ex.Message });
            }
            catch (InvalidOperationException ex)
            {
                _logger.LogError(ex, "AuditLogs Create failed (configuration)");
                return StatusCode(500, new { message = ex.Message });
            }
        }

        // Debug endpoint to verify DB connection and rows
        [HttpGet("debug/info")]
        public async Task<ActionResult<object>> DebugInfo()
        {
            try
            {
                var (db, count) = await _service.GetDebugInfoAsync();
                return Ok(new { database = db, rowCount = count });
            }
            catch (SqlException ex)
            {
                _logger.LogError(ex, "AuditLogs debug failed (SQL {Number})", ex.Number);
                return StatusCode(500, new { message = "Audit log debug query failed.", sqlNumber = ex.Number, sqlMessage = ex.Message });
            }
            catch (InvalidOperationException ex)
            {
                return StatusCode(500, new { message = ex.Message });
            }
        }
    }
}


