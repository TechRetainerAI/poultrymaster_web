// The structured water Profit & Loss and its drilldowns (migration 316).
//
// The report itself is ONE call: summary and statement lines together. The
// drilldowns are separate calls on purpose -- a period with ten thousand
// expenses should not ship all of them to draw four cards, and nobody opens
// every line.
//
// Every drilldown reads the same SQL function its line was built from, so a
// drilldown total can never disagree with the figure the user clicked.
//
// NOT api/Water/reports/profit-loss. The route is api/Water/profit-loss because
// the statement is now served at two places -- the Reports catalogue and the
// Money page -- and neither owns it.

using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/Water/profit-loss")]
    public class WaterProfitLossController : ControllerBase
    {
        private readonly IWaterProfitLossService _svc;
        public WaterProfitLossController(IWaterProfitLossService svc) => _svc = svc;

        /// <summary>
        /// Defaults to the current month, which is what an owner opening the page
        /// almost always wants and what every other report here defaults to.
        /// </summary>
        private static (DateTime start, DateTime end) Range(DateTime? from, DateTime? to)
        {
            var today = DateTime.UtcNow.Date;
            var s = from?.Date ?? new DateTime(today.Year, today.Month, 1);
            var e = to?.Date ?? s.AddMonths(1).AddDays(-1);
            return e < s ? (e, s) : (s, e);
        }

        [HttpGet]
        public async Task<ActionResult<WaterProfitLossReport>> Get(
            [FromQuery] string farmId, [FromQuery] DateTime? startDate, [FromQuery] DateTime? endDate)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var (s, e) = Range(startDate, endDate);
            try { return Ok(await _svc.GetReportAsync(farmId, s, e)); }
            catch (Npgsql.PostgresException ex) { return BadRequest(ex.MessageText); }
        }

        /// <summary>
        /// The rows behind one figure.
        ///
        /// `kind` names the drilldown (revenue, directcost, expense, loss,
        /// financing, capital, depreciation) and `lineKey` narrows it to a single
        /// line. An unknown kind is a 400, not a 500: it arrives from a query
        /// string and the service refuses it by allowlist rather than letting it
        /// anywhere near a function name.
        /// </summary>
        [HttpGet("detail")]
        public async Task<ActionResult<List<WaterPlDetailRow>>> Detail(
            [FromQuery] string farmId, [FromQuery] string kind,
            [FromQuery] string? lineKey,
            [FromQuery] DateTime? startDate, [FromQuery] DateTime? endDate)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            if (string.IsNullOrWhiteSpace(kind)) return BadRequest("A drilldown kind is required.");
            var (s, e) = Range(startDate, endDate);
            try { return Ok(await _svc.GetDetailAsync(farmId, s, e, kind, lineKey)); }
            catch (ArgumentException ex) { return BadRequest(ex.Message); }
            catch (Npgsql.PostgresException ex) { return BadRequest(ex.MessageText); }
        }
    }
}
