using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Filters;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/generic-company/{farmId}/deliveries")]
    [RequireCompanyType("Generic")]
    public class GenericDeliveryController : ControllerBase
    {
        private readonly IGenericDeliveryService _svc;

        public GenericDeliveryController(IGenericDeliveryService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<GenericDeliveryModel>>> GetAll(
            string farmId,
            [FromQuery] string? status = null,
            [FromQuery] DateTime? fromDate = null,
            [FromQuery] DateTime? toDate = null)
        {
            return Ok(await _svc.GetAllAsync(farmId, status, fromDate, toDate));
        }

        [HttpPost("load")]
        public async Task<ActionResult<int>> Load(string farmId, [FromBody] GenericDeliveryLoadRequest req)
        {
            req.FarmId = farmId;
            var id = await _svc.LoadAsync(req);
            return Ok(id);
        }

        [HttpPost("{id:int}/reconcile")]
        public async Task<IActionResult> Reconcile(string farmId, int id, [FromBody] GenericDeliveryReconcileRequest req)
        {
            req.FarmId = farmId;
            await _svc.ReconcileAsync(id, req);
            return Ok();
        }

        [HttpPost("{id:int}/reverse")]
        public async Task<IActionResult> Reverse(string farmId, int id)
        {
            await _svc.ReverseAsync(id, farmId);
            return Ok();
        }

        [HttpPost("{id:int}/cancel")]
        public async Task<IActionResult> Cancel(string farmId, int id)
        {
            await _svc.CancelAsync(id, farmId);
            return Ok();
        }

        [HttpPost("{id:int}/dispatch")]
        public async Task<IActionResult> Dispatch(string farmId, int id)
        {
            await _svc.DispatchAsync(id, farmId);
            return Ok();
        }

        [HttpPost("{id:int}/mark-delivered")]
        public async Task<IActionResult> MarkDelivered(string farmId, int id)
        {
            await _svc.MarkDeliveredAsync(id, farmId);
            return Ok();
        }

        [HttpGet("reports/by-driver")]
        public async Task<ActionResult<IEnumerable<GenericDriverReportRow>>> DriverReport(
            string farmId, [FromQuery] DateTime? fromDate = null, [FromQuery] DateTime? toDate = null,
            [FromQuery] string? driverName = null)
            => Ok(await _svc.DriverReportAsync(farmId, fromDate, toDate, driverName));

        [HttpGet("reports/by-product")]
        public async Task<ActionResult<IEnumerable<GenericProductDeliveryRow>>> ProductReport(
            string farmId, [FromQuery] DateTime? fromDate = null, [FromQuery] DateTime? toDate = null)
            => Ok(await _svc.ProductReportAsync(farmId, fromDate, toDate));

        [HttpGet("reports/by-route")]
        // Note: report endpoints are below
        public async Task<ActionResult<IEnumerable<GenericRouteReportRow>>> RouteReport(
            string farmId, [FromQuery] DateTime? fromDate = null, [FromQuery] DateTime? toDate = null)
            => Ok(await _svc.RouteReportAsync(farmId, fromDate, toDate));
    }

    // =========================================================================
    // Drivers
    // =========================================================================
    [ApiController]
    [Route("api/generic-company/{farmId}/drivers")]
    [RequireCompanyType("Generic")]
    public class GenericDriverController : ControllerBase
    {
        private readonly IGenericDriverService _svc;
        public GenericDriverController(IGenericDriverService svc) => _svc = svc;

        [HttpGet] public async Task<ActionResult<IEnumerable<GenericDriverModel>>> List(string farmId)
            => Ok(await _svc.ListAsync(farmId));

        [HttpPost] public async Task<ActionResult<int>> Create(string farmId, [FromBody] GenericDriverInput req)
        { req.FarmId = farmId; return Ok(await _svc.CreateAsync(req)); }

        [HttpPut("{id:int}")] public async Task<IActionResult> Update(string farmId, int id, [FromBody] GenericDriverInput req)
        { req.FarmId = farmId; await _svc.UpdateAsync(id, req); return Ok(); }

        [HttpDelete("{id:int}")] public async Task<IActionResult> Delete(string farmId, int id)
        { await _svc.DeleteAsync(id, farmId); return Ok(); }
    }

    // =========================================================================
    // Routes
    // =========================================================================
    [ApiController]
    [Route("api/generic-company/{farmId}/routes")]
    [RequireCompanyType("Generic")]
    public class GenericRouteController : ControllerBase
    {
        private readonly IGenericRouteService _svc;
        public GenericRouteController(IGenericRouteService svc) => _svc = svc;

        [HttpGet] public async Task<ActionResult<IEnumerable<GenericRouteModel>>> List(string farmId)
            => Ok(await _svc.ListAsync(farmId));

        [HttpPost] public async Task<ActionResult<int>> Create(string farmId, [FromBody] GenericRouteInput req)
        { req.FarmId = farmId; return Ok(await _svc.CreateAsync(req)); }

        [HttpPut("{id:int}")] public async Task<IActionResult> Update(string farmId, int id, [FromBody] GenericRouteInput req)
        { req.FarmId = farmId; await _svc.UpdateAsync(id, req); return Ok(); }

        [HttpDelete("{id:int}")] public async Task<IActionResult> Delete(string farmId, int id)
        { await _svc.DeleteAsync(id, farmId); return Ok(); }
    }
}
