using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class SupplierController : ControllerBase
    {
        private readonly ISupplierService _supplierService;

        public SupplierController(ISupplierService supplierService)
        {
            _supplierService = supplierService;
        }

        [HttpGet]
        public async Task<ActionResult<IEnumerable<SupplierModel>>> GetAll([FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(farmId))
                return BadRequest("FarmId is required.");
            var all = await _supplierService.GetAll(userId ?? "", farmId);
            return Ok(all);
        }

        [HttpGet("{id:int}")]
        public async Task<ActionResult<SupplierModel>> GetById(int id, [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(farmId))
                return BadRequest("FarmId is required.");
            var row = await _supplierService.GetById(id, userId ?? "", farmId);
            if (row == null) return NotFound();
            return Ok(row);
        }

        [HttpPost]
        public async Task<ActionResult<SupplierModel>> Create([FromBody] SupplierModel model)
        {
            if (string.IsNullOrWhiteSpace(model.FarmId) || string.IsNullOrWhiteSpace(model.UserId))
                return BadRequest("FarmId and UserId are required.");
            if (string.IsNullOrWhiteSpace(model.Name))
                return BadRequest("Name is required.");

            var newId = await _supplierService.Insert(model);
            model.SupplierId = newId;
            model.CreatedDate = DateTime.UtcNow;
            return CreatedAtAction(nameof(GetById), new { id = newId, userId = model.UserId, farmId = model.FarmId }, model);
        }

        [HttpPut("{id:int}")]
        public async Task<IActionResult> Update(int id, [FromBody] SupplierModel model)
        {
            if (string.IsNullOrWhiteSpace(model.FarmId) || string.IsNullOrWhiteSpace(model.UserId))
                return BadRequest("FarmId and UserId are required.");

            var existing = await _supplierService.GetById(id, model.UserId, model.FarmId);
            if (existing == null) return NotFound();

            model.SupplierId = id;
            await _supplierService.Update(model);
            return NoContent();
        }

        [HttpDelete("{id:int}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(farmId))
                return BadRequest("FarmId is required.");
            var existing = await _supplierService.GetById(id, userId ?? "", farmId);
            if (existing == null) return NotFound();
            await _supplierService.Delete(id, userId ?? "", farmId);
            return NoContent();
        }
    }
}
