// Restaurant payroll and staff loans & advances (migration 326).
//
// Same conventions as RestaurantFinanceController: every action checks the
// caller's JWT company against farmId (query string), the acting user comes from
// the token, and business-rule refusals from the database come back as 400 with
// the database's own sentence (RestaurantBusinessRuleFilter).

using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Filters;
using PoultryFarmAPIWeb.Helpers;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Authorize]
    [RestaurantBusinessRuleFilter]
    [Route("api/Restaurant")]
    public class RestaurantPayrollController : ControllerBase
    {
        private readonly IRestaurantPayrollService _svc;
        public RestaurantPayrollController(IRestaurantPayrollService svc) => _svc = svc;

        private string Me => HotelAuthHelper.GetUserName(User);
        private IActionResult? Deny(string? farmId) => HotelAuthHelper.VerifyFarmOwnership(User, farmId);

        // ===== STAFF LOANS & ADVANCES =====

        [HttpGet("staff-loans")]
        public async Task<IActionResult> ListLoans([FromQuery] string farmId, [FromQuery] string? status, [FromQuery] int? staffId)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.ListLoansAsync(farmId, status, staffId)); }

        [HttpGet("staff-loans/summary")]
        public async Task<IActionResult> LoanSummary([FromQuery] string farmId, [FromQuery] DateTime? from, [FromQuery] DateTime? to)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.LoanSummaryAsync(farmId, from, to)); }

        /// <summary>A staff member's open loans, with the suggested payroll deduction for each.</summary>
        [HttpGet("staff-loans/eligible")]
        public async Task<IActionResult> Eligible([FromQuery] string farmId, [FromQuery] int staffId, [FromQuery] int? excludeLineId)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.EligibleAsync(farmId, staffId, excludeLineId)); }

        /// <summary>Per staff member: owed now, and advanced / repaid between the dates.</summary>
        [HttpGet("staff-loans/staff-report")]
        public async Task<IActionResult> StaffReport([FromQuery] string farmId, [FromQuery] DateTime? from, [FromQuery] DateTime? to)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.StaffReportAsync(farmId, from, to)); }

        /// <summary>Repayments of one loan (loanId) or of the whole restaurant, reversed ones included.</summary>
        [HttpGet("staff-loans/repayments")]
        public async Task<IActionResult> Repayments([FromQuery] string farmId, [FromQuery] int? loanId)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.LoanRepaymentsAsync(farmId, loanId)); }

        [HttpPost("staff-loans")]
        public async Task<IActionResult> CreateLoan([FromQuery] string farmId, [FromBody] RestaurantStaffLoanCreateRequest req)
        { var d = Deny(farmId); if (d != null) return d; return Ok(new { staffLoanId = await _svc.CreateLoanAsync(farmId, req, Me) }); }

        [HttpPut("staff-loans/{id:int}")]
        public async Task<IActionResult> UpdateLoan(int id, [FromQuery] string farmId, [FromBody] RestaurantStaffLoanUpdateRequest req)
        { var d = Deny(farmId); if (d != null) return d; await _svc.UpdateLoanAsync(farmId, id, req); return Ok(); }

        [HttpPost("staff-loans/{id:int}/disburse")]
        public async Task<IActionResult> Disburse(int id, [FromQuery] string farmId, [FromBody] RestaurantStaffLoanDisburseRequest req)
        { var d = Deny(farmId); if (d != null) return d; await _svc.DisburseLoanAsync(farmId, id, req, Me); return Ok(); }

        [HttpPost("staff-loans/{id:int}/cancel")]
        public async Task<IActionResult> CancelLoan(int id, [FromQuery] string farmId, [FromBody] RestaurantReverseRequest req)
        { var d = Deny(farmId); if (d != null) return d; await _svc.CancelLoanAsync(farmId, id, req.Reason, Me); return Ok(); }

        [HttpPost("staff-loans/{id:int}/reverse")]
        public async Task<IActionResult> ReverseLoan(int id, [FromQuery] string farmId, [FromBody] RestaurantReverseRequest req)
        { var d = Deny(farmId); if (d != null) return d; await _svc.ReverseLoanAsync(farmId, id, req.Reason, Me); return Ok(); }

        [HttpPost("staff-loans/{id:int}/repayments")]
        public async Task<IActionResult> Repay(int id, [FromQuery] string farmId, [FromBody] RestaurantStaffLoanRepayRequest req)
        {
            var d = Deny(farmId); if (d != null) return d;
            try { return Ok(new { repaymentId = await _svc.RepayLoanAsync(farmId, id, req, Me) }); }
            catch (InvalidOperationException ex) { return BadRequest(new { message = ex.Message }); }
        }

        [HttpPost("staff-loans/repayments/{repaymentId:int}/reverse")]
        public async Task<IActionResult> ReverseRepayment(int repaymentId, [FromQuery] string farmId, [FromBody] RestaurantReverseRequest req)
        { var d = Deny(farmId); if (d != null) return d; await _svc.ReverseRepaymentAsync(farmId, repaymentId, req.Reason, Me); return Ok(); }

        // ===== PAYROLL =====

        [HttpGet("payroll/runs")]
        public async Task<IActionResult> ListRuns([FromQuery] string farmId, [FromQuery] string? status)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.ListRunsAsync(farmId, status)); }

        [HttpGet("payroll/runs/{id:int}")]
        public async Task<IActionResult> GetRun(int id, [FromQuery] string farmId)
        {
            var d = Deny(farmId); if (d != null) return d;
            var run = await _svc.GetRunAsync(farmId, id);
            return run == null ? NotFound(new { message = "Payroll run not found." }) : Ok(run);
        }

        [HttpPost("payroll/runs")]
        public async Task<IActionResult> CreateRun([FromQuery] string farmId, [FromBody] RestaurantPayrollRunRequest req)
        { var d = Deny(farmId); if (d != null) return d; return Ok(new { payrollRunId = await _svc.CreateRunAsync(farmId, req, Me) }); }

        [HttpPut("payroll/runs/{id:int}")]
        public async Task<IActionResult> UpdateRun(int id, [FromQuery] string farmId, [FromBody] RestaurantPayrollRunRequest req)
        { var d = Deny(farmId); if (d != null) return d; await _svc.UpdateRunAsync(farmId, id, req); return Ok(); }

        [HttpDelete("payroll/runs/{id:int}")]
        public async Task<IActionResult> DeleteRun(int id, [FromQuery] string farmId)
        { var d = Deny(farmId); if (d != null) return d; await _svc.DeleteRunAsync(farmId, id); return Ok(); }

        /// <summary>Add or update one staff member's line, with its staff loan deductions.</summary>
        [HttpPost("payroll/runs/{id:int}/lines")]
        public async Task<IActionResult> SaveLine(int id, [FromQuery] string farmId, [FromBody] RestaurantPayrollLineRequest req)
        { var d = Deny(farmId); if (d != null) return d; return Ok(new { payrollLineId = await _svc.SaveLineAsync(farmId, id, req, Me) }); }

        [HttpDelete("payroll/lines/{lineId:int}")]
        public async Task<IActionResult> DeleteLine(int lineId, [FromQuery] string farmId)
        { var d = Deny(farmId); if (d != null) return d; await _svc.DeleteLineAsync(farmId, lineId); return Ok(); }

        /// <summary>Every active staff member not yet on the run, at base pay, with suggested loan deductions.</summary>
        [HttpPost("payroll/runs/{id:int}/add-all-staff")]
        public async Task<IActionResult> AddAllStaff(int id, [FromQuery] string farmId)
        { var d = Deny(farmId); if (d != null) return d; return Ok(new { added = await _svc.AddAllStaffAsync(farmId, id, Me) }); }

        [HttpPost("payroll/runs/{id:int}/approve")]
        public async Task<IActionResult> Approve(int id, [FromQuery] string farmId)
        { var d = Deny(farmId); if (d != null) return d; return Ok(new { loanRepaymentsPosted = await _svc.ApproveRunAsync(farmId, id, Me) }); }

        [HttpPost("payroll/runs/{id:int}/reopen")]
        public async Task<IActionResult> Reopen(int id, [FromQuery] string farmId, [FromBody] RestaurantReverseRequest req)
        { var d = Deny(farmId); if (d != null) return d; return Ok(new { repaymentsReversed = await _svc.ReopenRunAsync(farmId, id, req.Reason, Me) }); }

        [HttpPost("payroll/runs/{id:int}/cancel")]
        public async Task<IActionResult> Cancel(int id, [FromQuery] string farmId, [FromBody] RestaurantReverseRequest req)
        { var d = Deny(farmId); if (d != null) return d; return Ok(new { repaymentsReversed = await _svc.CancelRunAsync(farmId, id, req.Reason, Me) }); }

        [HttpPost("payroll/runs/{id:int}/mark-paid")]
        public async Task<IActionResult> MarkPaid(int id, [FromQuery] string farmId, [FromBody] RestaurantPayrollPayRequest req)
        { var d = Deny(farmId); if (d != null) return d; await _svc.MarkPaidAsync(farmId, id, req, Me); return Ok(); }

        [HttpGet("payroll/report")]
        public async Task<IActionResult> Report([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.PayrollReportAsync(farmId, from, to)); }
    }
}
