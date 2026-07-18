using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class FarmProductionSettingsController : ControllerBase
    {
        private readonly IFarmProductionSettingsService _service;

        public FarmProductionSettingsController(IFarmProductionSettingsService service)
        {
            _service = service;
        }

        // GET: api/FarmProductionSettings?farmId=xxx
        [HttpGet]
        public async Task<ActionResult<FarmProductionSettingsModel>> Get([FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("FarmId is required.");
            return Ok(await _service.Get(farmId));
        }

        // PUT: api/FarmProductionSettings
        [HttpPut]
        public async Task<ActionResult<FarmProductionSettingsModel>> Upsert([FromBody] FarmProductionSettingsModel model)
        {
            if (model is null || string.IsNullOrWhiteSpace(model.FarmId)) return BadRequest("FarmId is required.");
            return Ok(await _service.Upsert(model));
        }
    }
}
