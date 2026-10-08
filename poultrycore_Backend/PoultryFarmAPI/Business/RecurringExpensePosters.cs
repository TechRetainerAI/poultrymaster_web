using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    // =========================================================================
    // Recurring Expense Engine (migration 348) -- the per-module adapters.
    //
    // Each one turns a claimed occurrence into an expense through that module's
    // EXISTING create path -- the same call its own Expenses page makes -- so
    // cash, supplier payments, payables and approvals stay that module's:
    //
    //   poultry     IExpenseService.Insert          posted; cash moves now if paid
    //   restaurant  IRestaurantExpenseService       posted; cash moves now if paid
    //   water       IWaterExpenseService            created Draft; cash on approval
    //   generic     IGenericExpenseRecordService    created Pending; cash on approval
    //   hotel       hotelexpenses (Draft)           created Draft; cash on approval
    //
    // A credit occurrence is created unpaid, so it becomes a payable under the
    // module's rules and moves no cash.
    // =========================================================================

    public interface IRecurringExpensePoster
    {
        string Module { get; }
        /// <summary>The module approves expenses itself, after creation.</summary>
        bool ModuleApproves { get; }
        Task<int> CreateExpenseAsync(string farmId, RecurringExpenseClaim c, string? actor);
    }

    public class PoultryRecurringExpensePoster : IRecurringExpensePoster
    {
        private readonly IExpenseService _expenses;
        public PoultryRecurringExpensePoster(IExpenseService expenses) => _expenses = expenses;
        public string Module => "poultry";
        public bool ModuleApproves => false;

        public Task<int> CreateExpenseAsync(string farmId, RecurringExpenseClaim c, string? actor) =>
            _expenses.Insert(new ExpenseModel
            {
                FarmId = farmId,
                UserId = actor ?? string.Empty,
                ExpenseDate = c.ExpenseDate.Date,
                Category = c.CategoryName ?? "Other",
                Description = c.Description,
                Amount = c.Amount,
                PaymentMethod = c.PaymentMethod,
                Supplier = c.PayeeName,
                SupplierId = c.SupplierId,
                // spexpense_insert: NULL = paid in full; with a supplier and a cash
                // account, a stated amount becomes a real supplier payment (245);
                // 0 = owed in full (a payable, no cash).
                AmountPaid = c.IsCredit ? 0m : (c.SupplierId.HasValue ? c.Amount : (decimal?)null),
                PoultryCashAccountId = c.IsCredit ? null : c.CashAccountId,
            });
    }

    public class RestaurantRecurringExpensePoster : IRecurringExpensePoster
    {
        private readonly IRestaurantExpenseService _expenses;
        public RestaurantRecurringExpensePoster(IRestaurantExpenseService expenses) => _expenses = expenses;
        public string Module => "restaurant";
        public bool ModuleApproves => false;

        public Task<int> CreateExpenseAsync(string farmId, RecurringExpenseClaim c, string? actor) =>
            _expenses.InsertExpenseAsync(new RestaurantExpenseModel
            {
                FarmId = farmId,
                ExpenseDate = c.ExpenseDate.Date,
                CategoryId = c.CategoryId,
                CategoryName = c.CategoryName,
                Description = c.Description ?? "Recurring expense",
                Amount = c.Amount,
                PaymentMethod = c.PaymentMethod,
                SupplierName = c.PayeeName,
                SupplierId = c.SupplierId,
                CashAccountId = c.IsCredit ? null : c.CashAccountId,
                AmountPaid = c.IsCredit ? 0m : (decimal?)null,
                ReceiptRef = $"REC-{c.OccurrenceId}",
                CreatedBy = actor,
            });
    }

    public class WaterRecurringExpensePoster : IRecurringExpensePoster
    {
        private readonly IWaterExpenseService _expenses;
        public WaterRecurringExpensePoster(IWaterExpenseService expenses) => _expenses = expenses;
        public string Module => "water";
        public bool ModuleApproves => true;

        public async Task<int> CreateExpenseAsync(string farmId, RecurringExpenseClaim c, string? actor)
        {
            var id = await _expenses.InsertAsync(new WaterExpenseModel
            {
                FarmId = farmId,
                ExpenseDate = c.ExpenseDate.Date,
                WaterExpenseCategoryId = c.CategoryId ?? 0,
                Description = c.Description,
                Amount = c.Amount,
                PaidTo = c.PayeeName,
                PaymentMethod = c.PaymentMethod,
                WaterCashAccountId = c.IsCredit ? null : c.CashAccountId,
                SupplierId = c.SupplierId,
                Notes = c.Note,
                CreatedBy = actor,
            });
            // The Water Expenses form does the same right after saving: 0 = owed in full.
            if (c.IsCredit)
                await _expenses.SetPaymentAsync(id, farmId, 0m, null);
            return id;
        }
    }

    public class GenericRecurringExpensePoster : IRecurringExpensePoster
    {
        private readonly IGenericExpenseRecordService _expenses;
        public GenericRecurringExpensePoster(IGenericExpenseRecordService expenses) => _expenses = expenses;
        public string Module => "generic";
        public bool ModuleApproves => true;

        public Task<int> CreateExpenseAsync(string farmId, RecurringExpenseClaim c, string? actor) =>
            _expenses.InsertAsync(new GenericExpenseModel
            {
                FarmId = farmId,
                ExpenseDate = c.ExpenseDate.Date,
                GenericExpenseCategoryId = c.CategoryId ?? 0,
                GenericSupplierId = c.SupplierId,
                Description = c.Description,
                Amount = c.Amount,
                PaidTo = c.PayeeName,
                PaymentMethod = c.PaymentMethod,
                GenericCashAccountId = c.IsCredit ? null : c.CashAccountId,
                Notes = c.Note,
                CreatedBy = actor,
            });
    }

    /// <summary>
    /// Hotel has no expense service: its Expenses page inserts a Draft row
    /// directly (HotelFinanceController.CreateExpense). This writes the same row
    /// the same way; Submit/Approve then post the cash exactly as for any other
    /// hotel expense.
    /// </summary>
    public class HotelRecurringExpensePoster : IRecurringExpensePoster
    {
        private readonly string _cs;
        public HotelRecurringExpensePoster(string cs) => _cs = cs;
        public string Module => "hotel";
        public bool ModuleApproves => true;

        public async Task<int> CreateExpenseAsync(string farmId, RecurringExpenseClaim c, string? actor)
        {
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            using var cmd = new NpgsqlCommand(
                "INSERT INTO hotelexpenses(farmid,category,description,amount,expensedate,vendor,notes,paymentmethod,hotelcashaccountid,paidto,hotelexpensecategoryid,status,hotelsupplierid) " +
                "VALUES(@f,@c,@d,@a,@e::date,@v,@n,@pm,@ca,@pt,@eci,'Draft',@sid) RETURNING hotelexpenseid", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            cmd.Parameters.AddWithValue("@c", c.CategoryName ?? "Other");
            cmd.Parameters.AddWithValue("@d", c.Description ?? "Recurring expense");
            cmd.Parameters.AddWithValue("@a", c.Amount);
            cmd.Parameters.AddWithValue("@e", c.ExpenseDate.ToString("yyyy-MM-dd"));
            cmd.Parameters.AddWithValue("@v", (object?)c.PayeeName ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@n", (object?)c.Note ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@pm", c.PaymentMethod);
            cmd.Parameters.AddWithValue("@ca", c.IsCredit ? DBNull.Value : (object?)c.CashAccountId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@pt", (object?)c.PayeeName ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@eci", (object?)c.CategoryId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@sid", (object?)c.SupplierId ?? DBNull.Value);
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }
    }
}
