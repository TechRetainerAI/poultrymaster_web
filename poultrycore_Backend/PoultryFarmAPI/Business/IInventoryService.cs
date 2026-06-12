using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IInventoryService
    {
        Task<List<InventoryItemModel>> GetAllItemsAsync(string userId, string farmId);
        Task<InventoryItemModel?> GetItemByIdAsync(int itemId, string userId, string farmId);
        Task<int> CreateItemAsync(InventoryItemModel model);
        Task UpdateItemAsync(InventoryItemModel model);
        Task DeleteItemAsync(int itemId, string userId, string farmId);

        Task<List<InventoryTransactionModel>> GetTransactionsByItemAsync(int itemId, string userId, string farmId);
        Task<int> CreateTransactionAsync(InventoryTransactionModel model);
    }

}