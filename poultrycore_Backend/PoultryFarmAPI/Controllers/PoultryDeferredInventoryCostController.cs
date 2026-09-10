// Poultry deferred inventory costs (migration 288).
//
// Three GETs, all read-only, and deliberately so: what has reached Profit & Loss
// is DERIVED from the cost layers and their allocations. An endpoint here that
// could "adjust" a recognised figure would be a second source of truth, and the
// first thing it would do is disagree with the P&L.
//
// Recognition itself happens where consumption happens -- inside
// sppoultryproductionrawmaterialsync (266) -- not on this rail.

using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/Poultry/deferred-inventory-costs")]
    public class PoultryDeferredInventoryCostController : ControllerBase
    {
        private readonly IPoultryDeferredInventoryCostService _svc;
        public PoultryDeferredInventoryCostController(IPoultryDeferredInventoryCostService svc) => _svc = svc;

        /// <summary>
        /// Inventory purchases and where their cost has got to, with the summary
        /// cards for the same filter.
        /// </summary>
        /// <param name="scope">
        /// DEFERRED (default) cost still waiting; RECOGNIZED lots that were
        /// deferred and are now fully expensed; EXCEPTION only rows that need
        /// looking at; ALL every purchase however it was recognised.
        /// </param>
        [HttpGet]
        public async Task<ActionResult<PoultryDeferredCostResponse>> Get(
            [FromQuery] string farmId,
            [FromQuery] string? scope = "DEFERRED",
            [FromQuery] int? itemId = null,
            [FromQuery] int? supplierId = null,
            [FromQuery] string? category = null,
            [FromQuery] DateTime? fromDate = null,
            [FromQuery] DateTime? toDate = null,
            [FromQuery] string? search = null)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetAsync(farmId, scope, itemId, supplierId, category, fromDate, toDate, search));

        /// <summary>
        /// Every usage that drew on one purchase lot: quantity taken, the unit
        /// cost it was taken at, and what of it reached Profit &amp; Loss.
        /// An empty list means nothing has drawn on the lot yet.
        /// </summary>
        [HttpGet("{purchaseId:int}/history")]
        public async Task<ActionResult<List<PoultryDeferredRecognitionModel>>> GetHistory(
            int purchaseId, [FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetHistoryAsync(farmId, purchaseId));

        /// <summary>
        /// The other direction: how ONE production record's consumption cost was
        /// arrived at, lot by lot. This is what "View cost breakdown" shows on a
        /// production record and on the expense it generated.
        /// </summary>
        [HttpGet("breakdown/{productionRecordId:int}")]
        public async Task<ActionResult<List<PoultryConsumptionCostLayerModel>>> GetBreakdown(
            int productionRecordId, [FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetCostBreakdownAsync(farmId, productionRecordId));
    }
}
