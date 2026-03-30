using Microsoft.AspNetCore.Mvc;
using PoultryWeb.Business;
using PoultryWeb.Models;
//using System.Web.Mvc;
using Microsoft.AspNetCore.Authorization;

namespace PoultryWeb.Controllers
{
    [Authorize]
    public class ExpenseController : Controller
    {
        private readonly IExpenseWebApiService _expenseService;

        public ExpenseController(IExpenseWebApiService expenseService)
        {
            _expenseService = expenseService;
        }

        // GET: /Expense/Index
        public async Task<IActionResult> Index()
        {
            var allExpenses = await _expenseService.GetAllAsync();
            return View(allExpenses);
        }

        // GET: /Expense/Details/5
        public async Task<IActionResult> Details(int id)
        {
            var expense = await _expenseService.GetByIdAsync(id);
            if (expense == null) return NotFound();
            return View(expense);
        }

        // GET: /Expense/Create
        public IActionResult Create()
        {
            // Default date to Today
            var model = new ExpenseModel
            {
                ExpenseDate = DateTime.Today
            };
            return View(model);
        }

        // POST: /Expense/Create
        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Create(ExpenseModel model)
        {
            if (!ModelState.IsValid)
                return View(model);

            var created = await _expenseService.CreateAsync(model);
            return RedirectToAction(nameof(Index));
        }

        // GET: /Expense/Edit/5
        public async Task<IActionResult> Edit(int id)
        {
            var expense = await _expenseService.GetByIdAsync(id);
            if (expense == null) return NotFound();

            return View(expense);
        }

        // POST: /Expense/Edit/5
        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Edit(ExpenseModel model)
        {
            if (!ModelState.IsValid)
                return View(model);

            await _expenseService.UpdateAsync(model.ExpenseId, model);
            return RedirectToAction(nameof(Index));
        }

        // GET: /Expense/Delete/5
        public async Task<IActionResult> Delete(int id)
        {
            var expense = await _expenseService.GetByIdAsync(id);
            if (expense == null) return NotFound();

            return View(expense);
        }

        // POST: /Expense/DeleteConfirmed/5
        [HttpPost, ActionName("DeleteConfirmed")]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> DeleteConfirmed(int expenseId)
        {
            await _expenseService.DeleteAsync(expenseId);
            return RedirectToAction(nameof(Index));
        }

        // OPTIONAL: If you want a separate view for retrieving expenses by Flock
        public async Task<IActionResult> ByFlock(int flockId)
        {
            var records = await _expenseService.GetByFlockAsync(flockId);
            ViewBag.FlockId = flockId;
            return View(records);
        }

        // GET: /Expense/CreatePartial
        [HttpGet]
        public IActionResult CreatePartial()
        {
            var model = new ExpenseModel
            {
                ExpenseDate = DateTime.Today,
                // set any defaults
            };
            return PartialView("_CreatePartial", model);
        }

        // GET: /Expense/EditPartial/5
        [HttpGet]
        public async Task<IActionResult> EditPartial(int id)
        {
            var record = await _expenseService.GetByIdAsync(id);
            if (record == null) return NotFound();
            return PartialView("_EditPartial", record);
        }

        // GET: /Expense/DeletePartial/5
        [HttpGet]
        public async Task<IActionResult> DeletePartial(int id)
        {
            var record = await _expenseService.GetByIdAsync(id);
            if (record == null) return NotFound();
            return PartialView("_DeletePartial", record);
        }
    }
}
