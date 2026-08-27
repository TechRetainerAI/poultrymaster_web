using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // =========================================================================
    // Water Internal Use (migration 212)
    //
    // Water convention, matching WaterDailyProductionController: farmId comes
    // from the query string on GET/DELETE and from the body on POST/PUT, and the
    // workflow verbs take it on the query string.
    //
    // Errors raised by the SPs ("Not enough Sachet Water: 240 in stock, 900
    // needed.") propagate deliberately — GlobalExceptionMiddleware turns a
    // PostgresException into structured JSON the frontend toasts verbatim.
    // =========================================================================
    [ApiController]
    [Route("api/Water/internal-usage")]
    public class WaterInternalUsageController : ControllerBase
    {
        private readonly IWaterInternalUsageService _svc;
        public WaterInternalUsageController(IWaterInternalUsageService svc) => _svc = svc;

        // Internal use records something that already happened, so it cannot be
        // dated forward. UTC day — the product's companies run on GMT+0.
        private static bool IsFutureDate(DateTime d) => d.Date > DateTime.UtcNow.Date;

        [HttpGet]
        public async Task<ActionResult<List<WaterInternalUsageModel>>> GetAll(
            [FromQuery] string farmId, [FromQuery] string? status, [FromQuery] string? category,
            [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetAllAsync(farmId, status, category, fromDate, toDate));
        }

        [HttpGet("{id:int}")]
        public async Task<ActionResult<WaterInternalUsageModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var found = await _svc.GetByIdAsync(id, farmId);
            return found is null ? NotFound() : Ok(found);
        }

        // Seeds the cost field in the form. The user may override it, and 0 is a
        // legitimate answer for a product with no costed inflow.
        [HttpGet("suggested-cost")]
        public async Task<ActionResult<SuggestedCostResponse>> SuggestedCost(
            [FromQuery] string farmId, [FromQuery] int waterProductId, [FromQuery] string? entryUnit)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            if (waterProductId <= 0) return BadRequest("Pick a product first.");
            var cost = await _svc.GetSuggestedCostAsync(farmId, waterProductId, entryUnit);
            return Ok(new SuggestedCostResponse { WaterProductId = waterProductId, UnitCost = cost });
        }

        [HttpPost]
        public async Task<ActionResult<WaterInternalUsageModel>> Create([FromBody] WaterInternalUsageModel m)
        {
            var bad = Validate(m);
            if (bad is not null) return BadRequest(bad);

            m.CreatedBy ??= m.UserId;
            var id = await _svc.InsertAsync(m);
            var saved = await _svc.GetByIdAsync(id, m.FarmId);
            return CreatedAtAction(nameof(GetById), new { id, farmId = m.FarmId }, saved);
        }

        [HttpPut("{id:int}")]
        public async Task<IActionResult> Update(int id, [FromBody] WaterInternalUsageModel m)
        {
            var bad = Validate(m);
            if (bad is not null) return BadRequest(bad);
            if (id != m.WaterInternalUsageId) return BadRequest("Route id and body id do not match.");

            await _svc.UpdateAsync(m);
            return NoContent();
        }

        [HttpDelete("{id:int}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string farmId, [FromQuery] string? userId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.DeleteAsync(id, farmId, userId);
            return NoContent();
        }

        [HttpPost("{id:int}/post")]
        public async Task<ActionResult<WaterInternalUsageModel>> Post(
            int id, [FromQuery] string farmId, [FromQuery] string? postedBy)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.PostAsync(id, farmId, postedBy);
            return Ok(await _svc.GetByIdAsync(id, farmId));
        }

        [HttpPost("{id:int}/reverse")]
        public async Task<ActionResult<WaterInternalUsageModel>> Reverse(
            int id, [FromQuery] string farmId, [FromQuery] string? reversedBy,
            [FromBody] InternalUsageActionRequest? req)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.ReverseAsync(id, farmId, req?.Reason, reversedBy ?? req?.UserId);
            return Ok(await _svc.GetByIdAsync(id, farmId));
        }

        private static string? Validate(WaterInternalUsageModel? m)
        {
            if (m is null || string.IsNullOrWhiteSpace(m.FarmId)) return "Company ID is required.";
            if (!InternalUseCategories.IsValid(m.Category))
                return "Pick what the stock was used for.";
            if (IsFutureDate(m.UsageDate)) return "The date cannot be in the future.";
            if (m.Items is null || m.Items.Count == 0)
                return "Add at least one product.";
            if (m.Items.Exists(i => i.WaterProductId <= 0))
                return "Every line needs a product.";
            if (m.Items.Exists(i => i.EntryQuantity <= 0))
                return "Every line needs a quantity greater than zero.";
            if (m.StaffCount is <= 0) return "Staff count must be greater than zero.";
            return null;
        }
    }

    // =========================================================================
    // Poultry Internal Use (migration 216)
    //
    // Same shape as the water controller. Poultry uses the same query-string
    // farmId convention.
    // =========================================================================
    [ApiController]
    [Route("api/Poultry/internal-usage")]
    public class PoultryInternalUsageController : ControllerBase
    {
        private readonly IPoultryInternalUsageService _svc;
        public PoultryInternalUsageController(IPoultryInternalUsageService svc) => _svc = svc;

        private static bool IsFutureDate(DateTime d) => d.Date > DateTime.UtcNow.Date;

        [HttpGet]
        public async Task<ActionResult<List<PoultryInternalUsageModel>>> GetAll(
            [FromQuery] string farmId, [FromQuery] string? status, [FromQuery] string? category,
            [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetAllAsync(farmId, status, category, fromDate, toDate));
        }

        [HttpGet("{id:int}")]
        public async Task<ActionResult<PoultryInternalUsageModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var found = await _svc.GetByIdAsync(id, farmId);
            return found is null ? NotFound() : Ok(found);
        }

        [HttpGet("suggested-cost")]
        public async Task<ActionResult<object>> SuggestedCost(
            [FromQuery] string farmId, [FromQuery] int poultryProductId, [FromQuery] string? entryUnit)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            if (poultryProductId <= 0) return BadRequest("Pick a product first.");
            var cost = await _svc.GetSuggestedCostAsync(farmId, poultryProductId, entryUnit);
            return Ok(new { poultryProductId, unitCost = cost });
        }

        [HttpPost]
        public async Task<ActionResult<PoultryInternalUsageModel>> Create([FromBody] PoultryInternalUsageModel m)
        {
            var bad = Validate(m);
            if (bad is not null) return BadRequest(bad);

            m.CreatedBy ??= m.UserId;
            var id = await _svc.InsertAsync(m);
            var saved = await _svc.GetByIdAsync(id, m.FarmId);
            return CreatedAtAction(nameof(GetById), new { id, farmId = m.FarmId }, saved);
        }

        [HttpPut("{id:int}")]
        public async Task<IActionResult> Update(int id, [FromBody] PoultryInternalUsageModel m)
        {
            var bad = Validate(m);
            if (bad is not null) return BadRequest(bad);
            if (id != m.PoultryInternalUsageId) return BadRequest("Route id and body id do not match.");

            await _svc.UpdateAsync(m);
            return NoContent();
        }

        [HttpDelete("{id:int}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string farmId, [FromQuery] string? userId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.DeleteAsync(id, farmId, userId);
            return NoContent();
        }

        [HttpPost("{id:int}/post")]
        public async Task<ActionResult<PoultryInternalUsageModel>> Post(
            int id, [FromQuery] string farmId, [FromQuery] string? postedBy)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.PostAsync(id, farmId, postedBy);
            return Ok(await _svc.GetByIdAsync(id, farmId));
        }

        [HttpPost("{id:int}/reverse")]
        public async Task<ActionResult<PoultryInternalUsageModel>> Reverse(
            int id, [FromQuery] string farmId, [FromQuery] string? reversedBy,
            [FromBody] InternalUsageActionRequest? req)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.ReverseAsync(id, farmId, req?.Reason, reversedBy ?? req?.UserId);
            return Ok(await _svc.GetByIdAsync(id, farmId));
        }

        private static string? Validate(PoultryInternalUsageModel? m)
        {
            if (m is null || string.IsNullOrWhiteSpace(m.FarmId)) return "Company ID is required.";
            if (!InternalUseCategories.IsValid(m.Category))
                return "Pick what the stock was used for.";
            if (IsFutureDate(m.UsageDate)) return "The date cannot be in the future.";
            if (m.Items is null || m.Items.Count == 0)
                return "Add at least one product.";
            if (m.Items.Exists(i => i.PoultryProductId <= 0))
                return "Every line needs a product.";
            if (m.Items.Exists(i => i.EntryQuantity <= 0))
                return "Every line needs a quantity greater than zero.";
            if (m.StaffCount is <= 0) return "Staff count must be greater than zero.";
            return null;
        }
    }

    // =========================================================================
    // Generic Internal Use (migration 217)
    //
    // Same shape as the water and poultry controllers. Kept on the query-string
    // farmId convention rather than generic's usual /{farmId}/ path segment so
    // all three Internal Use controllers are callable identically.
    // =========================================================================
    [ApiController]
    [Route("api/generic-company/internal-usage")]
    public class GenericInternalUsageController : ControllerBase
    {
        private readonly IGenericInternalUsageService _svc;
        public GenericInternalUsageController(IGenericInternalUsageService svc) => _svc = svc;

        private static bool IsFutureDate(DateTime d) => d.Date > DateTime.UtcNow.Date;

        [HttpGet]
        public async Task<ActionResult<List<GenericInternalUsageModel>>> GetAll(
            [FromQuery] string farmId, [FromQuery] string? status, [FromQuery] string? category,
            [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetAllAsync(farmId, status, category, fromDate, toDate));
        }

        [HttpGet("{id:int}")]
        public async Task<ActionResult<GenericInternalUsageModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var found = await _svc.GetByIdAsync(id, farmId);
            return found is null ? NotFound() : Ok(found);
        }

        [HttpGet("suggested-cost")]
        public async Task<ActionResult<object>> SuggestedCost(
            [FromQuery] string farmId, [FromQuery] int genericProductId, [FromQuery] string? entryUnit)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            if (genericProductId <= 0) return BadRequest("Pick a product first.");
            var cost = await _svc.GetSuggestedCostAsync(farmId, genericProductId, entryUnit);
            return Ok(new { genericProductId, unitCost = cost });
        }

        [HttpPost]
        public async Task<ActionResult<GenericInternalUsageModel>> Create([FromBody] GenericInternalUsageModel m)
        {
            var bad = Validate(m);
            if (bad is not null) return BadRequest(bad);

            m.CreatedBy ??= m.UserId;
            var id = await _svc.InsertAsync(m);
            var saved = await _svc.GetByIdAsync(id, m.FarmId);
            return CreatedAtAction(nameof(GetById), new { id, farmId = m.FarmId }, saved);
        }

        [HttpPut("{id:int}")]
        public async Task<IActionResult> Update(int id, [FromBody] GenericInternalUsageModel m)
        {
            var bad = Validate(m);
            if (bad is not null) return BadRequest(bad);
            if (id != m.GenericInternalUsageId) return BadRequest("Route id and body id do not match.");

            await _svc.UpdateAsync(m);
            return NoContent();
        }

        [HttpDelete("{id:int}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string farmId, [FromQuery] string? userId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.DeleteAsync(id, farmId, userId);
            return NoContent();
        }

        [HttpPost("{id:int}/post")]
        public async Task<ActionResult<GenericInternalUsageModel>> Post(
            int id, [FromQuery] string farmId, [FromQuery] string? postedBy)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.PostAsync(id, farmId, postedBy);
            return Ok(await _svc.GetByIdAsync(id, farmId));
        }

        [HttpPost("{id:int}/reverse")]
        public async Task<ActionResult<GenericInternalUsageModel>> Reverse(
            int id, [FromQuery] string farmId, [FromQuery] string? reversedBy,
            [FromBody] InternalUsageActionRequest? req)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.ReverseAsync(id, farmId, req?.Reason, reversedBy ?? req?.UserId);
            return Ok(await _svc.GetByIdAsync(id, farmId));
        }

        private static string? Validate(GenericInternalUsageModel? m)
        {
            if (m is null || string.IsNullOrWhiteSpace(m.FarmId)) return "Company ID is required.";
            if (!InternalUseCategories.IsValid(m.Category))
                return "Pick what the stock was used for.";
            if (IsFutureDate(m.UsageDate)) return "The date cannot be in the future.";
            if (m.Items is null || m.Items.Count == 0)
                return "Add at least one product.";
            if (m.Items.Exists(i => i.GenericProductId <= 0))
                return "Every line needs a product.";
            if (m.Items.Exists(i => i.EntryQuantity <= 0))
                return "Every line needs a quantity greater than zero.";
            if (m.StaffCount is <= 0) return "Staff count must be greater than zero.";
            return null;
        }
    }
}
