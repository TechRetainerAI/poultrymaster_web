using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class HealthController : ControllerBase
    {
        private readonly IHealthRecordService _healthService;

        public HealthController(IHealthRecordService healthService)
        {
            _healthService = healthService;
        }

        // GET: api/Health?userId=xxx&farmId=yyy&flockId=1&houseId=2&itemId=3
        [HttpGet]
        public async Task<ActionResult<IEnumerable<HealthRecordModel>>> GetAll(
            [FromQuery] string userId,
            [FromQuery] string farmId,
            [FromQuery] int? flockId = null,
            [FromQuery] int? houseId = null,
            [FromQuery] int? itemId = null)
        {
            if (string.IsNullOrWhiteSpace(userId))
                return BadRequest("UserId is required.");
            if (string.IsNullOrWhiteSpace(farmId))
                return BadRequest("FarmId is required.");

            var records = await _healthService.GetAll(userId, farmId, flockId, houseId, itemId);
            return Ok(records);
        }

        // GET: api/Health/5?userId=xxx&farmId=yyy
        [HttpGet("{id}")]
        public async Task<ActionResult<HealthRecordModel>> GetById(int id, [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(userId))
                return BadRequest("UserId is required.");
            if (string.IsNullOrWhiteSpace(farmId))
                return BadRequest("FarmId is required.");

            var record = await _healthService.GetById(id, userId, farmId);
            if (record == null)
                return NotFound();

            return Ok(record);
        }

        // POST: api/Health
        [HttpPost]
        public async Task<ActionResult<HealthRecordModel>> Create([FromBody] HealthRecordModel model)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);

            if (string.IsNullOrWhiteSpace(model.UserId))
                return BadRequest("UserId is required in the model.");
            if (string.IsNullOrWhiteSpace(model.FarmId))
                return BadRequest("FarmId is required in the model.");

            var newId = await _healthService.Insert(model);
            var created = await _healthService.GetById(newId, model.UserId, model.FarmId!);
            return CreatedAtAction(nameof(GetById), new { id = newId, userId = model.UserId, farmId = model.FarmId }, created);
        }

        // PUT: api/Health/5
        [HttpPut("{id}")]
        public async Task<IActionResult> Update(int id, [FromBody] HealthRecordModel model)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);

            if (string.IsNullOrWhiteSpace(model.UserId))
                return BadRequest("UserId is required in the model.");
            if (string.IsNullOrWhiteSpace(model.FarmId))
                return BadRequest("FarmId is required in the model.");

            var existing = await _healthService.GetById(id, model.UserId, model.FarmId!);
            if (existing == null)
                return NotFound();

            model.Id = id;
            await _healthService.Update(model);
            return NoContent();
        }

        // DELETE: api/Health/5?userId=xxx&farmId=yyy
        [HttpDelete("{id}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(userId))
                return BadRequest("UserId is required.");
            if (string.IsNullOrWhiteSpace(farmId))
                return BadRequest("FarmId is required.");

            var existing = await _healthService.GetById(id, userId, farmId);
            if (existing == null)
                return NotFound();

            await _healthService.Delete(id, userId, farmId);
            return NoContent();
        }
    }
}
