using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IRestaurantMenuService
    {
        // Menu Categories
        Task<List<RestaurantMenuCategoryModel>> ListCategoriesAsync(string farmId);
        Task<RestaurantMenuCategoryModel?> GetCategoryAsync(int id, string farmId);
        Task<int> InsertCategoryAsync(RestaurantMenuCategoryModel m);
        Task UpdateCategoryAsync(RestaurantMenuCategoryModel m);
        Task DeleteCategoryAsync(int id, string farmId);

        // Menu Items
        Task<List<RestaurantMenuItemModel>> ListItemsAsync(string farmId, int? categoryId = null);
        Task<RestaurantMenuItemModel?> GetItemAsync(int id, string farmId);
        Task<int> InsertItemAsync(RestaurantMenuItemModel m);
        Task UpdateItemAsync(RestaurantMenuItemModel m);
        Task DeleteItemAsync(int id, string farmId);
        Task ToggleItemAvailabilityAsync(int id, string farmId, bool isAvailable);

        // Modifier Groups
        Task<List<RestaurantModifierGroupModel>> ListModifierGroupsAsync(string farmId);
        Task<int> InsertModifierGroupAsync(RestaurantModifierGroupModel m);
        Task UpdateModifierGroupAsync(RestaurantModifierGroupModel m);
        Task DeleteModifierGroupAsync(int id, string farmId);

        // Modifiers
        Task<List<RestaurantModifierModel>> ListModifiersAsync(string farmId, int? groupId = null);
        Task<int> InsertModifierAsync(RestaurantModifierModel m);
        Task UpdateModifierAsync(RestaurantModifierModel m);
        Task DeleteModifierAsync(int id, string farmId);

        // Menu Item <-> Modifier Group assignments
        Task<List<RestaurantMenuItemModifierGroupModel>> ListItemModifierGroupsAsync(int menuItemId, string farmId);
        Task<int> AssignModifierGroupToItemAsync(string farmId, int menuItemId, int modifierGroupId, int sortOrder);
        Task UnassignModifierGroupFromItemAsync(int id, string farmId);

        // Combos
        Task<List<RestaurantComboModel>> ListCombosAsync(string farmId);
        Task<int> InsertComboAsync(RestaurantComboModel m);
        Task UpdateComboAsync(RestaurantComboModel m);
        Task DeleteComboAsync(int id, string farmId);

        // Combo Items
        Task<List<RestaurantComboItemModel>> ListComboItemsAsync(int comboId, string farmId);
        Task<int> InsertComboItemAsync(RestaurantComboItemModel m);
        Task DeleteComboItemAsync(int id, string farmId);

        // Menu Schedules
        Task<List<RestaurantMenuScheduleModel>> ListSchedulesAsync(string farmId);
        Task<int> InsertScheduleAsync(RestaurantMenuScheduleModel m);
        Task UpdateScheduleAsync(RestaurantMenuScheduleModel m);
        Task DeleteScheduleAsync(int id, string farmId);

        // Schedule Items
        Task<List<RestaurantMenuScheduleItemModel>> ListScheduleItemsAsync(int scheduleId, string farmId);
        Task<int> AssignItemToScheduleAsync(string farmId, int scheduleId, int menuItemId, decimal? overridePrice);
        Task UnassignItemFromScheduleAsync(int id, string farmId);

        // Item Tags
        Task<List<RestaurantItemTagModel>> ListItemTagsAsync(int menuItemId, string farmId);
        Task<int> AddItemTagAsync(string farmId, int menuItemId, string tag);
        Task RemoveItemTagAsync(int id, string farmId);
    }
}
