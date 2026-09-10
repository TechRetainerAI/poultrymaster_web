// The structured Poultry Profit & Loss and its drilldowns (migration 272).
//
// The report itself is ONE call: summary and statement lines together. The
// drilldowns are separate calls on purpose -- a period with ten thousand
// expenses should not ship all of them to draw four cards, and nobody opens
// every line.
//
// Every drilldown reads the same SQL function its line was built from, so a
// drilldown total can never disagree with the figure the user clicked.

using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/Poultry/profit-loss")]
    public class PoultryProfitLossController : ControllerBase
    {
        private readonly IPoultryProfitLossService _svc;
        public PoultryProfitLossController(IPoultryProfitLossService svc) => _svc = svc;

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
        public async Task<ActionResult<PoultryProfitLossReport>> Get(
            [FromQuery] string farmId, [FromQuery] DateTime? startDate, [FromQuery] DateTime? endDate)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var (s, e) = Range(startDate, endDate);
            return Ok(await _svc.GetAsync(farmId, s, e));
        }

        /// <summary>Any expense line. Null lineKey returns everything in profit.</summary>
        [HttpGet("expenses")]
        public async Task<ActionResult<List<PoultryProfitLossExpenseRow>>> Expenses(
            [FromQuery] string farmId, [FromQuery] DateTime? startDate, [FromQuery] DateTime? endDate,
            [FromQuery] string? lineKey)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var (s, e) = Range(startDate, endDate);
            return Ok(await _svc.GetExpenseDetailAsync(farmId, s, e, lineKey));
        }

        [HttpGet("revenue")]
        public async Task<ActionResult<List<PoultryProfitLossRevenueRow>>> Revenue(
            [FromQuery] string farmId, [FromQuery] DateTime? startDate, [FromQuery] DateTime? endDate,
            [FromQuery] string? lineKey)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var (s, e) = Range(startDate, endDate);
            return Ok(await _svc.GetRevenueDetailAsync(farmId, s, e, lineKey));
        }

        /// <summary>
        /// Feed or medication, with the recognition column. A period that spans a
        /// settings change legitimately holds both a purchase recognised at
        /// purchase and a consumption recognised at consumption; without that
        /// column the two read as double counting.
        /// </summary>
        [HttpGet("inventory")]
        public async Task<ActionResult<List<PoultryProfitLossInventoryRow>>> Inventory(
            [FromQuery] string farmId, [FromQuery] DateTime? startDate, [FromQuery] DateTime? endDate,
            [FromQuery] string lineKey = "Feed")
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var (s, e) = Range(startDate, endDate);
            return Ok(await _svc.GetInventoryDetailAsync(farmId, s, e, lineKey));
        }

        [HttpGet("depreciation")]
        public async Task<ActionResult<List<PoultryAssetDepreciationModel>>> Depreciation(
            [FromQuery] string farmId, [FromQuery] DateTime? startDate, [FromQuery] DateTime? endDate)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var (s, e) = Range(startDate, endDate);
            return Ok(await _svc.GetDepreciationDetailAsync(farmId, s, e));
        }

        /// <summary>
        /// Interest, fees, owner money and loan principal. Principal is returned
        /// under its own line key and is NOT a cost -- repaying what was borrowed
        /// is giving back money that was never income.
        /// </summary>
        [HttpGet("financing")]
        public async Task<ActionResult<List<PoultryProfitLossFinancingRow>>> Financing(
            [FromQuery] string farmId, [FromQuery] DateTime? startDate, [FromQuery] DateTime? endDate,
            [FromQuery] string? lineKey)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var (s, e) = Range(startDate, endDate);
            return Ok(await _svc.GetFinancingDetailAsync(farmId, s, e, lineKey));
        }

        [HttpGet("capital-investments")]
        public async Task<ActionResult<List<PoultryProfitLossCapitalRow>>> Capital(
            [FromQuery] string farmId, [FromQuery] DateTime? startDate, [FromQuery] DateTime? endDate)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var (s, e) = Range(startDate, endDate);
            return Ok(await _svc.GetCapitalDetailAsync(farmId, s, e));
        }
    }
}
