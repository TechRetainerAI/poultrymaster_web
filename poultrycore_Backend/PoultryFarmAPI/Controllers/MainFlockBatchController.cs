using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    // Handles all API requests for the MainFlockBatch entity.
    public class MainFlockBatchController : ControllerBase
    {
        private readonly IMainFlockBatchService _batchService;

        public MainFlockBatchController(IMainFlockBatchService batchService)
        {
            _batchService = batchService;
        }

        // GET: api/MainFlockBatch?userId=xxx&farmId=xxx
        // Retrieves all batches for a specific farm/user.
        [HttpGet]
        public async Task<ActionResult<IEnumerable<MainFlockBatchModel>>> GetAll([FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId))
                return BadRequest("UserId is required.");

            if (string.IsNullOrEmpty(farmId))
                return BadRequest("FarmId is required.");

            var allBatches = await _batchService.GetAll(userId, farmId);
            return Ok(allBatches);
        }

        // GET: api/MainFlockBatch/5?userId=xxx&farmId=xxx
        // Retrieves a single batch by ID.
        [HttpGet("{id}")]
        public async Task<ActionResult<MainFlockBatchModel>> GetById(int id, [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId))
                return BadRequest("UserId is required.");

            if (string.IsNullOrEmpty(farmId))
                return BadRequest("FarmId is required.");

            var batch = await _batchService.GetById(id, userId, farmId);
            if (batch == null) return NotFound();
            return Ok(batch);
        }

        // POST: api/MainFlockBatch
        // Creates a new batch record.
        [HttpPost]
        public async Task<ActionResult<MainFlockBatchModel>> Create([FromBody] MainFlockBatchModel model)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);

            if (string.IsNullOrEmpty(model.UserId))
                return BadRequest("UserId is required in the model.");

            if (string.IsNullOrEmpty(model.FarmId))
                return BadRequest("FarmId is required in the model.");

            var newId = await _batchService.Insert(model);
            // Retrieve the full created record to return in the 201 Created response.
            var createdRecord = await _batchService.GetById(newId, model.UserId, model.FarmId);
            return CreatedAtAction(nameof(GetById), new { id = newId, userId = model.UserId, farmId = model.FarmId }, createdRecord);
        }

        // PUT: api/MainFlockBatch/5
        // Updates an existing batch record.
        [HttpPut("{id}")]
        public async Task<IActionResult> Update(int id, [FromBody] MainFlockBatchModel model)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);

            if (string.IsNullOrEmpty(model.UserId))
                return BadRequest("UserId is required in the model.");

            if (string.IsNullOrEmpty(model.FarmId))
                return BadRequest("FarmId is required in the model.");

            var existing = await _batchService.GetById(id, model.UserId, model.FarmId);
            if (existing == null) return NotFound();

            model.BatchId = id;
            await _batchService.Update(model);
            return NoContent(); // 204 No Content success response.
        }

        // DELETE: api/MainFlockBatch/5?userId=xxx&farmId=xxx
        // Deletes a batch record.
        [HttpDelete("{id}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId))
                return BadRequest("UserId is required.");

            if (string.IsNullOrEmpty(farmId))
                return BadRequest("FarmId is required.");

            var existing = await _batchService.GetById(id, userId, farmId);
            if (existing == null) return NotFound();

            await _batchService.Delete(id, userId, farmId);
            return NoContent(); // 204 No Content success response.
        }

        // POST: api/MainFlockBatch/5/pay-balance
        // Records a follow-up payment toward the batch's outstanding balance.
        [HttpPost("{id:int}/pay-balance")]
        public async Task<IActionResult> PayBalance(int id, [FromBody] FlockBatchPayBalanceRequest body)
        {
            if (body is null || string.IsNullOrWhiteSpace(body.FarmId))
                return BadRequest("FarmId is required.");
            if (body.Amount <= 0)
                return BadRequest("Payment amount must be greater than 0.");

            var balance = await _batchService.PayBalance(id, body.FarmId, body.Amount, body.PaymentMethod, body.PaymentDate, body.CreatedBy);
            return Ok(new { Balance = balance });
        }
    }

    // Body for POST api/MainFlockBatch/{id}/pay-balance.
    public class FlockBatchPayBalanceRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public decimal Amount { get; set; }
        public string? PaymentMethod { get; set; }
        public DateTime? PaymentDate { get; set; }
        public string? CreatedBy { get; set; }
    }
}
