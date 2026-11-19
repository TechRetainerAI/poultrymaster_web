// Employee Credit (migration 441): money the farm is holding for staff.
// Reads are open to anyone with the page; every write -- adding credit by hand,
// paying it out, reversing -- is owner/admin only (SetupAdminOnly), because a
// typed-in credit or payout moves money and payroll cost.
//
// Payroll savings are added on the payroll run itself (deduction type
// 'EmployeeCredit'), not here.

using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Filters;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/Generic/employee-credit")]
    [RequireCompanyType("Generic")]
    public class GenericEmployeeCreditController : ControllerBase
    {
        private readonly IGenericEmployeeCreditService _svc;
        public GenericEmployeeCreditController(IGenericEmployeeCreditService svc) => _svc = svc;

        private string? CallerId(string? fallback) =>
            User?.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value ?? fallback;

        /// <summary>One row per member of staff who has, or had, credit.</summary>
        [HttpGet("balances")]
        public async Task<ActionResult<IEnumerable<GenericEmployeeCreditBalance>>> Balances([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetBalancesAsync(farmId));

        /// <summary>The statement: every entry, newest first, with a running balance.</summary>
        [HttpGet("entries")]
        public async Task<ActionResult<IEnumerable<GenericEmployeeCreditEntry>>> Entries(
            [FromQuery] string farmId, [FromQuery] int? staffId)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetEntriesAsync(farmId, staffId));

        /// <summary>What the farm is holding for staff in total -- shown beside cash.</summary>
        [HttpGet("total")]
        public async Task<ActionResult<GenericEmployeeCreditTotal>> Total([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetTotalAsync(farmId));

        /// <summary>Opening balance, money handed in, or wages owed outside payroll.</summary>
        [HttpPost]
        [SetupAdminOnly]
        public async Task<ActionResult> Add([FromBody] GenericEmployeeCreditAddRequest r)
        {
            if (r is null || string.IsNullOrWhiteSpace(r.FarmId)) return BadRequest("Company ID is required.");
            if (r.GenericStaffId <= 0) return BadRequest("Choose the member of staff.");
            r.CreatedBy = CallerId(r.CreatedBy);
            var id = await _svc.AddAsync(r);
            return Ok(new { GenericEmployeeCreditId = id });
        }

        /// <summary>Hand money over. Cash out, no expense.</summary>
        [HttpPost("payout")]
        [SetupAdminOnly]
        public async Task<ActionResult> Payout([FromBody] GenericEmployeeCreditPayoutRequest r)
        {
            if (r is null || string.IsNullOrWhiteSpace(r.FarmId)) return BadRequest("Company ID is required.");
            if (r.GenericStaffId <= 0) return BadRequest("Choose the member of staff.");
            if (r.GenericCashAccountId <= 0) return BadRequest("Choose the cash account the money is paid from.");
            r.CreatedBy = CallerId(r.CreatedBy);
            var id = await _svc.PayoutAsync(r);
            return Ok(new { GenericEmployeeCreditId = id });
        }

        /// <summary>Append-only correction. Payroll savings are undone by reopening the payroll.</summary>
        [HttpPost("{id:int}/reverse")]
        [SetupAdminOnly]
        public async Task<IActionResult> Reverse(int id, [FromBody] GenericEmployeeCreditReverseRequest r)
        {
            if (r is null || string.IsNullOrWhiteSpace(r.FarmId)) return BadRequest("Company ID is required.");
            if (string.IsNullOrWhiteSpace(r.Reason)) return BadRequest("Give a reason for the reversal.");
            r.ActionBy = CallerId(r.ActionBy);
            await _svc.ReverseAsync(id, r);
            return NoContent();
        }
    }
}
