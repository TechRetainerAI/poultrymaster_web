using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Helpers;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController][Authorize][Route("api/Hotel")]
    public class HotelEmployeeLoanController : ControllerBase
    {
        private readonly IHotelEmployeeLoanService _svc;
        public HotelEmployeeLoanController(IHotelEmployeeLoanService svc) { _svc = svc; }

        private string? UserId => User.FindFirst("UserId")?.Value ?? User.FindFirst("sub")?.Value;

        [HttpGet("employee-loans")]
        public async Task<IActionResult> GetAll([FromQuery] string farmId, [FromQuery] string? status, [FromQuery] int? staffId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.GetAllAsync(farmId, status, staffId));
        }

        [HttpGet("employee-loans/{id}")]
        public async Task<IActionResult> GetById(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            var m = await _svc.GetByIdAsync(id, farmId);
            return m == null ? NotFound() : Ok(m);
        }

        [HttpGet("employee-loans/summary")]
        public async Task<IActionResult> GetSummary([FromQuery] string farmId, [FromQuery] string? fromDate, [FromQuery] string? toDate)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            DateTime? from = string.IsNullOrEmpty(fromDate) ? null : DateTime.Parse(fromDate);
            DateTime? to = string.IsNullOrEmpty(toDate) ? null : DateTime.Parse(toDate);
            return Ok(await _svc.GetSummaryAsync(farmId, from, to));
        }

        [HttpPost("employee-loans")]
        public async Task<IActionResult> Create([FromBody] HotelEmployeeLoanCreateRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            try { var id = await _svc.CreateAsync(req, UserId); return Ok(new { hotelEmployeeLoanId = id }); }
            catch (Exception ex) { return BadRequest(ex.Message); }
        }

        [HttpPost("employee-loans/{id}/disburse")]
        public async Task<IActionResult> Disburse(int id, [FromBody] HotelEmployeeLoanDisburseRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            try
            {
                DateTime? date = string.IsNullOrEmpty(req.DisbursementDate) ? null : DateTime.Parse(req.DisbursementDate);
                await _svc.DisburseAsync(id, req.FarmId, req.HotelCashAccountId, date, req.Reference, UserId);
                return Ok();
            }
            catch (Exception ex) { return BadRequest(ex.Message); }
        }

        [HttpPost("employee-loans/{id}/cancel")]
        public async Task<IActionResult> Cancel(int id, [FromBody] HotelEmployeeLoanReasonRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            try { await _svc.CancelAsync(id, req.FarmId, req.Reason, UserId); return Ok(); }
            catch (Exception ex) { return BadRequest(ex.Message); }
        }

        [HttpPost("employee-loans/{id}/reverse")]
        public async Task<IActionResult> Reverse(int id, [FromBody] HotelEmployeeLoanReasonRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            try { await _svc.ReverseAsync(id, req.FarmId, req.Reason, UserId); return Ok(); }
            catch (Exception ex) { return BadRequest(ex.Message); }
        }

        [HttpGet("employee-loans/{id}/repayments")]
        public async Task<IActionResult> GetRepayments(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.GetRepaymentsAsync(id, farmId));
        }

        [HttpPost("employee-loan-repayments")]
        public async Task<IActionResult> RecordRepayment([FromBody] HotelEmployeeLoanRepaymentRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            try { var id = await _svc.RecordRepaymentAsync(req, UserId); return Ok(new { hotelEmployeeLoanRepaymentId = id }); }
            catch (Exception ex) { return BadRequest(ex.Message); }
        }

        [HttpPost("employee-loan-repayments/{id}/reverse")]
        public async Task<IActionResult> ReverseRepayment(int id, [FromBody] HotelEmployeeLoanReasonRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            try { await _svc.ReverseRepaymentAsync(id, req.FarmId, req.Reason, UserId); return Ok(); }
            catch (Exception ex) { return BadRequest(ex.Message); }
        }
    }
}
