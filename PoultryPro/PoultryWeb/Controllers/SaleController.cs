using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryWeb.Business;
using PoultryWeb.Models;
//using System.Web.Mvc;

namespace PoultryWeb.Controllers
{
    [Authorize]
    public class SaleController : Controller
    {
        private readonly ISaleWebApiService _saleService;

        public SaleController(ISaleWebApiService saleService)
        {
            _saleService = saleService;
        }

        // GET: /Sale/Index
        public async Task<IActionResult> Index()
        {
            var allSales = await _saleService.GetAllAsync();
            return View(allSales);
        }

        // GET: /Sale/Details/5
        public async Task<IActionResult> Details(int id)
        {
            var sale = await _saleService.GetByIdAsync(id);
            if (sale == null) return NotFound();
            return View(sale);
        }

        // GET: /Sale/Create
        public IActionResult Create()
        {
            var model = new SaleModel
            {
                SaleDate = DateTime.Today
            };
            return View(model);
        }

        // POST: /Sale/Create
        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Create(SaleModel model)
        {
            if (!ModelState.IsValid)
            {
                return View(model);
            }

            // Compute or confirm total amount if needed:
            model.TotalAmount = model.Quantity * model.UnitPrice;

            var created = await _saleService.CreateAsync(model);
            return RedirectToAction(nameof(Index));
        }

        // GET: /Sale/Edit/5
        public async Task<IActionResult> Edit(int id)
        {
            var sale = await _saleService.GetByIdAsync(id);
            if (sale == null) return NotFound();
            return View(sale);
        }

        // POST: /Sale/Edit/5
        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Edit(int id, SaleModel model)
        {
            if (!ModelState.IsValid)
            {
                return View(model);
            }

            model.TotalAmount = model.Quantity * model.UnitPrice;
            await _saleService.UpdateAsync(id, model);
            return RedirectToAction(nameof(Index));
        }

        // GET: /Sale/Delete/5
        public async Task<IActionResult> Delete(int id)
        {
            var sale = await _saleService.GetByIdAsync(id);
            if (sale == null) return NotFound();
            return View(sale);
        }

        // POST: /Sale/DeleteConfirmed/5
        [HttpPost, ActionName("DeleteConfirmed")]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> DeleteConfirmed(int saleId)
        {
            await _saleService.DeleteAsync(saleId);
            return RedirectToAction(nameof(Index));
        }

        // OPTIONAL: if you want a separate action for /Sale/ByFlock
        public async Task<IActionResult> ByFlock(int flockId)
        {
            var sales = await _saleService.GetByFlockAsync(flockId);
            ViewBag.FlockId = flockId;
            return View(sales);
        }

        // GET: /Sale/CreatePartial
        [HttpGet]
        public IActionResult CreatePartial()
        {
            var model = new SaleModel
            {
                SaleDate = DateTime.Today
                // set any defaults
            };
            return PartialView("_CreatePartial", model);
        }

        // GET: /Sale/EditPartial/5
        [HttpGet]
        public async Task<IActionResult> EditPartial(int id)
        {
            var record = await _saleService.GetByIdAsync(id);
            if (record == null) return NotFound();
            return PartialView("_EditPartial", record);
        }

        // GET: /Sale/DeletePartial/5
        [HttpGet]
        public async Task<IActionResult> DeletePartial(int id)
        {
            var record = await _saleService.GetByIdAsync(id);
            if (record == null) return NotFound();
            return PartialView("_DeletePartial", record);
        }
    }
}
