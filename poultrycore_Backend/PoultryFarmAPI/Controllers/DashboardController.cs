using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class DashboardController : ControllerBase
    {
        private readonly IDashboardService _dashboardService;
        private readonly IIamDataGuard _guard;

        public DashboardController(IDashboardService dashboardService, IIamDataGuard guard)
        {
            _dashboardService = dashboardService;
            _guard = guard;
        }

        /// <summary>
        /// Open to every member (eggs, feed and flocks are operational), but the
        /// money figures need poultry.dashboard-financials.view (test 20).
        /// </summary>
        [HttpGet("Summary")]
        public async Task<IActionResult> GetSummary(string farmId)
        {
            var result = await _dashboardService.GetSummaryAsync(farmId);
            if (result is not null && !await _guard.AllowsAsync(User, farmId, "poultry.dashboard-financials.view"))
            {
                result.SalesToday = 0;
                result.ExpensesToday = 0;
                result.SalesChart = new();
                result.ExpensesChart = new();
            }
            return Ok(result);
        }
    }

}
