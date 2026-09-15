// Poultry Asset Register (migrations 270, 271, 273).
//
// Two rails, deliberately separate:
//
//   /api/Poultry/assets               the register itself
//   /api/Poultry/asset-depreciation   charging assets to Profit & Loss
//
// They are separate because the permission is separate: somebody who can add a
// vehicle to the register is not necessarily somebody who should be able to
// change what the owner reads as profit. IamPermissionMap maps each path to its
// own resource, and the /reverse and /dispose segments resolve to approve and
// delete through ResolveAction with no extra wiring.

using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/Poultry/assets")]
    public class PoultryAssetsController : ControllerBase
    {
        private readonly IPoultryCapitalAssetService _svc;
        public PoultryAssetsController(IPoultryCapitalAssetService svc) => _svc = svc;

        private static string? Farm(string? q, string? body) =>
            !string.IsNullOrWhiteSpace(q) ? q : body;

        [HttpGet("categories")]
        public async Task<ActionResult<List<PoultryAssetCategoryModel>>> Categories([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetCategoriesAsync(farmId));

        [HttpPost("categories")]
        public async Task<ActionResult<int>> UpsertCategory(
            [FromQuery] string farmId, [FromBody] PoultryAssetCategoryModel body, [FromQuery] string? userId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            if (!ModelState.IsValid) return BadRequest(ModelState);
            return Ok(await _svc.UpsertCategoryAsync(farmId, body, userId));
        }

        /// <summary>
        /// The register. Optional status and category filters; everything else --
        /// search, date, location -- is a client-side filter over the same list,
        /// which is what the other poultry list screens do.
        /// </summary>
        [HttpGet]
        public async Task<ActionResult<List<PoultryCapitalAssetModel>>> GetAll(
            [FromQuery] string farmId, [FromQuery] string? status, [FromQuery] int? categoryId)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetAllAsync(farmId, status, categoryId));

        /// <summary>
        /// The five cards. Book value is a BALANCE and ignores the dates; only
        /// "added in period" is period-scoped, which is what §61 asks for.
        /// </summary>
        [HttpGet("summary")]
        public async Task<ActionResult<PoultryCapitalAssetSummaryModel>> Summary(
            [FromQuery] string farmId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetSummaryAsync(farmId, fromDate, toDate));

        [HttpGet("{id:int}")]
        public async Task<ActionResult<PoultryCapitalAssetModel>> GetById(int id, [FromQuery] string farmId)
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
        public async Task<ActionResult<int>> Create([FromQuery] string farmId, [FromBody] PoultryCapitalAssetCreateRequest body)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            body.FarmId = Farm(farmId, body.FarmId);
            if (string.IsNullOrWhiteSpace(body.FarmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.CreateAsync(body));
        }

        [HttpPut("{id:int}")]
        public async Task<IActionResult> Update(int id, [FromQuery] string farmId, [FromBody] PoultryCapitalAssetUpdateRequest body)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            body.FarmId = Farm(farmId, body.FarmId);
            if (string.IsNullOrWhiteSpace(body.FarmId)) return BadRequest("Company ID is required.");
            await _svc.UpdateAsync(id, body);
            return NoContent();
        }

        [HttpPost("{id:int}/costs")]
        public async Task<ActionResult<int>> AddCost(int id, [FromQuery] string farmId, [FromBody] PoultryCapitalAssetCostRequest body)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            body.FarmId = Farm(farmId, body.FarmId);
            if (string.IsNullOrWhiteSpace(body.FarmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.AddCostAsync(id, body));
        }

        /// <summary>
        /// Proceeds reach CASH and are deliberately not revenue. Gain or loss on
        /// disposal is not computed -- see the note on the SP.
        /// </summary>
        [HttpPost("{id:int}/dispose")]
        public async Task<IActionResult> Dispose(int id, [FromQuery] string farmId, [FromBody] PoultryCapitalAssetDisposeRequest body)
        {
            body.FarmId = Farm(farmId, body.FarmId);
            if (string.IsNullOrWhiteSpace(body.FarmId)) return BadRequest("Company ID is required.");
            await _svc.DisposeAsync(id, body);
            return NoContent();
        }

        /// <summary>
        /// Unwinds an acquisition. Refused outright once depreciation has been
        /// posted, a supplier has been paid, or the asset has been disposed of --
        /// each of those would be left pointing at nothing.
        /// </summary>
        [HttpPost("{id:int}/reverse")]
        public async Task<IActionResult> Reverse(int id, [FromQuery] string farmId, [FromBody] PoultryReversalRequest body)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            body.FarmId = Farm(farmId, body.FarmId);
            if (string.IsNullOrWhiteSpace(body.FarmId)) return BadRequest("Company ID is required.");
            await _svc.ReverseAsync(id, body);
            return NoContent();
        }
    }

    [ApiController]
    [Route("api/Poultry/asset-depreciation")]
    public class PoultryAssetDepreciationController : ControllerBase
    {
        private readonly IPoultryCapitalAssetService _svc;
        public PoultryAssetDepreciationController(IPoultryCapitalAssetService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<List<PoultryAssetDepreciationModel>>> GetAll(
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
        public async Task<ActionResult<List<PoultryAssetDepreciationDueModel>>> Due(
            [FromQuery] string farmId, [FromQuery] DateTime? throughDate)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetDueAsync(farmId, throughDate));

        /// <summary>Idempotent: running it twice charges nothing the second time.</summary>
        [HttpPost("generate")]
        public async Task<ActionResult<PoultryAssetDepreciationRunResult>> Generate(
            [FromQuery] string farmId, [FromBody] PoultryDepreciationGenerateRequest body)
        {
            body.FarmId = string.IsNullOrWhiteSpace(farmId) ? body.FarmId : farmId;
            if (string.IsNullOrWhiteSpace(body.FarmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GenerateDepreciationAsync(body));
        }

        /// <summary>
        /// Appends the opposite entry and keeps the original. Does NOT reopen the
        /// month to the generator: use /adjust to re-post a corrected amount, so
        /// that reversing cannot be silently undone by the next Generate.
        /// </summary>
        [HttpPost("{id:int}/reverse")]
        public async Task<IActionResult> Reverse(int id, [FromQuery] string farmId, [FromBody] PoultryReversalRequest body)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            body.FarmId = string.IsNullOrWhiteSpace(farmId) ? body.FarmId : farmId;
            if (string.IsNullOrWhiteSpace(body.FarmId)) return BadRequest("Company ID is required.");
            await _svc.ReverseDepreciationAsync(id, body);
            return NoContent();
        }

        [HttpPost("adjust")]
        public async Task<ActionResult<int>> Adjust([FromQuery] string farmId, [FromBody] PoultryDepreciationAdjustRequest body)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            body.FarmId = string.IsNullOrWhiteSpace(farmId) ? body.FarmId : farmId;
            if (string.IsNullOrWhiteSpace(body.FarmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.AdjustDepreciationAsync(body));
        }
    }
}
