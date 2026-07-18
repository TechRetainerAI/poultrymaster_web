using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class ProductionRecordController : ControllerBase
    {
        private readonly IProductionRecordService _service;

        public ProductionRecordController(IProductionRecordService service)
        {
            _service = service;
        }

        [HttpGet]
        public async Task<ActionResult<IEnumerable<ProductionRecordModel>>> GetAll([FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId) || string.IsNullOrEmpty(farmId))
                return BadRequest("UserId and FarmId are required.");

            var records = await _service.GetAll(userId, farmId);
            return Ok(records);
        }

        [HttpGet("{id:int}")]
        public async Task<ActionResult<ProductionRecordModel>> GetById( int id, [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId) || string.IsNullOrEmpty(farmId))
                return BadRequest("UserId and FarmId are required.");

            var record = await _service.GetById(id, userId, farmId);
            if (record == null) return NotFound();
            return Ok(record);
        }

        // Production records capture what already happened, so the production date
        // can never be in the future. UTC-day comparison — farms run on GMT+0.
        private static bool IsFutureDate(DateTime d) => d.Date > DateTime.UtcNow.Date;

        [HttpPost]
        public async Task<ActionResult<ProductionRecordModel>> Create([FromBody] ProductionRecordModel model)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);

            if (string.IsNullOrEmpty(model.UserId) || string.IsNullOrEmpty(model.FarmId))
                return BadRequest("CreatedBy and FarmId are required in the model.");

            if (IsFutureDate(model.Date))
                return BadRequest("Production date cannot be in the future.");

            var newId = await _service.Insert(model);
            var createdRecord = await _service.GetById(newId, model.UserId, model.FarmId);
            
            if (createdRecord == null)
                return StatusCode(500, "Record was created but could not be retrieved.");
                
            return CreatedAtAction(nameof(GetById), new { id = newId, userId = model.UserId, farmId = model.FarmId }, createdRecord);
        }

        [HttpPut("{id}")]
        public async Task<IActionResult> Update(int id, [FromBody] ProductionRecordModel model)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);

            if (id != model.Id)
                return BadRequest("Record ID mismatch.");

            if (string.IsNullOrEmpty(model.UpdatedBy) || string.IsNullOrEmpty(model.FarmId))
                return BadRequest("UpdatedBy and FarmId are required in the model.");

            if (IsFutureDate(model.Date))
                return BadRequest("Production date cannot be in the future.");

            await _service.Update(model);
            return NoContent();
        }

        [HttpDelete("{id}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId) || string.IsNullOrEmpty(farmId))
                return BadRequest("UserId and FarmId are required.");

            await _service.Delete(id, userId, farmId);
            return NoContent();
        }
    }
}
