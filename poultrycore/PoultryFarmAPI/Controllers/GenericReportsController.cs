using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // =========================================================================
    // Daily Closing - Draft → Submitted (auto-aggregates) → Approved/Rejected.
    // =========================================================================
    [ApiController]
    [Route("api/generic-company/{farmId}/daily-closings")]
    public class GenericDailyClosingController : ControllerBase
    {
        private readonly IGenericDailyClosingService _svc;
        private readonly IGenericCompanyService _companies;

        public GenericDailyClosingController(IGenericDailyClosingService svc, IGenericCompanyService companies)
        {
            _svc = svc;
            _companies = companies;
        }

        [HttpGet]
        public async Task<ActionResult<IEnumerable<GenericDailyClosingModel>>> GetAll(
            string farmId,
            [FromQuery] DateTime? fromDate,
            [FromQuery] DateTime? toDate,
            [FromQuery] string? status,
            [FromQuery] int? branchId)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _svc.GetAllAsync(farmId, fromDate, toDate, status, branchId));
        }

        [HttpGet("{id:int}")]
        public async Task<ActionResult<GenericDailyClosingModel>> GetById(string farmId, int id)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            var c = await _svc.GetByIdAsync(id, farmId);
            return c is null ? NotFound() : Ok(c);
        }

        [HttpPost]
        public async Task<ActionResult<GenericDailyClosingModel>> Create(
            string farmId, [FromBody] GenericDailyClosingCreateRequest req, [FromQuery] string? createdBy)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            var newId = await _svc.InsertAsync(farmId, req, createdBy);
            var created = await _svc.GetByIdAsync(newId, farmId);
            return CreatedAtAction(nameof(GetById), new { farmId, id = newId }, created);
        }

        [HttpPost("{id:int}/submit")]
        public async Task<ActionResult<GenericDailyClosingModel>> Submit(
            string farmId, int id,
            [FromBody] GenericDailyClosingSubmitRequest req,
            [FromQuery] string? submittedBy)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            var updated = await _svc.SubmitAsync(id, farmId, req, submittedBy);
            return updated is null ? NotFound() : Ok(updated);
        }

        [HttpPost("{id:int}/approve")]
        public async Task<IActionResult> Approve(string farmId, int id, [FromQuery] string? approvedBy)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            await _svc.ApproveAsync(id, farmId, approvedBy);
            return NoContent();
        }

        [HttpPost("{id:int}/reject")]
        public async Task<IActionResult> Reject(
            string farmId, int id,
            [FromBody] GenericDailyClosingRejectRequest body,
            [FromQuery] string? approvedBy)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            await _svc.RejectAsync(id, farmId, body.RejectionReason, approvedBy);
            return NoContent();
        }
    }

    // =========================================================================
    // Reports.
    // =========================================================================
    [ApiController]
    [Route("api/generic-company/{farmId}/reports")]
    public class GenericReportController : ControllerBase
    {
        private readonly IGenericReportService _reports;
        private readonly IGenericCompanyService _companies;

        public GenericReportController(IGenericReportService reports, IGenericCompanyService companies)
        {
            _reports = reports;
            _companies = companies;
        }

        [HttpGet("dashboard")]
        public async Task<ActionResult<GenericDashboardModel>> Dashboard(
            string farmId, [FromQuery] DateTime? asOf)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _reports.GetDashboardAsync(farmId, asOf));
        }

        [HttpGet("period-pnl")]
        public async Task<ActionResult<GenericPeriodPnLModel>> PeriodPnL(
            string farmId, [FromQuery] DateTime fromDate, [FromQuery] DateTime toDate)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _reports.GetPeriodPnLAsync(farmId, fromDate, toDate));
        }

        [HttpGet("sales-by-product")]
        public async Task<ActionResult<IEnumerable<GenericSalesByProductRow>>> SalesByProduct(
            string farmId, [FromQuery] DateTime fromDate, [FromQuery] DateTime toDate)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _reports.GetSalesByProductAsync(farmId, fromDate, toDate));
        }

        [HttpGet("sales-by-customer")]
        public async Task<ActionResult<IEnumerable<GenericSalesByCustomerRow>>> SalesByCustomer(
            string farmId, [FromQuery] DateTime fromDate, [FromQuery] DateTime toDate)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _reports.GetSalesByCustomerAsync(farmId, fromDate, toDate));
        }

        [HttpGet("expenses-by-category")]
        public async Task<ActionResult<IEnumerable<GenericExpenseByCategoryRow>>> ExpensesByCategory(
            string farmId, [FromQuery] DateTime fromDate, [FromQuery] DateTime toDate)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _reports.GetExpensesByCategoryAsync(farmId, fromDate, toDate));
        }

        [HttpGet("inventory-value")]
        public async Task<ActionResult<GenericInventoryValueReport>> InventoryValue(string farmId)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _reports.GetInventoryValueAsync(farmId));
        }

        [HttpGet("cash-summary")]
        public async Task<ActionResult<GenericCashSummaryReport>> CashSummary(
            string farmId, [FromQuery] DateTime fromDate, [FromQuery] DateTime toDate)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _reports.GetCashSummaryAsync(farmId, fromDate, toDate));
        }
    }
}
