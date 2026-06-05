using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryWeb.Business.Generic;

namespace PoultryWeb.Controllers
{
    [Authorize]
    public class GenericCashAccountsController : Controller
    {
        private readonly IGenericApiClient _api;
        public GenericCashAccountsController(IGenericApiClient api) => _api = api;

        public async Task<IActionResult> Index()
        {
            var rows = await _api.GetCashAccountsAsync();
            return View(rows);
        }
    }
}
