// Water deferred inventory costs (migration 281).
//
// Three GETs, all read-only, and deliberately so: what has reached Profit & Loss
// is DERIVED from the cost layers and their allocations. An endpoint here that
// could "adjust" a recognised figure would be a second source of truth, and the
// first thing it would do is disagree with the P&L.
//
// Recognition itself happens where consumption happens -- inside the water
// consumption rail -- not on this rail.
//
// The breakdown is keyed on a WATER PRODUCTION BATCH rather than a production
// record: water has no production records and no flocks, and the batch is the
// thing that consumed the stock.

using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/Water/deferred-inventory-costs")]
    public class WaterDeferredInventoryCostController : ControllerBase
    {
        private readonly IWaterDeferredInventoryCostService _svc;
        public WaterDeferredInventoryCostController(IWaterDeferredInventoryCostService svc) => _svc = svc;

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
        public async Task<ActionResult<WaterDeferredCostResponse>> Get(
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
        public async Task<ActionResult<List<WaterDeferredRecognitionModel>>> GetHistory(
            int purchaseId, [FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetHistoryAsync(farmId, purchaseId));

        /// <summary>
        /// The other direction: how ONE production batch's consumption cost was
        /// arrived at, lot by lot. This is what "View cost breakdown" shows on a
        /// production batch and on the expense it generated.
        /// </summary>
        [HttpGet("breakdown/{productionBatchId:int}")]
        public async Task<ActionResult<List<WaterConsumptionCostLayerModel>>> GetBreakdown(
            int productionBatchId, [FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetCostBreakdownAsync(farmId, productionBatchId));
    }
}
