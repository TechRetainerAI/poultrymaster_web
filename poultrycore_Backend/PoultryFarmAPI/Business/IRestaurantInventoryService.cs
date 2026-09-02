using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IRestaurantInventoryService
    {
        // Ingredients
        Task<List<RestaurantIngredientModel>> ListIngredientsAsync(string farmId, string? category = null);
        Task<int> InsertIngredientAsync(RestaurantIngredientModel m);
        Task UpdateIngredientAsync(RestaurantIngredientModel m);
        Task DeleteIngredientAsync(int id, string farmId);
        Task AdjustStockAsync(int id, string farmId, decimal quantity, string movementType, string reason, string createdBy);
        Task<List<RestaurantIngredientModel>> GetLowStockAsync(string farmId);

        // Recipes
        Task<List<RestaurantRecipeModel>> ListRecipeAsync(int menuItemId, string farmId);
        Task<int> UpsertRecipeAsync(string farmId, int menuItemId, int ingredientId, decimal quantity, string unit, decimal wastePercent, string? notes);
        Task DeleteRecipeAsync(int id, string farmId);
        Task<FoodCostModel> GetFoodCostAsync(int menuItemId, string farmId);
        Task<int> DeductOrderStockAsync(int orderId, string farmId);

        // Waste
        Task<List<RestaurantWasteLogModel>> ListWasteAsync(string farmId, DateTime? fromDate = null, DateTime? toDate = null);
        Task<int> LogWasteAsync(RestaurantWasteLogModel m);
        Task<List<WasteSummaryModel>> GetWasteSummaryAsync(string farmId, DateTime? fromDate = null, DateTime? toDate = null);

        // Stock Takes
        Task<List<RestaurantStockTakeModel>> ListStockTakesAsync(string farmId);
        Task<int> CreateStockTakeAsync(string farmId, string? notes);
        Task<List<RestaurantStockTakeItemModel>> GetStockTakeItemsAsync(int stockTakeId, string farmId);
        Task UpdateStockTakeItemAsync(int id, string farmId, decimal actualQty, string? notes);
        Task CompleteStockTakeAsync(int id, string farmId, string completedBy);

        // Reports
        Task<List<InventoryValueModel>> GetInventoryValueAsync(string farmId);
    }
}
