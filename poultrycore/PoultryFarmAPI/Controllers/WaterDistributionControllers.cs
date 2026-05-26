using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/Water/drivers")]
    public class WaterDriverController : ControllerBase
    {
        private readonly IWaterDriverService _svc;
        public WaterDriverController(IWaterDriverService svc) => _svc = svc;

        [HttpGet] public async Task<ActionResult<IEnumerable<WaterDriverModel>>> GetAll([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetAllAsync(farmId));

        [HttpGet("{id:int}")] public async Task<ActionResult<WaterDriverModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var m = await _svc.GetByIdAsync(id, farmId);
            return m is null ? NotFound() : Ok(m);
        }

        [HttpPost] public async Task<ActionResult<WaterDriverModel>> Create([FromBody] WaterDriverModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.InsertAsync(m);
            var created = await _svc.GetByIdAsync(id, m.FarmId);
            return CreatedAtAction(nameof(GetById), new { id, farmId = m.FarmId }, created);
        }

        [HttpPut("{id:int}")] public async Task<IActionResult> Update(int id, [FromBody] WaterDriverModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            m.WaterDriverId = id;
            await _svc.UpdateAsync(m);
            return NoContent();
        }

        [HttpDelete("{id:int}")] public async Task<IActionResult> Delete(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.DeleteAsync(id, farmId);
            return NoContent();
        }
    }

    [ApiController]
    [Route("api/Water/vehicles")]
    public class WaterVehicleController : ControllerBase
    {
        private readonly IWaterVehicleService _svc;
        public WaterVehicleController(IWaterVehicleService svc) => _svc = svc;

        [HttpGet] public async Task<ActionResult<IEnumerable<WaterVehicleModel>>> GetAll([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetAllAsync(farmId));

        [HttpGet("{id:int}")] public async Task<ActionResult<WaterVehicleModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var m = await _svc.GetByIdAsync(id, farmId);
            return m is null ? NotFound() : Ok(m);
        }

        [HttpPost] public async Task<ActionResult<WaterVehicleModel>> Create([FromBody] WaterVehicleModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.InsertAsync(m);
            var created = await _svc.GetByIdAsync(id, m.FarmId);
            return CreatedAtAction(nameof(GetById), new { id, farmId = m.FarmId }, created);
        }

        [HttpPut("{id:int}")] public async Task<IActionResult> Update(int id, [FromBody] WaterVehicleModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            m.WaterVehicleId = id;
            await _svc.UpdateAsync(m);
            return NoContent();
        }

        [HttpDelete("{id:int}")] public async Task<IActionResult> Delete(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.DeleteAsync(id, farmId);
            return NoContent();
        }
    }

    [ApiController]
    [Route("api/Water/routes")]
    public class WaterRouteController : ControllerBase
    {
        private readonly IWaterRouteService _svc;
        public WaterRouteController(IWaterRouteService svc) => _svc = svc;

        [HttpGet] public async Task<ActionResult<IEnumerable<WaterRouteModel>>> GetAll([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetAllAsync(farmId));

        [HttpGet("{id:int}")] public async Task<ActionResult<WaterRouteModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var m = await _svc.GetByIdAsync(id, farmId);
            return m is null ? NotFound() : Ok(m);
        }

        [HttpPost] public async Task<ActionResult<WaterRouteModel>> Create([FromBody] WaterRouteModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.InsertAsync(m);
            var created = await _svc.GetByIdAsync(id, m.FarmId);
            return CreatedAtAction(nameof(GetById), new { id, farmId = m.FarmId }, created);
        }

        [HttpPut("{id:int}")] public async Task<IActionResult> Update(int id, [FromBody] WaterRouteModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            m.WaterRouteId = id;
            await _svc.UpdateAsync(m);
            return NoContent();
        }

        [HttpDelete("{id:int}")] public async Task<IActionResult> Delete(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.DeleteAsync(id, farmId);
            return NoContent();
        }
    }

    [ApiController]
    [Route("api/Water/vehicle-loadings")]
    public class WaterVehicleLoadingController : ControllerBase
    {
        private readonly IWaterVehicleLoadingService _svc;
        public WaterVehicleLoadingController(IWaterVehicleLoadingService svc) => _svc = svc;

        [HttpGet] public async Task<ActionResult<IEnumerable<WaterVehicleLoadingModel>>> GetAll(
            [FromQuery] string farmId, [FromQuery] string? status, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetAllAsync(farmId, status, fromDate, toDate));

        [HttpGet("{id:int}")] public async Task<ActionResult<WaterVehicleLoadingModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var m = await _svc.GetByIdAsync(id, farmId);
            return m is null ? NotFound() : Ok(m);
        }

        [HttpPost] public async Task<ActionResult<WaterVehicleLoadingModel>> Create([FromBody] WaterVehicleLoadingModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.InsertAsync(m);
            var created = await _svc.GetByIdAsync(id, m.FarmId);
            return CreatedAtAction(nameof(GetById), new { id, farmId = m.FarmId }, created);
        }

        [HttpPost("{id:int}/approve")] public async Task<IActionResult> Approve(int id, [FromQuery] string farmId, [FromQuery] string? approvedBy)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.ApproveAsync(id, farmId, approvedBy);
            return NoContent();
        }

        [HttpPost("{id:int}/cancel")] public async Task<IActionResult> Cancel(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.CancelAsync(id, farmId);
            return NoContent();
        }
    }

    [ApiController]
    [Route("api/Water/driver-returns")]
    public class WaterDriverReturnController : ControllerBase
    {
        private readonly IWaterDriverReturnService _svc;
        public WaterDriverReturnController(IWaterDriverReturnService svc) => _svc = svc;

        [HttpGet] public async Task<ActionResult<IEnumerable<WaterDriverReturnModel>>> GetAll(
            [FromQuery] string farmId, [FromQuery] string? status, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetAllAsync(farmId, status, fromDate, toDate));

        [HttpGet("{id:int}")] public async Task<ActionResult<WaterDriverReturnModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var m = await _svc.GetByIdAsync(id, farmId);
            return m is null ? NotFound() : Ok(m);
        }

        [HttpPost] public async Task<ActionResult<WaterDriverReturnModel>> Create([FromBody] WaterDriverReturnModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.InsertAsync(m);
            var created = await _svc.GetByIdAsync(id, m.FarmId);
            return CreatedAtAction(nameof(GetById), new { id, farmId = m.FarmId }, created);
        }

        [HttpPost("{id:int}/approve")] public async Task<IActionResult> Approve(int id, [FromQuery] string farmId, [FromQuery] string? approvedBy)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.ApproveAsync(id, farmId, approvedBy);
            return NoContent();
        }

        [HttpPost("{id:int}/cancel")] public async Task<IActionResult> Cancel(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.CancelAsync(id, farmId);
            return NoContent();
        }
    }

    [ApiController]
    [Route("api/Water/driver-shortages")]
    public class WaterDriverShortageController : ControllerBase
    {
        private readonly IWaterDriverShortageService _svc;
        public WaterDriverShortageController(IWaterDriverShortageService svc) => _svc = svc;

        [HttpGet] public async Task<ActionResult<IEnumerable<WaterDriverShortageModel>>> GetAll(
            [FromQuery] string farmId, [FromQuery] string? status)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetAllAsync(farmId, status));

        [HttpPost("{id:int}/resolve")] public async Task<IActionResult> Resolve(int id, [FromQuery] string farmId,
            [FromBody] WaterDriverShortageResolveRequest req, [FromQuery] string? approvedBy)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            if (!ModelState.IsValid) return BadRequest(ModelState);
            await _svc.ResolveAsync(id, farmId, req.NewStatus, req.Reason, approvedBy);
            return NoContent();
        }
    }
}
