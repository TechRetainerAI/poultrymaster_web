using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;
using System.Text.Json;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class EggProductionController : ControllerBase
    {
        private readonly IEggProductionService _eggProductionService;
        private readonly ILogger<EggProductionController> _logger;

        public EggProductionController(IEggProductionService eggProductionService, ILogger<EggProductionController> logger)
        {
            _eggProductionService = eggProductionService;
            _logger = logger;
        }

        // GET: api/EggProduction?userId=xxx&farmId=yyy
        [HttpGet]
        public async Task<ActionResult<IEnumerable<EggProductionModel>>> GetAll([FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId) || string.IsNullOrEmpty(farmId))
                return BadRequest("UserId and FarmId are required.");

            var allRecords = await _eggProductionService.GetAll(userId, farmId);
            return Ok(allRecords);
        }

        // GET: api/EggProduction/5?userId=xxx&farmId=yyy
        [HttpGet("{id}")]
        public async Task<ActionResult<EggProductionModel>> GetById(int id, [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId) || string.IsNullOrEmpty(farmId))
                return BadRequest("UserId and FarmId are required.");

            var record = await _eggProductionService.GetById(id, userId, farmId);
            if (record == null)
                return NotFound();

            return Ok(record);
        }

        // POST: api/EggProduction
        [HttpPost]
        public async Task<ActionResult<EggProductionModel>> Create([FromBody] EggProductionModel model)
        {
            _logger.LogInformation("Received request to create EggProduction record.");
            _logger.LogInformation($"Received model data: {JsonSerializer.Serialize(model)}");

            if (!ModelState.IsValid)
            {
                _logger.LogWarning("ModelState is invalid.");
                return BadRequest(ModelState);
            }
            if (string.IsNullOrEmpty(model.UserId) || string.IsNullOrEmpty(model.FarmId))
            {
                _logger.LogWarning("UserId or FarmId is null or empty.");
                return BadRequest("UserId and FarmId are required.");
            }

            //Defensive check to diagnose potential deserialization issues.
            //if (model.TotalProduction == 0 && (model.Production9AM + model.Production12PM + model.Production4PM) == 0)
            //{
            //    _logger.LogWarning("Production values are all zero.");
            //    return BadRequest("Production values cannot all be zero. This may indicate a data binding or deserialization issue.");
            //}

            var newId = await _eggProductionService.Insert(model);
            var createdRecord = await _eggProductionService.GetById(newId, model.UserId, model.FarmId);

            return CreatedAtAction(nameof(GetById), new { id = newId, userId = model.UserId, farmId = model.FarmId }, createdRecord);
        }

        // PUT: api/EggProduction/5
        [HttpPut("{id}")]
        public async Task<IActionResult> Update(int id, [FromBody] EggProductionModel model)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);
            if (string.IsNullOrEmpty(model.UserId) || string.IsNullOrEmpty(model.FarmId))
                return BadRequest("UserId and FarmId are required.");

            var existing = await _eggProductionService.GetById(id, model.UserId, model.FarmId);
            if (existing == null)
                return NotFound();

            model.ProductionId = id;
            await _eggProductionService.Update(model);
            return NoContent();
        }

        // DELETE: api/EggProduction/5?userId=xxx&farmId=yyy
        [HttpDelete("{id}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId) || string.IsNullOrEmpty(farmId))
                return BadRequest("UserId and FarmId are required.");

            var existing = await _eggProductionService.GetById(id, userId, farmId);
            if (existing == null)
                return NotFound();

            await _eggProductionService.Delete(id, userId, farmId);
            return NoContent();
        }
    }
}
