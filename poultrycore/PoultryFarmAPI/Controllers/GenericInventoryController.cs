using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // =========================================================================
    // Products + product categories + low-stock report.
    // All endpoints are FarmId-scoped and require the Farm's Type = 'Generic'.
    // =========================================================================
    [ApiController]
    [Route("api/generic-company/{farmId}")]
    public class GenericProductController : ControllerBase
    {
        private readonly IGenericProductService _products;
        private readonly IGenericCompanyService _companies;

        public GenericProductController(IGenericProductService products, IGenericCompanyService companies)
        {
            _products = products;
            _companies = companies;
        }

        // ---------------------------------------------------------------------
        // Categories
        // ---------------------------------------------------------------------
        [HttpGet("product-categories")]
        public async Task<ActionResult<IEnumerable<GenericProductCategoryModel>>> GetCategories(string farmId)
        {
            var guard = await EnsureGenericFarm(farmId);
            if (guard is not null) return guard;
            return Ok(await _products.GetCategoriesAsync(farmId));
        }

        [HttpPost("product-categories")]
        public async Task<ActionResult<GenericProductCategoryModel>> CreateCategory(string farmId, [FromBody] GenericProductCategoryModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await EnsureGenericFarm(farmId);
            if (guard is not null) return guard;

            m.FarmId = farmId;
            m.GenericProductCategoryId = await _products.InsertCategoryAsync(m);
            return CreatedAtAction(nameof(GetCategories), new { farmId }, m);
        }

        [HttpPut("product-categories/{id:int}")]
        public async Task<IActionResult> UpdateCategory(string farmId, int id, [FromBody] GenericProductCategoryModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await EnsureGenericFarm(farmId);
            if (guard is not null) return guard;

            m.FarmId = farmId;
            m.GenericProductCategoryId = id;
            await _products.UpdateCategoryAsync(m);
            return NoContent();
        }

        [HttpDelete("product-categories/{id:int}")]
        public async Task<IActionResult> DeleteCategory(string farmId, int id)
        {
            var guard = await EnsureGenericFarm(farmId);
            if (guard is not null) return guard;

            await _products.DeleteCategoryAsync(id, farmId);
            return NoContent();
        }

        // ---------------------------------------------------------------------
        // Products
        // ---------------------------------------------------------------------
        [HttpGet("products")]
        public async Task<ActionResult<IEnumerable<GenericProductModel>>> GetAll(string farmId)
        {
            var guard = await EnsureGenericFarm(farmId);
            if (guard is not null) return guard;
            return Ok(await _products.GetAllAsync(farmId));
        }

        [HttpGet("products/{id:int}")]
        public async Task<ActionResult<GenericProductModel>> GetById(string farmId, int id)
        {
            var guard = await EnsureGenericFarm(farmId);
            if (guard is not null) return guard;

            var p = await _products.GetByIdAsync(id, farmId);
            return p is null ? NotFound() : Ok(p);
        }

        [HttpPost("products")]
        public async Task<ActionResult<GenericProductModel>> Create(string farmId, [FromBody] GenericProductModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await EnsureGenericFarm(farmId);
            if (guard is not null) return guard;

            m.FarmId = farmId;
            var newId = await _products.InsertAsync(m);
            var created = await _products.GetByIdAsync(newId, farmId);
            return CreatedAtAction(nameof(GetById), new { farmId, id = newId }, created);
        }

        [HttpPut("products/{id:int}")]
        public async Task<IActionResult> Update(string farmId, int id, [FromBody] GenericProductModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await EnsureGenericFarm(farmId);
            if (guard is not null) return guard;

            m.FarmId = farmId;
            m.GenericProductId = id;
            await _products.UpdateAsync(m);
            return NoContent();
        }

        [HttpDelete("products/{id:int}")]
        public async Task<IActionResult> Delete(string farmId, int id)
        {
            var guard = await EnsureGenericFarm(farmId);
            if (guard is not null) return guard;

            await _products.DeleteAsync(id, farmId);
            return NoContent();
        }

        // ---------------------------------------------------------------------
        // Inventory reports
        // ---------------------------------------------------------------------
        [HttpGet("products/low-stock")]
        public async Task<ActionResult<IEnumerable<GenericProductLowStockRowModel>>> GetLowStock(string farmId)
        {
            var guard = await EnsureGenericFarm(farmId);
            if (guard is not null) return guard;
            return Ok(await _products.GetLowStockAsync(farmId));
        }

        // Recomputes Product.CurrentStock from SUM(StockMovements). Reserved
        // for the owner/admin if the cache ever drifts. No-op when everything
        // is in sync.
        [HttpPost("products/reconcile-stock")]
        public async Task<IActionResult> ReconcileStock(string farmId)
        {
            var guard = await EnsureGenericFarm(farmId);
            if (guard is not null) return guard;
            await _products.ReconcileStockAsync(farmId);
            return NoContent();
        }

        // ---------------------------------------------------------------------
        private async Task<ActionResult?> EnsureGenericFarm(string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var farmType = await _companies.GetFarmTypeAsync(farmId);
            if (farmType is null)
                return NotFound("Company not found.");
            if (!string.Equals(farmType, "Generic", StringComparison.OrdinalIgnoreCase))
                return Conflict($"This company is not a Generic company (current type: {farmType}).");
            return null;
        }
    }

    // =========================================================================
    // Services + service categories.
    // =========================================================================
    [ApiController]
    [Route("api/generic-company/{farmId}")]
    public class GenericServiceCatalogController : ControllerBase
    {
        private readonly IGenericServiceCatalogService _services;
        private readonly IGenericCompanyService _companies;

        public GenericServiceCatalogController(IGenericServiceCatalogService services, IGenericCompanyService companies)
        {
            _services = services;
            _companies = companies;
        }

        // ---------------------------------------------------------------------
        // Categories
        // ---------------------------------------------------------------------
        [HttpGet("service-categories")]
        public async Task<ActionResult<IEnumerable<GenericServiceCategoryModel>>> GetCategories(string farmId)
        {
            var guard = await EnsureGenericFarm(farmId);
            if (guard is not null) return guard;
            return Ok(await _services.GetCategoriesAsync(farmId));
        }

        [HttpPost("service-categories")]
        public async Task<ActionResult<GenericServiceCategoryModel>> CreateCategory(string farmId, [FromBody] GenericServiceCategoryModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await EnsureGenericFarm(farmId);
            if (guard is not null) return guard;

            m.FarmId = farmId;
            m.GenericServiceCategoryId = await _services.InsertCategoryAsync(m);
            return CreatedAtAction(nameof(GetCategories), new { farmId }, m);
        }

        [HttpPut("service-categories/{id:int}")]
        public async Task<IActionResult> UpdateCategory(string farmId, int id, [FromBody] GenericServiceCategoryModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await EnsureGenericFarm(farmId);
            if (guard is not null) return guard;

            m.FarmId = farmId;
            m.GenericServiceCategoryId = id;
            await _services.UpdateCategoryAsync(m);
            return NoContent();
        }

        [HttpDelete("service-categories/{id:int}")]
        public async Task<IActionResult> DeleteCategory(string farmId, int id)
        {
            var guard = await EnsureGenericFarm(farmId);
            if (guard is not null) return guard;
            await _services.DeleteCategoryAsync(id, farmId);
            return NoContent();
        }

        // ---------------------------------------------------------------------
        // Services
        // ---------------------------------------------------------------------
        [HttpGet("services")]
        public async Task<ActionResult<IEnumerable<GenericServiceModel>>> GetAll(string farmId)
        {
            var guard = await EnsureGenericFarm(farmId);
            if (guard is not null) return guard;
            return Ok(await _services.GetAllAsync(farmId));
        }

        [HttpGet("services/{id:int}")]
        public async Task<ActionResult<GenericServiceModel>> GetById(string farmId, int id)
        {
            var guard = await EnsureGenericFarm(farmId);
            if (guard is not null) return guard;

            var s = await _services.GetByIdAsync(id, farmId);
            return s is null ? NotFound() : Ok(s);
        }

        [HttpPost("services")]
        public async Task<ActionResult<GenericServiceModel>> Create(string farmId, [FromBody] GenericServiceModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await EnsureGenericFarm(farmId);
            if (guard is not null) return guard;

            m.FarmId = farmId;
            var newId = await _services.InsertAsync(m);
            var created = await _services.GetByIdAsync(newId, farmId);
            return CreatedAtAction(nameof(GetById), new { farmId, id = newId }, created);
        }

        [HttpPut("services/{id:int}")]
        public async Task<IActionResult> Update(string farmId, int id, [FromBody] GenericServiceModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await EnsureGenericFarm(farmId);
            if (guard is not null) return guard;

            m.FarmId = farmId;
            m.GenericServiceId = id;
            await _services.UpdateAsync(m);
            return NoContent();
        }

        [HttpDelete("services/{id:int}")]
        public async Task<IActionResult> Delete(string farmId, int id)
        {
            var guard = await EnsureGenericFarm(farmId);
            if (guard is not null) return guard;
            await _services.DeleteAsync(id, farmId);
            return NoContent();
        }

        // ---------------------------------------------------------------------
        private async Task<ActionResult?> EnsureGenericFarm(string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var farmType = await _companies.GetFarmTypeAsync(farmId);
            if (farmType is null)
                return NotFound("Company not found.");
            if (!string.Equals(farmType, "Generic", StringComparison.OrdinalIgnoreCase))
                return Conflict($"This company is not a Generic company (current type: {farmType}).");
            return null;
        }
    }

    // =========================================================================
    // Inventory: stock movements (read), stock adjustments (full CRUD +
    // approval workflow).
    // =========================================================================
    [ApiController]
    [Route("api/generic-company/{farmId}/inventory")]
    public class GenericInventoryController : ControllerBase
    {
        private readonly IGenericInventoryService _inv;
        private readonly IGenericCompanyService _companies;

        public GenericInventoryController(IGenericInventoryService inv, IGenericCompanyService companies)
        {
            _inv = inv;
            _companies = companies;
        }

        // ---------------------------------------------------------------------
        // Stock movements (read-only here)
        // ---------------------------------------------------------------------
        [HttpGet("movements")]
        public async Task<ActionResult<IEnumerable<GenericStockMovementModel>>> GetMovements(
            string farmId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
        {
            var guard = await EnsureGenericFarm(farmId);
            if (guard is not null) return guard;
            return Ok(await _inv.GetMovementsForFarmAsync(farmId, fromDate, toDate));
        }

        [HttpGet("products/{productId:int}/movements")]
        public async Task<ActionResult<IEnumerable<GenericStockMovementModel>>> GetMovementsForProduct(string farmId, int productId)
        {
            var guard = await EnsureGenericFarm(farmId);
            if (guard is not null) return guard;
            return Ok(await _inv.GetMovementsForProductAsync(productId, farmId));
        }

        // ---------------------------------------------------------------------
        // Stock adjustments (Draft → Submitted → Approved/Rejected)
        // ---------------------------------------------------------------------
        [HttpGet("adjustments")]
        public async Task<ActionResult<IEnumerable<GenericStockAdjustmentModel>>> GetAdjustments(
            string farmId, [FromQuery] string? status)
        {
            var guard = await EnsureGenericFarm(farmId);
            if (guard is not null) return guard;
            return Ok(await _inv.GetAdjustmentsAsync(farmId, status));
        }

        [HttpGet("adjustments/{id:int}")]
        public async Task<ActionResult<GenericStockAdjustmentModel>> GetAdjustment(string farmId, int id)
        {
            var guard = await EnsureGenericFarm(farmId);
            if (guard is not null) return guard;

            var a = await _inv.GetAdjustmentByIdAsync(id, farmId);
            return a is null ? NotFound() : Ok(a);
        }

        [HttpPost("adjustments")]
        public async Task<ActionResult<GenericStockAdjustmentModel>> CreateAdjustment(
            string farmId, [FromBody] GenericStockAdjustmentModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await EnsureGenericFarm(farmId);
            if (guard is not null) return guard;

            if (m.AdjustmentType != GenericStockAdjustmentType.Increase &&
                m.AdjustmentType != GenericStockAdjustmentType.Decrease)
                return BadRequest("AdjustmentType must be Increase or Decrease.");

            m.FarmId = farmId;
            var newId = await _inv.InsertAdjustmentAsync(m);
            var created = await _inv.GetAdjustmentByIdAsync(newId, farmId);
            return CreatedAtAction(nameof(GetAdjustment), new { farmId, id = newId }, created);
        }

        [HttpPost("adjustments/{id:int}/submit")]
        public async Task<IActionResult> SubmitAdjustment(string farmId, int id)
        {
            var guard = await EnsureGenericFarm(farmId);
            if (guard is not null) return guard;

            await _inv.SubmitAdjustmentAsync(id, farmId);
            return NoContent();
        }

        [HttpPost("adjustments/{id:int}/approve")]
        public async Task<IActionResult> ApproveAdjustment(string farmId, int id, [FromQuery] string? approvedBy)
        {
            var guard = await EnsureGenericFarm(farmId);
            if (guard is not null) return guard;

            await _inv.ApproveAdjustmentAsync(id, farmId, approvedBy);
            return NoContent();
        }

        [HttpPost("adjustments/{id:int}/reject")]
        public async Task<IActionResult> RejectAdjustment(
            string farmId, int id,
            [FromBody] GenericStockAdjustmentRejectRequest body,
            [FromQuery] string? approvedBy)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await EnsureGenericFarm(farmId);
            if (guard is not null) return guard;

            await _inv.RejectAdjustmentAsync(id, farmId, body.RejectionReason, approvedBy);
            return NoContent();
        }

        // ---------------------------------------------------------------------
        private async Task<ActionResult?> EnsureGenericFarm(string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var farmType = await _companies.GetFarmTypeAsync(farmId);
            if (farmType is null)
                return NotFound("Company not found.");
            if (!string.Equals(farmType, "Generic", StringComparison.OrdinalIgnoreCase))
                return Conflict($"This company is not a Generic company (current type: {farmType}).");
            return null;
        }
    }
}
