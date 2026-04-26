using PoultryFarmAPIWeb.Models;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace PoultryFarmAPIWeb.Business
{
    public interface IExpenseService
    {
        // Insert a new expense (model should include UserId and FarmId).
        Task<int> Insert(ExpenseModel model);

        // Update an existing expense (model should include UserId and FarmId).
        Task Update(ExpenseModel model);

        // Get a specific expense by ID, scoped to a user and farm.
        Task<ExpenseModel?> GetById(int expenseId, string userId, string farmId);

        // Get all expenses for a specific user and farm.
        Task<List<ExpenseModel>> GetAll(string userId, string farmId);

        // Delete an expense for a specific user and farm.
        Task Delete(int expenseId, string userId, string farmId);

        // Get expenses for a specific flock, user, and farm.
        Task<List<ExpenseModel>> GetByFlock(int flockId, string userId, string farmId);
    }

}
