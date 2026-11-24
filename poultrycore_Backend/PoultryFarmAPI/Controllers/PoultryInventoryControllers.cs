using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Filters;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // Poultry raw materials + inventory (mirrors the Water raw-material controllers).
    // Routes under /api/Poultry/* — reached via the frontend same-origin proxy.

    [ApiController]
    [Route("api/Poultry/raw-material-items")]
    [RequireCompanyType("Poultry")]
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

        // Manual stock adjustment (increase/decrease) on a raw material / supply.
        // Side-effect-free: does not post to Expense or production usage.
        [HttpPost("{id:int}/adjust")] public async Task<ActionResult<object>> Adjust(int id, [FromBody] PoultryRawMaterialAdjustRequest body)
        {
            if (body is null || string.IsNullOrWhiteSpace(body.FarmId)) return BadRequest("Company ID is required.");
            if (body.Quantity == 0) return BadRequest("Adjustment quantity cannot be zero.");
            var current = await _svc.AdjustAsync(id, body);
            return Ok(new { CurrentQuantity = current });
        }

        // Recompute CurrentQuantity from purchases, usage and adjustments. Omit
        // itemId to recalculate every raw material / supply for the company.
        [HttpPost("recalculate-stock")] public async Task<ActionResult<IEnumerable<PoultryRawMaterialRecalcRow>>> RecalculateStock(
            [FromQuery] string farmId, [FromQuery] int? itemId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.RecalculateStockAsync(farmId, itemId));
    }

    [ApiController]
    [Route("api/Poultry/raw-material-adjustments")]
    [RequireCompanyType("Poultry")]
    public class PoultryRawMaterialAdjustmentController : ControllerBase
    {
        private readonly IPoultryRawMaterialItemService _svc;
        public PoultryRawMaterialAdjustmentController(IPoultryRawMaterialItemService svc) => _svc = svc;

        [HttpGet] public async Task<ActionResult<IEnumerable<PoultryRawMaterialAdjustmentModel>>> GetAll(
            [FromQuery] string farmId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetAdjustmentsAsync(farmId, fromDate, toDate));
    }

    [ApiController]
    [Route("api/Poultry/raw-material-purchases")]
    [RequireCompanyType("Poultry")]
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

        // 418. Purchases can no longer be deleted (web or mobile): reverse them.
        [HttpDelete("{id:int}")] public IActionResult Delete(int id, [FromQuery] string farmId)
            => BadRequest("Purchases can't be deleted. Reverse the purchase instead -- it stays in the list marked Reversed.");

        // GET {id}/reversal-preview?farmId=  -- 479: what reversing it would do.
        [HttpGet("{id:int}/reversal-preview")]
        public async Task<IActionResult> ReversalPreview(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest(new { message = "Company ID is required." });
            return Content(await _svc.GetReversalPreviewAsync(id, farmId), "application/json");
        }

        // GET {id}/reversal?farmId=  -- 479: the reversal of a reversed purchase.
        [HttpGet("{id:int}/reversal")]
        public async Task<IActionResult> Reversal(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest(new { message = "Company ID is required." });
            var json = await _svc.GetReversalAsync(id, farmId);
            return json is null ? NotFound(new { message = "This purchase has not been reversed." }) : Content(json, "application/json");
        }

        [HttpPost("{id:int}/reverse")] public async Task<IActionResult> Reverse(int id, [FromBody] PoultryRawMaterialPurchaseReverseRequest body)
        {
            if (body is null || string.IsNullOrWhiteSpace(body.FarmId)) return BadRequest("Company ID is required.");

            // 479: the sale reversal model -- reason code, money choices, stale check.
            if (body.ReasonCode is not null || body.PaymentHandling is not null)
            {
                if (string.IsNullOrWhiteSpace(body.ReasonCode) && string.IsNullOrWhiteSpace(body.Reason))
                    return BadRequest(new { message = "Give a reason for reversing this purchase." });
                // The person on the token, not whatever the body claims.
                body.UserId = User?.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value ?? body.UserId;
                try
                {
                    var reversalId = await _svc.ReverseWithPreviewAsync(id, body);
                    return Ok(new { purchaseReversalId = reversalId, reversal = await _svc.GetReversalAsync(id, body.FarmId) is string j
                                                                        ? System.Text.Json.JsonDocument.Parse(j).RootElement
                                                                        : (System.Text.Json.JsonElement?)null });
                }
                catch (SaleRuleException ex) when (ex.Stale)
                {
                    return Conflict(new { message = ex.Message, stale = true });
                }
                catch (SaleRuleException ex)
                {
                    return BadRequest(new { message = ex.Message });
                }
            }

            // 418: an old client (free-text reason only) -- refunds where it can.
            if (string.IsNullOrWhiteSpace(body.Reason)) return BadRequest("Give a reason for reversing this purchase.");
            await _svc.ReverseAsync(id, body.FarmId, body.Reason.Trim(), body.ReversedBy);
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
    [RequireCompanyType("Poultry")]
    public class PoultryRawMaterialUsageController : ControllerBase
    {
        private readonly IPoultryRawMaterialUsageService _svc;
        public PoultryRawMaterialUsageController(IPoultryRawMaterialUsageService svc) => _svc = svc;

        [HttpGet("history")] public async Task<ActionResult<IEnumerable<PoultryRawMaterialUsageModel>>> GetHistory(
            [FromQuery] string farmId, [FromQuery] int? itemId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetHistoryAsync(farmId, itemId, fromDate, toDate));
    }
}
