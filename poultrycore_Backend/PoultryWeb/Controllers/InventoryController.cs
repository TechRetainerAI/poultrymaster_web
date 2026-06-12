using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using PoultryWeb.Business;
using PoultryWeb.Models;
//using System.Web.Mvc;

namespace PoultryWeb.Controllers
{
    [Authorize]
    public class InventoryController : Controller
    {
        private readonly IInventoryWebApiService _inventoryService;

        public InventoryController(IInventoryWebApiService inventoryService)
        {
            _inventoryService = inventoryService;
        }

        public async Task<IActionResult> Index()
        {
            var items = await _inventoryService.GetAllItemsAsync();
            return View(items);
        }

        public async Task<IActionResult> Details(int id)
        {
            var item = await _inventoryService.GetItemByIdAsync(id);
            if (item == null) return NotFound();

            var transactions = await _inventoryService.GetTransactionsByItemAsync(id);
            ViewBag.Transactions = transactions;
            return View(item);
        }

        public IActionResult Create()
        {
            return View(new InventoryItemModel { IsActive = true });
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Create(InventoryItemModel model)
        {
            if (!ModelState.IsValid) return View(model);
            await _inventoryService.CreateItemAsync(model);
            return RedirectToAction(nameof(Index));
        }

        public async Task<IActionResult> Edit(int id)
        {
            var item = await _inventoryService.GetItemByIdAsync(id);
            if (item == null) return NotFound();
            return View(item);
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Edit(InventoryItemModel model)
        {
            if (!ModelState.IsValid) return View(model);
            await _inventoryService.UpdateItemAsync(model.ItemId, model);
            return RedirectToAction(nameof(Index));
        }

        public async Task<IActionResult> Delete(int id)
        {
            var item = await _inventoryService.GetItemByIdAsync(id);
            if (item == null) return NotFound();
            return View(item);
        }

        [HttpPost, ActionName("DeleteConfirmed")]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> DeleteConfirmed(int itemId)
        {
            var hasTransactions = await _inventoryService.GetTransactionsByItemAsync(itemId);
            if (hasTransactions.Count > 0)
            {
                // Return error message
                ModelState.AddModelError("", "Cannot delete this item because it is referenced by transactions.");   //Would have to  handle this validation at the UI. ETC
                return RedirectToAction(nameof(Index));
            }

            await _inventoryService.DeleteItemAsync(itemId);
            return RedirectToAction(nameof(Index));
        }

        public async Task<IActionResult> AddTransaction(int itemId)
        {
            ViewBag.ItemId = itemId;
            return View(new InventoryTransactionModel
            {
                ItemId = itemId,
                TransactionDate = DateTime.Today
            });
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> AddTransaction(InventoryTransactionModel model)
        {
            if (!ModelState.IsValid)
            {
                ViewBag.ItemId = model.ItemId;
                return View(model);
            }

            await _inventoryService.CreateTransactionAsync(model);
            return RedirectToAction("Details", new { id = model.ItemId });
        }


        // GET: /Inventory/CreatePartial
        [HttpGet]
        public IActionResult CreatePartial()
        {
            var model = new InventoryItemModel
            {
                IsActive = true,
                // any other defaults, e.g. QuantityInStock=0
            };
            return PartialView("_CreatePartial", model);
        }

        // GET: /Inventory/EditPartial/5
        [HttpGet]
        public async Task<IActionResult> EditPartial(int id)
        {
            var record = await _inventoryService.GetItemByIdAsync(id);
            if (record == null) return NotFound();
            return PartialView("_EditPartial", record);
        }

        // GET: /Inventory/DeletePartial/5
        [HttpGet]
        public async Task<IActionResult> DeletePartial(int id)
        {
            var record = await _inventoryService.GetItemByIdAsync(id);
            if (record == null) return NotFound();
            return PartialView("_DeletePartial", record);
        }
    }
}