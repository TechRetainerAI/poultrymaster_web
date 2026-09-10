// Poultry inventory valuation (migrations 267, 268).
//
// One GET, three result sets: the farm summary, the per-item breakdown, and
// whatever the cost-layer audit has to say. Read-only -- there is no write on
// this rail, deliberately: a valuation is derived from the lots, and anything
// that could "correct" it here would be a second source of truth.

using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/Poultry/inventory-valuation")]
    public class PoultryInventoryValuationController : ControllerBase
    {
        private readonly IPoultryInventoryValuationService _svc;
        public PoultryInventoryValuationController(IPoultryInventoryValuationService svc) => _svc = svc;

        /// <summary>
        /// Stock valued twice: what it cost, and what of that has still to reach
        /// Profit &amp; Loss. A farm on expense-at-purchase reports a real
        /// operational value and a deferred value of zero -- that is correct, not
        /// an empty result.
        /// </summary>
        [HttpGet]
        public async Task<ActionResult<PoultryInventoryValuationResponse>> Get([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetAsync(farmId));
    }
}
