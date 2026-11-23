using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Filters;
using System;
using System.Security.Claims;
using System.Text.Json;
using System.Threading.Tasks;

namespace PoultryFarmAPIWeb.Controllers
{
    /// <summary>
    /// Egg Cost &amp; Profit Analyzer (migration 481), Poultry companies only.
    ///
    /// <para>
    /// Permissions come from IamPermissionMap's "poultry/egg-cost" entry
    /// (poultry.reports, the same right as Profit &amp; Loss): GET = view, POST /
    /// PUT / DELETE = create / edit / delete. Changing the costing assumptions
    /// -- settings, flock lifetime assumptions, historical costs -- is also
    /// owner / admin only ([SetupAdminOnly]), because it changes every figure the
    /// tool shows. Company isolation is the IAM filter's: the farmId on the
    /// query must be one the caller belongs to.
    /// </para>
    ///
    /// <para>Nothing here posts an expense, sale, cash or stock movement.</para>
    /// </summary>
    [ApiController]
    [Route("api/poultry/egg-cost")]
    [RequireCompanyType("Poultry")]
    public class PoultryEggCostController : ControllerBase
    {
        private readonly IPoultryEggCostService _svc;
        public PoultryEggCostController(IPoultryEggCostService svc) => _svc = svc;

        private string? Caller => User?.FindFirst(ClaimTypes.Name)?.Value ?? User?.FindFirst(ClaimTypes.NameIdentifier)?.Value;

        private async Task<IActionResult> Guard(Func<Task<IActionResult>> run)
        {
            try { return await run(); }
            catch (EggCostRuleException ex) { return BadRequest(new { message = ex.Message }); }
        }

        // GET facts?farmId=&startDate=&endDate=
        [HttpGet("facts")]
        public Task<IActionResult> Facts([FromQuery] string farmId, [FromQuery] DateTime startDate, [FromQuery] DateTime endDate) => Guard(async () =>
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest(new { message = "Company ID is required." });
            return Content(await _svc.GetFactsAsync(farmId, startDate, endDate), "application/json");
        });

        [HttpPut("settings")]
        [SetupAdminOnly]
        public Task<IActionResult> SaveSettings([FromQuery] string farmId, [FromBody] JsonElement settings) => Guard(async () =>
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest(new { message = "Company ID is required." });
            return Content(await _svc.SaveSettingsAsync(farmId, settings.GetRawText(), Caller), "application/json");
        });

        [HttpPut("flocks/{flockId:int}/assumptions")]
        [SetupAdminOnly]
        public Task<IActionResult> SaveAssumption(int flockId, [FromQuery] string farmId, [FromBody] JsonElement assumption) => Guard(async () =>
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest(new { message = "Company ID is required." });
            await _svc.SaveAssumptionAsync(farmId, flockId, assumption.GetRawText(), Caller);
            return NoContent();
        });

        [HttpPost("historical-costs")]
        [SetupAdminOnly]
        public Task<IActionResult> AddHistorical([FromQuery] string farmId, [FromBody] PoultryEggCostHistoricalInput input) => Guard(async () =>
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest(new { message = "Company ID is required." });
            if (input is null) return BadRequest(new { message = "Nothing to save." });
            return Ok(new { historicalCostId = await _svc.AddHistoricalCostAsync(farmId, input, Caller) });
        });

        public class ReasonBody { public string Reason { get; set; } = string.Empty; }

        [HttpPost("historical-costs/{id:int}/reverse")]
        [SetupAdminOnly]
        public Task<IActionResult> ReverseHistorical(int id, [FromQuery] string farmId, [FromBody] ReasonBody body) => Guard(async () =>
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest(new { message = "Company ID is required." });
            await _svc.ReverseHistoricalCostAsync(farmId, id, body?.Reason ?? string.Empty, Caller);
            return NoContent();
        });

        [HttpGet("snapshots")]
        public Task<IActionResult> Snapshots([FromQuery] string farmId) => Guard(async () =>
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest(new { message = "Company ID is required." });
            return Content(await _svc.ListSnapshotsAsync(farmId), "application/json");
        });

        [HttpGet("snapshots/{id:int}")]
        public Task<IActionResult> Snapshot(int id, [FromQuery] string farmId) => Guard(async () =>
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest(new { message = "Company ID is required." });
            var json = await _svc.GetSnapshotAsync(farmId, id);
            return json is null ? NotFound(new { message = "Saved analysis not found." }) : Content(json, "application/json");
        });

        [HttpPost("snapshots")]
        public Task<IActionResult> SaveSnapshot([FromQuery] string farmId, [FromBody] PoultryEggCostSnapshotInput input) => Guard(async () =>
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest(new { message = "Company ID is required." });
            if (input is null) return BadRequest(new { message = "Nothing to save." });
            return Ok(new { snapshotId = await _svc.SaveSnapshotAsync(farmId, input, Caller) });
        });

        [HttpDelete("snapshots/{id:int}")]
        public Task<IActionResult> DeleteSnapshot(int id, [FromQuery] string farmId) => Guard(async () =>
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest(new { message = "Company ID is required." });
            await _svc.DeleteSnapshotAsync(farmId, id, Caller);
            return NoContent();
        });

        [HttpGet("audit")]
        public Task<IActionResult> Audit([FromQuery] string farmId) => Guard(async () =>
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest(new { message = "Company ID is required." });
            return Content(await _svc.ListAuditAsync(farmId), "application/json");
        });
    }
}
