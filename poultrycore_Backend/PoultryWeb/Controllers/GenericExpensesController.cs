using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryWeb.Business.Generic;

namespace PoultryWeb.Controllers
{
    [Authorize]
    public class GenericExpensesController : Controller
    {
        private readonly IGenericApiClient _api;
        public GenericExpensesController(IGenericApiClient api) => _api = api;

        public async Task<IActionResult> Index(string? status)
        {
            ViewBag.Status = status;
            var rows = await _api.GetExpensesAsync(status);
            return View(rows);
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Approve(int id)
        {
            await _api.ApproveExpenseAsync(id);
            TempData["Success"] = $"Expense #{id} approved.";
            return RedirectToAction(nameof(Index));
        }
    }
}
