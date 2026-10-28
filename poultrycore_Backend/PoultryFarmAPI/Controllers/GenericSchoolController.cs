using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Filters;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // School-specific endpoints: classes and academic terms (migration 366).
    // Available to all Generic companies but only useful for schools.

    [ApiController]
    [Route("api/generic-company/{farmId}/classes")]
    [RequireCompanyType("Generic")]
    public class GenericClassController : ControllerBase
    {
        private readonly IGenericSchoolService _svc;
        private readonly IGenericCompanyService _companies;

        public GenericClassController(IGenericSchoolService svc, IGenericCompanyService companies)
        {
            _svc = svc;
            _companies = companies;
        }

        [HttpGet]
        public async Task<ActionResult<IEnumerable<GenericClassModel>>> GetAll(string farmId)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _svc.GetClassesAsync(farmId));
        }

        [HttpPost]
        public async Task<ActionResult> Upsert(string farmId, [FromBody] GenericClassModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            m.FarmId = farmId;
            var id = await _svc.UpsertClassAsync(farmId, m);
            return Ok(new { genericClassId = id });
        }

        [HttpDelete("{id:int}")]
        public async Task<IActionResult> Delete(string farmId, int id)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            await _svc.DeleteClassAsync(id, farmId);
            return NoContent();
        }
    }

    [ApiController]
    [Route("api/generic-company/{farmId}/academic-terms")]
    [RequireCompanyType("Generic")]
    public class GenericAcademicTermController : ControllerBase
    {
        private readonly IGenericSchoolService _svc;
        private readonly IGenericCompanyService _companies;

        public GenericAcademicTermController(IGenericSchoolService svc, IGenericCompanyService companies)
        {
            _svc = svc;
            _companies = companies;
        }

        [HttpGet]
        public async Task<ActionResult<IEnumerable<GenericAcademicTermModel>>> GetAll(string farmId)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _svc.GetTermsAsync(farmId));
        }

        [HttpPost]
        public async Task<ActionResult> Upsert(string farmId, [FromBody] GenericAcademicTermModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            m.FarmId = farmId;
            var id = await _svc.UpsertTermAsync(farmId, m);
            return Ok(new { genericAcademicTermId = id });
        }

        [HttpDelete("{id:int}")]
        public async Task<IActionResult> Delete(string farmId, int id)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            await _svc.DeleteTermAsync(id, farmId);
            return NoContent();
        }
    }

    // Student/Customer Attendance (migration 367)
    [ApiController]
    [Route("api/generic-company/{farmId}/customer-attendance")]
    [RequireCompanyType("Generic")]
    public class GenericCustomerAttendanceController : ControllerBase
    {
        private readonly IGenericSchoolService _svc;
        private readonly IGenericCompanyService _companies;

        public GenericCustomerAttendanceController(IGenericSchoolService svc, IGenericCompanyService companies)
        {
            _svc = svc;
            _companies = companies;
        }

        [HttpGet]
        public async Task<ActionResult<IEnumerable<GenericCustomerAttendanceModel>>> GetAll(
            string farmId, [FromQuery] string? date = null, [FromQuery] int? classId = null)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            DateTime? d = date != null ? DateTime.Parse(date) : null;
            return Ok(await _svc.GetCustomerAttendanceAsync(farmId, d, classId));
        }

        [HttpPost]
        public async Task<ActionResult> Upsert(string farmId, [FromBody] GenericCustomerAttendanceModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            m.FarmId = farmId;
            var id = await _svc.UpsertCustomerAttendanceAsync(farmId, m);
            return Ok(new { genericCustomerAttendanceId = id });
        }

        [HttpDelete("{id:int}")]
        public async Task<IActionResult> Delete(string farmId, int id)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            await _svc.DeleteCustomerAttendanceAsync(id, farmId);
            return NoContent();
        }
    }
}
