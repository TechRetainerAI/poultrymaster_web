// Financial Activity — one endpoint returning the period's events, their
// position changes and the period totals together. Split endpoints were
// considered and rejected: the page always needs all three at once, and three
// round trips would let the summary and the rows be computed over slightly
// different data if anything were posted in between.

using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/Poultry/financial-activity")]
    public class PoultryFinancialActivityController : ControllerBase
    {
        private readonly IPoultryFinancialActivityService _svc;
        public PoultryFinancialActivityController(IPoultryFinancialActivityService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<FinancialActivityResponse>> Get(
            [FromQuery] string farmId,
            [FromQuery] DateTime? fromDate,
            [FromQuery] DateTime? toDate)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");

            // Both ends are whole days: the SQL works in dates and treats the end
            // as inclusive, so a caller passing one day gets that day rather than
            // nothing. Missing dates fall back to the current month, which is what
            // the page opens on.
            var today = DateTime.Today;
            var from = (fromDate ?? new DateTime(today.Year, today.Month, 1)).Date;
            var to = (toDate ?? today).Date;

            // An inverted range would silently report an empty period, which reads
            // as "nothing happened" rather than as a mistake. Swap it instead.
            if (to < from) (from, to) = (to, from);

            return Ok(await _svc.GetAsync(farmId, from, to));
        }
    }
}
