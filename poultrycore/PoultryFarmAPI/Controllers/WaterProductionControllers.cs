using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // =========================================================================
    // Phase W1 controllers — boreholes, machines, production batches,
    // quality tests, daily pumping logs.
    // Same FarmId-from-query pattern as the existing WaterControllers.cs.
    // =========================================================================

    [ApiController]
    [Route("api/Water/boreholes")]
    public class WaterBoreholeController : ControllerBase
    {
        private readonly IWaterBoreholeService _svc;
        public WaterBoreholeController(IWaterBoreholeService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<WaterBoreholeModel>>> GetAll([FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetAllAsync(farmId));
        }

        [HttpGet("{id:int}")]
        public async Task<ActionResult<WaterBoreholeModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var m = await _svc.GetByIdAsync(id, farmId);
            return m is null ? NotFound() : Ok(m);
        }

        [HttpPost]
        public async Task<ActionResult<WaterBoreholeModel>> Create([FromBody] WaterBoreholeModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.InsertAsync(m);
            var created = await _svc.GetByIdAsync(id, m.FarmId);
            return CreatedAtAction(nameof(GetById), new { id, farmId = m.FarmId }, created);
        }

        [HttpPut("{id:int}")]
        public async Task<IActionResult> Update(int id, [FromBody] WaterBoreholeModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            m.WaterBoreholeId = id;
            await _svc.UpdateAsync(m);
            return NoContent();
        }

        [HttpDelete("{id:int}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.DeleteAsync(id, farmId);
            return NoContent();
        }
    }

    [ApiController]
    [Route("api/Water/machines")]
    public class WaterMachineController : ControllerBase
    {
        private readonly IWaterMachineService _svc;
        public WaterMachineController(IWaterMachineService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<WaterMachineModel>>> GetAll([FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetAllAsync(farmId));
        }

        [HttpGet("{id:int}")]
        public async Task<ActionResult<WaterMachineModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var m = await _svc.GetByIdAsync(id, farmId);
            return m is null ? NotFound() : Ok(m);
        }

        [HttpPost]
        public async Task<ActionResult<WaterMachineModel>> Create([FromBody] WaterMachineModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.InsertAsync(m);
            var created = await _svc.GetByIdAsync(id, m.FarmId);
            return CreatedAtAction(nameof(GetById), new { id, farmId = m.FarmId }, created);
        }

        [HttpPut("{id:int}")]
        public async Task<IActionResult> Update(int id, [FromBody] WaterMachineModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            m.WaterMachineId = id;
            await _svc.UpdateAsync(m);
            return NoContent();
        }

        [HttpDelete("{id:int}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.DeleteAsync(id, farmId);
            return NoContent();
        }
    }

    [ApiController]
    [Route("api/Water/production-batches")]
    public class WaterProductionBatchController : ControllerBase
    {
        private readonly IWaterProductionBatchService _svc;
        public WaterProductionBatchController(IWaterProductionBatchService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<WaterProductionBatchModel>>> GetAll(
            [FromQuery] string farmId,
            [FromQuery] string? status,
            [FromQuery] DateTime? fromDate,
            [FromQuery] DateTime? toDate)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetAllAsync(farmId, status, fromDate, toDate));
        }

        [HttpGet("{id:int}")]
        public async Task<ActionResult<WaterProductionBatchModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var m = await _svc.GetByIdAsync(id, farmId);
            return m is null ? NotFound() : Ok(m);
        }

        [HttpPost]
        public async Task<ActionResult<WaterProductionBatchModel>> Create([FromBody] WaterProductionBatchModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.InsertAsync(m);
            var created = await _svc.GetByIdAsync(id, m.FarmId);
            return CreatedAtAction(nameof(GetById), new { id, farmId = m.FarmId }, created);
        }

        [HttpPut("{id:int}")]
        public async Task<IActionResult> Update(int id, [FromBody] WaterProductionBatchModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            m.WaterProductionBatchId = id;
            await _svc.UpdateAsync(m);
            return NoContent();
        }

        [HttpPost("{id:int}/approve")]
        public async Task<IActionResult> Approve(int id, [FromQuery] string farmId, [FromQuery] string? approvedBy)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.ApproveAsync(id, farmId, approvedBy);
            return NoContent();
        }

        [HttpPost("{id:int}/cancel")]
        public async Task<IActionResult> Cancel(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.CancelAsync(id, farmId);
            return NoContent();
        }

        [HttpPost("{id:int}/reopen")]
        public async Task<IActionResult> Reopen(int id, [FromQuery] string farmId, [FromQuery] string? reopenedBy)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.ReopenAsync(id, farmId, reopenedBy);
            return NoContent();
        }
    }

    [ApiController]
    [Route("api/Water/quality-tests")]
    public class WaterQualityTestController : ControllerBase
    {
        private readonly IWaterQualityTestService _svc;
        public WaterQualityTestController(IWaterQualityTestService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<WaterQualityTestModel>>> GetAll(
            [FromQuery] string farmId,
            [FromQuery] int? boreholeId,
            [FromQuery] int? batchId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetAllAsync(farmId, boreholeId, batchId));
        }

        [HttpPost]
        public async Task<ActionResult<int>> Create([FromBody] WaterQualityTestModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.InsertAsync(m);
            return Ok(new { WaterQualityTestId = id });
        }
    }

    [ApiController]
    [Route("api/Water/pumping-logs")]
    public class WaterDailyPumpingLogController : ControllerBase
    {
        private readonly IWaterDailyPumpingLogService _svc;
        public WaterDailyPumpingLogController(IWaterDailyPumpingLogService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<WaterDailyPumpingLogModel>>> GetAll(
            [FromQuery] string farmId,
            [FromQuery] DateTime? fromDate,
            [FromQuery] DateTime? toDate)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetAllAsync(farmId, fromDate, toDate));
        }

        [HttpPost]
        public async Task<ActionResult<int>> Create([FromBody] WaterDailyPumpingLogModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.InsertAsync(m);
            return Ok(new { WaterDailyPumpingLogId = id });
        }
    }
}
