// 451. Generic payroll, the Poultry way: api/Generic/payroll-runs,
// api/Generic/payroll-templates, api/Generic/payroll-deductions. Ported from the
// Poultry controllers. (Eligible advances: api/Generic/employee-loans/eligible,
// already in GenericEmployeeLoanController.)

using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Filters;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // ====================================================================
    // Payroll Runs + Items
    // ====================================================================
    [ApiController]
    [Route("api/Generic/payroll-runs")]
    [RequireCompanyType("Generic")]
    public class GenericPayRunController : ControllerBase
    {
        private readonly IGenericPayRunService _svc;
        public GenericPayRunController(IGenericPayRunService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<GenericPayRunModel>>> GetAll(
            [FromQuery] string farmId, [FromQuery] string? status)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetRunsAsync(farmId, status));

        [HttpGet("{id:int}")]
        public async Task<ActionResult<GenericPayRunModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var m = await _svc.GetRunAsync(id, farmId);
            return m is null ? NotFound() : Ok(m);
        }

        [HttpPost]
        public async Task<ActionResult<object>> Create(
            [FromBody] GenericPayRunCreateRequest req, [FromQuery] string? createdBy)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.CreateRunAsync(req, createdBy);
            return Ok(new { GenericPayrollRunId = id });
        }

        [HttpPost("{id:int}/items")]
        public async Task<ActionResult<GenericPayItemModel>> UpsertItem(
            int id, [FromQuery] string farmId, [FromBody] GenericPayItemUpsertRequest req)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var item = await _svc.UpsertItemAsync(id, farmId, req);
            return item is null ? StatusCode(500, "Item upsert returned no row.") : Ok(item);
        }

        [HttpDelete("items/{itemId:int}")]
        public async Task<IActionResult> DeleteItem(int itemId, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.DeleteItemAsync(itemId, farmId);
            return NoContent();
        }

        [HttpPost("{id:int}/approve")]
        public async Task<IActionResult> Approve(int id, [FromQuery] string farmId, [FromQuery] string? approvedBy)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.ApproveAsync(id, farmId, approvedBy);
            return NoContent();
        }

        [HttpPost("{id:int}/mark-paid")]
        public async Task<IActionResult> MarkPaid(
            int id, [FromQuery] string farmId, [FromQuery] string? paidBy,
            [FromBody] GenericPayRunMarkPaidRequest? body)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.MarkPaidAsync(id, farmId, paidBy, body?.PayDate);
            return NoContent();
        }

        [HttpPost("{id:int}/cancel")]
        public async Task<IActionResult> Cancel(
            int id, [FromQuery] string farmId, [FromQuery] string? cancelledBy,
            [FromBody] GenericPayRunCancelRequest? body)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.CancelAsync(id, farmId, cancelledBy, body?.Reason);
            return NoContent();
        }

        [HttpPost("{id:int}/unapprove")]
        public async Task<IActionResult> Unapprove(
            int id, [FromQuery] string farmId, [FromQuery] string? reopenedBy,
            [FromBody] GenericPayRunCancelRequest? body)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.UnapproveAsync(id, farmId, reopenedBy, body?.Reason);
            return NoContent();
        }

        [HttpDelete("{id:int}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string farmId, [FromQuery] string? deletedBy)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.DeleteRunAsync(id, farmId, deletedBy);
            return NoContent();
        }

        [HttpGet("{id:int}/details")]
        public async Task<ActionResult<GenericPayRunDetailsModel>> GetDetails(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var details = await _svc.GetDetailsWithYtdAsync(id, farmId);
            return details is null ? NotFound() : Ok(details);
        }
    }

    [ApiController]
    [Route("api/Generic/payroll-templates")]
    [RequireCompanyType("Generic")]
    public class GenericPayrollTemplateController : ControllerBase
    {
        private readonly IGenericPayrollTemplateService _svc;
        public GenericPayrollTemplateController(IGenericPayrollTemplateService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<GenericPayrollTemplateModel>>> GetAll(
            [FromQuery] string farmId, [FromQuery] bool includeInactive = false)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetAllAsync(farmId, includeInactive));

        [HttpGet("{id:int}")]
        public async Task<ActionResult<GenericPayrollTemplateModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var t = await _svc.GetAsync(id, farmId);
            return t is null ? NotFound() : Ok(t);
        }

        [HttpPost]
        public async Task<ActionResult<object>> Create([FromBody] GenericPayrollTemplateSaveRequest req)
        {
            if (req is null || string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.SaveAsync(null, req);
            return Ok(new { GenericPayrollTemplateId = id });
        }

        [HttpPut("{id:int}")]
        public async Task<ActionResult<object>> Update(int id, [FromBody] GenericPayrollTemplateSaveRequest req)
        {
            if (req is null || string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required.");
            await _svc.SaveAsync(id, req);
            return Ok(new { GenericPayrollTemplateId = id });
        }

        [HttpPost("{id:int}/active")]
        public async Task<IActionResult> SetActive(int id, [FromBody] GenericPayrollTemplateSetActiveRequest req)
        {
            if (req is null || string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required.");
            await _svc.SetActiveAsync(id, req);
            return NoContent();
        }

        [HttpPost("{id:int}/create-run")]
        public async Task<ActionResult<object>> CreateRun(int id, [FromBody] GenericPayrollTemplateCreateRunRequest req)
        {
            if (req is null || string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required.");
            if (req.PeriodStart > req.PeriodEnd) return BadRequest("Period start cannot be after period end.");
            var runId = await _svc.CreateRunAsync(id, req);
            return Ok(new { GenericPayrollRunId = runId });
        }
    }

    /// <summary>
    /// The detail behind a payroll line's Deductions figure (306).
    ///
    /// Separate controller because it is payroll's resource, not the advance's:
    /// a deduction belongs to a payslip and only sometimes points at a loan.
    /// </summary>
    [ApiController]
    [Route("api/Generic/payroll-deductions")]
    [RequireCompanyType("Generic")]
    public class GenericPayrollDeductionController : ControllerBase
    {
        private readonly IGenericPayrollDeductionService _svc;
        public GenericPayrollDeductionController(IGenericPayrollDeductionService svc) => _svc = svc;

        /// <summary>
        /// The breakdown for one payslip line. Includes the synthetic legacy row
        /// for any part of the total no structured row explains -- it comes back
        /// with a null id, which is how the UI knows it cannot be edited.
        /// The rows always add up to the line's Deductions figure.
        /// </summary>
        [HttpGet]
        public async Task<ActionResult<IEnumerable<GenericPayrollDeductionModel>>> GetForItem(
            [FromQuery] string farmId, [FromQuery] int payrollItemId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            if (payrollItemId <= 0) return BadRequest("Payroll line is required.");
            return Ok(await _svc.GetDeductionsAsync(farmId, payrollItemId));
        }

        /// <summary>One row per line for a whole run: totals, and what the advances suggest.</summary>
        [HttpGet("run/{runId:int}")]
        public async Task<ActionResult<IEnumerable<GenericPayrollDeductionRunRow>>> GetForRun(
            int runId, [FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetRunDeductionsAsync(farmId, runId));

        /// <summary>
        /// Add or change a deduction. Unapproved runs only, and nothing here
        /// moves a loan balance -- a deduction is a plan until the payroll is
        /// approved (section 38).
        /// </summary>
        [HttpPost]
        public async Task<ActionResult<int>> Save([FromBody] GenericPayrollDeductionSaveRequest r)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(r.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.SaveDeductionAsync(r);
            return Ok(new { GenericPayrollItemDeductionId = id });
        }

        /// <summary>
        /// Draft deductions only. A posted one has a repayment behind it and is
        /// undone by reopening the payroll, not by deleting the row.
        /// </summary>
        [HttpDelete("{deductionId:int}")]
        public async Task<IActionResult> Delete(
            int deductionId, [FromQuery] string farmId, [FromQuery] string? deletedBy)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.DeleteDeductionAsync(deductionId, farmId, deletedBy);
            return NoContent();
        }
    }
}
