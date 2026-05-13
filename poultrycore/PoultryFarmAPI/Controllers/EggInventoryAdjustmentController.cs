using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class EggInventoryAdjustmentController : ControllerBase
    {
        private readonly IEggInventoryAdjustmentService _service;

        public EggInventoryAdjustmentController(IEggInventoryAdjustmentService service)
        {
            _service = service;
        }

        private static readonly string[] ValidTypes = { "OpeningBalance", "Stocktake", "Correction" };

        [HttpGet]
        public async Task<ActionResult<List<EggInventoryAdjustmentModel>>> GetAll([FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId))
                return BadRequest("FarmId is required.");
            var list = await _service.GetAllAsync(farmId);
            return Ok(list);
        }

        [HttpGet("{id:int}")]
        public async Task<ActionResult<EggInventoryAdjustmentModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId))
                return BadRequest("FarmId is required.");
            var row = await _service.GetByIdAsync(id, farmId);
            if (row == null) return NotFound();
            return Ok(row);
        }

        [HttpPost]
        public async Task<ActionResult<EggInventoryAdjustmentModel>> Create([FromBody] EggInventoryAdjustmentModel model)
        {
            if (string.IsNullOrWhiteSpace(model.UserId))
                return BadRequest("UserId is required.");
            if (string.IsNullOrWhiteSpace(model.FarmId))
                return BadRequest("FarmId is required.");
            if (string.IsNullOrWhiteSpace(model.AdjustmentType))
                return BadRequest("AdjustmentType is required.");
            if (!ValidTypes.Contains(model.AdjustmentType, StringComparer.OrdinalIgnoreCase))
                return BadRequest($"AdjustmentType must be one of: {string.Join(", ", ValidTypes)}.");
            if (model.EggDelta == 0)
                return BadRequest("EggDelta cannot be zero.");

            var newId = await _service.InsertAsync(model);
            model.AdjustmentId = newId;
            model.CreatedDate = DateTime.UtcNow;
            return CreatedAtAction(nameof(GetById), new { id = newId, farmId = model.FarmId }, model);
        }

        [HttpPut("{id:int}")]
        public async Task<IActionResult> Update(int id, [FromBody] EggInventoryAdjustmentModel model)
        {
            if (string.IsNullOrWhiteSpace(model.FarmId))
                return BadRequest("FarmId is required.");
            if (!ValidTypes.Contains(model.AdjustmentType, StringComparer.OrdinalIgnoreCase))
                return BadRequest($"AdjustmentType must be one of: {string.Join(", ", ValidTypes)}.");
            if (model.EggDelta == 0)
                return BadRequest("EggDelta cannot be zero.");

            var existing = await _service.GetByIdAsync(id, model.FarmId);
            if (existing == null) return NotFound();

            model.AdjustmentId = id;
            model.UserId = existing.UserId;
            await _service.UpdateAsync(model);
            return NoContent();
        }

        [HttpDelete("{id:int}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId))
                return BadRequest("FarmId is required.");
            var existing = await _service.GetByIdAsync(id, farmId);
            if (existing == null) return NotFound();
            await _service.DeleteAsync(id, farmId);
            return NoContent();
        }
    }
}
