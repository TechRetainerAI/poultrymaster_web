using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryWeb.Business;
using PoultryWeb.Models;
//using System.Web.Mvc;

namespace PoultryWeb.Controllers
{
    [Authorize]
    public class FeedUsageController : Controller
    {
        private readonly IFeedUsageWebApiService _feedUsageService;

        public FeedUsageController(IFeedUsageWebApiService feedUsageService)
        {
            _feedUsageService = feedUsageService;
        }

        // GET: /FeedUsage/Index
        public async Task<IActionResult> Index()
        {
            var usageList = await _feedUsageService.GetAllAsync();
            return View(usageList);
        }

        // GET: /FeedUsage/Details/5
        public async Task<IActionResult> Details(int id)
        {
            var record = await _feedUsageService.GetByIdAsync(id);
            if (record == null) return NotFound();
            return View(record);
        }

        // GET: /FeedUsage/Create
        public IActionResult Create()
        {
            // Optionally prefill UsageDate to today
            var model = new FeedUsageModel
            {
                UsageDate = DateTime.Today
            };
            return View(model);
        }

        // POST: /FeedUsage/Create
        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Create(FeedUsageModel model)
        {
            // Add debugging to check FarmId in the model
            var farmIdClaim = User.FindFirst("FarmId")?.Value;
            var userIdClaim = User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;

            // Log for debugging
            Console.WriteLine($"[FeedUsage Create] FarmId from claims: '{farmIdClaim ?? "NULL"}'");
            Console.WriteLine($"[FeedUsage Create] UserId from claims: '{userIdClaim ?? "NULL"}'");
            Console.WriteLine($"[FeedUsage Create] model.FarmId: '{model.FarmId ?? "NULL"}'");
            Console.WriteLine($"[FeedUsage Create] model.UserId: '{model.UserId ?? "NULL"}'");

            // Show alert if FarmId is empty
            if (string.IsNullOrEmpty(farmIdClaim))
            {
                TempData["ErrorMessage"] = "⚠️ ALERT: FarmId is EMPTY in user claims! Please log out and log back in.";
                return View(model);
            }

            if (!ModelState.IsValid)
            {
                return View(model);
            }

            try
            {
                var created = await _feedUsageService.CreateAsync(model);
                TempData["SuccessMessage"] = "Feed usage record created successfully!";
                return RedirectToAction(nameof(Index));
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = $"Error creating feed usage: {ex.Message}";
                return View(model);
            }
        }

        // GET: /FeedUsage/Edit/5
        public async Task<IActionResult> Edit(int id)
        {
            var record = await _feedUsageService.GetByIdAsync(id);
            if (record == null) return NotFound();
            return View(record);
        }

        // POST: /FeedUsage/Edit/5
        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Edit(FeedUsageModel model)
        {
            if (!ModelState.IsValid)
            {
                return View(model);
            }
            //model.FeedUsageId = id; // ensure correct ID
            await _feedUsageService.UpdateAsync(model.FeedUsageId, model);
            return RedirectToAction(nameof(Index));
        }

        // GET: /FeedUsage/Delete/5
        public async Task<IActionResult> Delete(int id)
        {
            var record = await _feedUsageService.GetByIdAsync(id);
            if (record == null) return NotFound();
            return View(record);
        }

        // POST: /FeedUsage/DeleteConfirmed/5
        [HttpPost, ActionName("DeleteConfirmed")]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> DeleteConfirmed(int feedUsageId)
        {
            await _feedUsageService.DeleteAsync(feedUsageId);
            return RedirectToAction(nameof(Index));
        }


        // GET: /FeedUsage/CreatePartial
        [HttpGet]
        public IActionResult CreatePartial()
        {
            var model = new FeedUsageModel
            {
                UsageDate = DateTime.Today
                // set any defaults
            };
            return PartialView("_CreatePartial", model);
        }

        // GET: /FeedUsage/EditPartial/5
        [HttpGet]
        public async Task<IActionResult> EditPartial(int id)
        {
            var record = await _feedUsageService.GetByIdAsync(id);
            if (record == null) return NotFound();
            return PartialView("_EditPartial", record);
        }

        // GET: /FeedUsage/DeletePartial/5
        [HttpGet]
        public async Task<IActionResult> DeletePartial(int id)
        {
            var record = await _feedUsageService.GetByIdAsync(id);
            if (record == null) return NotFound();
            return PartialView("_DeletePartial", record);
        }

    }
}
