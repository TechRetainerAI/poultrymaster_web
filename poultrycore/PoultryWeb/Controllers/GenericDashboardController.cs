using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryWeb.Business.Generic;

namespace PoultryWeb.Controllers
{
    [Authorize]
    public class GenericDashboardController : Controller
    {
        private readonly IGenericApiClient _api;
        public GenericDashboardController(IGenericApiClient api) => _api = api;

        public async Task<IActionResult> Index()
        {
            var model = await _api.GetDashboardAsync();
            return View(model);
        }
    }
}
