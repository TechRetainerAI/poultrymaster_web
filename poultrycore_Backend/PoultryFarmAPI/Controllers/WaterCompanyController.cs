using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // Water Company profile + setup. GET returns 404 when not set up (frontend
    // treats that as "needs setup"). POST /setup is idempotent and also seeds
    // the finance defaults (categories + cash accounts) via the SP.
    [ApiController]
    [Route("api/Water/company")]
    public class WaterCompanyController : ControllerBase
    {
        private readonly IWaterCompanyService _svc;
        public WaterCompanyController(IWaterCompanyService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<WaterCompanyProfileModel>> GetProfile([FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var p = await _svc.GetProfileAsync(farmId);
            return p is null ? NotFound() : Ok(p);
        }

        [HttpPost("setup")]
        public async Task<ActionResult<WaterCompanyProfileModel>> Setup([FromBody] WaterCompanySetupRequest req)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required.");
            var p = await _svc.SetupAsync(req);
            return p is null ? StatusCode(500, "Setup did not return a profile.") : Ok(p);
        }

        [HttpPut]
        public async Task<ActionResult<WaterCompanyProfileModel>> Update(
            [FromQuery] string farmId, [FromBody] WaterCompanyUpdateRequest req)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var p = await _svc.UpdateProfileAsync(farmId, req);
            return p is null ? NotFound() : Ok(p);
        }
    }
}
