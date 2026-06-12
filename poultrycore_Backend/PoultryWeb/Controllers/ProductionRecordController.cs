using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryWeb.Business;
using PoultryWeb.Models;

namespace PoultryWeb.Controllers
{
    [Authorize]
    public class ProductionRecordController : Controller
    {
        private readonly IProductionRecordWebApiService _service;

        public ProductionRecordController(IProductionRecordWebApiService service)
        {
            _service = service;
        }

        public async Task<IActionResult> Index()
        {
            var records = await _service.GetAllAsync();
            return View(records);
        }

        public async Task<IActionResult> Details(int id)
        {
            var record = await _service.GetByIdAsync(id);
            if (record == null) return NotFound();
            return View(record);
        }

        //public IActionResult Create()
        //{
        //    return View(new ProductionRecordViewModel());
        //}

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Create(ProductionRecordViewModel model)
        {
            // Normalize Medication
            model.Medication = string.IsNullOrWhiteSpace(model.Medication)
                ? "None"
                : model.Medication.Trim();

            // Remove keys the client didn't post so they don't trigger validation errors
            ModelState.Remove(nameof(model.Id));
            ModelState.Remove(nameof(model.FarmId));
            ModelState.Remove(nameof(model.UserId));
            ModelState.Remove(nameof(model.CreatedBy));
            ModelState.Remove(nameof(model.UpdatedBy));

            // If your Id is not posted on create, remove it too (not required on create)
            ModelState.Remove(nameof(model.Id));
            if (!ModelState.IsValid) return PartialView("_CreatePartial", model);
            //if (!ModelState.IsValid) return View(model);
            await _service.CreateAsync(model);
            return RedirectToAction(nameof(Index));
        }

        //public async Task<IActionResult> Edit(int id)
        //{
        //    var record = await _service.GetByIdAsync(id);
        //    if (record == null) return NotFound();
        //    return View(record);
        //}

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Edit(ProductionRecordViewModel model)
        {
            // Remove keys the client didn't post so they don't trigger validation errors
            ModelState.Remove(nameof(model.FarmId));
            ModelState.Remove(nameof(model.UserId));
            ModelState.Remove(nameof(model.CreatedBy));
            ModelState.Remove(nameof(model.UpdatedBy));

            if (!ModelState.IsValid) return PartialView("_EditPartial", model);
            //if (!ModelState.IsValid) return View(model);
            await _service.UpdateAsync(model.Id, model);
            return RedirectToAction(nameof(Index));
        }

        //public async Task<IActionResult> Delete(int id)
        //{
        //    var record = await _service.GetByIdAsync(id);
        //    if (record == null) return NotFound();
        //    return View(record);
        //}

        [HttpPost, ActionName("DeleteConfirmed")]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> DeleteConfirmed(int id)
        {
            await _service.DeleteAsync(id);
            return RedirectToAction(nameof(Index));
        }


        // GET: /ProductionRecord/CreatePartial
        [HttpGet]
        public IActionResult CreatePartial()
        {
            var model = new ProductionRecordViewModel
            {
                Date = DateTime.Today,
                // set any defaults
            };
            return PartialView("_CreatePartial", model);
        }

        // GET: /ProductionRecord/EditPartial/5
        [HttpGet]
        public async Task<IActionResult> EditPartial(int id)
        {
            var record = await _service.GetByIdAsync(id);
            if (record == null) return NotFound();
            return PartialView("_EditPartial", record);
        }


        // GET: /ProductionRecord/DeletePartial/5
        [HttpGet]
        public async Task<IActionResult> DeletePartial(int id)
        {
            var record = await _service.GetByIdAsync(id);
            if (record == null) return NotFound();
            return PartialView("_DeletePartial", record);
        }
    }
}
