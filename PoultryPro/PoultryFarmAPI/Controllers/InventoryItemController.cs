using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class InventoryItemController : ControllerBase
    {
        private readonly IInventoryService _inventoryService;

        public InventoryItemController(IInventoryService inventoryService)
        {
            _inventoryService = inventoryService;
        }

        // GET: api/InventoryItem?userId=xxx&farmId=yyy
        // userId is optional for farm-shared visibility compatibility.
        [HttpGet]
        public async Task<ActionResult<List<InventoryItemModel>>> GetAll([FromQuery] string userId, [FromQuery] string farmId)
        {
            if (!IsValidFarmId(farmId))
                return BadRequest("Valid FarmId is required.");

            var items = await _inventoryService.GetAllItemsAsync(userId, farmId);
            return Ok(items);
        }

        // GET: api/InventoryItem/5?userId=xxx&farmId=yyy
        [HttpGet("{id}")]
        public async Task<ActionResult<InventoryItemModel>> GetById(int id, [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (!IsValidFarmId(farmId))
                return BadRequest("Valid FarmId is required.");

            var item = await _inventoryService.GetItemByIdAsync(id, userId, farmId);
            if (item == null)
                return NotFound();

            return Ok(item);
        }

        // POST: api/InventoryItem
        [HttpPost]
        public async Task<ActionResult<InventoryItemModel>> Create([FromBody] InventoryItemModel model)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);

            if (string.IsNullOrEmpty(model.UserId))
                return BadRequest("UserId is required in the model.");
            if (!IsValidFarmId(model.FarmId))
                return BadRequest("Valid FarmId is required in the model.");

            int newId = await _inventoryService.CreateItemAsync(model);
            var created = await _inventoryService.GetItemByIdAsync(newId, model.UserId, model.FarmId);
            return CreatedAtAction(nameof(GetById), new { id = newId, userId = model.UserId, farmId = model.FarmId }, created);
        }

        // PUT: api/InventoryItem/5
        [HttpPut("{id}")]
        public async Task<IActionResult> Update(int id, [FromBody] InventoryItemModel model)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);

            if (string.IsNullOrEmpty(model.UserId))
                return BadRequest("UserId is required in the model.");
            if (!IsValidFarmId(model.FarmId))
                return BadRequest("Valid FarmId is required in the model.");

            var existing = await _inventoryService.GetItemByIdAsync(id, model.UserId, model.FarmId);
            if (existing == null)
                return NotFound();

            model.ItemId = id;
            await _inventoryService.UpdateItemAsync(model);
            return NoContent();
        }

        // DELETE: api/InventoryItem/5?userId=xxx&farmId=yyy
        [HttpDelete("{id}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (!IsValidFarmId(farmId))
                return BadRequest("Valid FarmId is required.");

            var existing = await _inventoryService.GetItemByIdAsync(id, userId, farmId);
            if (existing == null)
                return NotFound();

            await _inventoryService.DeleteItemAsync(id, userId, farmId);
            return NoContent();
        }

        private static bool IsValidFarmId(string? farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId))
                return false;

            var normalized = farmId.Trim();
            if (normalized == "0")
                return false;
            if (normalized.Equals("string", StringComparison.OrdinalIgnoreCase))
                return false;
            if (normalized.Equals("null", StringComparison.OrdinalIgnoreCase))
                return false;

            // FarmId is expected to be a GUID in this system.
            return Guid.TryParse(normalized, out _);
        }
    }
}
