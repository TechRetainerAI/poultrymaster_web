using Microsoft.AspNetCore.Mvc;
using PoultryWeb.Business;
using PoultryWeb.Models;

namespace PoultryWeb.Controllers
{
    public class CustomerController : Controller
    {
        private readonly ICustomerWebApiService _customerService;

        public CustomerController(ICustomerWebApiService customerService)
        {
            _customerService = customerService;
        }

        // GET: /Customer/Index
        public async Task<IActionResult> Index()
        {
            var allCustomers = await _customerService.GetAllAsync();
            return View(allCustomers);
        }

        // GET: /Customer/Details/5
        public async Task<IActionResult> Details(int id)
        {
            var customer = await _customerService.GetByIdAsync(id);
            if (customer == null) return NotFound();
            return View(customer);
        }

        // GET: /Customer/Create
        public IActionResult Create()
        {
            return View(new CustomerModel());
        }

        // POST: /Customer/Create
        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Create(CustomerModel model)
        {
            if (!ModelState.IsValid) return View(model);

            var created = await _customerService.CreateAsync(model);
            return RedirectToAction(nameof(Index));
        }

        // GET: /Customer/Edit/5
        public async Task<IActionResult> Edit(int id)
        {
            var customer = await _customerService.GetByIdAsync(id);
            if (customer == null) return NotFound();
            return View(customer);
        }

        // POST: /Customer/Edit/5
        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Edit(CustomerModel model)
        {
            if (!ModelState.IsValid) return View(model);

            await _customerService.UpdateAsync(model.CustomerId, model);
            return RedirectToAction(nameof(Index));
        }

        // GET: /Customer/Delete/5
        public async Task<IActionResult> Delete(int id)
        {
            var customer = await _customerService.GetByIdAsync(id);
            if (customer == null) return NotFound();
            return View(customer);
        }

        // POST: /Customer/DeleteConfirmed/5
        [HttpPost, ActionName("DeleteConfirmed")]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> DeleteConfirmed(int customerId)
        {
            await _customerService.DeleteAsync(customerId);
            return RedirectToAction(nameof(Index));
        }

        // GET: /Customer/CreatePartial
        [HttpGet]
        public IActionResult CreatePartial()
        {
            var model = new CustomerModel
            {
                // set any defaults here if needed
            };
            return PartialView("_CreatePartial", model);
        }

        // GET: /Customer/EditPartial/5
        [HttpGet]
        public async Task<IActionResult> EditPartial(int id)
        {
            var record = await _customerService.GetByIdAsync(id);
            if (record == null) return NotFound();
            return PartialView("_EditPartial", record);
        }

        // GET: /Customer/DeletePartial/5
        [HttpGet]
        public async Task<IActionResult> DeletePartial(int id)
        {
            var record = await _customerService.GetByIdAsync(id);
            if (record == null) return NotFound();
            return PartialView("_DeletePartial", record);
        }
    }
}
