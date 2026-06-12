using System.Threading.Tasks;
using PoultryFarmApp.Business;
using PoultryWeb.Models;
using System.Collections.Generic;
using Microsoft.AspNetCore.Mvc;
using PoultryWeb.Business;
using System.Diagnostics;

namespace PoultryWeb.Controllers
{
    public class DashboardController : Controller
    {
        private readonly IDashboardWebApiService _dashboardService;

        public DashboardController(IDashboardWebApiService dashboardService)
        {
            _dashboardService = dashboardService;
        }

        public async Task<IActionResult> Index()
        {
            var model = await _dashboardService.GetDashboardSummaryAsync();
            return View(model);
        }
    }

}
