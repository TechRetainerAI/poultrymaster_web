// Generic Financial Activity (migration 419): /api/generic-company/{farmId}/financial-activity.
// Same pattern as Hotel (336) with Generic conventions.

using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Filters;
using PoultryFarmAPIWeb.Business;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/generic-company/{farmId}/financial-activity")]
    [RequireCompanyType("Generic")]
    public class GenericFinancialActivityController : ControllerBase
    {
        private readonly IGenericFinancialActivityService _svc;
        public GenericFinancialActivityController(IGenericFinancialActivityService svc) => _svc = svc;

        [HttpGet]
        public async Task<IActionResult> Get(string farmId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest(new { message = "Company ID is required." });
            var today = DateTime.Today;
            var from = (fromDate ?? new DateTime(today.Year, today.Month, 1)).Date;
            var to = (toDate ?? today).Date;
            if (to < from) (from, to) = (to, from);
            return Ok(await _svc.GetAsync(farmId, from, to));
        }
    }
}
