using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // ====================================================================
    // Staff
    // ====================================================================
    [ApiController]
    [Route("api/Poultry/staff")]
    public class PoultryStaffController : ControllerBase
    {
        private readonly IPoultryStaffService _svc;
        public PoultryStaffController(IPoultryStaffService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<PoultryStaffModel>>> GetAll(
            [FromQuery] string farmId, [FromQuery] string? role)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetAllAsync(farmId, role));

        [HttpGet("{id:int}")]
        public async Task<ActionResult<PoultryStaffModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var m = await _svc.GetByIdAsync(id, farmId);
            return m is null ? NotFound() : Ok(m);
        }

        [HttpPost]
        public async Task<ActionResult<PoultryStaffModel>> Create([FromBody] PoultryStaffModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.InsertAsync(m);
            var created = await _svc.GetByIdAsync(id, m.FarmId);
            return CreatedAtAction(nameof(GetById), new { id, farmId = m.FarmId }, created);
        }

        [HttpPut("{id:int}")]
        public async Task<IActionResult> Update(int id, [FromBody] PoultryStaffModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            m.PoultryStaffId = id;
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
    [Route("api/Poultry/staff-attendance")]
    public class PoultryStaffAttendanceController : ControllerBase
    {
        private readonly IPoultryStaffAttendanceService _svc;
        public PoultryStaffAttendanceController(IPoultryStaffAttendanceService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<PoultryStaffAttendanceModel>>> GetAll(
            [FromQuery] string farmId,
            [FromQuery] int? staffId,
            [FromQuery] DateTime? fromDate,
            [FromQuery] DateTime? toDate)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetAllAsync(farmId, staffId, fromDate, toDate));

        [HttpPost]
        public async Task<ActionResult<PoultryStaffAttendanceModel>> Upsert(
            [FromQuery] string farmId, [FromQuery] string? createdBy,
            [FromBody] PoultryStaffAttendanceUpsertRequest req)
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
    [Route("api/Poultry/payroll-runs")]
    public class PoultryPayrollController : ControllerBase
    {
        private readonly IPoultryPayrollService _svc;
        public PoultryPayrollController(IPoultryPayrollService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<PoultryPayrollRunModel>>> GetAll(
            [FromQuery] string farmId, [FromQuery] string? status)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetRunsAsync(farmId, status));

        [HttpGet("{id:int}")]
        public async Task<ActionResult<PoultryPayrollRunModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var m = await _svc.GetRunAsync(id, farmId);
            return m is null ? NotFound() : Ok(m);
        }

        [HttpPost]
        public async Task<ActionResult<object>> Create(
            [FromBody] PoultryPayrollRunCreateRequest req, [FromQuery] string? createdBy)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.CreateRunAsync(req, createdBy);
            return Ok(new { PoultryPayrollRunId = id });
        }

        [HttpPost("{id:int}/items")]
        public async Task<ActionResult<PoultryPayrollItemModel>> UpsertItem(
            int id, [FromQuery] string farmId, [FromBody] PoultryPayrollItemUpsertRequest req)
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
            [FromBody] PoultryPayrollRunMarkPaidRequest? body)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.MarkPaidAsync(id, farmId, paidBy, body?.PayDate);
            return NoContent();
        }

        [HttpPost("{id:int}/cancel")]
        public async Task<IActionResult> Cancel(
            int id, [FromQuery] string farmId, [FromQuery] string? cancelledBy,
            [FromBody] PoultryPayrollRunCancelRequest? body)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.CancelAsync(id, farmId, cancelledBy, body?.Reason);
            return NoContent();
        }

        [HttpPost("{id:int}/unapprove")]
        public async Task<IActionResult> Unapprove(
            int id, [FromQuery] string farmId, [FromQuery] string? reopenedBy,
            [FromBody] PoultryPayrollRunCancelRequest? body)
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
        public async Task<ActionResult<PoultryPayrollRunDetailsModel>> GetDetails(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var details = await _svc.GetDetailsWithYtdAsync(id, farmId);
            return details is null ? NotFound() : Ok(details);
        }
    }
}
