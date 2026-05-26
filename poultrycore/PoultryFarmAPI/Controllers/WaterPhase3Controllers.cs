using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/Water/raw-material-items")]
    public class WaterRawMaterialItemController : ControllerBase
    {
        private readonly IWaterRawMaterialItemService _svc;
        public WaterRawMaterialItemController(IWaterRawMaterialItemService svc) => _svc = svc;

        [HttpGet] public async Task<ActionResult<IEnumerable<WaterRawMaterialItemModel>>> GetAll([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetAllAsync(farmId));

        [HttpGet("{id:int}")] public async Task<ActionResult<WaterRawMaterialItemModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var m = await _svc.GetByIdAsync(id, farmId);
            return m is null ? NotFound() : Ok(m);
        }

        [HttpGet("low-stock")] public async Task<ActionResult<IEnumerable<WaterRawMaterialItemModel>>> GetLowStock([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetLowStockAsync(farmId));

        [HttpPost] public async Task<ActionResult<WaterRawMaterialItemModel>> Create([FromBody] WaterRawMaterialItemModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.InsertAsync(m);
            var created = await _svc.GetByIdAsync(id, m.FarmId);
            return CreatedAtAction(nameof(GetById), new { id, farmId = m.FarmId }, created);
        }

        [HttpPut("{id:int}")] public async Task<IActionResult> Update(int id, [FromBody] WaterRawMaterialItemModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            m.WaterRawMaterialItemId = id;
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
    [Route("api/Water/raw-material-purchases")]
    public class WaterRawMaterialPurchaseController : ControllerBase
    {
        private readonly IWaterRawMaterialPurchaseService _svc;
        public WaterRawMaterialPurchaseController(IWaterRawMaterialPurchaseService svc) => _svc = svc;

        [HttpGet] public async Task<ActionResult<IEnumerable<WaterRawMaterialPurchaseModel>>> GetAll(
            [FromQuery] string farmId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetAllAsync(farmId, fromDate, toDate));

        [HttpPost] public async Task<ActionResult<int>> Create([FromBody] WaterRawMaterialPurchaseModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.InsertAsync(m);
            return Ok(new { WaterRawMaterialPurchaseId = id });
        }

        [HttpPut("{id:int}")] public async Task<IActionResult> Update(int id, [FromBody] WaterRawMaterialPurchaseModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            m.WaterRawMaterialPurchaseId = id;
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
    [Route("api/Water/raw-material-usage")]
    public class WaterRawMaterialUsageController : ControllerBase
    {
        private readonly IWaterRawMaterialUsageService _svc;
        public WaterRawMaterialUsageController(IWaterRawMaterialUsageService svc) => _svc = svc;

        [HttpGet] public async Task<ActionResult<IEnumerable<WaterRawMaterialUsageModel>>> GetAll(
            [FromQuery] string farmId, [FromQuery] int? batchId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetAllAsync(farmId, batchId, fromDate, toDate));

        [HttpPost] public async Task<ActionResult<int>> Create([FromBody] WaterRawMaterialUsageModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.InsertAsync(m);
            return Ok(new { WaterRawMaterialUsageId = id });
        }
    }

    [ApiController]
    [Route("api/Water/loss-records")]
    public class WaterLossRecordController : ControllerBase
    {
        private readonly IWaterLossRecordService _svc;
        public WaterLossRecordController(IWaterLossRecordService svc) => _svc = svc;

        [HttpGet] public async Task<ActionResult<IEnumerable<WaterLossRecordModel>>> GetAll(
            [FromQuery] string farmId, [FromQuery] string? lossType, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetAllAsync(farmId, lossType, fromDate, toDate));

        [HttpPost] public async Task<ActionResult<int>> Create([FromBody] WaterLossRecordModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.InsertAsync(m);
            return Ok(new { WaterLossRecordId = id });
        }

        [HttpPost("{id:int}/approve")] public async Task<IActionResult> Approve(int id, [FromQuery] string farmId, [FromQuery] string? approvedBy)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.ApproveAsync(id, farmId, approvedBy);
            return NoContent();
        }
    }

    [ApiController]
    [Route("api/Water/daily-closings")]
    public class WaterDailyClosingController : ControllerBase
    {
        private readonly IWaterDailyClosingService _svc;
        public WaterDailyClosingController(IWaterDailyClosingService svc) => _svc = svc;

        [HttpGet] public async Task<ActionResult<IEnumerable<WaterDailyClosingModel>>> GetAll(
            [FromQuery] string farmId, [FromQuery] string? status, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetAllAsync(farmId, status, fromDate, toDate));

        [HttpGet("{id:int}")] public async Task<ActionResult<WaterDailyClosingModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var m = await _svc.GetByIdAsync(id, farmId);
            return m is null ? NotFound() : Ok(m);
        }

        [HttpPost] public async Task<ActionResult<WaterDailyClosingModel>> Create([FromBody] WaterDailyClosingModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.InsertAsync(m);
            var created = await _svc.GetByIdAsync(id, m.FarmId);
            return CreatedAtAction(nameof(GetById), new { id, farmId = m.FarmId }, created);
        }

        [HttpPost("{id:int}/submit")] public async Task<ActionResult<WaterDailyClosingModel>> Submit(
            int id, [FromQuery] string farmId, [FromBody] WaterDailyClosingSubmitRequest req, [FromQuery] string? submittedBy)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var updated = await _svc.SubmitAsync(id, farmId, req, submittedBy);
            return updated is null ? NotFound() : Ok(updated);
        }

        [HttpPost("{id:int}/approve")] public async Task<IActionResult> Approve(int id, [FromQuery] string farmId, [FromQuery] string? approvedBy)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.ApproveAsync(id, farmId, approvedBy);
            return NoContent();
        }

        [HttpPost("{id:int}/reject")] public async Task<IActionResult> Reject(
            int id, [FromQuery] string farmId, [FromBody] WaterDailyClosingRejectRequest req, [FromQuery] string? approvedBy)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            if (!ModelState.IsValid) return BadRequest(ModelState);
            await _svc.RejectAsync(id, farmId, req.RejectionReason, approvedBy);
            return NoContent();
        }

        // Delete a Draft or Rejected closing. Returns 404 with a hint if the row is Submitted/Approved
        // (or doesn't exist) — keeps the audit trail honest by not silently swallowing the no-op.
        [HttpDelete("{id:int}")] public async Task<IActionResult> Delete(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var deleted = await _svc.DeleteAsync(id, farmId);
            return deleted ? NoContent() : NotFound("Closing not found, or it is Submitted/Approved (immutable).");
        }

        // Edit ManagerNotes on a Draft or Rejected closing. The auto-aggregated production / sales / cash
        // fields are NOT user-editable (they come from the source SPs at submit time).
        [HttpPut("{id:int}/notes")] public async Task<IActionResult> UpdateNotes(
            int id, [FromQuery] string farmId, [FromBody] WaterDailyClosingNotesRequest req)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            if (req == null) return BadRequest("Body required.");
            var updated = await _svc.UpdateNotesAsync(id, farmId, req.ManagerNotes);
            return updated ? NoContent() : NotFound("Closing not found, or it is Submitted/Approved (immutable).");
        }
    }

    public class WaterDailyClosingNotesRequest
    {
        public string? ManagerNotes { get; set; }
    }

    [ApiController]
    [Route("api/Water/reports")]
    public class WaterReportController : ControllerBase
    {
        private readonly IWaterReportService _svc;
        public WaterReportController(IWaterReportService svc) => _svc = svc;

        [HttpGet("period-pnl")] public async Task<ActionResult<WaterPeriodPnLModel>> PeriodPnL(
            [FromQuery] string farmId, [FromQuery] DateTime fromDate, [FromQuery] DateTime toDate)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") :
               (await _svc.GetPeriodPnLAsync(farmId, fromDate, toDate)) is { } pnl ? Ok(pnl) : NotFound();

        [HttpGet("route-profitability")] public async Task<ActionResult<IEnumerable<WaterRouteProfitabilityRow>>> RouteProfitability(
            [FromQuery] string farmId, [FromQuery] DateTime fromDate, [FromQuery] DateTime toDate)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetRouteProfitabilityAsync(farmId, fromDate, toDate));

        [HttpGet("driver-reconciliation")] public async Task<ActionResult<IEnumerable<WaterDriverReconciliationRow>>> DriverReconciliation(
            [FromQuery] string farmId, [FromQuery] DateTime fromDate, [FromQuery] DateTime toDate)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetDriverReconciliationAsync(farmId, fromDate, toDate));

        [HttpGet("raw-material-variance")] public async Task<ActionResult<IEnumerable<WaterRawMaterialVarianceRow>>> RawMaterialVariance(
            [FromQuery] string farmId, [FromQuery] DateTime fromDate, [FromQuery] DateTime toDate)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetRawMaterialVarianceAsync(farmId, fromDate, toDate));

        [HttpGet("dashboard-extended")] public async Task<ActionResult<WaterDashboardExtendedModel>> DashboardExtended([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetDashboardExtendedAsync(farmId));

        // Migration 057: dashboard intelligence (gap #7 — owner-intelligence cards)

        [HttpGet("expense-by-category")] public async Task<ActionResult<IEnumerable<WaterExpenseByCategoryRow>>> ExpenseByCategory(
            [FromQuery] string farmId, [FromQuery] DateTime fromDate, [FromQuery] DateTime toDate)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetExpenseByCategoryAsync(farmId, fromDate, toDate));

        [HttpGet("top-customers")] public async Task<ActionResult<IEnumerable<WaterTopCustomerRow>>> TopCustomers(
            [FromQuery] string farmId, [FromQuery] DateTime fromDate, [FromQuery] DateTime toDate, [FromQuery] int topN = 10)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetTopCustomersAsync(farmId, fromDate, toDate, topN));
    }
}
