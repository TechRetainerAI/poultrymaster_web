using PoultryWeb.Models;

namespace PoultryWeb.Business
{
    public interface IInventoryWebApiService
    {
        Task<List<InventoryItemModel>> GetAllItemsAsync();
        Task<InventoryItemModel?> GetItemByIdAsync(int id);
        Task CreateItemAsync(InventoryItemModel model);
        Task UpdateItemAsync(int id, InventoryItemModel model);
        Task DeleteItemAsync(int id);

        Task<List<InventoryTransactionModel>> GetTransactionsByItemAsync(int itemId);
        Task CreateTransactionAsync(InventoryTransactionModel model);
    }
}
