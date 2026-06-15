// Water Company finance layer services.
//
// Bundled in one file to mirror the WaterDistributionServices.cs / WaterPhase3
// pattern already in the project. Each service maps 1:1 to its SP family from
// migration 048. The transactional SPs (expense approve, transfer approve)
// handle multi-table writes inside SQL Server; the C# side just sends params.

using System.Data;
using System.Data.SqlClient;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    // ====================================================================
    // Expense categories
    // ====================================================================
    public interface IWaterExpenseCategoryService
    {
        Task<List<WaterExpenseCategoryModel>> GetAllAsync(string farmId);
        Task<int>  InsertAsync(WaterExpenseCategoryModel m);
        Task       UpdateAsync(WaterExpenseCategoryModel m);
        Task       DeleteAsync(int id, string farmId);
    }

    public class WaterExpenseCategoryService : IWaterExpenseCategoryService
    {
        private readonly string _cs;
        public WaterExpenseCategoryService(string cs) => _cs = cs;

        public async Task<List<WaterExpenseCategoryModel>> GetAllAsync(string farmId)
        {
            var list = new List<WaterExpenseCategoryModel>();
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterExpenseCategory_GetAll", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(Read(r));
            return list;
        }

        public async Task<int> InsertAsync(WaterExpenseCategoryModel m)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterExpenseCategory_Insert", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Name", m.Name);
            cmd.Parameters.AddWithValue("@Description", (object?)m.Description ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            await c.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateAsync(WaterExpenseCategoryModel m)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterExpenseCategory_Update", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterExpenseCategoryId", m.WaterExpenseCategoryId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Name", m.Name);
            cmd.Parameters.AddWithValue("@Description", (object?)m.Description ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteAsync(int id, string farmId)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterExpenseCategory_Delete", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterExpenseCategoryId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static WaterExpenseCategoryModel Read(SqlDataReader r) => new()
        {
            WaterExpenseCategoryId = r.GetInt32(r.GetOrdinal("WaterExpenseCategoryId")),
            FarmId                 = r.GetString(r.GetOrdinal("FarmId")),
            Name                   = r.GetString(r.GetOrdinal("Name")),
            Description            = r.IsDBNull(r.GetOrdinal("Description")) ? null : r.GetString(r.GetOrdinal("Description")),
            IsActive               = r.GetBoolean(r.GetOrdinal("IsActive")),
            IsDeleted              = r.GetBoolean(r.GetOrdinal("IsDeleted")),
            CreatedAt              = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt              = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };
    }

    // ====================================================================
    // Cash accounts
    // ====================================================================
    public interface IWaterCashAccountService
    {
        Task<List<WaterCashAccountModel>> GetAllAsync(string farmId);
        Task<WaterCashAccountModel?>      GetByIdAsync(int id, string farmId);
        Task<int>  InsertAsync(WaterCashAccountModel m);
        Task       UpdateAsync(WaterCashAccountModel m);
        Task       DeleteAsync(int id, string farmId);
        Task       ReconcileBalanceAsync(string farmId);
        // Manual balance adjustment: signed amount (+ adds, - removes) posts an
        // AdjustmentIn/Out cash transaction and moves the stored balance.
        Task       AdjustAsync(int id, string farmId, decimal amount, string reason, string? createdBy);

        Task<List<WaterCashTransactionModel>> GetTransactionsAsync(
            string farmId, int? cashAccountId, DateTime? fromDate, DateTime? toDate);
    }

    public class WaterCashAccountService : IWaterCashAccountService
    {
        private readonly string _cs;
        public WaterCashAccountService(string cs) => _cs = cs;

        public async Task<List<WaterCashAccountModel>> GetAllAsync(string farmId)
        {
            var list = new List<WaterCashAccountModel>();
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterCashAccount_GetAll", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(Read(r));
            return list;
        }

        public async Task<WaterCashAccountModel?> GetByIdAsync(int id, string farmId)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterCashAccount_GetById", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterCashAccountId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Read(r) : null;
        }

        public async Task<int> InsertAsync(WaterCashAccountModel m)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterCashAccount_Insert", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@AccountName", m.AccountName);
            cmd.Parameters.AddWithValue("@AccountType", m.AccountType);
            cmd.Parameters.AddWithValue("@OpeningBalance", m.OpeningBalance);
            cmd.Parameters.AddWithValue("@AllowNegativeBalance", m.AllowNegativeBalance);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            await c.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateAsync(WaterCashAccountModel m)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterCashAccount_Update", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterCashAccountId", m.WaterCashAccountId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@AccountName", m.AccountName);
            cmd.Parameters.AddWithValue("@AccountType", m.AccountType);
            cmd.Parameters.AddWithValue("@AllowNegativeBalance", m.AllowNegativeBalance);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteAsync(int id, string farmId)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterCashAccount_Delete", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterCashAccountId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task ReconcileBalanceAsync(string farmId)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterCashAccount_ReconcileBalance", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task AdjustAsync(int id, string farmId, decimal amount, string reason, string? createdBy)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterCashAccount_Adjust", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterCashAccountId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Amount", amount);
            cmd.Parameters.AddWithValue("@Reason", (object?)reason ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)createdBy ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<List<WaterCashTransactionModel>> GetTransactionsAsync(
            string farmId, int? cashAccountId, DateTime? fromDate, DateTime? toDate)
        {
            var list = new List<WaterCashTransactionModel>();
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterCashTransaction_GetByFarm", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@WaterCashAccountId", (object?)cashAccountId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ToDate",   (object?)toDate   ?? DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                list.Add(new WaterCashTransactionModel
                {
                    WaterCashTransactionId  = r.GetInt32(r.GetOrdinal("WaterCashTransactionId")),
                    FarmId                  = r.GetString(r.GetOrdinal("FarmId")),
                    WaterCashAccountId      = r.GetInt32(r.GetOrdinal("WaterCashAccountId")),
                    AccountName             = r.IsDBNull(r.GetOrdinal("AccountName")) ? null : r.GetString(r.GetOrdinal("AccountName")),
                    TransactionDate         = r.GetDateTime(r.GetOrdinal("TransactionDate")),
                    TransactionType         = r.GetString(r.GetOrdinal("TransactionType")),
                    SourceType              = r.IsDBNull(r.GetOrdinal("SourceType")) ? null : r.GetString(r.GetOrdinal("SourceType")),
                    SourceId                = r.IsDBNull(r.GetOrdinal("SourceId")) ? null : r.GetInt32(r.GetOrdinal("SourceId")),
                    Amount                  = r.GetDecimal(r.GetOrdinal("Amount")),
                    BalanceAfterTransaction = r.IsDBNull(r.GetOrdinal("BalanceAfterTransaction")) ? null : r.GetDecimal(r.GetOrdinal("BalanceAfterTransaction")),
                    Description             = r.IsDBNull(r.GetOrdinal("Description")) ? null : r.GetString(r.GetOrdinal("Description")),
                    CreatedBy               = r.IsDBNull(r.GetOrdinal("CreatedBy")) ? null : r.GetString(r.GetOrdinal("CreatedBy")),
                    ApprovedBy              = r.IsDBNull(r.GetOrdinal("ApprovedBy")) ? null : r.GetString(r.GetOrdinal("ApprovedBy")),
                    ApprovedAt              = r.IsDBNull(r.GetOrdinal("ApprovedAt")) ? null : r.GetDateTime(r.GetOrdinal("ApprovedAt")),
                    CreatedAt               = r.GetDateTime(r.GetOrdinal("CreatedAt")),
                });
            }
            return list;
        }

        private static WaterCashAccountModel Read(SqlDataReader r) => new()
        {
            WaterCashAccountId   = r.GetInt32(r.GetOrdinal("WaterCashAccountId")),
            FarmId               = r.GetString(r.GetOrdinal("FarmId")),
            AccountName          = r.GetString(r.GetOrdinal("AccountName")),
            AccountType          = r.GetString(r.GetOrdinal("AccountType")),
            OpeningBalance       = r.GetDecimal(r.GetOrdinal("OpeningBalance")),
            CurrentBalance       = r.GetDecimal(r.GetOrdinal("CurrentBalance")),
            AllowNegativeBalance = r.GetBoolean(r.GetOrdinal("AllowNegativeBalance")),
            IsActive             = r.GetBoolean(r.GetOrdinal("IsActive")),
            Notes                = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            CreatedAt            = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt            = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };
    }

    // ====================================================================
    // Cash transfers
    // ====================================================================
    public interface IWaterCashTransferService
    {
        Task<List<WaterCashTransferModel>> GetAllAsync(string farmId, string? status);
        Task<WaterCashTransferModel?>      GetByIdAsync(int id, string farmId);
        Task<int>  InsertAsync(WaterCashTransferModel m);
        Task       ApproveAsync(int id, string farmId, string? approvedBy);
        Task       CancelAsync(int id, string farmId);
    }

    public class WaterCashTransferService : IWaterCashTransferService
    {
        private readonly string _cs;
        public WaterCashTransferService(string cs) => _cs = cs;

        public async Task<List<WaterCashTransferModel>> GetAllAsync(string farmId, string? status)
        {
            var list = new List<WaterCashTransferModel>();
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterCashTransfer_GetAll", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(Read(r));
            return list;
        }

        public async Task<WaterCashTransferModel?> GetByIdAsync(int id, string farmId)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterCashTransfer_GetById", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterCashTransferId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Read(r) : null;
        }

        public async Task<int> InsertAsync(WaterCashTransferModel m)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterCashTransfer_Insert", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@FromWaterCashAccountId", m.FromWaterCashAccountId);
            cmd.Parameters.AddWithValue("@ToWaterCashAccountId",   m.ToWaterCashAccountId);
            cmd.Parameters.AddWithValue("@Amount", m.Amount);
            cmd.Parameters.AddWithValue("@TransferDate",
                m.TransferDate == default ? (object)DBNull.Value : m.TransferDate);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)m.CreatedBy ?? DBNull.Value);
            await c.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task ApproveAsync(int id, string farmId, string? approvedBy)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterCashTransfer_Approve", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterCashTransferId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task CancelAsync(int id, string farmId)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterCashTransfer_Cancel", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterCashTransferId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static WaterCashTransferModel Read(SqlDataReader r) => new()
        {
            WaterCashTransferId    = r.GetInt32(r.GetOrdinal("WaterCashTransferId")),
            FarmId                 = r.GetString(r.GetOrdinal("FarmId")),
            FromWaterCashAccountId = r.GetInt32(r.GetOrdinal("FromWaterCashAccountId")),
            FromAccountName        = r.IsDBNull(r.GetOrdinal("FromAccountName")) ? null : r.GetString(r.GetOrdinal("FromAccountName")),
            ToWaterCashAccountId   = r.GetInt32(r.GetOrdinal("ToWaterCashAccountId")),
            ToAccountName          = r.IsDBNull(r.GetOrdinal("ToAccountName")) ? null : r.GetString(r.GetOrdinal("ToAccountName")),
            TransferDate           = r.GetDateTime(r.GetOrdinal("TransferDate")),
            Amount                 = r.GetDecimal(r.GetOrdinal("Amount")),
            Status                 = r.GetString(r.GetOrdinal("Status")),
            Notes                  = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            CreatedBy              = r.IsDBNull(r.GetOrdinal("CreatedBy")) ? null : r.GetString(r.GetOrdinal("CreatedBy")),
            ApprovedBy             = r.IsDBNull(r.GetOrdinal("ApprovedBy")) ? null : r.GetString(r.GetOrdinal("ApprovedBy")),
            ApprovedAt             = r.IsDBNull(r.GetOrdinal("ApprovedAt")) ? null : r.GetDateTime(r.GetOrdinal("ApprovedAt")),
            CreatedAt              = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt              = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };
    }

    // ====================================================================
    // Expenses (the big one — approval workflow + cash side-effects)
    // ====================================================================
    public interface IWaterExpenseService
    {
        Task<List<WaterExpenseModel>> GetAllAsync(string farmId, string? status, DateTime? fromDate, DateTime? toDate);
        Task<WaterExpenseModel?>      GetByIdAsync(int id, string farmId);
        Task<int>  InsertAsync(WaterExpenseModel m);
        Task       SubmitAsync(int id, string farmId);
        Task       ApproveAsync(int id, string farmId, string? approvedBy);
        Task       RejectAsync(int id, string farmId, string? approvedBy, string? reason);
        Task       CancelAsync(int id, string farmId, string? cancelledBy, string? reason);
        Task       DeleteAsync(int id, string farmId);

        // Per-farm seed (default categories + cash accounts).
        Task<(int categoryCount, int cashAccountCount)> SeedDefaultsAsync(string farmId);
    }

    public class WaterExpenseService : IWaterExpenseService
    {
        private readonly string _cs;
        public WaterExpenseService(string cs) => _cs = cs;

        public async Task<List<WaterExpenseModel>> GetAllAsync(string farmId, string? status, DateTime? fromDate, DateTime? toDate)
        {
            var list = new List<WaterExpenseModel>();
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterExpense_GetAll", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status",   (object?)status   ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ToDate",   (object?)toDate   ?? DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(Read(r));
            return list;
        }

        public async Task<WaterExpenseModel?> GetByIdAsync(int id, string farmId)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterExpense_GetById", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterExpenseId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Read(r) : null;
        }

        public async Task<int> InsertAsync(WaterExpenseModel m)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterExpense_Insert", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@ExpenseDate",
                m.ExpenseDate == default ? (object)DBNull.Value : m.ExpenseDate);
            cmd.Parameters.AddWithValue("@WaterExpenseCategoryId", m.WaterExpenseCategoryId);
            cmd.Parameters.AddWithValue("@Description", (object?)m.Description ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Amount", m.Amount);
            cmd.Parameters.AddWithValue("@PaidTo", (object?)m.PaidTo ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PaymentMethod", m.PaymentMethod);
            cmd.Parameters.AddWithValue("@WaterCashAccountId", (object?)m.WaterCashAccountId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ReceiptUrl", (object?)m.ReceiptUrl ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@LinkedWaterVehicleId",   (object?)m.LinkedWaterVehicleId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@LinkedWaterMachineId",   (object?)m.LinkedWaterMachineId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@LinkedWaterProductionBatchId", (object?)m.LinkedWaterProductionBatchId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)m.CreatedBy ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@SupplierId", (object?)m.SupplierId ?? DBNull.Value);
            await c.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task SubmitAsync(int id, string farmId)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterExpense_Submit", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterExpenseId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task ApproveAsync(int id, string farmId, string? approvedBy)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterExpense_Approve", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterExpenseId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task RejectAsync(int id, string farmId, string? approvedBy, string? reason)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterExpense_Reject", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterExpenseId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Reason", (object?)reason ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task CancelAsync(int id, string farmId, string? cancelledBy, string? reason)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterExpense_Cancel", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterExpenseId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@CancelledBy", (object?)cancelledBy ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Reason", (object?)reason ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteAsync(int id, string farmId)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterExpense_Delete", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterExpenseId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<(int categoryCount, int cashAccountCount)> SeedDefaultsAsync(string farmId)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterFinance_SeedDefaults", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            if (await r.ReadAsync())
            {
                var cats = r.GetInt32(r.GetOrdinal("ExpenseCategoryCount"));
                var accts = r.GetInt32(r.GetOrdinal("CashAccountCount"));
                return (cats, accts);
            }
            return (0, 0);
        }

        private static WaterExpenseModel Read(SqlDataReader r) => new()
        {
            WaterExpenseId               = r.GetInt32(r.GetOrdinal("WaterExpenseId")),
            FarmId                       = r.GetString(r.GetOrdinal("FarmId")),
            ExpenseDate                  = r.GetDateTime(r.GetOrdinal("ExpenseDate")),
            WaterExpenseCategoryId       = r.GetInt32(r.GetOrdinal("WaterExpenseCategoryId")),
            CategoryName                 = r.IsDBNull(r.GetOrdinal("CategoryName")) ? null : r.GetString(r.GetOrdinal("CategoryName")),
            Description                  = r.IsDBNull(r.GetOrdinal("Description")) ? null : r.GetString(r.GetOrdinal("Description")),
            Amount                       = r.GetDecimal(r.GetOrdinal("Amount")),
            PaidTo                       = r.IsDBNull(r.GetOrdinal("PaidTo")) ? null : r.GetString(r.GetOrdinal("PaidTo")),
            PaymentMethod                = r.GetString(r.GetOrdinal("PaymentMethod")),
            WaterCashAccountId           = r.IsDBNull(r.GetOrdinal("WaterCashAccountId")) ? null : r.GetInt32(r.GetOrdinal("WaterCashAccountId")),
            CashAccountName              = r.IsDBNull(r.GetOrdinal("CashAccountName")) ? null : r.GetString(r.GetOrdinal("CashAccountName")),
            ReceiptUrl                   = r.IsDBNull(r.GetOrdinal("ReceiptUrl")) ? null : r.GetString(r.GetOrdinal("ReceiptUrl")),
            LinkedWaterVehicleId         = r.IsDBNull(r.GetOrdinal("LinkedWaterVehicleId")) ? null : r.GetInt32(r.GetOrdinal("LinkedWaterVehicleId")),
            LinkedWaterMachineId         = r.IsDBNull(r.GetOrdinal("LinkedWaterMachineId")) ? null : r.GetInt32(r.GetOrdinal("LinkedWaterMachineId")),
            LinkedWaterProductionBatchId = r.IsDBNull(r.GetOrdinal("LinkedWaterProductionBatchId")) ? null : r.GetInt32(r.GetOrdinal("LinkedWaterProductionBatchId")),
            SupplierId                   = HasCol(r, "SupplierId")   && !r.IsDBNull(r.GetOrdinal("SupplierId"))   ? r.GetInt32(r.GetOrdinal("SupplierId"))    : (int?)null,
            SupplierName                 = HasCol(r, "SupplierName") && !r.IsDBNull(r.GetOrdinal("SupplierName")) ? r.GetString(r.GetOrdinal("SupplierName")) : null,
            SourceType                   = HasCol(r, "SourceType")   && !r.IsDBNull(r.GetOrdinal("SourceType"))   ? r.GetString(r.GetOrdinal("SourceType"))   : null,
            SourceId                     = HasCol(r, "SourceId")     && !r.IsDBNull(r.GetOrdinal("SourceId"))     ? r.GetInt32(r.GetOrdinal("SourceId"))      : (int?)null,
            Status                       = r.GetString(r.GetOrdinal("Status")),
            Notes                        = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            CreatedBy                    = r.IsDBNull(r.GetOrdinal("CreatedBy")) ? null : r.GetString(r.GetOrdinal("CreatedBy")),
            ApprovedBy                   = r.IsDBNull(r.GetOrdinal("ApprovedBy")) ? null : r.GetString(r.GetOrdinal("ApprovedBy")),
            ApprovedAt                   = r.IsDBNull(r.GetOrdinal("ApprovedAt")) ? null : r.GetDateTime(r.GetOrdinal("ApprovedAt")),
            CreatedAt                    = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt                    = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };

        // Defensive column-exists check — lets us add new columns to the SP
        // result set without breaking older deployments where the SP hasn't
        // been refreshed yet (e.g. prod skipping a dev-only migration).
        private static bool HasCol(SqlDataReader r, string name)
        {
            for (int i = 0; i < r.FieldCount; i++)
                if (string.Equals(r.GetName(i), name, StringComparison.OrdinalIgnoreCase))
                    return true;
            return false;
        }
    }

    // ====================================================================
    // WaterSupplier — master list backing the "Paid To" dropdown on the
    // Expense form, the supplier dropdown on Raw Material Purchases, the
    // standalone /water-suppliers page and the Setup tab. See migration 076.
    // ====================================================================
    public interface IWaterSupplierService
    {
        Task<List<WaterSupplierModel>> ListAsync(string farmId, bool includeInactive, bool includeDeleted, string? search);
        Task<WaterSupplierModel?>      GetByIdAsync(int id, string farmId);
        Task<int>                      InsertAsync(WaterSupplierModel m);
        Task                           UpdateAsync(WaterSupplierModel m);
        Task                           DeleteAsync(int id, string farmId, string? deletedBy);
    }

    public class WaterSupplierService : IWaterSupplierService
    {
        private readonly string _cs;
        public WaterSupplierService(string cs) => _cs = cs;

        public async Task<List<WaterSupplierModel>> ListAsync(string farmId, bool includeInactive, bool includeDeleted, string? search)
        {
            var list = new List<WaterSupplierModel>();
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterSupplier_ListByFarm", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@IncludeInactive", includeInactive ? 1 : 0);
            cmd.Parameters.AddWithValue("@IncludeDeleted",  includeDeleted  ? 1 : 0);
            cmd.Parameters.AddWithValue("@Search", (object?)search ?? DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(ReadSupplier(r));
            return list;
        }

        public async Task<WaterSupplierModel?> GetByIdAsync(int id, string farmId)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterSupplier_GetById", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterSupplierId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? ReadSupplier(r) : null;
        }

        public async Task<int> InsertAsync(WaterSupplierModel m)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterSupplier_Insert", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@SupplierName", m.SupplierName);
            cmd.Parameters.AddWithValue("@ContactPerson", (object?)m.ContactPerson ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Phone",         (object?)m.Phone         ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Email",         (object?)m.Email         ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Address",       (object?)m.Address       ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@SupplierType",  (object?)m.SupplierType  ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes",         (object?)m.Notes         ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy",     (object?)m.CreatedBy     ?? DBNull.Value);
            await c.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateAsync(WaterSupplierModel m)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterSupplier_Update", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterSupplierId", m.WaterSupplierId);
            cmd.Parameters.AddWithValue("@FarmId",          m.FarmId);
            cmd.Parameters.AddWithValue("@SupplierName",    m.SupplierName);
            cmd.Parameters.AddWithValue("@ContactPerson",   (object?)m.ContactPerson ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Phone",           (object?)m.Phone         ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Email",           (object?)m.Email         ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Address",         (object?)m.Address       ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@SupplierType",    (object?)m.SupplierType  ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes",           (object?)m.Notes         ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive",        m.IsActive);
            cmd.Parameters.AddWithValue("@UpdatedBy",       (object?)m.UpdatedBy     ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteAsync(int id, string farmId, string? deletedBy)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterSupplier_Delete", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterSupplierId", id);
            cmd.Parameters.AddWithValue("@FarmId",          farmId);
            cmd.Parameters.AddWithValue("@DeletedBy",       (object?)deletedBy ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static WaterSupplierModel ReadSupplier(SqlDataReader r) => new()
        {
            WaterSupplierId = r.GetInt32(r.GetOrdinal("WaterSupplierId")),
            FarmId          = r.GetString(r.GetOrdinal("FarmId")),
            SupplierName    = r.GetString(r.GetOrdinal("SupplierName")),
            ContactPerson   = r.IsDBNull(r.GetOrdinal("ContactPerson")) ? null : r.GetString(r.GetOrdinal("ContactPerson")),
            Phone           = r.IsDBNull(r.GetOrdinal("Phone"))         ? null : r.GetString(r.GetOrdinal("Phone")),
            Email           = r.IsDBNull(r.GetOrdinal("Email"))         ? null : r.GetString(r.GetOrdinal("Email")),
            Address         = r.IsDBNull(r.GetOrdinal("Address"))       ? null : r.GetString(r.GetOrdinal("Address")),
            SupplierType    = r.IsDBNull(r.GetOrdinal("SupplierType"))  ? null : r.GetString(r.GetOrdinal("SupplierType")),
            Notes           = r.IsDBNull(r.GetOrdinal("Notes"))         ? null : r.GetString(r.GetOrdinal("Notes")),
            IsActive        = r.GetBoolean(r.GetOrdinal("IsActive")),
            IsDeleted       = r.GetBoolean(r.GetOrdinal("IsDeleted")),
            CreatedBy       = r.IsDBNull(r.GetOrdinal("CreatedBy"))     ? null : r.GetString(r.GetOrdinal("CreatedBy")),
            CreatedAt       = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedBy       = r.IsDBNull(r.GetOrdinal("UpdatedBy"))     ? null : r.GetString(r.GetOrdinal("UpdatedBy")),
            UpdatedAt       = r.IsDBNull(r.GetOrdinal("UpdatedAt"))     ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };
    }

    // ====================================================================
    // Customer ledger
    // ====================================================================
    public interface IWaterCustomerLedgerService
    {
        Task<List<WaterCustomerLedgerEntryModel>> GetForCustomerAsync(string farmId, int customerId);
        Task<(int id, decimal newBalance)> AddEntryAsync(string farmId, WaterCustomerLedgerAddRequest req, string? createdBy);
    }

    public class WaterCustomerLedgerService : IWaterCustomerLedgerService
    {
        private readonly string _cs;
        public WaterCustomerLedgerService(string cs) => _cs = cs;

        public async Task<List<WaterCustomerLedgerEntryModel>> GetForCustomerAsync(string farmId, int customerId)
        {
            var list = new List<WaterCustomerLedgerEntryModel>();
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterCustomerLedger_GetForCustomer", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@WaterCustomerId", customerId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                list.Add(new WaterCustomerLedgerEntryModel
                {
                    WaterCustomerLedgerId   = r.GetInt32(r.GetOrdinal("WaterCustomerLedgerId")),
                    FarmId                  = r.GetString(r.GetOrdinal("FarmId")),
                    WaterCustomerId         = r.GetInt32(r.GetOrdinal("WaterCustomerId")),
                    TransactionDate         = r.GetDateTime(r.GetOrdinal("TransactionDate")),
                    TransactionType         = r.GetString(r.GetOrdinal("TransactionType")),
                    WaterSaleId             = r.IsDBNull(r.GetOrdinal("WaterSaleId")) ? null : r.GetInt32(r.GetOrdinal("WaterSaleId")),
                    WaterPaymentId          = r.IsDBNull(r.GetOrdinal("WaterPaymentId")) ? null : r.GetInt32(r.GetOrdinal("WaterPaymentId")),
                    DebitAmount             = r.GetDecimal(r.GetOrdinal("DebitAmount")),
                    CreditAmount            = r.GetDecimal(r.GetOrdinal("CreditAmount")),
                    BalanceAfterTransaction = r.GetDecimal(r.GetOrdinal("BalanceAfterTransaction")),
                    Description             = r.IsDBNull(r.GetOrdinal("Description")) ? null : r.GetString(r.GetOrdinal("Description")),
                    CreatedBy               = r.IsDBNull(r.GetOrdinal("CreatedBy")) ? null : r.GetString(r.GetOrdinal("CreatedBy")),
                    CreatedAt               = r.GetDateTime(r.GetOrdinal("CreatedAt")),
                });
            }
            return list;
        }

        public async Task<(int id, decimal newBalance)> AddEntryAsync(string farmId, WaterCustomerLedgerAddRequest req, string? createdBy)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterCustomerLedger_AddEntry", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@WaterCustomerId", req.WaterCustomerId);
            cmd.Parameters.AddWithValue("@TransactionType", req.TransactionType);
            cmd.Parameters.AddWithValue("@WaterSaleId",    (object?)req.WaterSaleId    ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@WaterPaymentId", (object?)req.WaterPaymentId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DebitAmount",  req.DebitAmount);
            cmd.Parameters.AddWithValue("@CreditAmount", req.CreditAmount);
            cmd.Parameters.AddWithValue("@Description",  (object?)req.Description ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy",    (object?)createdBy ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@TransactionDate", (object?)req.TransactionDate ?? DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            if (await r.ReadAsync())
            {
                var id  = r.GetInt32(r.GetOrdinal("WaterCustomerLedgerId"));
                var bal = r.GetDecimal(r.GetOrdinal("BalanceAfterTransaction"));
                return (id, bal);
            }
            return (0, 0m);
        }
    }
}
