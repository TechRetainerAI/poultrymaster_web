using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class FlockController : ControllerBase
    {
        private readonly IBirdFlockService _flockService;
        private readonly IMainFlockBatchService _batchService;

        public FlockController(IBirdFlockService flockService, IMainFlockBatchService batchService)
        {
            _flockService = flockService;
            _batchService = batchService;
        }

        // GET: api/Flock/{id}?userId=xxx&farmId=yyy
        [HttpGet("{id:int}")]
        public ActionResult<FlockModel> Get(int id, [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId))
                return BadRequest("UserId is required.");
            if (string.IsNullOrEmpty(farmId))
                return BadRequest("FarmId is required.");

            var flock = _flockService.GetFlockById(id, userId, farmId);
            if (flock == null)
                return NotFound();

            return Ok(flock);
        }

        // GET: api/Flock?userId=xxx&farmId=yyy
        [HttpGet]
        public ActionResult<List<FlockModel>> GetAll([FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId))
                return BadRequest("UserId is required.");
            if (string.IsNullOrEmpty(farmId))
                return BadRequest("FarmId is required.");

            var flocks = _flockService.GetAllFlocks(userId, farmId);
            return Ok(flocks);
        }

        // POST: api/Flock
        [HttpPost]
        public async Task<ActionResult> Create([FromBody] FlockModel model)
        {
            try
            {
                if (!ModelState.IsValid)
                {
                    var errors = ModelState.Values.SelectMany(v => v.Errors).Select(e => e.ErrorMessage);
                    return BadRequest(new { message = "Validation failed", errors = errors });
                }

                if (string.IsNullOrEmpty(model.UserId))
                    return BadRequest(new { message = "UserId is required in the flock model." });
                if (string.IsNullOrEmpty(model.FarmId))
                    return BadRequest(new { message = "FarmId is required in the flock model." });

                if (model.BatchId <= 0)
                    return BadRequest(new { message = "BatchId is required and must be greater than 0." });

                var batch = await _batchService.GetById(model.BatchId, model.UserId, model.FarmId);
                if (batch == null)
                {
                    return BadRequest(new { message = $"Flock Batch with ID {model.BatchId} not found." });
                }

                var existingFlockQuantityInBatch = await _flockService.GetTotalFlockQuantityForBatch(model.BatchId, model.UserId, model.FarmId);
                if (existingFlockQuantityInBatch + model.Quantity > batch.NumberOfBirds)
                {
                    return BadRequest(new { message = $"The total quantity of birds ({existingFlockQuantityInBatch + model.Quantity}) exceeds the available birds in batch '{batch.BatchName}' ({batch.NumberOfBirds})." });
                }

                int newFlockId = await _flockService.CreateFlock(model);
                var createdFlock = _flockService.GetFlockById(newFlockId, model.UserId, model.FarmId);
                return CreatedAtAction(nameof(Get), new { id = newFlockId, userId = model.UserId, farmId = model.FarmId }, createdFlock);
            }
            catch (Exception ex)
            {
                // Log the exception for debugging
                Console.WriteLine($"Error in FlockController.Create: {ex.Message}");
                Console.WriteLine($"Stack trace: {ex.StackTrace}");
                if (ex.InnerException != null)
                {
                    Console.WriteLine($"Inner exception: {ex.InnerException.Message}");
                }
                
                return StatusCode(500, new { 
                    message = "An error occurred while creating the flock.", 
                    error = ex.Message,
                    details = ex.InnerException?.Message 
                });
            }
        }

        // PUT: api/Flock/{id}
        [HttpPut("{id:int}")]
        public async Task<ActionResult> Update(int id, [FromBody] FlockModel model)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);

            if (string.IsNullOrEmpty(model.UserId))
                return BadRequest("UserId is required in the flock model.");
            if (string.IsNullOrEmpty(model.FarmId))
                return BadRequest("FarmId is required in the flock model.");

            var existingFlock = _flockService.GetFlockById(id, model.UserId, model.FarmId);
            if (existingFlock == null)
                return NotFound();

            var batch = await _batchService.GetById(model.BatchId, model.UserId, model.FarmId);
            if (batch == null)
            {
                return BadRequest($"Flock Batch with ID {model.BatchId} not found.");
            }

            // Calculate total quantity excluding the current flock's original quantity
            var totalQuantityExcludingCurrent = await _flockService.GetTotalFlockQuantityForBatch(model.BatchId, model.UserId, model.FarmId, id);
            
            if (totalQuantityExcludingCurrent + model.Quantity > batch.NumberOfBirds)
            {
                return BadRequest($"The total quantity of birds ({totalQuantityExcludingCurrent + model.Quantity}) exceeds the available birds in batch '{batch.BatchName}' ({batch.NumberOfBirds}).");
            }


            model.FlockId = id;
            await _flockService.UpdateFlock(model);
            return NoContent();
        }

        // DELETE: api/Flock/{id}?userId=xxx&farmId=yyy
        [HttpDelete("{id:int}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string userId, [FromQuery] string farmId)
        {
            Console.WriteLine($"FlockController.Delete called for FlockId={id}, UserId={userId}, FarmId={farmId}");
            if (string.IsNullOrEmpty(userId))
                return BadRequest("UserId is required.");
            if (string.IsNullOrEmpty(farmId))
                return BadRequest("FarmId is required.");

            var existingFlock = _flockService.GetFlockById(id, userId, farmId);
            if (existingFlock == null)
                return NotFound();

            await _flockService.DeleteFlock(id, userId, farmId);
            return NoContent();
        }
    }
}
