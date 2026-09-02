using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Helpers;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController][Authorize][Route("api/Restaurant/inventory")]
    public class RestaurantInventoryController : ControllerBase
    {
        private readonly IRestaurantInventoryService _svc;
        public RestaurantInventoryController(IRestaurantInventoryService svc) => _svc = svc;

        // Ingredients
        [HttpGet("ingredients")]
        public async Task<IActionResult> ListIngredients([FromQuery] string farmId, [FromQuery] string? category = null)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; return Ok(await _svc.ListIngredientsAsync(farmId, category)); }

        [HttpPost("ingredients")]
        public async Task<IActionResult> CreateIngredient([FromBody] RestaurantIngredientModel m)
        { if (!ModelState.IsValid) return BadRequest(ModelState); var a = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (a != null) return a; return Ok(new { ingredientId = await _svc.InsertIngredientAsync(m) }); }

        [HttpPut("ingredients/{id}")]
        public async Task<IActionResult> UpdateIngredient(int id, [FromBody] RestaurantIngredientModel m)
        { if (!ModelState.IsValid) return BadRequest(ModelState); var a = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (a != null) return a; m.IngredientId = id; await _svc.UpdateIngredientAsync(m); return NoContent(); }

        [HttpDelete("ingredients/{id}")]
        public async Task<IActionResult> DeleteIngredient(int id, [FromQuery] string farmId)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; await _svc.DeleteIngredientAsync(id, farmId); return NoContent(); }

        [HttpPost("ingredients/{id}/adjust")]
        public async Task<IActionResult> AdjustStock(int id, [FromQuery] string farmId, [FromBody] StockAdjustReq req)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a;
          await _svc.AdjustStockAsync(id, farmId, req.Quantity, req.MovementType, req.Reason, HotelAuthHelper.GetUserName(User)); return NoContent(); }

        [HttpGet("low-stock")]
        public async Task<IActionResult> LowStock([FromQuery] string farmId)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; return Ok(await _svc.GetLowStockAsync(farmId)); }

        // Recipes
        [HttpGet("recipes/{menuItemId}")]
        public async Task<IActionResult> ListRecipe(int menuItemId, [FromQuery] string farmId)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; return Ok(await _svc.ListRecipeAsync(menuItemId, farmId)); }

        [HttpPost("recipes")]
        public async Task<IActionResult> UpsertRecipe([FromQuery] string farmId, [FromBody] RecipeUpsertReq req)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a;
          return Ok(new { recipeId = await _svc.UpsertRecipeAsync(farmId, req.MenuItemId, req.IngredientId, req.Quantity, req.Unit, req.WastePercent, req.Notes) }); }

        [HttpDelete("recipes/{id}")]
        public async Task<IActionResult> DeleteRecipe(int id, [FromQuery] string farmId)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; await _svc.DeleteRecipeAsync(id, farmId); return NoContent(); }

        [HttpGet("food-cost/{menuItemId}")]
        public async Task<IActionResult> FoodCost(int menuItemId, [FromQuery] string farmId)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; return Ok(await _svc.GetFoodCostAsync(menuItemId, farmId)); }

        [HttpPost("deduct-order/{orderId}")]
        public async Task<IActionResult> DeductOrder(int orderId, [FromQuery] string farmId)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; return Ok(new { itemsDeducted = await _svc.DeductOrderStockAsync(orderId, farmId) }); }

        // Waste
        [HttpGet("waste")]
        public async Task<IActionResult> ListWaste([FromQuery] string farmId, [FromQuery] DateTime? fromDate = null, [FromQuery] DateTime? toDate = null)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; return Ok(await _svc.ListWasteAsync(farmId, fromDate, toDate)); }

        [HttpPost("waste")]
        public async Task<IActionResult> LogWaste([FromBody] RestaurantWasteLogModel m)
        { if (!ModelState.IsValid) return BadRequest(ModelState); var a = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (a != null) return a;
          m.LoggedBy ??= HotelAuthHelper.GetUserName(User); return Ok(new { wasteLogId = await _svc.LogWasteAsync(m) }); }

        [HttpGet("waste/summary")]
        public async Task<IActionResult> WasteSummary([FromQuery] string farmId, [FromQuery] DateTime? fromDate = null, [FromQuery] DateTime? toDate = null)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; return Ok(await _svc.GetWasteSummaryAsync(farmId, fromDate, toDate)); }

        // Stock Takes
        [HttpGet("stock-takes")]
        public async Task<IActionResult> ListStockTakes([FromQuery] string farmId)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; return Ok(await _svc.ListStockTakesAsync(farmId)); }

        [HttpPost("stock-takes")]
        public async Task<IActionResult> CreateStockTake([FromQuery] string farmId, [FromBody] StockTakeCreateReq req)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; return Ok(new { stockTakeId = await _svc.CreateStockTakeAsync(farmId, req.Notes) }); }

        [HttpGet("stock-takes/{id}/items")]
        public async Task<IActionResult> StockTakeItems(int id, [FromQuery] string farmId)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; return Ok(await _svc.GetStockTakeItemsAsync(id, farmId)); }

        [HttpPatch("stock-takes/items/{id}")]
        public async Task<IActionResult> UpdateStockTakeItem(int id, [FromQuery] string farmId, [FromBody] StockTakeItemUpdateReq req)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; await _svc.UpdateStockTakeItemAsync(id, farmId, req.ActualQty, req.Notes); return NoContent(); }

        [HttpPost("stock-takes/{id}/complete")]
        public async Task<IActionResult> CompleteStockTake(int id, [FromQuery] string farmId)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; await _svc.CompleteStockTakeAsync(id, farmId, HotelAuthHelper.GetUserName(User)); return NoContent(); }

        // Reports
        [HttpGet("value")]
        public async Task<IActionResult> InventoryValue([FromQuery] string farmId)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; return Ok(await _svc.GetInventoryValueAsync(farmId)); }
    }

    public class StockAdjustReq { public decimal Quantity { get; set; } public string MovementType { get; set; } = ""; public string Reason { get; set; } = ""; }
    public class RecipeUpsertReq { public int MenuItemId { get; set; } public int IngredientId { get; set; } public decimal Quantity { get; set; } public string Unit { get; set; } = ""; public decimal WastePercent { get; set; } public string? Notes { get; set; } }
    public class StockTakeCreateReq { public string? Notes { get; set; } }
    public class StockTakeItemUpdateReq { public decimal ActualQty { get; set; } public string? Notes { get; set; } }
}
