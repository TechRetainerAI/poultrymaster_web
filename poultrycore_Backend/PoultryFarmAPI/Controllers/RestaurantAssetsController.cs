// Restaurant Capital Investments/Assets (migration 328).
//
// The same two rails as PoultryAssetsController, under /api/Restaurant:
//
//   /api/Restaurant/assets               the register itself
//   /api/Restaurant/asset-depreciation   charging assets to Profit & Loss
//
// Same conventions as RestaurantPayrollController: every action checks the
// caller's JWT company against farmId (query string), the acting user comes from
// the token, and business-rule refusals from the database come back as 400 with
// the database's own sentence (RestaurantBusinessRuleFilter).

using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Filters;
using PoultryFarmAPIWeb.Helpers;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Authorize]
    [RestaurantBusinessRuleFilter]
    [Route("api/Restaurant/assets")]
    public class RestaurantAssetsController : ControllerBase
    {
        private readonly IRestaurantCapitalAssetService _svc;
        public RestaurantAssetsController(IRestaurantCapitalAssetService svc) => _svc = svc;

        private string Me => HotelAuthHelper.GetUserName(User);
        private IActionResult? Deny(string? farmId) => HotelAuthHelper.VerifyFarmOwnership(User, farmId);

        /// <summary>Seeds the restaurant defaults on first read.</summary>
        [HttpGet("categories")]
        public async Task<IActionResult> Categories([FromQuery] string farmId)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.CategoriesAsync(farmId)); }

        [HttpPost("categories")]
        public async Task<IActionResult> UpsertCategory([FromQuery] string farmId, [FromBody] RestaurantAssetCategoryRequest req)
        { var d = Deny(farmId); if (d != null) return d; return Ok(new { assetCategoryId = await _svc.UpsertCategoryAsync(farmId, req, Me) }); }

        [HttpGet]
        public async Task<IActionResult> List([FromQuery] string farmId, [FromQuery] string? status, [FromQuery] int? categoryId)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.ListAsync(farmId, status, categoryId)); }

        /// <summary>The five cards. Book value is a BALANCE; only "added in period" uses the dates.</summary>
        [HttpGet("summary")]
        public async Task<IActionResult> Summary([FromQuery] string farmId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.SummaryAsync(farmId, fromDate, toDate)); }

        /// <summary>
        /// What is still owed on capital purchases, one row per purchase document.
        /// The seam the Supplier Balances feature will read.
        /// </summary>
        [HttpGet("payables")]
        public async Task<IActionResult> Payables([FromQuery] string farmId)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.PayablesAsync(farmId)); }

        [HttpGet("{id:int}")]
        public async Task<IActionResult> Get(int id, [FromQuery] string farmId)
        {
            var d = Deny(farmId); if (d != null) return d;
            var a = await _svc.GetAsync(farmId, id);
            return a == null ? NotFound(new { message = "Capital investment not found." }) : Ok(a);
        }

        /// <summary>The cost is OPTIONAL: something built cost by cost starts at nothing and grows through /costs.</summary>
        [HttpPost]
        public async Task<IActionResult> Create([FromQuery] string farmId, [FromBody] RestaurantCapitalAssetCreateRequest req)
        { var d = Deny(farmId); if (d != null) return d; return Ok(new { capitalAssetId = await _svc.CreateAsync(farmId, req, Me) }); }

        [HttpPut("{id:int}")]
        public async Task<IActionResult> Update(int id, [FromQuery] string farmId, [FromBody] RestaurantCapitalAssetUpdateRequest req)
        { var d = Deny(farmId); if (d != null) return d; await _svc.UpdateAsync(farmId, id, req, Me); return Ok(); }

        [HttpPost("{id:int}/costs")]
        public async Task<IActionResult> AddCost(int id, [FromQuery] string farmId, [FromBody] RestaurantCapitalAssetCostRequest req)
        { var d = Deny(farmId); if (d != null) return d; return Ok(new { assetCostId = await _svc.AddCostAsync(farmId, id, req, Me) }); }

        /// <summary>Corrects the ORIGINAL acquisition cost: a dated, reasoned correction row, never an edit.</summary>
        [HttpPut("{id:int}/original-cost")]
        public async Task<IActionResult> CorrectOriginalCost(int id, [FromQuery] string farmId, [FromBody] RestaurantCapitalAssetCorrectCostRequest req)
        { var d = Deny(farmId); if (d != null) return d; return Ok(new { assetCostId = await _svc.CorrectOriginalCostAsync(farmId, id, req, Me) }); }

        /// <summary>Reverses ONE added cost. Nothing is deleted: the row is kept and marked Reversed.</summary>
        [HttpDelete("{id:int}/costs/{costId:int}")]
        public async Task<IActionResult> ReverseCost(int id, int costId, [FromQuery] string farmId, [FromBody] RestaurantReverseRequest req)
        { var d = Deny(farmId); if (d != null) return d; await _svc.ReverseCostAsync(farmId, id, costId, req.Reason, Me); return Ok(); }

        /// <summary>Proceeds reach CASH and are not revenue. Gain or loss is not computed (as in Poultry).</summary>
        [HttpPost("{id:int}/dispose")]
        public async Task<IActionResult> Dispose(int id, [FromQuery] string farmId, [FromBody] RestaurantCapitalAssetDisposeRequest req)
        { var d = Deny(farmId); if (d != null) return d; await _svc.DisposeAsync(farmId, id, req, Me); return Ok(); }

        /// <summary>Refused once depreciation is posted or the asset is disposed.</summary>
        [HttpPost("{id:int}/reverse")]
        public async Task<IActionResult> Reverse(int id, [FromQuery] string farmId, [FromBody] RestaurantReverseRequest req)
        { var d = Deny(farmId); if (d != null) return d; await _svc.ReverseAsync(farmId, id, req.Reason, Me); return Ok(); }
    }

    [ApiController]
    [Authorize]
    [RestaurantBusinessRuleFilter]
    [Route("api/Restaurant/asset-depreciation")]
    public class RestaurantAssetDepreciationController : ControllerBase
    {
        private readonly IRestaurantCapitalAssetService _svc;
        public RestaurantAssetDepreciationController(IRestaurantCapitalAssetService svc) => _svc = svc;

        private string Me => HotelAuthHelper.GetUserName(User);
        private IActionResult? Deny(string? farmId) => HotelAuthHelper.VerifyFarmOwnership(User, farmId);

        [HttpGet]
        public async Task<IActionResult> List([FromQuery] string farmId, [FromQuery] int? assetId,
                                              [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.DepreciationAsync(farmId, assetId, fromDate, toDate)); }

        /// <summary>What Generate would charge, without charging it.</summary>
        [HttpGet("due")]
        public async Task<IActionResult> Due([FromQuery] string farmId, [FromQuery] DateTime? throughDate)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.DueAsync(farmId, throughDate)); }

        /// <summary>Idempotent: running it twice charges nothing the second time. Never moves cash.</summary>
        [HttpPost("generate")]
        public async Task<IActionResult> Generate([FromQuery] string farmId, [FromBody] RestaurantDepreciationGenerateRequest req)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.GenerateAsync(farmId, req, Me)); }

        /// <summary>Appends the opposite entry and keeps the original; the month is not reopened.</summary>
        [HttpPost("{id:int}/reverse")]
        public async Task<IActionResult> Reverse(int id, [FromQuery] string farmId, [FromBody] RestaurantReverseRequest req)
        { var d = Deny(farmId); if (d != null) return d; await _svc.ReverseDepreciationAsync(farmId, id, req.Reason, Me); return Ok(); }

        [HttpPost("adjust")]
        public async Task<IActionResult> Adjust([FromQuery] string farmId, [FromBody] RestaurantDepreciationAdjustRequest req)
        { var d = Deny(farmId); if (d != null) return d; return Ok(new { assetDepreciationId = await _svc.AdjustDepreciationAsync(farmId, req, Me) }); }
    }
}
