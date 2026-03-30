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

        public AuditLogsController(IAuditLogService service)
        {
            _service = service;
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

            var logs = await _service.GetAllAsync(userId, farmId, status, startDate, endDate, page, pageSize);
            return Ok(logs);
        }

        [HttpGet("{id:int}")]
        public async Task<ActionResult<AuditLogModel>> GetById(int id)
        {
            var log = await _service.GetByIdAsync(id);
            if (log == null) return NotFound();
            return Ok(log);
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

            var id = await _service.InsertAsync(model);
            var createdLog = await _service.GetByIdAsync(id);
            
            if (createdLog == null)
                return StatusCode(500, "Log was created but could not be retrieved.");
                
            return CreatedAtAction(nameof(GetById), new { id }, createdLog);
        }

        // Debug endpoint to verify DB connection and rows
        [HttpGet("debug/info")]
        public async Task<ActionResult<object>> DebugInfo()
        {
            var (db, count) = await _service.GetDebugInfoAsync();
            return Ok(new { database = db, rowCount = count });
        }
    }
}


