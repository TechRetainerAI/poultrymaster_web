// Hotel supply purchases, Internal Use and Deferred inventory cost (migration 334).
//
//   /api/Hotel/supplies/purchases ...           purchases that carry a cost, and their reversal
//   /api/Hotel/supplies/cost-recognition        per-category "Expense when purchased / consumed"
//   /api/Hotel/deferred-inventory-costs ...     the read-only Deferred inventory cost page
//   /api/Hotel/internal-usage ...               Internal Use: Draft -> Posted -> Reversed
//
// Every action checks the caller's JWT company; the acting user comes from the
// token; refusals come back as 400 with the database's sentence.

using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Filters;
using PoultryFarmAPIWeb.Helpers;

namespace PoultryFarmAPIWeb.Controllers
{
    public class HotelSupplyPurchaseRequest : HotelSupplyPurchaseInput { public string FarmId { get; set; } = ""; }
    public class HotelSupplyReasonRequest { public string FarmId { get; set; } = ""; public string? Reason { get; set; } }
    public class HotelSupplyCostModeRequest { public string FarmId { get; set; } = ""; public string Category { get; set; } = ""; public string CostMode { get; set; } = ""; }
    public class HotelInternalUseRequest : HotelInternalUseInput { public string FarmId { get; set; } = ""; }

    [ApiController][Authorize][Route("api/Hotel")][HotelBusinessRuleFilter]
    public class HotelSuppliesController : ControllerBase
    {
        private readonly IHotelSuppliesService _svc;
        public HotelSuppliesController(IHotelSuppliesService svc) { _svc = svc; }

        private string By => HotelAuthHelper.GetUserName(User);
        private IActionResult? Deny(string? farmId) =>
            string.IsNullOrWhiteSpace(farmId) ? BadRequest(new { message = "Company ID is required." }) : HotelAuthHelper.VerifyFarmOwnership(User, farmId);

        // ---- purchases --------------------------------------------------------
        [HttpGet("supplies/purchases")]
        public async Task<IActionResult> Purchases([FromQuery] string farmId, [FromQuery] DateTime? from, [FromQuery] DateTime? to,
            [FromQuery] int? supplierId, [FromQuery] int? itemId, [FromQuery] int? purchaseId)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.PurchasesAsync(farmId, from, to, supplierId, itemId, purchaseId)); }

        /// <summary>Adds stock, a cost lot, the cash paid now and the supplier balance, in one transaction.</summary>
        [HttpPost("supplies/purchases")]
        public async Task<IActionResult> CreatePurchase([FromBody] HotelSupplyPurchaseRequest r)
        { var d = Deny(r.FarmId); if (d != null) return d; return Ok(new { purchaseId = await _svc.CreatePurchaseAsync(r.FarmId, r, By) }); }

        [HttpPost("supplies/purchases/{id:int}/reverse")]
        public async Task<IActionResult> ReversePurchase(int id, [FromBody] HotelSupplyReasonRequest r)
        {
            var d = Deny(r.FarmId); if (d != null) return d;
            if (string.IsNullOrWhiteSpace(r.Reason)) return BadRequest(new { message = "A reason is required to reverse a purchase." });
            await _svc.ReversePurchaseAsync(r.FarmId, id, r.Reason, By); return Ok();
        }

        [HttpGet("supplies/cost-recognition")]
        public async Task<IActionResult> CostModes([FromQuery] string farmId)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.CostModesAsync(farmId)); }

        [HttpPut("supplies/cost-recognition")]
        public async Task<IActionResult> SetCostMode([FromBody] HotelSupplyCostModeRequest r)
        { var d = Deny(r.FarmId); if (d != null) return d; await _svc.SetCostModeAsync(r.FarmId, r.Category, r.CostMode, By); return Ok(); }

        // ---- deferred inventory cost ------------------------------------------
        [HttpGet("deferred-inventory-costs")]
        public async Task<IActionResult> Deferred([FromQuery] string farmId, [FromQuery] string? scope, [FromQuery] int? itemId,
            [FromQuery] int? supplierId, [FromQuery] string? category, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate,
            [FromQuery] string? search)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.DeferredAsync(farmId, scope, itemId, supplierId, category, fromDate, toDate, search)); }

        [HttpGet("deferred-inventory-costs/{purchaseId:int}/history")]
        public async Task<IActionResult> DeferredHistory(int purchaseId, [FromQuery] string farmId)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.DeferredHistoryAsync(farmId, purchaseId)); }

        // ---- internal use -----------------------------------------------------
        [HttpGet("internal-usage")]
        public async Task<IActionResult> InternalUse([FromQuery] string farmId)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.InternalUseListAsync(farmId)); }

        [HttpGet("internal-usage/items")]
        public async Task<IActionResult> InternalUseItems([FromQuery] string farmId)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.InternalUseItemsAsync(farmId)); }

        [HttpGet("internal-usage/{id:int}")]
        public async Task<IActionResult> InternalUseOne(int id, [FromQuery] string farmId)
        {
            var d = Deny(farmId); if (d != null) return d;
            var row = await _svc.InternalUseGetAsync(farmId, id);
            return row == null ? NotFound(new { message = "Internal use record not found." }) : Ok(row);
        }

        [HttpPost("internal-usage")]
        public async Task<IActionResult> InternalUseCreate([FromBody] HotelInternalUseRequest r)
        {
            var d = Deny(r.FarmId); if (d != null) return d;
            var id = await _svc.InternalUseCreateAsync(r.FarmId, r, By);
            return Ok(await _svc.InternalUseGetAsync(r.FarmId, id));
        }

        [HttpPut("internal-usage/{id:int}")]
        public async Task<IActionResult> InternalUseUpdate(int id, [FromBody] HotelInternalUseRequest r)
        {
            var d = Deny(r.FarmId); if (d != null) return d;
            await _svc.InternalUseUpdateAsync(r.FarmId, id, r, By);
            return Ok(await _svc.InternalUseGetAsync(r.FarmId, id));
        }

        [HttpDelete("internal-usage/{id:int}")]
        public async Task<IActionResult> InternalUseDelete(int id, [FromQuery] string farmId)
        { var d = Deny(farmId); if (d != null) return d; await _svc.InternalUseDeleteAsync(farmId, id, By); return NoContent(); }

        /// <summary>Takes the stock out through the cost lots; non-cash.</summary>
        [HttpPost("internal-usage/{id:int}/post")]
        public async Task<IActionResult> InternalUsePost(int id, [FromQuery] string farmId)
        {
            var d = Deny(farmId); if (d != null) return d;
            await _svc.InternalUsePostAsync(farmId, id, By);
            return Ok(await _svc.InternalUseGetAsync(farmId, id));
        }

        [HttpPost("internal-usage/{id:int}/reverse")]
        public async Task<IActionResult> InternalUseReverse(int id, [FromBody] HotelSupplyReasonRequest r)
        {
            var d = Deny(r.FarmId); if (d != null) return d;
            if (string.IsNullOrWhiteSpace(r.Reason)) return BadRequest(new { message = "A reason is required to reverse this internal use." });
            await _svc.InternalUseReverseAsync(r.FarmId, id, r.Reason, By);
            return Ok(await _svc.InternalUseGetAsync(r.FarmId, id));
        }
    }
}
