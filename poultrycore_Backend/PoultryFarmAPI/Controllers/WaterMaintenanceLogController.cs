using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/Water/maintenance-logs")]
    public class WaterMaintenanceLogController : ControllerBase
    {
        private readonly IWaterMaintenanceLogService _svc;
        public WaterMaintenanceLogController(IWaterMaintenanceLogService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<WaterMaintenanceLogModel>>> GetAll(
            [FromQuery] string farmId,
            [FromQuery] string? status,
            [FromQuery] string? assetType,
            [FromQuery] DateTime? fromDate,
            [FromQuery] DateTime? toDate)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetAllAsync(farmId, status, assetType, fromDate, toDate));

        [HttpGet("{id:int}")]
        public async Task<ActionResult<WaterMaintenanceLogModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var m = await _svc.GetByIdAsync(id, farmId);
            return m is null ? NotFound() : Ok(m);
        }

        [HttpPost]
        public async Task<ActionResult<WaterMaintenanceLogModel>> Create([FromBody] WaterMaintenanceLogModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.InsertAsync(m);
            var created = await _svc.GetByIdAsync(id, m.FarmId);
            return CreatedAtAction(nameof(GetById), new { id, farmId = m.FarmId }, created);
        }

        [HttpPut("{id:int}")]
        public async Task<IActionResult> Update(int id, [FromBody] WaterMaintenanceLogModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            m.WaterMaintenanceLogId = id;
            await _svc.UpdateAsync(m);
            return NoContent();
        }

        // Complete + (optionally) book CashOut for repair cost against a cash account.
        [HttpPost("{id:int}/complete")]
        public async Task<IActionResult> Complete(
            int id, [FromQuery] string farmId, [FromQuery] string? completedBy,
            [FromBody] WaterMaintenanceLogCompleteRequest? body)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.CompleteAsync(id, farmId, completedBy, body?.CompletedDate, body?.WaterCashAccountId);
            return NoContent();
        }

        [HttpDelete("{id:int}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.DeleteAsync(id, farmId);
            return NoContent();
        }

        // Dashboard alerts: machines/boreholes due or overdue for service.
        [HttpGet("due-alerts")]
        public async Task<ActionResult<IEnumerable<WaterMaintenanceLogAlertModel>>> GetDueAlerts([FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetDueAlertsAsync(farmId));
        }
    }
}
