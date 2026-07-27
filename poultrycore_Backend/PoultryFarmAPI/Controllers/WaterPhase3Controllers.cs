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

        // Recompute CurrentQuantity from purchases, usage and adjustments. Omit
        // itemId to recalculate every raw material / supply for the company.
        [HttpPost("recalculate-stock")] public async Task<ActionResult<IEnumerable<WaterRawMaterialRecalcRow>>> RecalculateStock(
            [FromQuery] string farmId, [FromQuery] int? itemId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.RecalculateStockAsync(farmId, itemId));

        // Manual stock adjustment (increase/decrease) on a raw material / supply.
        // Side-effect-free: does not post to Expense or production usage.
        [HttpPost("{id:int}/adjust")] public async Task<ActionResult<object>> Adjust(int id, [FromBody] WaterRawMaterialAdjustRequest body)
        {
            if (body is null || string.IsNullOrWhiteSpace(body.FarmId)) return BadRequest("Company ID is required.");
            if (body.Quantity == 0) return BadRequest("Adjustment quantity cannot be zero.");
            var current = await _svc.AdjustAsync(id, body);
            return Ok(new { CurrentQuantity = current });
        }
    }

    [ApiController]
    [Route("api/Water/raw-material-adjustments")]
    public class WaterRawMaterialAdjustmentController : ControllerBase
    {
        private readonly IWaterRawMaterialItemService _svc;
        public WaterRawMaterialAdjustmentController(IWaterRawMaterialItemService svc) => _svc = svc;

        [HttpGet] public async Task<ActionResult<IEnumerable<WaterRawMaterialAdjustmentModel>>> GetAll(
            [FromQuery] string farmId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetAdjustmentsAsync(farmId, fromDate, toDate));
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

        // Record a follow-up payment against an outstanding purchase balance.
        // Posts its own expense + cash-out and returns the new outstanding balance.
        [HttpPost("{id:int}/pay-balance")] public async Task<IActionResult> PayBalance(int id, [FromBody] PayBalanceRequest body)
        {
            if (body is null || string.IsNullOrWhiteSpace(body.FarmId)) return BadRequest("Company ID is required.");
            if (body.Amount <= 0) return BadRequest("Payment amount must be greater than 0.");
            var balance = await _svc.PayBalanceAsync(id, body.FarmId, body.Amount, body.PaymentMethod, body.PaymentDate, body.CreatedBy);
            return Ok(new { Balance = balance });
        }
    }

    public class PayBalanceRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public decimal Amount { get; set; }
        public string? PaymentMethod { get; set; }
        public DateTime? PaymentDate { get; set; }
        public string? CreatedBy { get; set; }
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

        // Migration 068 — Edit a Pending loss record inline. SP rejects edits
        // on Approved records (must Unapprove first).
        [HttpPut("{id:int}")]
        public async Task<IActionResult> Update(int id, [FromQuery] string farmId, [FromBody] WaterLossRecordModel m)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            if (!ModelState.IsValid) return BadRequest(ModelState);
            m.WaterLossRecordId = id;
            m.FarmId = farmId;
            await _svc.UpdateAsync(m);
            return NoContent();
        }

        // Migration 068 — Unapprove an Approved record. Reason is captured for audit.
        [HttpPost("{id:int}/unapprove")]
        public async Task<IActionResult> Unapprove(int id, [FromQuery] string farmId, [FromQuery] string? unapprovedBy,
            [FromBody] UnapproveLossRequest? body)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.UnapproveAsync(id, farmId, unapprovedBy, body?.Reason);
            return NoContent();
        }

        public class UnapproveLossRequest { public string? Reason { get; set; } }
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

        // Migration 068 — Reopen an active closing (marks it Reopened) so a
        // new submission can be made for the same date.
        [HttpPost("{id:int}/reopen")]
        public async Task<IActionResult> Reopen(int id, [FromQuery] string farmId, [FromQuery] string? reopenedBy,
            [FromBody] ReopenClosingRequest? body)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.ReopenAsync(id, farmId, reopenedBy, body?.Reason);
            return NoContent();
        }

        // Migration 068 — Link a fresh closing back to the one it superseded.
        // Frontend calls this after a successful Resubmit.
        [HttpPost("{newId:int}/link-superseded")]
        public async Task<IActionResult> LinkSuperseded(int newId, [FromQuery] string farmId,
            [FromBody] LinkSupersededRequest body)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            if (body is null || body.PreviousClosingId <= 0) return BadRequest("PreviousClosingId is required.");
            await _svc.LinkSupersededAsync(newId, farmId, body.PreviousClosingId);
            return NoContent();
        }

        public class ReopenClosingRequest { public string? Reason { get; set; } }
        public class LinkSupersededRequest { public int PreviousClosingId { get; set; } }

        // Migration 079 — one-shot Recreate. Used by the "Recreate Closing"
        // button shown on a Reopened row in the Daily Closing UI.
        [HttpPost("recreate")]
        public async Task<ActionResult<object>> Recreate(
            [FromQuery] string farmId,
            [FromQuery] string? createdBy,
            [FromBody] RecreateClosingRequest body)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            if (body is null || body.PredecessorClosingId <= 0)
                return BadRequest("PredecessorClosingId is required.");

            var newId = await _svc.RecreateAsync(
                farmId,
                body.ClosingDate,
                body.PredecessorClosingId,
                createdBy,
                body.ActualCashCounted,
                body.ManagerNotes,
                body.DifferenceReason);

            var created = await _svc.GetByIdAsync(newId, farmId);
            return Ok(new { WaterDailyClosingId = newId, Closing = created });
        }

        public class RecreateClosingRequest
        {
            public DateTime ClosingDate { get; set; }
            public int      PredecessorClosingId { get; set; }
            public decimal  ActualCashCounted { get; set; }
            public string?  ManagerNotes { get; set; }
            public string?  DifferenceReason { get; set; }
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

        // Migration 066: Prompt 2 #16 — Driver Collection Report.
        [HttpGet("driver-collection")]
        public async Task<ActionResult<WaterDriverCollectionReport>> DriverCollection(
            [FromQuery] string farmId,
            [FromQuery] DateTime fromDate,
            [FromQuery] DateTime toDate,
            [FromQuery] int? waterDriverId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetDriverCollectionAsync(farmId, fromDate, toDate, waterDriverId));
        }

        [HttpGet("dashboard-extended")] public async Task<ActionResult<WaterDashboardExtendedModel>> DashboardExtended([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetDashboardExtendedAsync(farmId));

        // Migration 057: dashboard intelligence (gap #7 — owner-intelligence cards)

        [HttpGet("expense-by-category")] public async Task<ActionResult<IEnumerable<WaterExpenseByCategoryRow>>> ExpenseByCategory(
            [FromQuery] string farmId, [FromQuery] DateTime fromDate, [FromQuery] DateTime toDate)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetExpenseByCategoryAsync(farmId, fromDate, toDate));

        [HttpGet("top-customers")] public async Task<ActionResult<IEnumerable<WaterTopCustomerRow>>> TopCustomers(
            [FromQuery] string farmId, [FromQuery] DateTime fromDate, [FromQuery] DateTime toDate, [FromQuery] int topN = 10)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetTopCustomersAsync(farmId, fromDate, toDate, topN));

        // Migration 081 — Supplier activity report.
        [HttpGet("supplier-activity")] public async Task<ActionResult<IEnumerable<WaterSupplierActivityRow>>> SupplierActivity(
            [FromQuery] string farmId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetSupplierActivityAsync(farmId, fromDate, toDate));
    }

    // Migration 068 — currency settings on the Water company. The Login API
    // owns the rest of the Farms row (Name, Type, OwnerUserId) but currency is
    // read/written here so the Water UI doesn't need cross-API plumbing.
    [ApiController]
    [Route("api/Water/farm-settings")]
    public class WaterFarmSettingsController : ControllerBase
    {
        private readonly IWaterFarmSettingsService _svc;
        public WaterFarmSettingsController(IWaterFarmSettingsService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<WaterFarmSettingsModel>> Get([FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var s = await _svc.GetAsync(farmId);
            return s is null ? NotFound() : Ok(s);
        }

        [HttpPut("currency")]
        public async Task<ActionResult<WaterFarmSettingsModel>> UpdateCurrency(
            [FromQuery] string farmId, [FromBody] WaterFarmSettingsCurrencyRequest body)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            if (body is null) return BadRequest("Body required.");
            var s = await _svc.UpdateCurrencyAsync(
                farmId,
                string.IsNullOrWhiteSpace(body.CurrencyCode)   ? "GHS" : body.CurrencyCode,
                string.IsNullOrWhiteSpace(body.CurrencySymbol) ? "GHC" : body.CurrencySymbol,
                body.ShowCurrencySymbol);
            return s is null ? NotFound() : Ok(s);
        }
    }
}
