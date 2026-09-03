using System.ComponentModel.DataAnnotations;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Helpers;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Authorize]
    [Route("api/Restaurant/menu")]
    public class RestaurantMenuController : ControllerBase
    {
        private readonly IRestaurantMenuService _svc;
        public RestaurantMenuController(IRestaurantMenuService svc) => _svc = svc;

        // =====================================================================
        // CATEGORIES
        // =====================================================================

        [HttpGet("categories")]
        public async Task<IActionResult> ListCategories([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.ListCategoriesAsync(farmId));
        }

        [HttpGet("categories/{id}")]
        public async Task<IActionResult> GetCategory(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            var c = await _svc.GetCategoryAsync(id, farmId);
            if (c == null) return NotFound();
            return Ok(c);
        }

        [HttpPost("categories")]
        public async Task<IActionResult> CreateCategory([FromBody] RestaurantMenuCategoryModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (auth != null) return auth;
            var id = await _svc.InsertCategoryAsync(m);
            var created = await _svc.GetCategoryAsync(id, m.FarmId);
            return CreatedAtAction(nameof(GetCategory), new { id, farmId = m.FarmId }, created);
        }

        [HttpPut("categories/{id}")]
        public async Task<IActionResult> UpdateCategory(int id, [FromBody] RestaurantMenuCategoryModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (auth != null) return auth;
            m.MenuCategoryId = id;
            await _svc.UpdateCategoryAsync(m);
            return NoContent();
        }

        [HttpDelete("categories/{id}")]
        public async Task<IActionResult> DeleteCategory(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            await _svc.DeleteCategoryAsync(id, farmId);
            return NoContent();
        }

        // =====================================================================
        // MENU ITEMS
        // =====================================================================

        [HttpGet("items")]
        public async Task<IActionResult> ListItems([FromQuery] string farmId, [FromQuery] int? categoryId = null)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.ListItemsAsync(farmId, categoryId));
        }

        [HttpGet("items/{id}")]
        public async Task<IActionResult> GetItem(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            var item = await _svc.GetItemAsync(id, farmId);
            if (item == null) return NotFound();
            return Ok(item);
        }

        [HttpPost("items")]
        public async Task<IActionResult> CreateItem([FromBody] RestaurantMenuItemModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (auth != null) return auth;
            var id = await _svc.InsertItemAsync(m);
            var created = await _svc.GetItemAsync(id, m.FarmId);
            return CreatedAtAction(nameof(GetItem), new { id, farmId = m.FarmId }, created);
        }

        [HttpPut("items/{id}")]
        public async Task<IActionResult> UpdateItem(int id, [FromBody] RestaurantMenuItemModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (auth != null) return auth;
            m.MenuItemId = id;
            await _svc.UpdateItemAsync(m);
            return NoContent();
        }

        [HttpDelete("items/{id}")]
        public async Task<IActionResult> DeleteItem(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            await _svc.DeleteItemAsync(id, farmId);
            return NoContent();
        }

        [HttpPatch("items/{id}/availability")]
        public async Task<IActionResult> ToggleAvailability(int id, [FromQuery] string farmId, [FromQuery] bool isAvailable)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            await _svc.ToggleItemAvailabilityAsync(id, farmId, isAvailable);
            return NoContent();
        }

        // =====================================================================
        // MODIFIER GROUPS
        // =====================================================================

        [HttpGet("modifier-groups")]
        public async Task<IActionResult> ListModifierGroups([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.ListModifierGroupsAsync(farmId));
        }

        [HttpPost("modifier-groups")]
        public async Task<IActionResult> CreateModifierGroup([FromBody] RestaurantModifierGroupModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (auth != null) return auth;
            var id = await _svc.InsertModifierGroupAsync(m);
            return Ok(new { modifierGroupId = id });
        }

        [HttpPut("modifier-groups/{id}")]
        public async Task<IActionResult> UpdateModifierGroup(int id, [FromBody] RestaurantModifierGroupModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (auth != null) return auth;
            m.ModifierGroupId = id;
            await _svc.UpdateModifierGroupAsync(m);
            return NoContent();
        }

        [HttpDelete("modifier-groups/{id}")]
        public async Task<IActionResult> DeleteModifierGroup(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            await _svc.DeleteModifierGroupAsync(id, farmId);
            return NoContent();
        }

        // =====================================================================
        // MODIFIERS
        // =====================================================================

        [HttpGet("modifiers")]
        public async Task<IActionResult> ListModifiers([FromQuery] string farmId, [FromQuery] int? groupId = null)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.ListModifiersAsync(farmId, groupId));
        }

        [HttpPost("modifiers")]
        public async Task<IActionResult> CreateModifier([FromBody] RestaurantModifierModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (auth != null) return auth;
            var id = await _svc.InsertModifierAsync(m);
            return Ok(new { modifierId = id });
        }

        [HttpPut("modifiers/{id}")]
        public async Task<IActionResult> UpdateModifier(int id, [FromBody] RestaurantModifierModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (auth != null) return auth;
            m.ModifierId = id;
            await _svc.UpdateModifierAsync(m);
            return NoContent();
        }

        [HttpDelete("modifiers/{id}")]
        public async Task<IActionResult> DeleteModifier(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            await _svc.DeleteModifierAsync(id, farmId);
            return NoContent();
        }

        // =====================================================================
        // MENU ITEM <-> MODIFIER GROUP ASSIGNMENTS
        // =====================================================================

        [HttpGet("items/{menuItemId}/modifier-groups")]
        public async Task<IActionResult> ListItemModifierGroups(int menuItemId, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.ListItemModifierGroupsAsync(menuItemId, farmId));
        }

        [HttpPost("items/{menuItemId}/modifier-groups")]
        public async Task<IActionResult> AssignModifierGroup(int menuItemId, [FromQuery] string farmId,
            [FromBody] MenuItemModifierGroupAssignRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            var id = await _svc.AssignModifierGroupToItemAsync(farmId, menuItemId, req.ModifierGroupId, req.SortOrder);
            return Ok(new { menuItemModifierGroupId = id });
        }

        [HttpDelete("items/modifier-groups/{id}")]
        public async Task<IActionResult> UnassignModifierGroup(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            await _svc.UnassignModifierGroupFromItemAsync(id, farmId);
            return NoContent();
        }

        // =====================================================================
        // COMBOS
        // =====================================================================

        [HttpGet("combos")]
        public async Task<IActionResult> ListCombos([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.ListCombosAsync(farmId));
        }

        [HttpPost("combos")]
        public async Task<IActionResult> CreateCombo([FromBody] RestaurantComboModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (auth != null) return auth;
            var id = await _svc.InsertComboAsync(m);
            return Ok(new { comboId = id });
        }

        [HttpPut("combos/{id}")]
        public async Task<IActionResult> UpdateCombo(int id, [FromBody] RestaurantComboModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (auth != null) return auth;
            m.ComboId = id;
            await _svc.UpdateComboAsync(m);
            return NoContent();
        }

        [HttpDelete("combos/{id}")]
        public async Task<IActionResult> DeleteCombo(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            await _svc.DeleteComboAsync(id, farmId);
            return NoContent();
        }

        // ---- Combo Items ----

        [HttpGet("combos/{comboId}/items")]
        public async Task<IActionResult> ListComboItems(int comboId, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.ListComboItemsAsync(comboId, farmId));
        }

        [HttpPost("combos/{comboId}/items")]
        public async Task<IActionResult> AddComboItem(int comboId, [FromBody] RestaurantComboItemModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (auth != null) return auth;
            m.ComboId = comboId;
            var id = await _svc.InsertComboItemAsync(m);
            return Ok(new { comboItemId = id });
        }

        [HttpDelete("combos/items/{id}")]
        public async Task<IActionResult> RemoveComboItem(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            await _svc.DeleteComboItemAsync(id, farmId);
            return NoContent();
        }

        // =====================================================================
        // MENU SCHEDULES
        // =====================================================================

        [HttpGet("schedules")]
        public async Task<IActionResult> ListSchedules([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.ListSchedulesAsync(farmId));
        }

        [HttpPost("schedules")]
        public async Task<IActionResult> CreateSchedule([FromBody] RestaurantMenuScheduleModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (auth != null) return auth;
            var id = await _svc.InsertScheduleAsync(m);
            return Ok(new { menuScheduleId = id });
        }

        [HttpPut("schedules/{id}")]
        public async Task<IActionResult> UpdateSchedule(int id, [FromBody] RestaurantMenuScheduleModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (auth != null) return auth;
            m.MenuScheduleId = id;
            await _svc.UpdateScheduleAsync(m);
            return NoContent();
        }

        [HttpDelete("schedules/{id}")]
        public async Task<IActionResult> DeleteSchedule(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            await _svc.DeleteScheduleAsync(id, farmId);
            return NoContent();
        }

        // ---- Schedule Items ----

        [HttpGet("schedules/{scheduleId}/items")]
        public async Task<IActionResult> ListScheduleItems(int scheduleId, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.ListScheduleItemsAsync(scheduleId, farmId));
        }

        [HttpPost("schedules/{scheduleId}/items")]
        public async Task<IActionResult> AssignScheduleItem(int scheduleId, [FromQuery] string farmId,
            [FromBody] ScheduleItemAssignRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            var id = await _svc.AssignItemToScheduleAsync(farmId, scheduleId, req.MenuItemId, req.OverridePrice);
            return Ok(new { menuScheduleItemId = id });
        }

        [HttpDelete("schedules/items/{id}")]
        public async Task<IActionResult> UnassignScheduleItem(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            await _svc.UnassignItemFromScheduleAsync(id, farmId);
            return NoContent();
        }

        // =====================================================================
        // ITEM TAGS
        // =====================================================================

        [HttpGet("items/{menuItemId}/tags")]
        public async Task<IActionResult> ListItemTags(int menuItemId, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.ListItemTagsAsync(menuItemId, farmId));
        }

        [HttpPost("items/{menuItemId}/tags")]
        public async Task<IActionResult> AddItemTag(int menuItemId, [FromQuery] string farmId, [FromBody] ItemTagRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            var id = await _svc.AddItemTagAsync(farmId, menuItemId, req.Tag);
            return Ok(new { itemTagId = id });
        }

        [HttpDelete("items/tags/{id}")]
        public async Task<IActionResult> RemoveItemTag(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            await _svc.RemoveItemTagAsync(id, farmId);
            return NoContent();
        }
    }

    // ---- Request DTOs ----

    public class MenuItemModifierGroupAssignRequest
    {
        public int ModifierGroupId { get; set; }
        public int SortOrder { get; set; }
    }

    public class ScheduleItemAssignRequest
    {
        public int MenuItemId { get; set; }
        public decimal? OverridePrice { get; set; }
    }

    public class ItemTagRequest
    {
        [Required]
        public string Tag { get; set; } = string.Empty;
    }
}
