using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Helpers;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Authorize]
    [Route("api/Restaurant/setup")]
    public class RestaurantSetupController : ControllerBase
    {
        private readonly IRestaurantSetupService _svc;
        public RestaurantSetupController(IRestaurantSetupService svc) => _svc = svc;

        [HttpGet("profile")]
        public async Task<IActionResult> GetProfile([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            var p = await _svc.GetProfileAsync(farmId);
            if (p == null) return NotFound();
            return Ok(p);
        }

        [HttpPost("profile")]
        public async Task<IActionResult> UpsertProfile([FromBody] RestaurantProfileModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (auth != null) return auth;
            var result = await _svc.UpsertProfileAsync(m);
            return Ok(result);
        }
    }
}
