using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryWeb.Business;
using PoultryWeb.Models;

namespace PoultryWeb.Controllers
{
    [Authorize]
    public class EmployeeController : Controller
    {
        private readonly IEmployeeWebApiService _employeeService;
        private readonly ILogger<EmployeeController> _logger;

        public EmployeeController(IEmployeeWebApiService employeeService, ILogger<EmployeeController> logger)
        {
            _employeeService = employeeService;
            _logger = logger;
        }

        // GET: /Employee/Index
        public async Task<IActionResult> Index()
        {
            try
            {
                var employees = await _employeeService.GetAllEmployeesAsync();
                return View(employees);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error loading employees");
                TempData["ErrorMessage"] = $"Error loading employees: {ex.Message}";
                return View(new List<EmployeeModel>());
            }
        }

        // GET: /Employee/Details/5
        public async Task<IActionResult> Details(string id)
        {
            try
            {
                var employee = await _employeeService.GetEmployeeByIdAsync(id);
                if (employee == null)
                {
                    TempData["ErrorMessage"] = "Employee not found";
                    return RedirectToAction(nameof(Index));
                }
                return View(employee);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error loading employee details");
                TempData["ErrorMessage"] = $"Error loading employee: {ex.Message}";
                return RedirectToAction(nameof(Index));
            }
        }

        // GET: /Employee/Create
        public IActionResult Create()
        {
            var model = new EmployeeModel();
            return View(model);
        }

        // POST: /Employee/Create
        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Create(EmployeeModel model)
        {
            // Remove validation for fields not posted
            ModelState.Remove(nameof(model.Id));
            ModelState.Remove(nameof(model.FarmId));
            ModelState.Remove(nameof(model.FarmName));
            ModelState.Remove(nameof(model.IsStaff));
            ModelState.Remove(nameof(model.EmailConfirmed));
            ModelState.Remove(nameof(model.CreatedDate));

            if (!ModelState.IsValid)
            {
                return View(model);
            }

            // Validate password
            if (string.IsNullOrEmpty(model.Password))
            {
                ModelState.AddModelError("Password", "Password is required");
                return View(model);
            }

            if (model.Password != model.ConfirmPassword)
            {
                ModelState.AddModelError("ConfirmPassword", "Passwords do not match");
                return View(model);
            }

            try
            {
                var created = await _employeeService.CreateEmployeeAsync(model);
                TempData["SuccessMessage"] = $"Employee '{model.FirstName} {model.LastName}' created successfully!";
                return RedirectToAction(nameof(Index));
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error creating employee");
                ModelState.AddModelError("", $"Error creating employee: {ex.Message}");
                return View(model);
            }
        }

        // GET: /Employee/Edit/5
        public async Task<IActionResult> Edit(string id)
        {
            try
            {
                var employee = await _employeeService.GetEmployeeByIdAsync(id);
                if (employee == null)
                {
                    TempData["ErrorMessage"] = "Employee not found";
                    return RedirectToAction(nameof(Index));
                }
                return View(employee);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error loading employee for edit");
                TempData["ErrorMessage"] = $"Error loading employee: {ex.Message}";
                return RedirectToAction(nameof(Index));
            }
        }

        // POST: /Employee/Edit/5
        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Edit(string id, EmployeeModel model)
        {
            if (id != model.Id)
            {
                return BadRequest();
            }

            // Remove validation for fields not being updated
            ModelState.Remove(nameof(model.Password));
            ModelState.Remove(nameof(model.ConfirmPassword));
            ModelState.Remove(nameof(model.FarmId));
            ModelState.Remove(nameof(model.FarmName));
            ModelState.Remove(nameof(model.IsStaff));
            ModelState.Remove(nameof(model.EmailConfirmed));
            ModelState.Remove(nameof(model.CreatedDate));
            ModelState.Remove(nameof(model.UserName));

            if (!ModelState.IsValid)
            {
                return View(model);
            }

            try
            {
                await _employeeService.UpdateEmployeeAsync(id, model);
                TempData["SuccessMessage"] = $"Employee '{model.FirstName} {model.LastName}' updated successfully!";
                return RedirectToAction(nameof(Index));
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error updating employee");
                ModelState.AddModelError("", $"Error updating employee: {ex.Message}");
                return View(model);
            }
        }

        // GET: /Employee/Delete/5
        public async Task<IActionResult> Delete(string id)
        {
            try
            {
                var employee = await _employeeService.GetEmployeeByIdAsync(id);
                if (employee == null)
                {
                    TempData["ErrorMessage"] = "Employee not found";
                    return RedirectToAction(nameof(Index));
                }
                return View(employee);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error loading employee for delete");
                TempData["ErrorMessage"] = $"Error loading employee: {ex.Message}";
                return RedirectToAction(nameof(Index));
            }
        }

        // POST: /Employee/DeleteConfirmed/5
        [HttpPost, ActionName("DeleteConfirmed")]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> DeleteConfirmed(string id)
        {
            try
            {
                await _employeeService.DeleteEmployeeAsync(id);
                TempData["SuccessMessage"] = "Employee deleted successfully!";
                return RedirectToAction(nameof(Index));
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error deleting employee");
                TempData["ErrorMessage"] = $"Error deleting employee: {ex.Message}";
                return RedirectToAction(nameof(Index));
            }
        }
    }
}

