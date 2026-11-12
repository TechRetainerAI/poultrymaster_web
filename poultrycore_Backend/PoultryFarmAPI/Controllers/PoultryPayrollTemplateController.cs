using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Filters;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // 428. Payroll templates: set the payroll up once, create each period's run from it.
    [ApiController]
    [Route("api/Poultry/payroll-templates")]
    [RequireCompanyType("Poultry")]
    public class PoultryPayrollTemplateController : ControllerBase
    {
        private readonly IPoultryPayrollTemplateService _svc;
        public PoultryPayrollTemplateController(IPoultryPayrollTemplateService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<PoultryPayrollTemplateModel>>> GetAll(
            [FromQuery] string farmId, [FromQuery] bool includeInactive = false)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetAllAsync(farmId, includeInactive));

        [HttpGet("{id:int}")]
        public async Task<ActionResult<PoultryPayrollTemplateModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var t = await _svc.GetAsync(id, farmId);
            return t is null ? NotFound() : Ok(t);
        }

        [HttpPost]
        public async Task<ActionResult<object>> Create([FromBody] PoultryPayrollTemplateSaveRequest req)
        {
            if (req is null || string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.SaveAsync(null, req);
            return Ok(new { PoultryPayrollTemplateId = id });
        }

        [HttpPut("{id:int}")]
        public async Task<ActionResult<object>> Update(int id, [FromBody] PoultryPayrollTemplateSaveRequest req)
        {
            if (req is null || string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required.");
            await _svc.SaveAsync(id, req);
            return Ok(new { PoultryPayrollTemplateId = id });
        }

        [HttpPost("{id:int}/active")]
        public async Task<IActionResult> SetActive(int id, [FromBody] PoultryPayrollTemplateSetActiveRequest req)
        {
            if (req is null || string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required.");
            await _svc.SetActiveAsync(id, req);
            return NoContent();
        }

        [HttpPost("{id:int}/create-run")]
        public async Task<ActionResult<object>> CreateRun(int id, [FromBody] PoultryPayrollTemplateCreateRunRequest req)
        {
            if (req is null || string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required.");
            if (req.PeriodStart > req.PeriodEnd) return BadRequest("Period start cannot be after period end.");
            var runId = await _svc.CreateRunAsync(id, req);
            return Ok(new { PoultryPayrollRunId = runId });
        }
    }
}
