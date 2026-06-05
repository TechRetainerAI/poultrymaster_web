using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryWeb.Business.Generic;
using PoultryWeb.Models.Generic;

namespace PoultryWeb.Controllers
{
    [Authorize]
    public class GenericCustomersController : Controller
    {
        private readonly IGenericApiClient _api;
        public GenericCustomersController(IGenericApiClient api) => _api = api;

        public async Task<IActionResult> Index()
        {
            var rows = await _api.GetCustomersAsync();
            return View(rows);
        }

        public IActionResult Create() => View(new GenericCustomerVm());

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Create(GenericCustomerVm m)
        {
            if (!ModelState.IsValid) return View(m);
            var created = await _api.CreateCustomerAsync(m);
            if (created is null)
            {
                TempData["Error"] = "Could not create customer.";
                return View(m);
            }
            TempData["Success"] = $"Customer '{created.CustomerName}' created.";
            return RedirectToAction(nameof(Index));
        }
    }
}
