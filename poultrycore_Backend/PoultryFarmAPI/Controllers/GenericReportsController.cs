using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Filters;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // =========================================================================
    // Daily Closing - Draft → Submitted (auto-aggregates) → Approved/Rejected.
    // =========================================================================
    [ApiController]
    [Route("api/generic-company/{farmId}/daily-closings")]
    [RequireCompanyType("Generic")]
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
    [RequireCompanyType("Generic")]
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

        [HttpGet("profit-loss")]
        [Microsoft.AspNetCore.Authorization.Authorize]
        public async Task<ActionResult<List<GenericProfitLossEntry>>> ProfitLoss(
            string farmId, [FromQuery] DateOnly fromDate, [FromQuery] DateOnly toDate,
            [FromServices] IIamService iam, CancellationToken cancellationToken)
        {
            if (fromDate == default || toDate == default || fromDate > toDate)
                return BadRequest("Choose a valid start and end date.");
            if (Request.Query.ContainsKey("farmId"))
                return BadRequest("Specify the company in the report URL.");
            if (!string.Equals(User.FindFirst("FarmId")?.Value, farmId, StringComparison.OrdinalIgnoreCase))
            {
                var userId = User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;
                if (userId is null || !await iam.HasPermissionAsync(userId, farmId, "generic.reports.view"))
                    return Forbid();
            }
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            try
            {
                return Ok(await _reports.GetProfitLossEntriesAsync(farmId, fromDate, toDate, cancellationToken));
            }
            catch (Npgsql.PostgresException ex) when (ex.SqlState is "42P01" or "42703" or "42883")
            {
                // Missing table (42P01), column (42703) or function (42883): this database
                // has not had the Generic money migrations applied (405-408, 442, 448-455).
                return StatusCode(500, $"Profit & Loss needs database migrations that are not applied here " +
                    $"(Generic 405-408, 442, 448-455). Database said: {ex.MessageText}");
            }
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

        // ---- Phase 4 (migration 442) ----

        [HttpGet("financial-preview")]
        public async Task<ActionResult<GenericFinancialPreviewModel>> FinancialPreview(
            string farmId, [FromQuery] int productId, [FromQuery] decimal quantity, [FromQuery] string transactionType)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            if (productId <= 0) return BadRequest("productId is required.");
            if (quantity <= 0) return BadRequest("quantity must be positive.");
            if (string.IsNullOrWhiteSpace(transactionType)) return BadRequest("transactionType is required (Sale, InternalUse, Production, Purchase).");
            return Ok(await _reports.GetFinancialPreviewAsync(farmId, productId, quantity, transactionType));
        }

        [HttpGet("pnl-breakdown")]
        public async Task<ActionResult<GenericPnLBreakdownModel>> PnLBreakdown(
            string farmId, [FromQuery] DateTime fromDate, [FromQuery] DateTime toDate)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _reports.GetPnLBreakdownAsync(farmId, fromDate, toDate));
        }

        [HttpGet("item-cost-reconciliation")]
        public async Task<ActionResult<GenericItemCostReconciliationModel>> ItemCostReconciliation(
            string farmId, [FromQuery] int productId)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            if (productId <= 0) return BadRequest("productId is required.");
            return Ok(await _reports.GetItemCostReconciliationAsync(farmId, productId));
        }

        // ---- Phase 5 (migration 443) ----

        [HttpGet("inventory-balance")]
        public async Task<ActionResult<IEnumerable<GenericInventoryBalanceRow>>> InventoryBalance(
            string farmId, [FromQuery] DateTime fromDate, [FromQuery] DateTime toDate)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _reports.GetInventoryBalanceAsync(farmId, fromDate, toDate));
        }

        [HttpGet("internal-consumption")]
        public async Task<ActionResult<IEnumerable<GenericConsumptionRow>>> InternalConsumption(
            string farmId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate, [FromQuery] string? category)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _reports.GetInternalConsumptionAsync(farmId, fromDate, toDate, category));
        }

        [HttpGet("consumption-summary")]
        public async Task<ActionResult<GenericConsumptionSummary>> ConsumptionSummary(
            string farmId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _reports.GetConsumptionSummaryAsync(farmId, fromDate, toDate));
        }

        [HttpGet("inventory-reconciliation")]
        public async Task<ActionResult<IEnumerable<GenericReconciliationRow>>> InventoryReconciliation(string farmId)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _reports.GetInventoryReconciliationAsync(farmId));
        }

        [HttpGet("restock-forecast")]
        public async Task<ActionResult<IEnumerable<GenericRestockForecastRow>>> RestockForecast(
            string farmId, [FromQuery] int lookbackDays = 30)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _reports.GetRestockForecastAsync(farmId, lookbackDays));
        }
    }
}
