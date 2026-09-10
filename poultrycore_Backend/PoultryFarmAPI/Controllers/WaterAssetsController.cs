// Water Asset Register (migrations 283, 284, 286).
//
// Two rails, deliberately separate:
//
//   /api/Water/assets               the register itself
//   /api/Water/asset-depreciation   charging assets to Profit & Loss
//
// They are separate because the permission is separate: somebody who can add a
// delivery truck to the register is not necessarily somebody who should be able
// to change what the owner reads as profit. IamPermissionMap maps each path to
// its own resource, and the /reverse and /dispose segments resolve to approve
// and delete through ResolveAction with no extra wiring.
//
// SP EXCEPTIONS COME BACK AS 400, NOT 500
// ---------------------------------------
// Nearly every refusal in 283 and 284 is a user-facing rule with wording written
// for a person: "Depreciation has already been posted for this asset, so its
// in-service date, useful life and residual value are locked." Those are the
// user's mistake, not a server fault, and the SP's own message is better than
// anything this layer could invent. So PostgresException is translated rather
// than allowed to become an opaque 500.

using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/Water/assets")]
    public class WaterAssetsController : ControllerBase
    {
        private readonly IWaterCapitalAssetService _svc;
        public WaterAssetsController(IWaterCapitalAssetService svc) => _svc = svc;

        private static string? Farm(string? q, string? body) =>
            !string.IsNullOrWhiteSpace(q) ? q : body;

        [HttpGet("categories")]
        public async Task<ActionResult<List<WaterAssetCategoryModel>>> Categories([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetCategoriesAsync(farmId));

        [HttpPost("categories")]
        public async Task<ActionResult<int>> UpsertCategory(
            [FromQuery] string farmId, [FromBody] WaterAssetCategoryModel body, [FromQuery] string? userId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            if (!ModelState.IsValid) return BadRequest(ModelState);
            try { return Ok(await _svc.UpsertCategoryAsync(farmId, body, userId)); }
            catch (Npgsql.PostgresException ex) { return BadRequest(ex.MessageText); }
        }

        /// <summary>
        /// The register. Optional status and category filters; everything else --
        /// search, date, location -- is a client-side filter over the same list,
        /// which is what the other water list screens do.
        /// </summary>
        [HttpGet]
        public async Task<ActionResult<List<WaterCapitalAssetModel>>> GetAll(
            [FromQuery] string farmId, [FromQuery] string? status, [FromQuery] int? categoryId)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetAllAsync(farmId, status, categoryId));

        /// <summary>
        /// The five cards. Book value is a BALANCE and ignores the dates; only
        /// "added in period" is period-scoped.
        /// </summary>
        [HttpGet("summary")]
        public async Task<ActionResult<WaterCapitalAssetSummaryModel>> Summary(
            [FromQuery] string farmId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetSummaryAsync(farmId, fromDate, toDate));

        [HttpGet("{id:int}")]
        public async Task<ActionResult<WaterCapitalAssetModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var asset = await _svc.GetByIdAsync(farmId, id);
            return asset is null ? NotFound() : Ok(asset);
        }

        /// <summary>
        /// Records an asset. The acquisition amount is OPTIONAL: an asset that
        /// will be built starts at nothing and grows through /costs, which is the
        /// construction workflow without a second set of screens.
        /// </summary>
        [HttpPost]
        public async Task<ActionResult<int>> Create([FromQuery] string farmId, [FromBody] WaterCapitalAssetCreateRequest body)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            body.FarmId = Farm(farmId, body.FarmId);
            if (string.IsNullOrWhiteSpace(body.FarmId)) return BadRequest("Company ID is required.");
            try { return Ok(await _svc.CreateAsync(body)); }
            catch (Npgsql.PostgresException ex) { return BadRequest(ex.MessageText); }
        }

        [HttpPut("{id:int}")]
        public async Task<IActionResult> Update(int id, [FromQuery] string farmId, [FromBody] WaterCapitalAssetUpdateRequest body)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            body.FarmId = Farm(farmId, body.FarmId);
            if (string.IsNullOrWhiteSpace(body.FarmId)) return BadRequest("Company ID is required.");
            try { await _svc.UpdateAsync(id, body); return NoContent(); }
            catch (Npgsql.PostgresException ex) { return BadRequest(ex.MessageText); }
        }

        [HttpPost("{id:int}/costs")]
        public async Task<ActionResult<int>> AddCost(int id, [FromQuery] string farmId, [FromBody] WaterCapitalAssetCostRequest body)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            body.FarmId = Farm(farmId, body.FarmId);
            if (string.IsNullOrWhiteSpace(body.FarmId)) return BadRequest("Company ID is required.");
            try { return Ok(await _svc.AddCostAsync(id, body)); }
            catch (Npgsql.PostgresException ex) { return BadRequest(ex.MessageText); }
        }

        /// <summary>
        /// Proceeds reach CASH and are deliberately not revenue. Gain or loss on
        /// disposal is not computed -- see the note on the SP.
        /// </summary>
        [HttpPost("{id:int}/dispose")]
        public async Task<IActionResult> Dispose(int id, [FromQuery] string farmId, [FromBody] WaterCapitalAssetDisposeRequest body)
        {
            body.FarmId = Farm(farmId, body.FarmId);
            if (string.IsNullOrWhiteSpace(body.FarmId)) return BadRequest("Company ID is required.");
            try { await _svc.DisposeAsync(id, body); return NoContent(); }
            catch (Npgsql.PostgresException ex) { return BadRequest(ex.MessageText); }
        }

        /// <summary>
        /// Unwinds an acquisition. Refused outright once depreciation has been
        /// posted, a supplier has been paid, or the asset has been disposed of --
        /// each of those would be left pointing at nothing.
        /// </summary>
        [HttpPost("{id:int}/reverse")]
        public async Task<IActionResult> Reverse(int id, [FromQuery] string farmId, [FromBody] WaterReversalRequest body)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            body.FarmId = Farm(farmId, body.FarmId);
            if (string.IsNullOrWhiteSpace(body.FarmId)) return BadRequest("Company ID is required.");
            try { await _svc.ReverseAsync(id, body); return NoContent(); }
            catch (Npgsql.PostgresException ex) { return BadRequest(ex.MessageText); }
        }
    }

    [ApiController]
    [Route("api/Water/asset-depreciation")]
    public class WaterAssetDepreciationController : ControllerBase
    {
        private readonly IWaterCapitalAssetService _svc;
        public WaterAssetDepreciationController(IWaterCapitalAssetService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<List<WaterAssetDepreciationModel>>> GetAll(
            [FromQuery] string farmId, [FromQuery] int? assetId,
            [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetDepreciationAsync(farmId, assetId, fromDate, toDate));

        /// <summary>
        /// What Generate would charge, without charging it. The register needs to
        /// be able to say "3 assets, 7 months, 14,000" before anyone presses a
        /// button that writes to Profit &amp; Loss.
        /// </summary>
        [HttpGet("due")]
        public async Task<ActionResult<List<WaterAssetDepreciationDueModel>>> Due(
            [FromQuery] string farmId, [FromQuery] DateTime? throughDate)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetDueAsync(farmId, throughDate));

        /// <summary>Idempotent: running it twice charges nothing the second time.</summary>
        [HttpPost("generate")]
        public async Task<ActionResult<WaterAssetDepreciationRunResult>> Generate(
            [FromQuery] string farmId, [FromBody] WaterDepreciationGenerateRequest body)
        {
            body.FarmId = string.IsNullOrWhiteSpace(farmId) ? body.FarmId : farmId;
            if (string.IsNullOrWhiteSpace(body.FarmId)) return BadRequest("Company ID is required.");
            try { return Ok(await _svc.GenerateDepreciationAsync(body)); }
            catch (Npgsql.PostgresException ex) { return BadRequest(ex.MessageText); }
        }

        /// <summary>
        /// Appends the opposite entry and keeps the original. Does NOT reopen the
        /// month to the generator: use /adjust to re-post a corrected amount, so
        /// that reversing cannot be silently undone by the next Generate.
        /// </summary>
        [HttpPost("{id:int}/reverse")]
        public async Task<IActionResult> Reverse(int id, [FromQuery] string farmId, [FromBody] WaterReversalRequest body)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            body.FarmId = string.IsNullOrWhiteSpace(farmId) ? body.FarmId : farmId;
            if (string.IsNullOrWhiteSpace(body.FarmId)) return BadRequest("Company ID is required.");
            try { await _svc.ReverseDepreciationAsync(id, body); return NoContent(); }
            catch (Npgsql.PostgresException ex) { return BadRequest(ex.MessageText); }
        }

        [HttpPost("adjust")]
        public async Task<ActionResult<int>> Adjust([FromQuery] string farmId, [FromBody] WaterDepreciationAdjustRequest body)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            body.FarmId = string.IsNullOrWhiteSpace(farmId) ? body.FarmId : farmId;
            if (string.IsNullOrWhiteSpace(body.FarmId)) return BadRequest("Company ID is required.");
            try { return Ok(await _svc.AdjustDepreciationAsync(body)); }
            catch (Npgsql.PostgresException ex) { return BadRequest(ex.MessageText); }
        }
    }
}
