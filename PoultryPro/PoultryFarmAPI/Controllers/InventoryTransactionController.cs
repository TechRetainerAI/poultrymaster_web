using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class InventoryTransactionController : ControllerBase
    {
        private readonly IInventoryService _inventoryService;

        public InventoryTransactionController(IInventoryService inventoryService)
        {
            _inventoryService = inventoryService;
        }

        [HttpGet("ByItem/{itemId}")]
        public async Task<ActionResult<IEnumerable<InventoryTransactionModel>>> GetByItem(
            int itemId,
            [FromQuery] string userId,
            [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId) || string.IsNullOrEmpty(farmId))
                return BadRequest("UserId and FarmId are required.");

            var transactions = await _inventoryService.GetTransactionsByItemAsync(itemId, userId, farmId);
            return Ok(transactions);
        }

        [HttpPost]
        public async Task<ActionResult<InventoryTransactionModel>> Create([FromBody] InventoryTransactionModel model)
        {
            if (string.IsNullOrEmpty(model.UserId) || string.IsNullOrEmpty(model.FarmId))
                return BadRequest("UserId and FarmId are required in the model.");

            var newId = await _inventoryService.CreateTransactionAsync(model);
            var all = await _inventoryService.GetTransactionsByItemAsync(model.ItemId, model.UserId, model.FarmId);
            var created = all.FirstOrDefault(t => t.TransactionId == newId);
            return CreatedAtAction(nameof(GetByItem), new { itemId = model.ItemId, userId = model.UserId, farmId = model.FarmId }, created);
        }
    }
}
