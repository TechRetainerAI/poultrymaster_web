using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/Hotel/profit-loss")]
    public class HotelProfitLossController : ControllerBase
    {
        private readonly IHotelProfitLossService _svc;
        public HotelProfitLossController(IHotelProfitLossService svc) => _svc = svc;

        private static (DateTime start, DateTime end) Range(DateTime? from, DateTime? to)
        {
            var today = DateTime.UtcNow.Date;
            var s = from?.Date ?? new DateTime(today.Year, today.Month, 1);
            var e = to?.Date ?? s.AddMonths(1).AddDays(-1);
            return e < s ? (e, s) : (s, e);
        }

        [HttpGet]
        public async Task<ActionResult<HotelProfitLossReport>> Get(
            [FromQuery] string farmId, [FromQuery] DateTime? startDate, [FromQuery] DateTime? endDate)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var (s, e) = Range(startDate, endDate);
            return Ok(await _svc.GetAsync(farmId, s, e));
        }

        [HttpGet("expenses")]
        public async Task<ActionResult<List<HotelPlExpenseRow>>> Expenses(
            [FromQuery] string farmId, [FromQuery] DateTime? startDate, [FromQuery] DateTime? endDate,
            [FromQuery] string? lineKey)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var (s, e) = Range(startDate, endDate);
            return Ok(await _svc.GetExpenseDetailAsync(farmId, s, e, lineKey));
        }

        [HttpGet("revenue")]
        public async Task<ActionResult<List<HotelPlRevenueRow>>> Revenue(
            [FromQuery] string farmId, [FromQuery] DateTime? startDate, [FromQuery] DateTime? endDate,
            [FromQuery] string? lineKey)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var (s, e) = Range(startDate, endDate);
            return Ok(await _svc.GetRevenueDetailAsync(farmId, s, e, lineKey));
        }
    }
}
