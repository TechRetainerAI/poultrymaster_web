using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Filters;
using PoultryFarmAPIWeb.Business;

namespace PoultryFarmAPIWeb.Controllers
{
    // Generic Deferred inventory cost (migration 452, Report 40 Part 6): the
    // Poultry/Water routes, read-only. The old per-product list
    // (api/generic-company/{farmId}/deferred-costs) is left as it was.
    [ApiController]
    [Route("api/Generic/deferred-inventory-costs")]
    [RequireCompanyType("Generic")]
    public class GenericDeferredInventoryCostController : ControllerBase
    {
        private readonly IGenericDeferredInventoryCostService _svc;
        public GenericDeferredInventoryCostController(IGenericDeferredInventoryCostService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<GenericDeferredResponse>> Get(
            [FromQuery] string farmId, [FromQuery] string? scope = "DEFERRED", [FromQuery] int? itemId = null,
            [FromQuery] int? supplierId = null, [FromQuery] string? category = null,
            [FromQuery] DateTime? fromDate = null, [FromQuery] DateTime? toDate = null, [FromQuery] string? search = null)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetAsync(farmId, scope, itemId, supplierId, category, fromDate, toDate, search));

        [HttpGet("{lotId:int}/history")]
        public async Task<ActionResult<List<GenericDeferredDraw>>> GetHistory(int lotId, [FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetHistoryAsync(farmId, lotId));
    }
}
