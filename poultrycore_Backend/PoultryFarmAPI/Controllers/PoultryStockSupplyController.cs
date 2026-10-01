// Days of supply (migration 337). Read-only except for the farm's thresholds.
// Mapped to poultry.raw-materials in IamPermissionMap: whoever may see the
// stock may see how long it lasts. Nothing here creates alerts or purchases.

using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Npgsql;
using PoultryFarmAPIWeb.Business;

namespace PoultryFarmAPIWeb.Controllers
{
    [Authorize]
    [ApiController]
    [Route("api/Poultry/stock-supply")]
    public class PoultryStockSupplyController : ControllerBase
    {
        private readonly IPoultryStockSupplyService _svc;
        public PoultryStockSupplyController(IPoultryStockSupplyService svc) => _svc = svc;

        /// <summary>Every active raw material, most urgent first. lookbackDays overrides the farm setting (1-90).</summary>
        [HttpGet]
        public async Task<ActionResult<IEnumerable<StockSupplyRow>>> Get([FromQuery] string farmId, [FromQuery] int? lookbackDays)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetAsync(farmId, lookbackDays));

        [HttpGet("settings")]
        public async Task<ActionResult<StockSupplySettings>> GetSettings([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetSettingsAsync(farmId));

        [HttpPut("settings")]
        public async Task<IActionResult> SetSettings([FromBody] StockSupplySettings body)
        {
            if (string.IsNullOrWhiteSpace(body.FarmId)) return BadRequest("Company ID is required.");
            try
            {
                await _svc.SetSettingsAsync(body, User.FindFirst(ClaimTypes.Name)?.Value ?? User.FindFirst(ClaimTypes.NameIdentifier)?.Value);
                return NoContent();
            }
            catch (PostgresException ex) when (ex.SqlState is "P0001" or "23514")
            {
                return BadRequest(new { message = ex.SqlState == "P0001" ? ex.MessageText
                    : "Lookback and minimum history must be 1–90 days, and warning must be more days than critical." });
            }
        }
    }
}
