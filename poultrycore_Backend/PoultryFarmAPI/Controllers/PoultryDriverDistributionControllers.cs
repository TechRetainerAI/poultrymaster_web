using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // Poultry Driver Distribution controllers. Routes under /api/Poultry/*.
    // Mirrors the Water distribution controllers; every request carries farmId.
    // SPs: migrations 139 + 140.

    [ApiController]
    [Route("api/Poultry/drivers")]
    public class PoultryDriversController : ControllerBase
    {
        private readonly IPoultryDriverDistributionService _svc;
        public PoultryDriversController(IPoultryDriverDistributionService svc) => _svc = svc;

        [HttpGet] public async Task<ActionResult<IEnumerable<PoultryDriverModel>>> GetAll([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetDriversAsync(farmId));

        [HttpGet("list-for-farm")] public async Task<ActionResult<IEnumerable<PoultryDriverModel>>> ListForFarm([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.ListDriversForFarmAsync(farmId));

        [HttpGet("{id:int}")] public async Task<ActionResult<PoultryDriverModel>> GetById(int id, [FromQuery] string farmId)
        { if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required."); var m = await _svc.GetDriverAsync(id, farmId); return m is null ? NotFound() : Ok(m); }

        [HttpPost] public async Task<ActionResult<PoultryDriverModel>> Create([FromBody] PoultryDriverModel m)
        { if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required."); var id = await _svc.InsertDriverAsync(m); return CreatedAtAction(nameof(GetById), new { id, farmId = m.FarmId }, await _svc.GetDriverAsync(id, m.FarmId)); }

        [HttpPut("{id:int}")] public async Task<IActionResult> Update(int id, [FromBody] PoultryDriverModel m)
        { if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required."); m.PoultryDriverId = id; await _svc.UpdateDriverAsync(m); return NoContent(); }

        [HttpDelete("{id:int}")] public async Task<IActionResult> Delete(int id, [FromQuery] string farmId)
        { if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required."); await _svc.DeleteDriverAsync(id, farmId); return NoContent(); }

        [HttpPost("from-employee")] public async Task<ActionResult<PoultryDriverModel>> FromEmployee([FromBody] PoultryDriverFromEmployeeRequest req)
        {
            if (string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required.");
            if (string.IsNullOrWhiteSpace(req.EmployeeUserId)) return BadRequest("Employee is required.");
            return Ok(await _svc.UpsertDriverForEmployeeAsync(req));
        }
    }

    [ApiController]
    [Route("api/Poultry/vehicles")]
    public class PoultryVehiclesController : ControllerBase
    {
        private readonly IPoultryDriverDistributionService _svc;
        public PoultryVehiclesController(IPoultryDriverDistributionService svc) => _svc = svc;

        [HttpGet] public async Task<ActionResult<IEnumerable<PoultryVehicleModel>>> GetAll([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetVehiclesAsync(farmId));

        [HttpGet("{id:int}")] public async Task<ActionResult<PoultryVehicleModel>> GetById(int id, [FromQuery] string farmId)
        { if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required."); var m = await _svc.GetVehicleAsync(id, farmId); return m is null ? NotFound() : Ok(m); }

        [HttpPost] public async Task<ActionResult<PoultryVehicleModel>> Create([FromBody] PoultryVehicleModel m)
        { if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required."); var id = await _svc.InsertVehicleAsync(m); return CreatedAtAction(nameof(GetById), new { id, farmId = m.FarmId }, await _svc.GetVehicleAsync(id, m.FarmId)); }

        [HttpPut("{id:int}")] public async Task<IActionResult> Update(int id, [FromBody] PoultryVehicleModel m)
        { if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required."); m.PoultryVehicleId = id; await _svc.UpdateVehicleAsync(m); return NoContent(); }

        [HttpDelete("{id:int}")] public async Task<IActionResult> Delete(int id, [FromQuery] string farmId)
        { if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required."); await _svc.DeleteVehicleAsync(id, farmId); return NoContent(); }
    }

    [ApiController]
    [Route("api/Poultry/routes")]
    public class PoultryRoutesController : ControllerBase
    {
        private readonly IPoultryDriverDistributionService _svc;
        public PoultryRoutesController(IPoultryDriverDistributionService svc) => _svc = svc;

        [HttpGet] public async Task<ActionResult<IEnumerable<PoultryRouteModel>>> GetAll([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetRoutesAsync(farmId));

        [HttpGet("{id:int}")] public async Task<ActionResult<PoultryRouteModel>> GetById(int id, [FromQuery] string farmId)
        { if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required."); var m = await _svc.GetRouteAsync(id, farmId); return m is null ? NotFound() : Ok(m); }

        [HttpPost] public async Task<ActionResult<PoultryRouteModel>> Create([FromBody] PoultryRouteModel m)
        { if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required."); var id = await _svc.InsertRouteAsync(m); return CreatedAtAction(nameof(GetById), new { id, farmId = m.FarmId }, await _svc.GetRouteAsync(id, m.FarmId)); }

        [HttpPut("{id:int}")] public async Task<IActionResult> Update(int id, [FromBody] PoultryRouteModel m)
        { if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required."); m.PoultryRouteId = id; await _svc.UpdateRouteAsync(m); return NoContent(); }

        [HttpDelete("{id:int}")] public async Task<IActionResult> Delete(int id, [FromQuery] string farmId)
        { if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required."); await _svc.DeleteRouteAsync(id, farmId); return NoContent(); }
    }

    [ApiController]
    [Route("api/Poultry/vehicle-loadings")]
    public class PoultryVehicleLoadingsController : ControllerBase
    {
        private readonly IPoultryDriverDistributionService _svc;
        public PoultryVehicleLoadingsController(IPoultryDriverDistributionService svc) => _svc = svc;

        [HttpGet] public async Task<ActionResult<IEnumerable<PoultryVehicleLoadingModel>>> GetAll(
            [FromQuery] string farmId, [FromQuery] string? status, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetLoadingsAsync(farmId, status, fromDate, toDate));

        [HttpGet("{id:int}")] public async Task<ActionResult<PoultryVehicleLoadingModel>> GetById(int id, [FromQuery] string farmId)
        { if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required."); var m = await _svc.GetLoadingAsync(id, farmId); return m is null ? NotFound() : Ok(m); }

        [HttpGet("{id:int}/items")] public async Task<ActionResult<IEnumerable<PoultryVehicleLoadingItemModel>>> GetItems(int id, [FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetLoadingItemsAsync(id, farmId));

        [HttpPost] public async Task<ActionResult<object>> Create([FromBody] PoultryVehicleLoadingCreateRequest req)
        { if (string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required."); var id = await _svc.InsertLoadingAsync(req); return Ok(new { poultryVehicleLoadingId = id }); }

        [HttpPost("{id:int}/approve")] public async Task<IActionResult> Approve(int id, [FromQuery] string farmId, [FromQuery] string? approvedBy)
        { if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required."); await _svc.ApproveLoadingAsync(id, farmId, approvedBy); return NoContent(); }

        [HttpPost("{id:int}/cancel")] public async Task<IActionResult> Cancel(int id, [FromQuery] string farmId)
        { if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required."); await _svc.CancelLoadingAsync(id, farmId); return NoContent(); }

        [HttpPost("{id:int}/void")] public async Task<IActionResult> Void(int id, [FromQuery] string farmId)
        { if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required."); await _svc.VoidLoadingAsync(id, farmId); return NoContent(); }

        [HttpPost("{id:int}/reload")] public async Task<ActionResult<object>> Reload(int id, [FromQuery] string farmId, [FromQuery] string? createdBy)
        { if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required."); var newId = await _svc.ReloadLoadingAsync(id, farmId, createdBy); return Ok(new { poultryVehicleLoadingId = newId }); }
    }

    [ApiController]
    [Route("api/Poultry/driver-returns")]
    public class PoultryDriverReturnsController : ControllerBase
    {
        private readonly IPoultryDriverDistributionService _svc;
        public PoultryDriverReturnsController(IPoultryDriverDistributionService svc) => _svc = svc;

        [HttpGet] public async Task<ActionResult<IEnumerable<PoultryDriverReturnModel>>> GetAll(
            [FromQuery] string farmId, [FromQuery] string? status, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetReturnsAsync(farmId, status, fromDate, toDate));

        [HttpGet("{id:int}")] public async Task<ActionResult<PoultryDriverReturnModel>> GetById(int id, [FromQuery] string farmId)
        { if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required."); var m = await _svc.GetReturnAsync(id, farmId); return m is null ? NotFound() : Ok(m); }

        [HttpGet("{id:int}/items")] public async Task<ActionResult<IEnumerable<PoultryDriverReturnItemModel>>> GetItems(int id, [FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetReturnItemsAsync(id, farmId));

        [HttpGet("{id:int}/customer-sales")] public async Task<ActionResult<IEnumerable<PoultryDriverReturnCustomerSaleRow>>> GetCustomerSales(int id, [FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetReturnCustomerSalesAsync(id, farmId));

        [HttpGet("{id:int}/expenses")] public async Task<ActionResult<IEnumerable<PoultryDriverDeliveryExpenseModel>>> GetExpenses(int id, [FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetReturnExpensesAsync(id, farmId));

        [HttpPost] public async Task<ActionResult<object>> Create([FromBody] PoultryDriverReturnCreateRequest req)
        { if (string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required."); var id = await _svc.InsertReturnAsync(req); return Ok(new { poultryDriverReturnId = id }); }

        [HttpPost("{id:int}/approve")] public async Task<IActionResult> Approve(int id, [FromQuery] string farmId, [FromQuery] string? approvedBy)
        { if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required."); await _svc.ApproveReturnAsync(id, farmId, approvedBy); return NoContent(); }

        [HttpPost("approve-reconcile")] public async Task<IActionResult> ApproveReconcile([FromBody] PoultryDriverReturnCreateRequest req)
        { if (string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required."); await _svc.ApproveReconcileReturnAsync(req); return Ok(); }

        [HttpPost("{id:int}/cancel")] public async Task<IActionResult> Cancel(int id, [FromQuery] string farmId)
        { if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required."); await _svc.CancelReturnAsync(id, farmId); return NoContent(); }

        [HttpPost("{id:int}/uncancel")] public async Task<IActionResult> Uncancel(int id, [FromQuery] string farmId)
        { if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required."); await _svc.UncancelReturnAsync(id, farmId); return NoContent(); }

        [HttpPost("{id:int}/reverse")] public async Task<IActionResult> Reverse(int id, [FromQuery] string farmId)
        { if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required."); await _svc.ReverseReturnAsync(id, farmId); return NoContent(); }

        [HttpDelete("{id:int}")] public async Task<IActionResult> Delete(int id, [FromQuery] string farmId)
        { if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required."); await _svc.DeleteReturnAsync(id, farmId); return NoContent(); }

        [HttpPost("{id:int}/posting-mode")] public async Task<IActionResult> PostingMode(int id, [FromBody] PoultryDriverReturnPostingModeRequest req)
        { if (string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required."); await _svc.UpdateReturnPostingModeAsync(id, req.FarmId, req.SalesPostingMode); return NoContent(); }
    }

    [ApiController]
    [Route("api/Poultry/driver-shortages")]
    public class PoultryDriverShortagesController : ControllerBase
    {
        private readonly IPoultryDriverDistributionService _svc;
        public PoultryDriverShortagesController(IPoultryDriverDistributionService svc) => _svc = svc;

        [HttpGet] public async Task<ActionResult<IEnumerable<PoultryDriverShortageModel>>> GetAll([FromQuery] string farmId, [FromQuery] string? status)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetShortagesAsync(farmId, status));

        [HttpPost("{id:int}/resolve")] public async Task<IActionResult> Resolve(int id, [FromBody] PoultryDriverShortageResolveRequest req)
        {
            if (string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required.");
            if (string.IsNullOrWhiteSpace(req.Status)) return BadRequest("Status is required.");
            await _svc.ResolveShortageAsync(id, req);
            return NoContent();
        }
    }

    [ApiController]
    [Route("api/Poultry/driver-delivery-expenses")]
    public class PoultryDriverDeliveryExpensesController : ControllerBase
    {
        private readonly IPoultryDriverDistributionService _svc;
        public PoultryDriverDeliveryExpensesController(IPoultryDriverDistributionService svc) => _svc = svc;

        [HttpGet] public async Task<ActionResult<IEnumerable<PoultryDriverDeliveryExpenseModel>>> GetAll(
            [FromQuery] string farmId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.ListDeliveryExpensesAsync(farmId, fromDate, toDate));
    }

    [ApiController]
    [Route("api/Poultry/reports")]
    public class PoultryDriverReportsController : ControllerBase
    {
        private readonly IPoultryDriverDistributionService _svc;
        public PoultryDriverReportsController(IPoultryDriverDistributionService svc) => _svc = svc;

        [HttpGet("driver-reconciliation")] public async Task<ActionResult<IEnumerable<PoultryDriverReconciliationRow>>> DriverReconciliation(
            [FromQuery] string farmId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetDriverReconciliationAsync(farmId, fromDate, toDate));

        [HttpGet("driver-collection")] public async Task<ActionResult<PoultryDriverCollectionReport>> DriverCollection(
            [FromQuery] string farmId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate, [FromQuery] int? poultryDriverId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetDriverCollectionAsync(farmId, fromDate, toDate, poultryDriverId));
    }
}
