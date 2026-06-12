using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryWeb.Business.Generic;

namespace PoultryWeb.Controllers
{
    [Authorize]
    public class GenericPurchasesController : Controller
    {
        private readonly IGenericApiClient _api;
        public GenericPurchasesController(IGenericApiClient api) => _api = api;

        public async Task<IActionResult> Index(string? status)
        {
            ViewBag.Status = status;
            var rows = await _api.GetPurchasesAsync(status);
            return View(rows);
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Approve(int id)
        {
            await _api.ApprovePurchaseAsync(id);
            TempData["Success"] = $"Purchase #{id} approved. Inventory and cash/supplier balances updated.";
            return RedirectToAction(nameof(Index));
        }
    }
}
