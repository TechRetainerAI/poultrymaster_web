// Poultry financial settings (migration 261).
//
// Setup -> Financial Settings -> Cost Recognition. Two independent choices,
// feed and medication, plus an optional forward-dated activation.
//
// Flat per-resource [Route] with FarmId on the query string, matching the
// convention the frontend already expects.

using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/Poultry/financial-settings")]
    public class PoultryFinancialSettingsController : ControllerBase
    {
        private readonly IPoultryFinancialSettingsService _svc;
        public PoultryFinancialSettingsController(IPoultryFinancialSettingsService svc) => _svc = svc;

        /// <summary>
        /// A farm that has never chosen reads back as today's behaviour with
        /// isConfigured = false, rather than 404. The page needs to render
        /// either way, and "not configured" is a state, not an error.
        /// </summary>
        [HttpGet("cost-recognition")]
        public async Task<ActionResult<PoultryFinancialSettingsModel>> Get([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetAsync(farmId));

        /// <summary>
        /// Both methods are written together because the page presents them
        /// together; sending one without the other would make "unchanged" and
        /// "reset to default" indistinguishable.
        ///
        /// The response carries previousFeedMethod / previousMedicationMethod so
        /// the audit trail records what actually changed. The SP refuses an
        /// effective date in the past.
        /// </summary>
        [HttpPut("cost-recognition")]
        public async Task<ActionResult<PoultryFinancialSettingsModel>> Update(
            [FromQuery] string farmId, [FromBody] PoultryFinancialSettingsUpdateRequest body)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            // The query string wins, matching every other write on this rail: the
            // active company is context, not something a request body may claim.
            if (!string.IsNullOrWhiteSpace(farmId)) body.FarmId = farmId;
            if (string.IsNullOrWhiteSpace(body.FarmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.UpsertAsync(body));
        }
    }
}
