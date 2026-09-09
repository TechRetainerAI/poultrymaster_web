// Water financial settings (migration 274).
//
// Setup -> Financial Settings -> Cost Recognition. Two independent choices,
// packaging and treatment, plus an optional forward-dated activation, and the
// per-item overrides that sit under them.
//
// Flat per-resource [Route] with FarmId on the query string, matching the
// convention the frontend already expects.

using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/Water/financial-settings")]
    public class WaterFinancialSettingsController : ControllerBase
    {
        private readonly IWaterFinancialSettingsService _svc;
        public WaterFinancialSettingsController(IWaterFinancialSettingsService svc) => _svc = svc;

        /// <summary>
        /// A company that has never chosen reads back as today's behaviour with
        /// isConfigured = false, rather than 404. The page needs to render
        /// either way, and "not configured" is a state, not an error.
        /// </summary>
        [HttpGet("cost-recognition")]
        public async Task<ActionResult<WaterFinancialSettingsModel>> Get([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetAsync(farmId));

        /// <summary>
        /// Both methods are written together because the page presents them
        /// together; sending one without the other would make "unchanged" and
        /// "reset to default" indistinguishable.
        ///
        /// The response carries previousPackagingMethod / previousTreatmentMethod
        /// so the audit trail records what actually changed. The SP refuses an
        /// effective date in the past.
        /// </summary>
        [HttpPut("cost-recognition")]
        public async Task<ActionResult<WaterFinancialSettingsModel>> Update(
            [FromQuery] string farmId, [FromBody] WaterFinancialSettingsUpdateRequest body)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            // The query string wins, matching every other write on this rail: the
            // active company is context, not something a request body may claim.
            if (!string.IsNullOrWhiteSpace(farmId)) body.FarmId = farmId;
            if (string.IsNullOrWhiteSpace(body.FarmId)) return BadRequest("Company ID is required.");

            try { return Ok(await _svc.UpsertAsync(body)); }
            // The SP raises for a backdated activation and for an unknown method.
            // Both are the user's mistake, not a server fault, so they come back
            // as 400 with the SP's own wording rather than a 500.
            catch (Npgsql.PostgresException ex) { return BadRequest(ex.MessageText); }
        }

        /// <summary>
        /// Every raw-material item with its resolved treatment.
        ///
        /// A separate read from the item list on purpose: 274 does not rewrite
        /// spwaterrawmaterialitem_getall, so the resolution is its own SP. The
        /// settings page joins the two by id.
        /// </summary>
        [HttpGet("items")]
        public async Task<ActionResult<List<WaterItemCostRecognitionModel>>> GetItems([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetItemsAsync(farmId));

        /// <summary>
        /// Sets or clears one item's override. Sending "USE_DEFAULT" or null
        /// clears it and returns the item to the company default.
        ///
        /// PUT rather than PATCH because the whole override is replaced: there is
        /// exactly one field and no partial state to merge.
        /// </summary>
        [HttpPut("items/{itemId:int}/cost-recognition")]
        public async Task<ActionResult<WaterItemCostRecognitionModel>> SetItemOverride(
            int itemId, [FromQuery] string farmId, [FromBody] WaterItemCostRecognitionUpdateRequest body)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (!string.IsNullOrWhiteSpace(farmId)) body.FarmId = farmId;
            if (string.IsNullOrWhiteSpace(body.FarmId)) return BadRequest("Company ID is required.");

            try
            {
                var row = await _svc.SetItemOverrideAsync(itemId, body);
                // The SP raises when the item belongs to another company, so a
                // null here means it returned no row for a reason it did not
                // consider an error. Treated as not found rather than 500.
                return row is null ? NotFound("Raw material item not found for this company.") : Ok(row);
            }
            catch (Npgsql.PostgresException ex) { return BadRequest(ex.MessageText); }
        }
    }
}
