using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // Poultry Company profile + setup, mirroring WaterCompanyController.
    // GET returns 404 when not set up (the frontend treats that as "needs
    // setup"). POST /setup is idempotent and also seeds the default cash
    // accounts via sppoultryfinance_seeddefaults. Unlike Water there are no
    // expense categories to seed: poultry expenses use the shared Expense table
    // with a free-text Category.
    [ApiController]
    [Route("api/Poultry/company")]
    public class PoultryCompanyController : ControllerBase
    {
        private readonly IPoultryCompanyService _svc;
        public PoultryCompanyController(IPoultryCompanyService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<PoultryCompanyProfileModel>> GetProfile([FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var p = await _svc.GetProfileAsync(farmId);
            return p is null ? NotFound() : Ok(p);
        }

        [HttpPost("setup")]
        public async Task<ActionResult<PoultryCompanyProfileModel>> Setup([FromBody] PoultryCompanySetupRequest req)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required.");
            var p = await _svc.SetupAsync(req);
            return p is null ? StatusCode(500, "Setup did not return a profile.") : Ok(p);
        }

        [HttpPut]
        public async Task<ActionResult<PoultryCompanyProfileModel>> Update(
            [FromQuery] string farmId, [FromBody] PoultryCompanyUpdateRequest req)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var p = await _svc.UpdateProfileAsync(farmId, req);
            return p is null ? NotFound() : Ok(p);
        }
    }
}
