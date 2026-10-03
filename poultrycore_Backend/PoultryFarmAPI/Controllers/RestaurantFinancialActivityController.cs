// Restaurant Financial Activity (migration 335): /api/Restaurant/financial-activity.
// Poultry's endpoint (PoultryFinancialActivityController) with the Restaurant
// conventions: [Authorize] and the caller's JWT company must match farmId.

using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Helpers;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Authorize]
    [Route("api/Restaurant/financial-activity")]
    public class RestaurantFinancialActivityController : ControllerBase
    {
        private readonly IRestaurantFinancialActivityService _svc;
        public RestaurantFinancialActivityController(IRestaurantFinancialActivityService svc) => _svc = svc;

        [HttpGet]
        public async Task<IActionResult> Get([FromQuery] string farmId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest(new { message = "Company ID is required." });
            var deny = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (deny != null) return deny;
            // Whole days, inclusive; missing dates fall back to the current month; an inverted range is swapped.
            var today = DateTime.Today;
            var from = (fromDate ?? new DateTime(today.Year, today.Month, 1)).Date;
            var to = (toDate ?? today).Date;
            if (to < from) (from, to) = (to, from);
            return Ok(await _svc.GetAsync(farmId, from, to));
        }
    }
}
