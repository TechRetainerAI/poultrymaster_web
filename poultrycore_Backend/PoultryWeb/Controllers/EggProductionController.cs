using Microsoft.AspNetCore.Mvc;
using PoultryWeb.Business;
using PoultryWeb.Models;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Authorization;

namespace PoultryWeb.Controllers
{
    [Authorize] // <--- Ensure only logged-in users can access these actions
    public class EggProductionController : Controller
    {
        private readonly IEggProductionWebApiService _eggProductionService;

        public EggProductionController(IEggProductionWebApiService eggProductionService)
        {
            _eggProductionService = eggProductionService;
        }

        public async Task<IActionResult> Index()
        {
            // Calls the API to get all egg production records
            var allRecords = await _eggProductionService.GetAllAsync();
            return View(allRecords);
        }

        public async Task<IActionResult> Details(int id)
        {
            var record = await _eggProductionService.GetByIdAsync(id);
            if (record == null) return NotFound();

            return View(record);
        }

        public IActionResult Create()
        {
            // Optionally load a list of Flocks if the user can select a Flock ID
            var model = new EggProductionModel
            {
                ProductionDate = System.DateTime.Today
            };
            return View(model);
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Create(EggProductionModel model)
        {
            if (!ModelState.IsValid)
            {
                return View(model);
            }

            var newRecord = await _eggProductionService.CreateAsync(model);
            return RedirectToAction(nameof(Index));
        }

        public async Task<IActionResult> Edit(int id)
        {
            var record = await _eggProductionService.GetByIdAsync(id);
            if (record == null) return NotFound();

            return View(record);
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Edit(EggProductionModel model)
        {
            if (!ModelState.IsValid)
            {
                return View(model);
            }
            await _eggProductionService.UpdateAsync(model.ProductionId, model);
            return RedirectToAction(nameof(Index));
        }

        public async Task<IActionResult> Delete(int id)
        {
            var record = await _eggProductionService.GetByIdAsync(id);
            if (record == null) return NotFound();

            return View(record);
        }

        [HttpPost, ActionName("DeleteConfirmed")]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> DeleteConfirmed(int productionId)
        {
            await _eggProductionService.DeleteAsync(productionId);
            return RedirectToAction(nameof(Index));
        }



        [HttpGet]
        public async Task<IActionResult> EditPartial(int id)
        {
            var record = await _eggProductionService.GetByIdAsync(id);
            if (record == null) return NotFound();
            return PartialView("_EditPartial", record);
        }

        // GET: /EggProduction/CreatePartial
        [HttpGet]
        public IActionResult CreatePartial()
        {
            // Return a fresh model with optional defaults
            var model = new EggProductionModel
            {
                ProductionDate = System.DateTime.Today
                // set any defaults you want (BrokenEggs=0, etc.)
            };
            return PartialView("_CreatePartial", model);
        }

        // GET: /EggProduction/DeletePartial/5
        [HttpGet]
        public async Task<IActionResult> DeletePartial(int id)
        {
            var record = await _eggProductionService.GetByIdAsync(id);
            if (record == null) return NotFound();
            return PartialView("_DeletePartial", record);
        }
    }
}
