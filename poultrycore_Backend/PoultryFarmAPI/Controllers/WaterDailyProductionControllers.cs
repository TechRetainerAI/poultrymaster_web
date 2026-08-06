using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // =========================================================================
    // Water Daily Production (migration 193)
    //
    // Water convention: farmId comes from the query string on GET/DELETE and
    // from the body on POST/PUT. Workflow verbs take it on the query string,
    // matching the existing approve/cancel/reopen actions in
    // WaterProductionControllers.
    // =========================================================================
    [ApiController]
    [Route("api/Water/daily-productions")]
    public class WaterDailyProductionController : ControllerBase
    {
        private readonly IWaterDailyProductionService _svc;
        public WaterDailyProductionController(IWaterDailyProductionService svc) => _svc = svc;

        // A daily production record captures what already happened, so the
        // production date can never be in the future. UTC-day comparison — the
        // product's companies run on GMT+0.
        private static bool IsFutureDate(DateTime d) => d.Date > DateTime.UtcNow.Date;

        [HttpGet]
        public async Task<ActionResult<List<WaterDailyProductionModel>>> GetAll(
            [FromQuery] string farmId, [FromQuery] string? status,
            [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetAllAsync(farmId, status, fromDate, toDate));
        }

        [HttpGet("{id:int}")]
        public async Task<ActionResult<WaterDailyProductionModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var found = await _svc.GetByIdAsync(id, farmId);
            return found is null ? NotFound() : Ok(found);
        }

        [HttpPost]
        public async Task<ActionResult<WaterDailyProductionModel>> Create([FromBody] WaterDailyProductionModel m)
        {
            if (m is null || string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            if (m.WaterProductId <= 0) return BadRequest("Pick the product this day produces.");
            if (IsFutureDate(m.ProductionDate)) return BadRequest("Production date cannot be in the future.");

            m.CreatedBy ??= m.UserId;
            var id = await _svc.InsertAsync(m);
            var saved = await _svc.GetByIdAsync(id, m.FarmId);
            return CreatedAtAction(nameof(GetById), new { id, farmId = m.FarmId }, saved);
        }

        [HttpPut("{id:int}")]
        public async Task<IActionResult> Update(int id, [FromBody] WaterDailyProductionModel m)
        {
            if (m is null || string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            if (id != m.WaterDailyProductionId) return BadRequest("Route id and body id do not match.");
            if (m.WaterProductId <= 0) return BadRequest("Pick the product this day produces.");
            if (IsFutureDate(m.ProductionDate)) return BadRequest("Production date cannot be in the future.");

            await _svc.UpdateAsync(m);
            return NoContent();
        }

        [HttpDelete("{id:int}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string farmId, [FromQuery] string? userId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.DeleteAsync(id, farmId, userId);
            return NoContent();
        }

        [HttpPost("{id:int}/allocation")]
        public async Task<ActionResult<WaterDailyProductionModel>> SaveAllocation(
            int id, [FromQuery] string farmId, [FromBody] SaveWaterDailyProductionAllocationRequest req)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            if (req is null) return BadRequest("Allocation payload is required.");
            await _svc.SaveAllocationAsync(id, farmId, req.UpdatedBy, req.Status, req.Allocations);
            return Ok(await _svc.GetByIdAsync(id, farmId));
        }

        [HttpDelete("{id:int}/allocation")]
        public async Task<ActionResult<WaterDailyProductionModel>> DeleteAllocation(
            int id, [FromQuery] string farmId, [FromQuery] string? userId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.DeleteAllocationAsync(id, farmId, userId);
            return Ok(await _svc.GetByIdAsync(id, farmId));
        }

        [HttpPost("{id:int}/status")]
        public async Task<ActionResult<WaterDailyProductionModel>> SetStatus(
            int id, [FromQuery] string farmId, [FromBody] WaterDailyProductionActionRequest req)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            if (req is null || string.IsNullOrWhiteSpace(req.Status)) return BadRequest("Status is required.");
            await _svc.SetStatusAsync(id, farmId, req.Status!, req.UserId);
            return Ok(await _svc.GetByIdAsync(id, farmId));
        }

        [HttpPost("{id:int}/post")]
        public async Task<ActionResult<WaterDailyProductionModel>> Post(
            int id, [FromQuery] string farmId, [FromQuery] string? postedBy)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.PostAsync(id, farmId, postedBy);
            return Ok(await _svc.GetByIdAsync(id, farmId));
        }

        [HttpPost("{id:int}/reverse")]
        public async Task<ActionResult<WaterDailyProductionModel>> Reverse(
            int id, [FromQuery] string farmId, [FromQuery] string? reversedBy)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.ReverseAsync(id, farmId, reversedBy);
            return Ok(await _svc.GetByIdAsync(id, farmId));
        }
    }
}
