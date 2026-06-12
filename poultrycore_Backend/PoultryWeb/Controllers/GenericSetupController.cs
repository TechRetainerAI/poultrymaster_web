using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryWeb.Business.Generic;
using PoultryWeb.Models.Generic;

namespace PoultryWeb.Controllers
{
    // Generic Company setup page. Run once after the user creates a Farm row
    // (Type='Generic') via the existing /api/Companies endpoint. This attaches
    // a profile and seeds the default expense categories / cash accounts / etc.
    [Authorize]
    public class GenericSetupController : Controller
    {
        private readonly IGenericApiClient _api;
        public GenericSetupController(IGenericApiClient api) => _api = api;

        public async Task<IActionResult> Index()
        {
            var profile = await _api.GetProfileAsync();
            ViewBag.HasProfile = profile is not null;
            ViewBag.Profile = profile;
            ViewBag.Categories = await _api.GetBusinessCategoriesAsync();
            return View(new GenericCompanySetupRequestVm
            {
                FarmId = "",   // filled by the API client
                DefaultCurrency = profile?.DefaultCurrency ?? "GHC",
                BusinessCategoryId = profile?.BusinessCategoryId,
                BusinessDescription = profile?.BusinessDescription,
                MainLocation = profile?.MainLocation,
                OwnerName = profile?.OwnerName,
                PhoneNumber = profile?.PhoneNumber,
                OpeningCashBalance = profile?.OpeningCashBalance,
                Notes = profile?.Notes,
            });
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Index(GenericCompanySetupRequestVm req)
        {
            if (!ModelState.IsValid)
            {
                ViewBag.Categories = await _api.GetBusinessCategoriesAsync();
                return View(req);
            }

            var result = await _api.SetupAsync(req);
            if (result is null)
            {
                TempData["Error"] = "Could not save the Generic Company profile. Check the API logs.";
                ViewBag.Categories = await _api.GetBusinessCategoriesAsync();
                return View(req);
            }

            TempData["Success"] = "Generic Company is set up. Default categories, cash accounts, and lookups have been seeded.";
            return RedirectToAction("Index", "GenericDashboard");
        }
    }
}
