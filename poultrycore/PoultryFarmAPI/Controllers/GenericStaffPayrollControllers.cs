// Generic Company Staff + Attendance + Payroll controllers.
// Convention matches the existing Generic controllers: route is
// api/generic-company/{farmId}/..., GenericFarmGuard.EnsureAsync gates every
// endpoint on (farm exists) AND (farm.Type == 'Generic'). Re-uses the guard
// defined in GenericSalesController.cs (internal static class in the same
// PoultryFarmAPIWeb.Controllers namespace).

using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // ====================================================================
    // Staff
    // ====================================================================
    [ApiController]
    [Route("api/generic-company/{farmId}/staff")]
    public class GenericStaffController : ControllerBase
    {
        private readonly IGenericStaffService _svc;
        private readonly IGenericCompanyService _companies;

        public GenericStaffController(IGenericStaffService svc, IGenericCompanyService companies)
        {
            _svc = svc;
            _companies = companies;
        }

        [HttpGet]
        public async Task<ActionResult<IEnumerable<GenericStaffModel>>> GetAll(
            string farmId, [FromQuery] string? role)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _svc.GetAllAsync(farmId, role));
        }

        [HttpGet("{id:int}")]
        public async Task<ActionResult<GenericStaffModel>> GetById(string farmId, int id)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            var m = await _svc.GetByIdAsync(id, farmId);
            return m is null ? NotFound() : Ok(m);
        }

        [HttpPost]
        public async Task<ActionResult<GenericStaffModel>> Create(string farmId, [FromBody] GenericStaffModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            m.FarmId = farmId;
            var id = await _svc.InsertAsync(m);
            var created = await _svc.GetByIdAsync(id, farmId);
            return CreatedAtAction(nameof(GetById), new { farmId, id }, created);
        }

        [HttpPut("{id:int}")]
        public async Task<IActionResult> Update(string farmId, int id, [FromBody] GenericStaffModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            m.FarmId = farmId;
            m.GenericStaffId = id;
            await _svc.UpdateAsync(m);
            return NoContent();
        }

        [HttpDelete("{id:int}")]
        public async Task<IActionResult> Delete(string farmId, int id)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            await _svc.DeleteAsync(id, farmId);
            return NoContent();
        }
    }

    // ====================================================================
    // Attendance
    // ====================================================================
    [ApiController]
    [Route("api/generic-company/{farmId}/staff-attendance")]
    public class GenericStaffAttendanceController : ControllerBase
    {
        private readonly IGenericStaffAttendanceService _svc;
        private readonly IGenericCompanyService _companies;

        public GenericStaffAttendanceController(
            IGenericStaffAttendanceService svc, IGenericCompanyService companies)
        {
            _svc = svc;
            _companies = companies;
        }

        [HttpGet]
        public async Task<ActionResult<IEnumerable<GenericStaffAttendanceModel>>> GetAll(
            string farmId,
            [FromQuery] int? staffId,
            [FromQuery] DateTime? fromDate,
            [FromQuery] DateTime? toDate)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _svc.GetAllAsync(farmId, staffId, fromDate, toDate));
        }

        [HttpPost]
        public async Task<ActionResult<GenericStaffAttendanceModel>> Upsert(
            string farmId,
            [FromBody] GenericStaffAttendanceUpsertRequest req,
            [FromQuery] string? createdBy)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            var m = await _svc.UpsertAsync(farmId, req, createdBy);
            return Ok(m);
        }

        [HttpDelete("{id:int}")]
        public async Task<IActionResult> Delete(string farmId, int id)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            await _svc.DeleteAsync(id, farmId);
            return NoContent();
        }
    }

    // ====================================================================
    // Payroll Runs + Items
    // ====================================================================
    [ApiController]
    [Route("api/generic-company/{farmId}/payroll-runs")]
    public class GenericPayrollController : ControllerBase
    {
        private readonly IGenericPayrollService _svc;
        private readonly IGenericCompanyService _companies;

        public GenericPayrollController(IGenericPayrollService svc, IGenericCompanyService companies)
        {
            _svc = svc;
            _companies = companies;
        }

        [HttpGet]
        public async Task<ActionResult<IEnumerable<GenericPayrollRunModel>>> GetAll(
            string farmId, [FromQuery] string? status)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _svc.GetRunsAsync(farmId, status));
        }

        [HttpGet("{id:int}")]
        public async Task<ActionResult<GenericPayrollRunModel>> GetById(string farmId, int id)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            var m = await _svc.GetRunAsync(id, farmId);
            return m is null ? NotFound() : Ok(m);
        }

        [HttpPost]
        public async Task<ActionResult<object>> Create(
            string farmId,
            [FromBody] GenericPayrollRunCreateRequest req,
            [FromQuery] string? createdBy)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            req.FarmId = farmId;
            var id = await _svc.CreateRunAsync(req, createdBy);
            return Ok(new { GenericPayrollRunId = id });
        }

        [HttpPut("{id:int}")]
        public async Task<IActionResult> Update(
            string farmId, int id, [FromBody] GenericPayrollRunUpdateRequest req)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            await _svc.UpdateRunAsync(id, farmId, req);
            return NoContent();
        }

        [HttpPost("{id:int}/items")]
        public async Task<ActionResult<GenericPayrollItemModel>> UpsertItem(
            string farmId, int id, [FromBody] GenericPayrollItemUpsertRequest req)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            var item = await _svc.UpsertItemAsync(id, farmId, req);
            return item is null ? StatusCode(500, "Item upsert returned no row.") : Ok(item);
        }

        [HttpDelete("items/{itemId:int}")]
        public async Task<IActionResult> DeleteItem(string farmId, int itemId)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            await _svc.DeleteItemAsync(itemId, farmId);
            return NoContent();
        }

        [HttpPost("{id:int}/approve")]
        public async Task<IActionResult> Approve(string farmId, int id, [FromQuery] string? approvedBy)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            await _svc.ApproveAsync(id, farmId, approvedBy);
            return NoContent();
        }

        [HttpPost("{id:int}/mark-paid")]
        public async Task<IActionResult> MarkPaid(
            string farmId, int id,
            [FromBody] GenericPayrollRunMarkPaidRequest? body,
            [FromQuery] string? paidBy)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            await _svc.MarkPaidAsync(id, farmId, paidBy, body?.PayDate);
            return NoContent();
        }

        [HttpPost("{id:int}/cancel")]
        public async Task<IActionResult> Cancel(
            string farmId, int id,
            [FromBody] GenericPayrollRunCancelRequest? body,
            [FromQuery] string? cancelledBy)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            await _svc.CancelAsync(id, farmId, cancelledBy, body?.Reason);
            return NoContent();
        }
    }
}
