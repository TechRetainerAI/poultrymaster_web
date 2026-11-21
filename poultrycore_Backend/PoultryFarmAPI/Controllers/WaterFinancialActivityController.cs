// Water Financial Activity (migration 461): GET api/Water/financial-activity?farmId=&fromDate=&toDate=
// One timeline of every money and profit event; cash from Cash Flow, profit from
// the P&L itemisation (316), so it always agrees with both. Read-only.

using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Filters;
using PoultryFarmAPIWeb.Business;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/Water/financial-activity")]
    [RequireCompanyType("Water")]
    public class WaterFinancialActivityController : ControllerBase
    {
        private readonly IWaterFinancialActivityService _svc;
        public WaterFinancialActivityController(IWaterFinancialActivityService svc) => _svc = svc;

        [HttpGet]
        public async Task<IActionResult> Get([FromQuery] string farmId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
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
