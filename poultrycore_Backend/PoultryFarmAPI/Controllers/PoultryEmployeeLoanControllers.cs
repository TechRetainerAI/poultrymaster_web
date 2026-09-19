// Employee Loans & Advances (migrations 305/306) + structured payroll
// deductions. Same flat per-resource [Route] with farmId on the query string
// that the rest of the poultry finance controllers use.
//
// These endpoints are thin. Every financial rule is in the SQL functions, so a
// controller that "helpfully" pre-validated would only create a second place
// for the rules to be written down and a second place for them to drift.
//
// The AuditLogActionFilter is global, so every write here is audited without
// anything being wired up (spec section 79).

using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/Poultry/employee-loans")]
    public class PoultryEmployeeLoanController : ControllerBase
    {
        private readonly IPoultryEmployeeLoanService _svc;
        public PoultryEmployeeLoanController(IPoultryEmployeeLoanService svc) => _svc = svc;

        /// <summary>
        /// Server-side filtered and paged: a farm that has been running for
        /// years has more advances than a browser should hold (sections 70-72).
        /// </summary>
        [HttpGet]
        public async Task<ActionResult<PoultryEmployeeLoanPage>> GetAll(
            [FromQuery] string farmId,
            [FromQuery] int? staffId,
            [FromQuery] string? loanType,
            [FromQuery] string? status,
            [FromQuery] string? repaymentMethod,
            [FromQuery] DateTime? fromDate,
            [FromQuery] DateTime? toDate,
            [FromQuery] string? search,
            [FromQuery] int limit = 50,
            [FromQuery] int offset = 0)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            // A caller asking for everything gets a page, not everything.
            if (limit <= 0 || limit > 200) limit = 50;
            if (offset < 0) offset = 0;
            return Ok(await _svc.GetAllAsync(farmId, staffId, loanType, status, repaymentMethod,
                                             fromDate, toDate, search, limit, offset));
        }

        [HttpGet("summary")]
        public async Task<ActionResult<PoultryEmployeeLoanSummary>> Summary(
            [FromQuery] string farmId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetSummaryAsync(farmId, fromDate, toDate));

        /// <summary>
        /// The advances a payroll deduction may be applied to for one member of
        /// staff. Section 33: the page shows what this returns, and the posting
        /// function re-checks the same rules, so a hand-made id gets the same
        /// refusal the dropdown would have prevented.
        /// </summary>
        [HttpGet("eligible")]
        public async Task<ActionResult<IEnumerable<PoultryEmployeeLoanEligible>>> Eligible(
            [FromQuery] string farmId, [FromQuery] int staffId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            if (staffId <= 0) return BadRequest("Staff ID is required.");
            return Ok(await _svc.GetEligibleAsync(farmId, staffId));
        }

        [HttpGet("{id:int}")]
        public async Task<ActionResult<PoultryEmployeeLoanModel>> GetById(
            int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var m = await _svc.GetByIdAsync(id, farmId);
            return m is null ? NotFound() : Ok(m);
        }

        [HttpGet("{id:int}/repayments")]
        public async Task<ActionResult<IEnumerable<PoultryEmployeeLoanRepaymentModel>>> Repayments(
            int id, [FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetRepaymentsAsync(farmId, id));

        /// <summary>
        /// Creates the advance, and hands the money over too when
        /// DisburseNow is set. A Draft owes nothing and has no cash row;
        /// disbursement is what turns it into a claim on the worker.
        /// </summary>
        [HttpPost]
        public async Task<ActionResult<int>> Create([FromBody] PoultryEmployeeLoanCreateRequest r)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(r.FarmId)) return BadRequest("Company ID is required.");
            if (r.DisburseNow && (r.PoultryCashAccountId is null or <= 0))
                return BadRequest("Choose the cash account the money is coming out of.");
            var id = await _svc.CreateAsync(r);
            return Ok(new { PoultryEmployeeLoanId = id });
        }

        /// <summary>
        /// Terms only once the money has gone. The amount, the worker and the
        /// cash account are financial history after disbursement, and the SQL
        /// refuses to change them -- correcting a disbursed advance means
        /// reversing it and recording the right one.
        /// </summary>
        [HttpPut("{id:int}")]
        public async Task<IActionResult> Update(int id, [FromBody] PoultryEmployeeLoanUpdateRequest r)
        {
            if (string.IsNullOrWhiteSpace(r.FarmId)) return BadRequest("Company ID is required.");
            await _svc.UpdateAsync(id, r);
            return NoContent();
        }

        [HttpPost("{id:int}/disburse")]
        public async Task<IActionResult> Disburse(
            int id, [FromBody] PoultryEmployeeLoanDisburseRequest r)
        {
            if (string.IsNullOrWhiteSpace(r.FarmId)) return BadRequest("Company ID is required.");
            if (r.PoultryCashAccountId <= 0)
                return BadRequest("Choose the cash account the money is coming out of.");
            await _svc.DisburseAsync(id, r);
            return NoContent();
        }

        /// <summary>Draft only. A disbursed advance is reversed, not cancelled.</summary>
        [HttpPost("{id:int}/cancel")]
        public async Task<IActionResult> Cancel(int id, [FromBody] PoultryEmployeeLoanReasonRequest r)
        {
            if (string.IsNullOrWhiteSpace(r.FarmId)) return BadRequest("Company ID is required.");
            await _svc.CancelAsync(id, r);
            return NoContent();
        }

        /// <summary>
        /// Puts the money back and drops the claim. Refused while any repayment
        /// is still posted -- undoing the advance underneath its own repayments
        /// would leave repayments against something that never happened.
        /// </summary>
        [HttpPost("{id:int}/reverse")]
        public async Task<IActionResult> Reverse(int id, [FromBody] PoultryEmployeeLoanReasonRequest r)
        {
            if (string.IsNullOrWhiteSpace(r.FarmId)) return BadRequest("Company ID is required.");
            await _svc.ReverseAsync(id, r);
            return NoContent();
        }

        /// <summary>
        /// A repayment the worker actually made -- cash, MoMo, bank. Payroll
        /// deductions do not come through here: they are posted by approving
        /// the payroll run, which is also the only thing that can reverse them.
        /// </summary>
        [HttpPost("repayments")]
        public async Task<ActionResult<int>> RecordRepayment(
            [FromBody] PoultryEmployeeLoanRepaymentRequest r)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(r.FarmId)) return BadRequest("Company ID is required.");
            try
            {
                var id = await _svc.RecordRepaymentAsync(r);
                return Ok(new { PoultryEmployeeLoanRepaymentId = id });
            }
            catch (InvalidOperationException ex)
            {
                return BadRequest(ex.Message);
            }
        }

        [HttpPost("repayments/{repaymentId:int}/reverse")]
        public async Task<IActionResult> ReverseRepayment(
            int repaymentId, [FromBody] PoultryEmployeeLoanReasonRequest r)
        {
            if (string.IsNullOrWhiteSpace(r.FarmId)) return BadRequest("Company ID is required.");
            await _svc.ReverseRepaymentAsync(repaymentId, r);
            return NoContent();
        }
    }

    /// <summary>
    /// The detail behind a payroll line's Deductions figure (306).
    ///
    /// Separate controller because it is payroll's resource, not the advance's:
    /// a deduction belongs to a payslip and only sometimes points at a loan.
    /// </summary>
    [ApiController]
    [Route("api/Poultry/payroll-deductions")]
    public class PoultryPayrollDeductionController : ControllerBase
    {
        private readonly IPoultryEmployeeLoanService _svc;
        public PoultryPayrollDeductionController(IPoultryEmployeeLoanService svc) => _svc = svc;

        /// <summary>
        /// The breakdown for one payslip line. Includes the synthetic legacy row
        /// for any part of the total no structured row explains -- it comes back
        /// with a null id, which is how the UI knows it cannot be edited.
        /// The rows always add up to the line's Deductions figure.
        /// </summary>
        [HttpGet]
        public async Task<ActionResult<IEnumerable<PoultryPayrollDeductionModel>>> GetForItem(
            [FromQuery] string farmId, [FromQuery] int payrollItemId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            if (payrollItemId <= 0) return BadRequest("Payroll line is required.");
            return Ok(await _svc.GetDeductionsAsync(farmId, payrollItemId));
        }

        /// <summary>One row per line for a whole run: totals, and what the advances suggest.</summary>
        [HttpGet("run/{runId:int}")]
        public async Task<ActionResult<IEnumerable<PoultryPayrollDeductionRunRow>>> GetForRun(
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
        public async Task<ActionResult<int>> Save([FromBody] PoultryPayrollDeductionSaveRequest r)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(r.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.SaveDeductionAsync(r);
            return Ok(new { PoultryPayrollItemDeductionId = id });
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
