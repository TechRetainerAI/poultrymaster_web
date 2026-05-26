using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // =========================================================================
    // Business categories - platform-wide lookup (no FarmId scope).
    // =========================================================================
    [ApiController]
    [Route("api/business-categories")]
    public class BusinessCategoriesController : ControllerBase
    {
        private readonly IGenericCompanyService _svc;
        public BusinessCategoriesController(IGenericCompanyService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<BusinessCategoryModel>>> GetAll()
            => Ok(await _svc.GetBusinessCategoriesAsync());
    }

    // =========================================================================
    // Generic Company profile - per-Farm. All endpoints are FarmId-scoped and
    // require the Farm's Type = 'Generic'.
    //
    // The Farm row itself is created via the existing LoginAPI
    // POST /api/Companies with Type="Generic". Once that returns a FarmId,
    // the client calls POST /api/generic-company/setup to attach a profile
    // and seed defaults.
    // =========================================================================
    [ApiController]
    [Route("api/generic-company")]
    public class GenericCompanyController : ControllerBase
    {
        private readonly IGenericCompanyService _svc;

        public GenericCompanyController(IGenericCompanyService svc) => _svc = svc;

        // ---------------------------------------------------------------------
        // Profile
        // ---------------------------------------------------------------------
        [HttpPost("setup")]
        public async Task<ActionResult<GenericCompanyProfileModel>> Setup([FromBody] GenericCompanySetupRequest req)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required.");

            var typeCheck = await EnsureGenericFarm(req.FarmId);
            if (typeCheck is not null) return typeCheck;

            var profile = await _svc.SetupAsync(req);
            if (profile is null) return StatusCode(500, "Failed to set up the Generic Company.");
            return CreatedAtAction(nameof(GetProfile), new { farmId = profile.FarmId }, profile);
        }

        [HttpGet("{farmId}")]
        public async Task<ActionResult<GenericCompanyProfileModel>> GetProfile(string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var typeCheck = await EnsureGenericFarm(farmId);
            if (typeCheck is not null) return typeCheck;

            var profile = await _svc.GetProfileAsync(farmId);
            return profile is null ? NotFound() : Ok(profile);
        }

        [HttpPut("{farmId}")]
        public async Task<ActionResult<GenericCompanyProfileModel>> UpdateProfile(string farmId, [FromBody] GenericCompanyUpdateRequest req)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");

            var typeCheck = await EnsureGenericFarm(farmId);
            if (typeCheck is not null) return typeCheck;

            var updated = await _svc.UpdateProfileAsync(farmId, req);
            return updated is null ? NotFound() : Ok(updated);
        }

        // ---------------------------------------------------------------------
        // Expense categories (per-Farm)
        // ---------------------------------------------------------------------
        [HttpGet("{farmId}/expense-categories")]
        public async Task<ActionResult<IEnumerable<GenericExpenseCategoryModel>>> GetExpenseCategories(string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var typeCheck = await EnsureGenericFarm(farmId);
            if (typeCheck is not null) return typeCheck;
            return Ok(await _svc.GetExpenseCategoriesAsync(farmId));
        }

        [HttpPost("{farmId}/expense-categories")]
        public async Task<ActionResult<GenericExpenseCategoryModel>> CreateExpenseCategory(string farmId, [FromBody] GenericExpenseCategoryModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var typeCheck = await EnsureGenericFarm(farmId);
            if (typeCheck is not null) return typeCheck;

            m.FarmId = farmId;   // force scope from the route
            var newId = await _svc.InsertExpenseCategoryAsync(m);
            m.GenericExpenseCategoryId = newId;
            return CreatedAtAction(nameof(GetExpenseCategories), new { farmId }, m);
        }

        [HttpPut("{farmId}/expense-categories/{id:int}")]
        public async Task<IActionResult> UpdateExpenseCategory(string farmId, int id, [FromBody] GenericExpenseCategoryModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var typeCheck = await EnsureGenericFarm(farmId);
            if (typeCheck is not null) return typeCheck;

            m.FarmId = farmId;
            m.GenericExpenseCategoryId = id;
            await _svc.UpdateExpenseCategoryAsync(m);
            return NoContent();
        }

        [HttpDelete("{farmId}/expense-categories/{id:int}")]
        public async Task<IActionResult> DeleteExpenseCategory(string farmId, int id)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var typeCheck = await EnsureGenericFarm(farmId);
            if (typeCheck is not null) return typeCheck;

            await _svc.DeleteExpenseCategoryAsync(id, farmId);
            return NoContent();
        }

        // ---------------------------------------------------------------------
        // Cash accounts (per-Farm)
        // ---------------------------------------------------------------------
        [HttpGet("{farmId}/cash-accounts")]
        public async Task<ActionResult<IEnumerable<GenericCashAccountModel>>> GetCashAccounts(string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var typeCheck = await EnsureGenericFarm(farmId);
            if (typeCheck is not null) return typeCheck;
            return Ok(await _svc.GetCashAccountsAsync(farmId));
        }

        [HttpPost("{farmId}/cash-accounts")]
        public async Task<ActionResult<GenericCashAccountModel>> CreateCashAccount(string farmId, [FromBody] GenericCashAccountModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var typeCheck = await EnsureGenericFarm(farmId);
            if (typeCheck is not null) return typeCheck;

            m.FarmId = farmId;
            var newId = await _svc.InsertCashAccountAsync(m);
            m.GenericCashAccountId = newId;
            return CreatedAtAction(nameof(GetCashAccounts), new { farmId }, m);
        }

        [HttpPut("{farmId}/cash-accounts/{id:int}")]
        public async Task<IActionResult> UpdateCashAccount(string farmId, int id, [FromBody] GenericCashAccountModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var typeCheck = await EnsureGenericFarm(farmId);
            if (typeCheck is not null) return typeCheck;

            m.FarmId = farmId;
            m.GenericCashAccountId = id;
            await _svc.UpdateCashAccountAsync(m);
            return NoContent();
        }

        [HttpDelete("{farmId}/cash-accounts/{id:int}")]
        public async Task<IActionResult> DeleteCashAccount(string farmId, int id)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var typeCheck = await EnsureGenericFarm(farmId);
            if (typeCheck is not null) return typeCheck;

            await _svc.DeleteCashAccountAsync(id, farmId);
            return NoContent();
        }

        // ---------------------------------------------------------------------
        // Lookup lists (per-Farm) - read-only for Phase 1
        // ---------------------------------------------------------------------
        [HttpGet("{farmId}/customer-types")]
        public async Task<ActionResult<IEnumerable<GenericCustomerTypeModel>>> GetCustomerTypes(string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var typeCheck = await EnsureGenericFarm(farmId);
            if (typeCheck is not null) return typeCheck;
            return Ok(await _svc.GetCustomerTypesAsync(farmId));
        }

        [HttpGet("{farmId}/supplier-types")]
        public async Task<ActionResult<IEnumerable<GenericSupplierTypeModel>>> GetSupplierTypes(string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var typeCheck = await EnsureGenericFarm(farmId);
            if (typeCheck is not null) return typeCheck;
            return Ok(await _svc.GetSupplierTypesAsync(farmId));
        }

        [HttpGet("{farmId}/payment-methods")]
        public async Task<ActionResult<IEnumerable<GenericPaymentMethodModel>>> GetPaymentMethods(string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var typeCheck = await EnsureGenericFarm(farmId);
            if (typeCheck is not null) return typeCheck;
            return Ok(await _svc.GetPaymentMethodsAsync(farmId));
        }

        // ---------------------------------------------------------------------
        // Helpers
        // ---------------------------------------------------------------------
        // Returns null when the Farm exists and is Generic. Otherwise returns
        // the ActionResult the caller should return (404 / 409).
        private async Task<ActionResult?> EnsureGenericFarm(string farmId)
        {
            var farmType = await _svc.GetFarmTypeAsync(farmId);
            if (farmType is null)
                return NotFound("Company not found.");
            if (!string.Equals(farmType, "Generic", StringComparison.OrdinalIgnoreCase))
                return Conflict($"This company is not a Generic company (current type: {farmType}).");
            return null;
        }
    }
}
