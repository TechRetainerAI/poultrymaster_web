using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Helpers;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController][Authorize][Route("api/Hotel")]
    public class HotelAssetsController : ControllerBase
    {
        private readonly IHotelCapitalAssetService _svc;
        public HotelAssetsController(IHotelCapitalAssetService svc) { _svc = svc; }
        private string? UserId => User.FindFirst("UserId")?.Value ?? User.FindFirst("sub")?.Value;

        // Categories
        [HttpGet("assets/categories")]
        public async Task<IActionResult> GetCategories([FromQuery] string farmId)
        { var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth; return Ok(await _svc.GetCategoriesAsync(farmId)); }

        [HttpPost("assets/categories")]
        public async Task<IActionResult> UpsertCategory([FromQuery] string farmId, [FromBody] HotelAssetCategoryModel m)
        { var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
          try { return Ok(new { hotelAssetCategoryId = await _svc.UpsertCategoryAsync(farmId, m) }); } catch (Exception ex) { return BadRequest(ex.Message); } }

        // Assets
        [HttpGet("assets")]
        public async Task<IActionResult> GetAll([FromQuery] string farmId, [FromQuery] string? status, [FromQuery] int? categoryId)
        { var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth; return Ok(await _svc.GetAllAsync(farmId, status, categoryId)); }

        [HttpGet("assets/summary")]
        public async Task<IActionResult> GetSummary([FromQuery] string farmId)
        { var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth; return Ok(await _svc.GetSummaryAsync(farmId)); }

        [HttpGet("assets/{id}")]
        public async Task<IActionResult> GetById(int id, [FromQuery] string farmId)
        { var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth; var m = await _svc.GetByIdAsync(id, farmId); return m == null ? NotFound() : Ok(m); }

        [HttpPost("assets")]
        public async Task<IActionResult> Create([FromBody] HotelCapitalAssetCreateRequest req)
        { var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
          try { return Ok(new { hotelCapitalAssetId = await _svc.CreateAsync(req, UserId) }); } catch (Exception ex) { return BadRequest(ex.Message); } }

        [HttpPut("assets/{id}")]
        public async Task<IActionResult> Update(int id, [FromBody] HotelCapitalAssetUpdateRequest req)
        { var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
          try { await _svc.UpdateAsync(id, req); return Ok(); } catch (Exception ex) { return BadRequest(ex.Message); } }

        [HttpPost("assets/{id}/activate")]
        public async Task<IActionResult> Activate(int id, [FromQuery] string farmId)
        { var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
          try { await _svc.ActivateAsync(id, farmId); return Ok(); } catch (Exception ex) { return BadRequest(ex.Message); } }

        [HttpPost("assets/{id}/costs")]
        public async Task<IActionResult> AddCost(int id, [FromBody] HotelAssetCostRequest req)
        { var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
          try { DateTime? cd = string.IsNullOrEmpty(req.CostDate) ? null : DateTime.Parse(req.CostDate);
            return Ok(new { costId = await _svc.AddCostAsync(id, req.FarmId, req.Amount, req.Description, cd, UserId) }); } catch (Exception ex) { return BadRequest(ex.Message); } }

        [HttpDelete("assets/{assetId}/costs/{costId}")]
        public async Task<IActionResult> ReverseCost(int assetId, int costId, [FromQuery] string farmId, [FromQuery] string? reason)
        { var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
          try { await _svc.ReverseCostAsync(costId, assetId, farmId, reason, UserId); return Ok(); } catch (Exception ex) { return BadRequest(ex.Message); } }

        [HttpGet("assets/{id}/costs")]
        public async Task<IActionResult> GetCosts(int id, [FromQuery] string farmId)
        { var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth; return Ok(await _svc.GetCostsAsync(id, farmId)); }

        [HttpPost("assets/{id}/dispose")]
        public async Task<IActionResult> Dispose(int id, [FromBody] HotelAssetReasonRequest req)
        { var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
          try { DateTime? dd = string.IsNullOrEmpty(req.DisposalDate) ? null : DateTime.Parse(req.DisposalDate);
            await _svc.DisposeAsync(id, req.FarmId, dd, req.Reason, UserId); return Ok(); } catch (Exception ex) { return BadRequest(ex.Message); } }

        [HttpPost("assets/{id}/reverse")]
        public async Task<IActionResult> Reverse(int id, [FromBody] HotelAssetReasonRequest req)
        { var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
          try { await _svc.ReverseAsync(id, req.FarmId, req.Reason, UserId); return Ok(); } catch (Exception ex) { return BadRequest(ex.Message); } }

        // Depreciation
        [HttpGet("asset-depreciation")]
        public async Task<IActionResult> GetDepreciation([FromQuery] string farmId, [FromQuery] int? assetId)
        { var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth; return Ok(await _svc.GetDepreciationAsync(farmId, assetId)); }

        [HttpPost("asset-depreciation/generate")]
        public async Task<IActionResult> GenerateDepreciation([FromBody] HotelDepreciationGenerateRequest req)
        { var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
          try { DateTime? td = string.IsNullOrEmpty(req.ThroughDate) ? null : DateTime.Parse(req.ThroughDate);
            return Ok(await _svc.GenerateDepreciationAsync(req.FarmId, td, req.AssetId, UserId)); } catch (Exception ex) { return BadRequest(ex.Message); } }

        [HttpPost("asset-depreciation/{id}/reverse")]
        public async Task<IActionResult> ReverseDepreciation(int id, [FromBody] HotelAssetReasonRequest req)
        { var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
          try { await _svc.ReverseDepreciationAsync(id, req.FarmId, req.Reason, UserId); return Ok(); } catch (Exception ex) { return BadRequest(ex.Message); } }
    }
}
