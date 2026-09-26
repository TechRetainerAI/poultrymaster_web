using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Filters;
using PoultryFarmAPIWeb.Helpers;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // Business-rule refusals from the database ("the repayment is more than Ama
    // still owes") come back as 400 with that sentence, via HotelBusinessRuleFilter.
    [ApiController][Authorize][Route("api/Hotel")][HotelBusinessRuleFilter]
    public class HotelEmployeeLoanController : ControllerBase
    {
        private readonly IHotelEmployeeLoanService _svc;
        public HotelEmployeeLoanController(IHotelEmployeeLoanService svc) { _svc = svc; }

        // Who did it, in the same form the payroll and finance controllers record.
        private string By => HotelAuthHelper.GetUserName(User);

        private static DateTime? ParseDate(string? s) => string.IsNullOrEmpty(s) ? null : DateTime.Parse(s);

        [HttpGet("employee-loans")]
        public async Task<IActionResult> GetAll([FromQuery] string farmId, [FromQuery] string? status, [FromQuery] int? staffId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.GetAllAsync(farmId, status, staffId));
        }

        [HttpGet("employee-loans/summary")]
        public async Task<IActionResult> GetSummary([FromQuery] string farmId, [FromQuery] string? fromDate, [FromQuery] string? toDate)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.GetSummaryAsync(farmId, ParseDate(fromDate), ParseDate(toDate)));
        }

        /// <summary>A staff member's open loans, with the suggested payroll deduction for each.</summary>
        [HttpGet("employee-loans/eligible")]
        public async Task<IActionResult> GetEligible([FromQuery] string farmId, [FromQuery] int staffId, [FromQuery] int? excludeItemId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.GetEligibleAsync(farmId, staffId, excludeItemId));
        }

        /// <summary>Per staff member: owed now, and advanced / repaid in the period.</summary>
        [HttpGet("employee-loans/staff-report")]
        public async Task<IActionResult> GetStaffReport([FromQuery] string farmId, [FromQuery] string? fromDate, [FromQuery] string? toDate)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            // The end date is inclusive: a repayment on the last day counts.
            var to = ParseDate(toDate);
            return Ok(await _svc.GetStaffReportAsync(farmId, ParseDate(fromDate), to?.Date.AddDays(1).AddTicks(-1)));
        }

        [HttpGet("employee-loans/{id:int}")]
        public async Task<IActionResult> GetById(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            var m = await _svc.GetByIdAsync(id, farmId);
            return m == null ? NotFound(new { message = "Loan not found." }) : Ok(m);
        }

        [HttpPost("employee-loans")]
        public async Task<IActionResult> Create([FromBody] HotelEmployeeLoanCreateRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            var id = await _svc.CreateAsync(req, By);
            return Ok(new { hotelEmployeeLoanId = id });
        }

        [HttpPut("employee-loans/{id:int}")]
        public async Task<IActionResult> Update(int id, [FromBody] HotelEmployeeLoanUpdateRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            await _svc.UpdateAsync(id, req, By);
            return Ok();
        }

        [HttpPost("employee-loans/{id:int}/disburse")]
        public async Task<IActionResult> Disburse(int id, [FromBody] HotelEmployeeLoanDisburseRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            await _svc.DisburseAsync(id, req.FarmId, req.HotelCashAccountId, ParseDate(req.DisbursementDate), req.Reference, By);
            return Ok();
        }

        [HttpPost("employee-loans/{id:int}/cancel")]
        public async Task<IActionResult> Cancel(int id, [FromBody] HotelEmployeeLoanReasonRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            await _svc.CancelAsync(id, req.FarmId, req.Reason, By);
            return Ok();
        }

        [HttpPost("employee-loans/{id:int}/reverse")]
        public async Task<IActionResult> Reverse(int id, [FromBody] HotelEmployeeLoanReasonRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            await _svc.ReverseAsync(id, req.FarmId, req.Reason, By);
            return Ok();
        }

        [HttpGet("employee-loans/{id:int}/repayments")]
        public async Task<IActionResult> GetRepayments(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.GetRepaymentsAsync(id, farmId));
        }

        /// <summary>Every repayment of the hotel, including reversed ones.</summary>
        [HttpGet("employee-loan-repayments")]
        public async Task<IActionResult> GetAllRepayments([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.GetRepaymentsAsync(null, farmId));
        }

        [HttpPost("employee-loan-repayments")]
        public async Task<IActionResult> RecordRepayment([FromBody] HotelEmployeeLoanRepaymentRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            try
            {
                var id = await _svc.RecordRepaymentAsync(req, By);
                return Ok(new { hotelEmployeeLoanRepaymentId = id });
            }
            catch (InvalidOperationException ex) { return BadRequest(new { message = ex.Message }); }
        }

        [HttpPost("employee-loan-repayments/{id:int}/reverse")]
        public async Task<IActionResult> ReverseRepayment(int id, [FromBody] HotelEmployeeLoanReasonRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            await _svc.ReverseRepaymentAsync(id, req.FarmId, req.Reason, By);
            return Ok();
        }
    }
}
