using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Filters;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // Generic supplier credit / debt (migration 449, Report 40). The same routes
    // and shapes as WaterBalancesController (426) and PoultryBalancesController
    // (370), so lib/api/supplier-credit.ts only swaps the prefix ("Generic").
    [ApiController]
    [Route("api/Generic")]
    [RequireCompanyType("Generic")]
    public class GenericSupplierCreditsLedgerController : ControllerBase
    {
        private readonly IGenericSupplierCreditsLedgerService _svc;
        public GenericSupplierCreditsLedgerController(IGenericSupplierCreditsLedgerService svc) => _svc = svc;

        private string? Me() => User?.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;

        // -------------------------------------------- 449 supplier credit / debt
        // Same routes and shapes as PoultryBalancesController (370).

        private async Task<ActionResult> Run(Func<Task<object>> f)
        {
            try { return Ok(await f()); }
            catch (Npgsql.PostgresException ex) when (ex.SqlState == "P0001") { return BadRequest(new { message = ex.MessageText }); }
        }

        [HttpGet("supplier-credits")]
        public async Task<ActionResult<IEnumerable<SupplierCreditSummaryRow>>> GetSupplierCredits([FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest(new { message = "Company ID is required." });
            return Ok(await _svc.GetSupplierCreditSummary(farmId));
        }

        [HttpGet("supplier-credits/events")]
        public async Task<ActionResult<IEnumerable<SupplierCreditEventRow>>> GetSupplierCreditEvents([FromQuery] string farmId, [FromQuery] int? supplierId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest(new { message = "Company ID is required." });
            return Ok(await _svc.GetSupplierCreditEvents(farmId, supplierId));
        }

        [HttpGet("supplier-credits/applications")]
        public async Task<ActionResult<IEnumerable<SupplierCreditApplicationRow>>> GetSupplierCreditApplications([FromQuery] string farmId, [FromQuery] int? supplierId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest(new { message = "Company ID is required." });
            return Ok(await _svc.GetSupplierCreditApplications(farmId, supplierId));
        }

        [HttpPost("supplier-credits/manual")]
        [SetupAdminOnly]
        public Task<ActionResult> CreateSupplierCredit([FromBody] SupplierCreditCreateRequest r)
        {
            r.CreatedBy = Me() ?? r.CreatedBy;
            return Run(async () => new { paymentId = await _svc.CreateSupplierCredit(r) });
        }

        [HttpPost("supplier-credits/{paymentId:int}/reverse")]
        [SetupAdminOnly]
        public Task<ActionResult> ReverseSupplierCredit(int paymentId, [FromBody] SupplierReasonRequest r)
        {
            r.By = Me() ?? r.By;
            return Run(async () => new { reversed = await _svc.ReverseSupplierCredit(paymentId, r) });
        }

        [HttpPost("supplier-credits/apply")]
        public Task<ActionResult> ApplySupplierCredit([FromBody] SupplierCreditApplyRequest r)
        {
            r.CreatedBy = Me() ?? r.CreatedBy;
            return Run(async () => new { allocationId = await _svc.ApplySupplierCredit(r) });
        }

        [HttpPost("supplier-credits/applications/{allocationId:int}/reverse")]
        [SetupAdminOnly]
        public Task<ActionResult> UnapplySupplierCredit(int allocationId, [FromBody] SupplierReasonRequest r)
        {
            r.By = Me() ?? r.By;
            return Run(async () => new { allocationId = await _svc.UnapplySupplierCredit(allocationId, r) });
        }

        [HttpGet("supplier-credits/refunds")]
        public async Task<ActionResult<IEnumerable<SupplierRefundRow>>> GetSupplierRefunds([FromQuery] string farmId, [FromQuery] int? supplierId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest(new { message = "Company ID is required." });
            return Ok(await _svc.GetSupplierRefunds(farmId, supplierId));
        }

        [HttpPost("supplier-credits/refunds")]
        public Task<ActionResult> RecordSupplierRefund([FromBody] SupplierRefundRequest r)
        {
            r.CreatedBy = Me() ?? r.CreatedBy;
            return Run(async () => new { refundId = await _svc.RecordSupplierRefund(r) });
        }

        [HttpPost("supplier-credits/refunds/{refundId:int}/reverse")]
        [SetupAdminOnly]
        public Task<ActionResult> ReverseSupplierRefund(int refundId, [FromBody] SupplierReasonRequest r)
        {
            r.By = Me() ?? r.By;
            return Run(async () => new { refundId = await _svc.ReverseSupplierRefund(refundId, r) });
        }

        [HttpGet("supplier-debts")]
        public async Task<ActionResult<IEnumerable<SupplierDebtRow>>> GetSupplierDebts([FromQuery] string farmId, [FromQuery] int? supplierId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest(new { message = "Company ID is required." });
            return Ok(await _svc.GetSupplierDebts(farmId, supplierId));
        }

        [HttpPost("supplier-debts")]
        [SetupAdminOnly]
        public async Task<ActionResult> CreateSupplierDebt([FromBody] SupplierDebtRequest r)
        {
            r.CreatedBy = Me() ?? r.CreatedBy;
            try { return Content(await _svc.CreateSupplierDebt(r), "application/json"); }
            catch (Npgsql.PostgresException ex) when (ex.SqlState == "P0001") { return BadRequest(new { message = ex.MessageText }); }
        }

        [HttpPost("supplier-debts/{debtId:int}/reverse")]
        [SetupAdminOnly]
        public Task<ActionResult> ReverseSupplierDebt(int debtId, [FromBody] SupplierReasonRequest r)
        {
            r.By = Me() ?? r.By;
            return Run(async () => new { debtId = await _svc.ReverseSupplierDebt(debtId, r) });
        }

    }
}
