using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // Feed Production module controllers. Routes under /api/Poultry/* — reached
    // via the frontend same-origin proxy. Writes auto-audit via the global
    // AuditLogActionFilter. Farm scoping is enforced by @FarmId in every SP.

    [ApiController]
    [Route("api/Poultry/feed-formulas")]
    public class PoultryFeedFormulaController : ControllerBase
    {
        private readonly IPoultryFeedFormulaService _svc;
        public PoultryFeedFormulaController(IPoultryFeedFormulaService svc) => _svc = svc;

        [HttpGet] public async Task<ActionResult<IEnumerable<PoultryFeedFormulaModel>>> GetAll([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetAllAsync(farmId));

        [HttpGet("{id:int}")] public async Task<ActionResult<PoultryFeedFormulaModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var m = await _svc.GetByIdAsync(farmId, id);
            return m is null ? NotFound() : Ok(m);
        }

        [HttpPost] public async Task<ActionResult<object>> Upsert([FromBody] PoultryFeedFormulaUpsertRequest req)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required.");
            if (req.FinishedFeedItemId <= 0) return BadRequest("A finished feed item is required.");
            var id = await _svc.UpsertAsync(req);
            return Ok(new { PoultryFeedFormulaId = id });
        }

        [HttpDelete("{id:int}")] public async Task<IActionResult> Delete(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.DeleteAsync(farmId, id);
            return NoContent();
        }
    }

    [ApiController]
    [Route("api/Poultry/feed-production")]
    public class PoultryFeedProductionBatchController : ControllerBase
    {
        private readonly IPoultryFeedProductionBatchService _svc;
        public PoultryFeedProductionBatchController(IPoultryFeedProductionBatchService svc) => _svc = svc;

        [HttpGet] public async Task<ActionResult<IEnumerable<PoultryFeedProductionBatchModel>>> GetAll(
            [FromQuery] string farmId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate, [FromQuery] string? status)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetAllAsync(farmId, fromDate, toDate, status));

        [HttpGet("items")] public async Task<ActionResult<IEnumerable<PoultryFeedProductionBatchItemModel>>> GetBatchItems([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetBatchItemsAsync(farmId));

        [HttpGet("reports/ingredient-usage")] public async Task<ActionResult<IEnumerable<PoultryFeedIngredientUsageRow>>> IngredientUsage(
            [FromQuery] string farmId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetIngredientUsageReportAsync(farmId, fromDate, toDate));

        [HttpGet("{id:int}/traceability")] public async Task<ActionResult<IEnumerable<PoultryFeedTraceabilityRow>>> Traceability(int id, [FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetTraceabilityAsync(farmId, id));

        [HttpGet("{id:int}")] public async Task<ActionResult<PoultryFeedProductionBatchModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var m = await _svc.GetByIdAsync(farmId, id);
            return m is null ? NotFound() : Ok(m);
        }

        [HttpPost] public async Task<ActionResult<object>> Save([FromBody] PoultryFeedProductionBatchSaveRequest req)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required.");
            if (req.FinishedFeedItemId <= 0) return BadRequest("A finished feed item is required.");
            if (req.QuantityProduced <= 0) return BadRequest("Quantity produced must be greater than zero.");
            var id = await _svc.SaveAsync(req);
            var saved = await _svc.GetByIdAsync(req.FarmId, id);
            return Ok(saved);
        }

        [HttpDelete("{id:int}")] public async Task<IActionResult> Delete(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.DeleteAsync(farmId, id);
            return NoContent();
        }

        [HttpPost("{id:int}/post")] public async Task<ActionResult<PoultryFeedProductionBatchModel>> Post(int id, [FromBody] PoultryFeedProductionActionRequest req)
        {
            if (req is null || string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required.");
            await _svc.PostAsync(req.FarmId, id, req.UserId);
            var saved = await _svc.GetByIdAsync(req.FarmId, id);
            return saved is null ? NotFound() : Ok(saved);
        }

        [HttpPost("{id:int}/reverse")] public async Task<ActionResult<PoultryFeedProductionBatchModel>> Reverse(int id, [FromBody] PoultryFeedProductionActionRequest req)
        {
            if (req is null || string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required.");
            await _svc.ReverseAsync(req.FarmId, id, req.UserId, req.ReversalReason);
            var saved = await _svc.GetByIdAsync(req.FarmId, id);
            return saved is null ? NotFound() : Ok(saved);
        }
    }
}
