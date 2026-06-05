using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryWeb.Business.Generic;
using PoultryWeb.Models.Generic;

namespace PoultryWeb.Controllers
{
    [Authorize]
    public class GenericSuppliersController : Controller
    {
        private readonly IGenericApiClient _api;
        public GenericSuppliersController(IGenericApiClient api) => _api = api;

        public async Task<IActionResult> Index()
        {
            var rows = await _api.GetSuppliersAsync();
            return View(rows);
        }

        public IActionResult Create() => View(new GenericSupplierVm());

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Create(GenericSupplierVm m)
        {
            if (!ModelState.IsValid) return View(m);
            var created = await _api.CreateSupplierAsync(m);
            if (created is null)
            {
                TempData["Error"] = "Could not create supplier.";
                return View(m);
            }
            TempData["Success"] = $"Supplier '{created.SupplierName}' created.";
            return RedirectToAction(nameof(Index));
        }
    }
}
