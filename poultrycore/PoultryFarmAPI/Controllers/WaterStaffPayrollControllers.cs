using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // ====================================================================
    // Staff
    // ====================================================================
    [ApiController]
    [Route("api/Water/staff")]
    public class WaterStaffController : ControllerBase
    {
        private readonly IWaterStaffService _svc;
        public WaterStaffController(IWaterStaffService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<WaterStaffModel>>> GetAll(
            [FromQuery] string farmId, [FromQuery] string? role)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetAllAsync(farmId, role));

        [HttpGet("{id:int}")]
        public async Task<ActionResult<WaterStaffModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var m = await _svc.GetByIdAsync(id, farmId);
            return m is null ? NotFound() : Ok(m);
        }

        [HttpPost]
        public async Task<ActionResult<WaterStaffModel>> Create([FromBody] WaterStaffModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.InsertAsync(m);
            var created = await _svc.GetByIdAsync(id, m.FarmId);
            return CreatedAtAction(nameof(GetById), new { id, farmId = m.FarmId }, created);
        }

        [HttpPut("{id:int}")]
        public async Task<IActionResult> Update(int id, [FromBody] WaterStaffModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            m.WaterStaffId = id;
            await _svc.UpdateAsync(m);
            return NoContent();
        }

        [HttpDelete("{id:int}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.DeleteAsync(id, farmId);
            return NoContent();
        }
    }

    // ====================================================================
    // Attendance
    // ====================================================================
    [ApiController]
    [Route("api/Water/staff-attendance")]
    public class WaterStaffAttendanceController : ControllerBase
    {
        private readonly IWaterStaffAttendanceService _svc;
        public WaterStaffAttendanceController(IWaterStaffAttendanceService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<WaterStaffAttendanceModel>>> GetAll(
            [FromQuery] string farmId,
            [FromQuery] int? staffId,
            [FromQuery] DateTime? fromDate,
            [FromQuery] DateTime? toDate)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetAllAsync(farmId, staffId, fromDate, toDate));

        [HttpPost]
        public async Task<ActionResult<WaterStaffAttendanceModel>> Upsert(
            [FromQuery] string farmId, [FromQuery] string? createdBy,
            [FromBody] WaterStaffAttendanceUpsertRequest req)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var m = await _svc.UpsertAsync(farmId, req, createdBy);
            return Ok(m);
        }

        [HttpDelete("{id:int}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.DeleteAsync(id, farmId);
            return NoContent();
        }
    }

    // ====================================================================
    // Payroll Runs + Items
    // ====================================================================
    [ApiController]
    [Route("api/Water/payroll-runs")]
    public class WaterPayrollController : ControllerBase
    {
        private readonly IWaterPayrollService _svc;
        public WaterPayrollController(IWaterPayrollService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<WaterPayrollRunModel>>> GetAll(
            [FromQuery] string farmId, [FromQuery] string? status)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetRunsAsync(farmId, status));

        [HttpGet("{id:int}")]
        public async Task<ActionResult<WaterPayrollRunModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var m = await _svc.GetRunAsync(id, farmId);
            return m is null ? NotFound() : Ok(m);
        }

        [HttpPost]
        public async Task<ActionResult<object>> Create(
            [FromBody] WaterPayrollRunCreateRequest req, [FromQuery] string? createdBy)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.CreateRunAsync(req, createdBy);
            return Ok(new { WaterPayrollRunId = id });
        }

        [HttpPost("{id:int}/items")]
        public async Task<ActionResult<WaterPayrollItemModel>> UpsertItem(
            int id, [FromQuery] string farmId, [FromBody] WaterPayrollItemUpsertRequest req)
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
            [FromBody] WaterPayrollRunMarkPaidRequest? body)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.MarkPaidAsync(id, farmId, paidBy, body?.PayDate);
            return NoContent();
        }

        [HttpPost("{id:int}/cancel")]
        public async Task<IActionResult> Cancel(
            int id, [FromQuery] string farmId, [FromQuery] string? cancelledBy,
            [FromBody] WaterPayrollRunCancelRequest? body)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.CancelAsync(id, farmId, cancelledBy, body?.Reason);
            return NoContent();
        }

        // Migration 080 — flip Approved/Paid → Reopened, reverse linked expense + cash.
        [HttpPost("{id:int}/unapprove")]
        public async Task<IActionResult> Unapprove(
            int id, [FromQuery] string farmId, [FromQuery] string? reopenedBy,
            [FromBody] WaterPayrollRunCancelRequest? body)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.UnapproveAsync(id, farmId, reopenedBy, body?.Reason);
            return NoContent();
        }

        // Migration 080 — hard delete a Draft/Pending/Reopened run.
        [HttpDelete("{id:int}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string farmId, [FromQuery] string? deletedBy)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.DeleteRunAsync(id, farmId, deletedBy);
            return NoContent();
        }

        // Migration 082 — full Payroll Run Details with YTD totals + linked expense.
        // One round-trip; the page renders all four sections from this payload.
        [HttpGet("{id:int}/details")]
        public async Task<ActionResult<WaterPayrollRunDetailsModel>> GetDetails(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var details = await _svc.GetDetailsWithYtdAsync(id, farmId);
            return details is null ? NotFound() : Ok(details);
        }
    }
}
