// Generic Capital Investments/Assets (migration 453), the Water register's twin.
//
//   /api/Generic/assets               the register itself
//   /api/Generic/asset-depreciation   charging assets to Profit & Loss
//
// SP exceptions are user-facing rules, so PostgresException comes back as 400
// with the function's own message.

using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Filters;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/Generic/assets")]
    [RequireCompanyType("Generic")]
    public class GenericAssetsController : ControllerBase
    {
        private readonly IGenericCapitalAssetService _svc;
        public GenericAssetsController(IGenericCapitalAssetService svc) => _svc = svc;

        private static string? Farm(string? q, string? body) =>
            !string.IsNullOrWhiteSpace(q) ? q : body;

        [HttpGet("categories")]
        public async Task<ActionResult<List<GenericAssetCategoryModel>>> Categories([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetCategoriesAsync(farmId));

        [HttpPost("categories")]
        public async Task<ActionResult<int>> UpsertCategory(
            [FromQuery] string farmId, [FromBody] GenericAssetCategoryModel body, [FromQuery] string? userId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            if (!ModelState.IsValid) return BadRequest(ModelState);
            try { return Ok(await _svc.UpsertCategoryAsync(farmId, body, userId)); }
            catch (Npgsql.PostgresException ex) { return BadRequest(ex.MessageText); }
        }

        /// <summary>
        /// The register. Optional status and category filters; everything else --
        /// search, date, location -- is a client-side filter over the same list,
        /// which is what the other generic list screens do.
        /// </summary>
        [HttpGet]
        public async Task<ActionResult<List<GenericCapitalAssetModel>>> GetAll(
            [FromQuery] string farmId, [FromQuery] string? status, [FromQuery] int? categoryId)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetAllAsync(farmId, status, categoryId));

        /// <summary>
        /// The five cards. Book value is a BALANCE and ignores the dates; only
        /// "added in period" is period-scoped.
        /// </summary>
        [HttpGet("summary")]
        public async Task<ActionResult<GenericCapitalAssetSummaryModel>> Summary(
            [FromQuery] string farmId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetSummaryAsync(farmId, fromDate, toDate));

        [HttpGet("{id:int}")]
        public async Task<ActionResult<GenericCapitalAssetModel>> GetById(int id, [FromQuery] string farmId)
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
        public async Task<ActionResult<int>> Create([FromQuery] string farmId, [FromBody] GenericCapitalAssetCreateRequest body)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            body.FarmId = Farm(farmId, body.FarmId);
            if (string.IsNullOrWhiteSpace(body.FarmId)) return BadRequest("Company ID is required.");
            try { return Ok(await _svc.CreateAsync(body)); }
            catch (Npgsql.PostgresException ex) { return BadRequest(ex.MessageText); }
        }

        [HttpPut("{id:int}")]
        public async Task<IActionResult> Update(int id, [FromQuery] string farmId, [FromBody] GenericCapitalAssetUpdateRequest body)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            body.FarmId = Farm(farmId, body.FarmId);
            if (string.IsNullOrWhiteSpace(body.FarmId)) return BadRequest("Company ID is required.");
            try { await _svc.UpdateAsync(id, body); return NoContent(); }
            catch (Npgsql.PostgresException ex) { return BadRequest(ex.MessageText); }
        }

        [HttpPost("{id:int}/costs")]
        public async Task<ActionResult<int>> AddCost(int id, [FromQuery] string farmId, [FromBody] GenericCapitalAssetCostRequest body)
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
        /// <summary>
        /// Corrects the ORIGINAL acquisition cost -- the fix for a typed
        /// 130,000 that should have been 13,000. This is not Add cost and not an
        /// editable field: it appends a dated, authored, reasoned correction row
        /// and amends the acquisition's own expense so cash and the supplier
        /// balance follow, without a second document of any kind.
        ///
        /// PUT, and the segment is a NOUN, on purpose: it resolves to the
        /// `edit` action and therefore to generic.assets.edit, which exists and is
        /// granted. A /correct verb would resolve to `create`, and a
        /// /reverse-shaped one to an `approve` action this resource does not have.
        /// </summary>
        [HttpPut("{id:int}/original-cost")]
        public async Task<ActionResult<int>> CorrectOriginalCost(
            int id, [FromQuery] string farmId, [FromBody] GenericCapitalAssetCorrectCostRequest body)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            body.FarmId = Farm(farmId, body.FarmId);
            if (string.IsNullOrWhiteSpace(body.FarmId)) return BadRequest("Company ID is required.");
            try { return Ok(await _svc.CorrectOriginalCostAsync(id, body)); }
            catch (Npgsql.PostgresException ex) { return BadRequest(ex.MessageText); }
        }

        /// <summary>
        /// Reverses ONE additional capitalised cost.
        ///
        /// DELETE is the verb because it resolves to generic.assets.delete -- the
        /// right, and already-granted, permission for something that ends a
        /// financial record's life. Nothing is deleted: the row is kept and
        /// marked Reversed, and its cash and payable are unwound.
        /// </summary>
        [HttpDelete("{id:int}/costs/{costId:int}")]
        public async Task<IActionResult> ReverseCost(
            int id, int costId, [FromQuery] string farmId, [FromBody] GenericReversalRequest body)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            body.FarmId = Farm(farmId, body.FarmId);
            if (string.IsNullOrWhiteSpace(body.FarmId)) return BadRequest("Company ID is required.");
            try { await _svc.ReverseCostAsync(id, costId, body); return NoContent(); }
            catch (Npgsql.PostgresException ex) { return BadRequest(ex.MessageText); }
        }

        [HttpPost("{id:int}/dispose")]
        public async Task<IActionResult> Dispose(int id, [FromQuery] string farmId, [FromBody] GenericCapitalAssetDisposeRequest body)
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
        public async Task<IActionResult> Reverse(int id, [FromQuery] string farmId, [FromBody] GenericReversalRequest body)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            body.FarmId = Farm(farmId, body.FarmId);
            if (string.IsNullOrWhiteSpace(body.FarmId)) return BadRequest("Company ID is required.");
            try { await _svc.ReverseAsync(id, body); return NoContent(); }
            catch (Npgsql.PostgresException ex) { return BadRequest(ex.MessageText); }
        }
    }

    [ApiController]
    [Route("api/Generic/asset-depreciation")]
    [RequireCompanyType("Generic")]
    public class GenericAssetDepreciationController : ControllerBase
    {
        private readonly IGenericCapitalAssetService _svc;
        public GenericAssetDepreciationController(IGenericCapitalAssetService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<List<GenericAssetDepreciationModel>>> GetAll(
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
        public async Task<ActionResult<List<GenericAssetDepreciationDueModel>>> Due(
            [FromQuery] string farmId, [FromQuery] DateTime? throughDate)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetDueAsync(farmId, throughDate));

        /// <summary>Idempotent: running it twice charges nothing the second time.</summary>
        [HttpPost("generate")]
        public async Task<ActionResult<GenericAssetDepreciationRunResult>> Generate(
            [FromQuery] string farmId, [FromBody] GenericDepreciationGenerateRequest body)
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
        public async Task<IActionResult> Reverse(int id, [FromQuery] string farmId, [FromBody] GenericReversalRequest body)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            body.FarmId = string.IsNullOrWhiteSpace(farmId) ? body.FarmId : farmId;
            if (string.IsNullOrWhiteSpace(body.FarmId)) return BadRequest("Company ID is required.");
            try { await _svc.ReverseDepreciationAsync(id, body); return NoContent(); }
            catch (Npgsql.PostgresException ex) { return BadRequest(ex.MessageText); }
        }

        [HttpPost("adjust")]
        public async Task<ActionResult<int>> Adjust([FromQuery] string farmId, [FromBody] GenericDepreciationAdjustRequest body)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            body.FarmId = string.IsNullOrWhiteSpace(farmId) ? body.FarmId : farmId;
            if (string.IsNullOrWhiteSpace(body.FarmId)) return BadRequest("Company ID is required.");
            try { return Ok(await _svc.AdjustDepreciationAsync(body)); }
            catch (Npgsql.PostgresException ex) { return BadRequest(ex.MessageText); }
        }
    }
}
