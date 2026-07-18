using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class ProductionBatchRecordController : ControllerBase
    {
        private readonly IProductionBatchRecordService _service;

        public ProductionBatchRecordController(IProductionBatchRecordService service)
        {
            _service = service;
        }

        [HttpGet]
        public async Task<ActionResult<IEnumerable<ProductionBatchRecordModel>>> GetAll([FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId) || string.IsNullOrEmpty(farmId))
                return BadRequest("UserId and FarmId are required.");
            return Ok(await _service.GetAll(userId, farmId));
        }

        [HttpGet("{id:int}")]
        public async Task<ActionResult<ProductionBatchRecordModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(farmId))
                return BadRequest("FarmId is required.");
            var record = await _service.GetById(id, farmId);
            if (record == null) return NotFound();
            return Ok(record);
        }

        // Production records capture what already happened (eggs collected, feed
        // consumed, birds died), so the production date can never be in the future.
        // UTC-day comparison — the product's farms run on GMT+0.
        private static bool IsFutureDate(DateTime d) => d.Date > DateTime.UtcNow.Date;

        [HttpPost]
        public async Task<ActionResult<ProductionBatchRecordModel>> Create([FromBody] ProductionBatchRecordModel model)
        {
            if (string.IsNullOrEmpty(model.FarmId))
                return BadRequest("FarmId is required in the model.");
            if (IsFutureDate(model.ProductionDate))
                return BadRequest("Production date cannot be in the future.");
            if (string.IsNullOrEmpty(model.CreatedBy)) model.CreatedBy = model.UserId;

            var newId = await _service.Insert(model);
            var created = await _service.GetById(newId, model.FarmId);
            if (created == null) return StatusCode(500, "Record was created but could not be retrieved.");
            return CreatedAtAction(nameof(GetById), new { id = newId, farmId = model.FarmId }, created);
        }

        [HttpPut("{id:int}")]
        public async Task<IActionResult> Update(int id, [FromBody] ProductionBatchRecordModel model)
        {
            if (id != model.Id) return BadRequest("Record ID mismatch.");
            if (string.IsNullOrEmpty(model.FarmId)) return BadRequest("FarmId is required in the model.");
            if (IsFutureDate(model.ProductionDate))
                return BadRequest("Production date cannot be in the future.");
            if (string.IsNullOrEmpty(model.UpdatedBy)) model.UpdatedBy = model.UserId;
            await _service.Update(model);
            return NoContent();
        }

        [HttpDelete("{id:int}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId) || string.IsNullOrEmpty(farmId))
                return BadRequest("UserId and FarmId are required.");
            await _service.Delete(id, userId, farmId);
            return NoContent();
        }

        /// <summary>Save (replace) the allocation rows for a batch; marks it Allocated by default.</summary>
        [HttpPost("{id:int}/allocation")]
        public async Task<ActionResult<ProductionBatchRecordModel>> SaveAllocation(int id, [FromQuery] string farmId, [FromBody] SaveAllocationRequest body)
        {
            if (string.IsNullOrEmpty(farmId)) return BadRequest("FarmId is required.");
            await _service.SaveAllocation(id, farmId, body.UpdatedBy, body.Status, body.Allocations);
            var updated = await _service.GetById(id, farmId);
            return Ok(updated);
        }

        /// <summary>Change status (e.g. submit a Draft, or Cancel). Not for Post/Reverse.</summary>
        [HttpPost("{id:int}/status")]
        public async Task<IActionResult> SetStatus(int id, [FromQuery] string farmId, [FromBody] BatchActionRequest body)
        {
            if (string.IsNullOrEmpty(farmId) || string.IsNullOrEmpty(body.Status))
                return BadRequest("FarmId and Status are required.");
            await _service.SetStatus(id, farmId, body.Status, body.UserId);
            return NoContent();
        }

        /// <summary>Post the allocation: creates flock-level records + inventory/bird side-effects (transactional).</summary>
        [HttpPost("{id:int}/post")]
        public async Task<ActionResult<ProductionBatchRecordModel>> Post(int id, [FromQuery] string farmId, [FromBody] BatchActionRequest body)
        {
            if (string.IsNullOrEmpty(farmId) || string.IsNullOrEmpty(body.UserId))
                return BadRequest("FarmId and UserId are required.");
            await _service.Post(id, farmId, body.UserId!);
            var updated = await _service.GetById(id, farmId);
            return Ok(updated);
        }

        /// <summary>Reverse a posted batch: deletes generated flock records + their side-effects.</summary>
        [HttpPost("{id:int}/reverse")]
        public async Task<ActionResult<ProductionBatchRecordModel>> Reverse(int id, [FromQuery] string farmId, [FromBody] BatchActionRequest body)
        {
            if (string.IsNullOrEmpty(farmId) || string.IsNullOrEmpty(body.UserId))
                return BadRequest("FarmId and UserId are required.");
            await _service.Reverse(id, farmId, body.UserId!);
            var updated = await _service.GetById(id, farmId);
            return Ok(updated);
        }

        /// <summary>
        /// Delete the allocation only, keeping the parent batch record. A posted
        /// allocation is reversed first (its flock records + inventory/bird effects
        /// are undone) before the rows are removed; the batch returns to
        /// PendingAllocation so it can be re-allocated. Transactional server-side.
        /// </summary>
        [HttpDelete("{id:int}/allocation")]
        public async Task<ActionResult<ProductionBatchRecordModel>> DeleteAllocation(int id, [FromQuery] string farmId, [FromQuery] string userId)
        {
            if (string.IsNullOrEmpty(farmId) || string.IsNullOrEmpty(userId))
                return BadRequest("FarmId and UserId are required.");
            await _service.DeleteAllocation(id, farmId, userId);
            var updated = await _service.GetById(id, farmId);
            return Ok(updated);
        }
    }
}
