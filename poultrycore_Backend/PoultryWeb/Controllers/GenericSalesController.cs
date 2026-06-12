using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryWeb.Business.Generic;
using PoultryWeb.Models.Generic;

namespace PoultryWeb.Controllers
{
    [Authorize]
    public class GenericSalesController : Controller
    {
        private readonly IGenericApiClient _api;
        public GenericSalesController(IGenericApiClient api) => _api = api;

        public async Task<IActionResult> Index(string? status)
        {
            ViewBag.Status = status;
            var rows = await _api.GetSalesAsync(status);
            return View(rows);
        }

        public async Task<IActionResult> Details(int id)
        {
            var s = await _api.GetSaleAsync(id);
            if (s is null) return NotFound();
            return View(s);
        }

        public async Task<IActionResult> Create()
        {
            // Populate dropdowns for the create form.
            ViewBag.Customers    = await _api.GetCustomersAsync();
            ViewBag.Products     = await _api.GetProductsAsync();
            ViewBag.CashAccounts = await _api.GetCashAccountsAsync();

            return View(new GenericSaleCreateVm
            {
                SaleDate = DateTime.Today,
                SalesType = "WalkInSale",
                PaymentMethod = "Cash",
                Items = new List<GenericSaleItemVm>
                {
                    new() { ItemType = "Product", Quantity = 1, UnitPrice = 0, DiscountAmount = 0 }
                }
            });
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Create(GenericSaleCreateVm req)
        {
            // Drop blank item rows the user left empty (the create form starts
            // with one empty row and lets users add more).
            req.Items = req.Items?
                .Where(i => i.Quantity > 0 && (i.GenericProductId.HasValue || i.GenericServiceId.HasValue))
                .ToList() ?? new();

            if (req.Items.Count == 0)
            {
                ModelState.AddModelError("", "Add at least one item.");
            }

            if (!ModelState.IsValid)
            {
                ViewBag.Customers    = await _api.GetCustomersAsync();
                ViewBag.Products     = await _api.GetProductsAsync();
                ViewBag.CashAccounts = await _api.GetCashAccountsAsync();
                return View(req);
            }

            var newId = await _api.CreateSaleAsync(req);
            if (newId == 0)
            {
                TempData["Error"] = "Could not create the sale. Check the API logs.";
                ViewBag.Customers    = await _api.GetCustomersAsync();
                ViewBag.Products     = await _api.GetProductsAsync();
                ViewBag.CashAccounts = await _api.GetCashAccountsAsync();
                return View(req);
            }

            TempData["Success"] = "Sale created as Draft. Review and approve to commit it to inventory and cash.";
            return RedirectToAction(nameof(Details), new { id = newId });
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Approve(int id)
        {
            await _api.ApproveSaleAsync(id);
            TempData["Success"] = $"Sale #{id} approved. Inventory, cash and customer ledger have been updated.";
            return RedirectToAction(nameof(Details), new { id });
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Cancel(int id, string? reason)
        {
            await _api.CancelSaleAsync(id, reason);
            TempData["Success"] = $"Sale #{id} cancelled.";
            return RedirectToAction(nameof(Index));
        }
    }
}
