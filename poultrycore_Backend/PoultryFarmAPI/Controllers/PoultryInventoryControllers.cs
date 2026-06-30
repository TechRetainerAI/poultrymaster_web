using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // Poultry raw materials + inventory (mirrors the Water raw-material controllers).
    // Routes under /api/Poultry/* — reached via the frontend same-origin proxy.

    [ApiController]
    [Route("api/Poultry/raw-material-items")]
    public class PoultryRawMaterialItemController : ControllerBase
    {
        private readonly IPoultryRawMaterialItemService _svc;
        public PoultryRawMaterialItemController(IPoultryRawMaterialItemService svc) => _svc = svc;

        [HttpGet] public async Task<ActionResult<IEnumerable<PoultryRawMaterialItemModel>>> GetAll([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetAllAsync(farmId));

        [HttpGet("{id:int}")] public async Task<ActionResult<PoultryRawMaterialItemModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var m = await _svc.GetByIdAsync(id, farmId);
            return m is null ? NotFound() : Ok(m);
        }

        [HttpGet("low-stock")] public async Task<ActionResult<IEnumerable<PoultryRawMaterialItemModel>>> GetLowStock([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetLowStockAsync(farmId));

        [HttpPost] public async Task<ActionResult<PoultryRawMaterialItemModel>> Create([FromBody] PoultryRawMaterialItemModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.InsertAsync(m);
            var created = await _svc.GetByIdAsync(id, m.FarmId);
            return CreatedAtAction(nameof(GetById), new { id, farmId = m.FarmId }, created);
        }

        [HttpPut("{id:int}")] public async Task<IActionResult> Update(int id, [FromBody] PoultryRawMaterialItemModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            m.PoultryRawMaterialItemId = id;
            await _svc.UpdateAsync(m);
            return NoContent();
        }

        [HttpDelete("{id:int}")] public async Task<IActionResult> Delete(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.DeleteAsync(id, farmId);
            return NoContent();
        }
    }

    [ApiController]
    [Route("api/Poultry/raw-material-purchases")]
    public class PoultryRawMaterialPurchaseController : ControllerBase
    {
        private readonly IPoultryRawMaterialPurchaseService _svc;
        public PoultryRawMaterialPurchaseController(IPoultryRawMaterialPurchaseService svc) => _svc = svc;

        [HttpGet] public async Task<ActionResult<IEnumerable<PoultryRawMaterialPurchaseModel>>> GetAll(
            [FromQuery] string farmId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetAllAsync(farmId, fromDate, toDate));

        [HttpPost] public async Task<ActionResult<int>> Create([FromBody] PoultryRawMaterialPurchaseModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.InsertAsync(m);
            return Ok(new { PoultryRawMaterialPurchaseId = id });
        }

        [HttpPut("{id:int}")] public async Task<IActionResult> Update(int id, [FromBody] PoultryRawMaterialPurchaseModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            m.PoultryRawMaterialPurchaseId = id;
            await _svc.UpdateAsync(m);
            return NoContent();
        }

        [HttpDelete("{id:int}")] public async Task<IActionResult> Delete(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.DeleteAsync(id, farmId);
            return NoContent();
        }

        [HttpPost("{id:int}/pay-balance")] public async Task<IActionResult> PayBalance(int id, [FromBody] PoultryPayBalanceRequest body)
        {
            if (body is null || string.IsNullOrWhiteSpace(body.FarmId)) return BadRequest("Company ID is required.");
            if (body.Amount <= 0) return BadRequest("Payment amount must be greater than 0.");
            var balance = await _svc.PayBalanceAsync(id, body.FarmId, body.Amount, body.PaymentMethod, body.PaymentDate, body.CreatedBy);
            return Ok(new { Balance = balance });
        }
    }

    [ApiController]
    [Route("api/Poultry/raw-material-usage")]
    public class PoultryRawMaterialUsageController : ControllerBase
    {
        private readonly IPoultryRawMaterialUsageService _svc;
        public PoultryRawMaterialUsageController(IPoultryRawMaterialUsageService svc) => _svc = svc;

        [HttpGet("history")] public async Task<ActionResult<IEnumerable<PoultryRawMaterialUsageModel>>> GetHistory(
            [FromQuery] string farmId, [FromQuery] int? itemId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetHistoryAsync(farmId, itemId, fromDate, toDate));
    }
}
