using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class FeedUsageController : ControllerBase
    {
        private readonly IFeedUsageService _feedUsageService;
        private readonly ILogger<FeedUsageController> _logger;

        public FeedUsageController(IFeedUsageService feedUsageService, ILogger<FeedUsageController> logger)
        {
            _feedUsageService = feedUsageService;
            _logger = logger;
        }

        // GET: api/FeedUsage?userId=xxx&farmId=yyy
        [HttpGet]
        public async Task<ActionResult<IEnumerable<FeedUsageModel>>> GetAll([FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId))
                return BadRequest("UserId is required.");
            if (string.IsNullOrEmpty(farmId))
                return BadRequest("FarmId is required.");

            var allRecords = await _feedUsageService.GetAll(userId, farmId);
            return Ok(allRecords);
        }

        // GET: api/FeedUsage/5?userId=xxx&farmId=yyy
        [HttpGet("{id}")]
        public async Task<ActionResult<FeedUsageModel>> GetById(int id, [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId))
                return BadRequest("UserId is required.");
            if (string.IsNullOrEmpty(farmId))
                return BadRequest("FarmId is required.");

            var record = await _feedUsageService.GetById(id, userId, farmId);
            if (record == null)
                return NotFound();
            return Ok(record);
        }

        // POST: api/FeedUsage
        [HttpPost]
        public async Task<ActionResult<FeedUsageModel>> Create([FromBody] FeedUsageModel model)
        {
            // Log what was received
            _logger.LogWarning("=== FeedUsage CREATE API called ===");
            _logger.LogWarning("Received - UserId: '{UserId}', FarmId: '{FarmId}', FlockId: {FlockId}, FeedType: '{FeedType}'", 
                model?.UserId ?? "NULL", 
                model?.FarmId ?? "NULL", 
                model?.FlockId ?? 0,
                model?.FeedType ?? "NULL");
            
            var json = System.Text.Json.JsonSerializer.Serialize(model);
            _logger.LogWarning("Full JSON received: {Json}", json);

            if (!ModelState.IsValid)
            {
                _logger.LogError("ModelState is invalid");
                return BadRequest(ModelState);
            }

            if (string.IsNullOrEmpty(model.UserId))
            {
                _logger.LogError("UserId is empty!");
                return BadRequest("UserId is required in the model.");
            }
            
            if (string.IsNullOrEmpty(model.FarmId))
            {
                _logger.LogError("FarmId is empty! This is the error!");
                return BadRequest("FarmId is required in the model.");
            }

            var newId = await _feedUsageService.Insert(model);
            var createdRecord = await _feedUsageService.GetById(newId, model.UserId, model.FarmId);
            _logger.LogInformation("Feed usage created successfully with ID: {NewId}", newId);
            return CreatedAtAction(nameof(GetById), new { id = newId, userId = model.UserId, farmId = model.FarmId }, createdRecord);
        }

        // PUT: api/FeedUsage/5
        [HttpPut("{id}")]
        public async Task<IActionResult> Update(int id, [FromBody] FeedUsageModel model)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);

            if (string.IsNullOrEmpty(model.UserId))
                return BadRequest("UserId is required in the model.");
            if (string.IsNullOrEmpty(model.FarmId))
                return BadRequest("FarmId is required in the model.");

            var existing = await _feedUsageService.GetById(id, model.UserId, model.FarmId);
            if (existing == null)
                return NotFound();

            model.FeedUsageId = id;
            await _feedUsageService.Update(model);
            return NoContent();
        }

        // DELETE: api/FeedUsage/5?userId=xxx&farmId=yyy
        [HttpDelete("{id}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId))
                return BadRequest("UserId is required.");
            if (string.IsNullOrEmpty(farmId))
                return BadRequest("FarmId is required.");

            var existing = await _feedUsageService.GetById(id, userId, farmId);
            if (existing == null)
                return NotFound();

            await _feedUsageService.Delete(id, userId, farmId);
            return NoContent();
        }
    }
}
