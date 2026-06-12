using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryWeb.Business.Generic;
using PoultryWeb.Models.Generic;

namespace PoultryWeb.Controllers
{
    [Authorize]
    public class GenericDailyClosingsController : Controller
    {
        private readonly IGenericApiClient _api;
        public GenericDailyClosingsController(IGenericApiClient api) => _api = api;

        public async Task<IActionResult> Index()
        {
            var rows = await _api.GetDailyClosingsAsync();
            return View(rows);
        }

        public IActionResult Create() => View(new GenericDailyClosingCreateVm
        {
            ClosingDate = DateTime.Today,
        });

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Create(GenericDailyClosingCreateVm req)
        {
            if (!ModelState.IsValid) return View(req);

            var newId = await _api.CreateDailyClosingAsync(req);
            if (newId == 0)
            {
                TempData["Error"] = "Could not create the closing. There may already be one for this date.";
                return View(req);
            }

            // Immediately submit so the SP auto-aggregates the totals.
            await _api.SubmitDailyClosingAsync(newId);
            TempData["Success"] = $"Closing #{newId} created and submitted. Review and approve.";
            return RedirectToAction(nameof(Index));
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Submit(int id)
        {
            await _api.SubmitDailyClosingAsync(id);
            TempData["Success"] = $"Closing #{id} re-submitted with fresh totals.";
            return RedirectToAction(nameof(Index));
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Approve(int id)
        {
            await _api.ApproveDailyClosingAsync(id);
            TempData["Success"] = $"Closing #{id} approved and locked.";
            return RedirectToAction(nameof(Index));
        }
    }
}
