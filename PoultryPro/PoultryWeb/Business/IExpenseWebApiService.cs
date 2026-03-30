using PoultryWeb.Models;

namespace PoultryWeb.Business
{
    public interface IExpenseWebApiService
    {
        Task<List<ExpenseModel>> GetAllAsync();
        Task<ExpenseModel?> GetByIdAsync(int expenseId);
        Task<ExpenseModel?> CreateAsync(ExpenseModel model);
        Task UpdateAsync(int expenseId, ExpenseModel model);
        Task DeleteAsync(int expenseId);

        // Optional if you want to fetch expenses by Flock
        Task<List<ExpenseModel>> GetByFlockAsync(int flockId);
    }
}
