// Water Company finance layer services.
//
// Bundled in one file to mirror the WaterDistributionServices.cs / WaterPhase3
// pattern already in the project. Each service maps 1:1 to its SP family from
// migration 048. The transactional SPs (expense approve, transfer approve)
// handle multi-table writes inside SQL Server; the C# side just sends params.

using System.Data;
using Npgsql;
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
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwaterexpensecategory_getall(p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(Read(r));
            return list;
        }

        public async Task<int> InsertAsync(WaterExpenseCategoryModel m)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwaterexpensecategory_insert(p_farmid => @FarmId::text, p_name => @Name::text, p_description => @Description::text, p_isactive => @IsActive::boolean)", c);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Name", m.Name);
            cmd.Parameters.AddWithValue("@Description", (object?)m.Description ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            await c.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateAsync(WaterExpenseCategoryModel m)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwaterexpensecategory_update(p_waterexpensecategoryid => @WaterExpenseCategoryId::int, p_farmid => @FarmId::text, p_name => @Name::text, p_description => @Description::text, p_isactive => @IsActive::boolean)", c);
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
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwaterexpensecategory_delete(p_waterexpensecategoryid => @WaterExpenseCategoryId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@WaterExpenseCategoryId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static WaterExpenseCategoryModel Read(NpgsqlDataReader r) => new()
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
            string farmId, int? cashAccountId, DateTime? fromDate, DateTime? toDate,
            string? clearingStatus = null);
    }

    public class WaterCashAccountService : IWaterCashAccountService
    {
        private readonly string _cs;
        public WaterCashAccountService(string cs) => _cs = cs;

        public async Task<List<WaterCashAccountModel>> GetAllAsync(string farmId)
        {
            var list = new List<WaterCashAccountModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwatercashaccount_getall(p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(Read(r));
            return list;
        }

        public async Task<WaterCashAccountModel?> GetByIdAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwatercashaccount_getbyid(p_watercashaccountid => @WaterCashAccountId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@WaterCashAccountId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Read(r) : null;
        }

        public async Task<int> InsertAsync(WaterCashAccountModel m)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwatercashaccount_insert(p_farmid => @FarmId::text, p_accountname => @AccountName::text, p_accounttype => @AccountType::text, p_openingbalance => @OpeningBalance::numeric, p_allownegativebalance => @AllowNegativeBalance::boolean, p_notes => @Notes::text)", c);
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
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwatercashaccount_update(p_watercashaccountid => @WaterCashAccountId::int, p_farmid => @FarmId::text, p_accountname => @AccountName::text, p_accounttype => @AccountType::text, p_allownegativebalance => @AllowNegativeBalance::boolean, p_isactive => @IsActive::boolean, p_notes => @Notes::text)", c);
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
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwatercashaccount_delete(p_watercashaccountid => @WaterCashAccountId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@WaterCashAccountId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task ReconcileBalanceAsync(string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwatercashaccount_reconcilebalance(p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task AdjustAsync(int id, string farmId, decimal amount, string reason, string? createdBy)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwatercashaccount_adjust(p_watercashaccountid => @WaterCashAccountId::int, p_farmid => @FarmId::text, p_amount => @Amount::numeric, p_reason => @Reason::text, p_createdby => @CreatedBy::text)", c);
            cmd.Parameters.AddWithValue("@WaterCashAccountId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Amount", amount);
            cmd.Parameters.AddWithValue("@Reason", (object?)reason ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)createdBy ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // Reads through spwatercashtransaction_getledger (migration 222) rather
        // than the older spwatercashtransaction_getbyfarm: same first 15 columns,
        // plus clearing status. The old function is left in place untouched —
        // its Postgres body is not in this repo, so it cannot be safely altered.
        public async Task<List<WaterCashTransactionModel>> GetTransactionsAsync(
            string farmId, int? cashAccountId, DateTime? fromDate, DateTime? toDate,
            string? clearingStatus = null)
        {
            var list = new List<WaterCashTransactionModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwatercashtransaction_getledger(p_farmid => @FarmId::text, p_watercashaccountid => @WaterCashAccountId::int, p_fromdate => @FromDate::timestamp, p_todate => @ToDate::timestamp, p_clearingstatus => @ClearingStatus::text, p_watercashreconciliationid => NULL)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@WaterCashAccountId", (object?)cashAccountId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ToDate",   (object?)toDate   ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ClearingStatus", (object?)clearingStatus ?? DBNull.Value);
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
                    ClearingStatus          = r.IsDBNull(r.GetOrdinal("ClearingStatus")) ? null : r.GetString(r.GetOrdinal("ClearingStatus")),
                    ClearedDate             = r.IsDBNull(r.GetOrdinal("ClearedDate")) ? null : r.GetDateTime(r.GetOrdinal("ClearedDate")),
                    ClearedBy               = r.IsDBNull(r.GetOrdinal("ClearedBy")) ? null : r.GetString(r.GetOrdinal("ClearedBy")),
                    WaterCashReconciliationId = r.IsDBNull(r.GetOrdinal("WaterCashReconciliationId")) ? null : r.GetInt32(r.GetOrdinal("WaterCashReconciliationId")),
                    ClearingNotes           = r.IsDBNull(r.GetOrdinal("ClearingNotes")) ? null : r.GetString(r.GetOrdinal("ClearingNotes")),
                    ReconciliationReference = r.IsDBNull(r.GetOrdinal("ReconciliationReference")) ? null : r.GetString(r.GetOrdinal("ReconciliationReference")),
                });
            }
            return list;
        }

        private static WaterCashAccountModel Read(NpgsqlDataReader r) => new()
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
    // Cash reconciliation (migration 222)
    // ====================================================================
    // A CASH COUNT: compare what was counted against what the ledger says and
    // post the difference. Not to be confused with
    // IWaterCashAccountService.ReconcileBalancesAsync, which recomputes the
    // cached balance from the ledger and moves no money.
    public interface IWaterCashReconciliationService
    {
        Task<List<WaterCashReconciliationModel>> GetAllAsync(
            string farmId, int? cashAccountId, string? status, DateTime? fromDate, DateTime? toDate);
        Task<WaterCashReconciliationModel?> GetByIdAsync(int id, string farmId);
        Task<List<WaterCashReconciliationModel>> GetByAccountAsync(int cashAccountId, string farmId);
        Task<List<WaterCashAccountReconStatusModel>> GetAccountStatusAsync(string farmId);
        Task<int> InsertAsync(string farmId, int cashAccountId, DateTime? date,
                              decimal? actualBalance, string? reason, string? notes, string? createdBy);
        Task UpdateAsync(int id, string farmId, DateTime? date, decimal? actualBalance,
                         string? reason, string? notes, string? updatedBy);
        Task DeleteAsync(int id, string farmId, string? userId);
        /// <summary>Returns the adjustment transaction id, or null when the
        /// count balanced and no transaction was needed.</summary>
        Task<int?> PostAsync(int id, string farmId, string? postedBy, IEnumerable<int>? clearedTransactionIds);
        Task ReverseAsync(int id, string farmId, string? reason, string? reversedBy);
        Task<int> SetClearingAsync(string farmId, int cashAccountId, IEnumerable<int> transactionIds,
                                   string clearingStatus, string? notes, string? userId);
    }

    public class WaterCashReconciliationService : IWaterCashReconciliationService
    {
        private readonly string _cs;
        public WaterCashReconciliationService(string cs) => _cs = cs;

        public async Task<List<WaterCashReconciliationModel>> GetAllAsync(
            string farmId, int? cashAccountId, string? status, DateTime? fromDate, DateTime? toDate)
        {
            var list = new List<WaterCashReconciliationModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwatercashreconciliation_getall(p_farmid => @FarmId::text, p_watercashaccountid => @AccountId::int, p_status => @Status::text, p_fromdate => @FromDate::timestamp, p_todate => @ToDate::timestamp)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@AccountId", (object?)cashAccountId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ToDate", (object?)toDate ?? DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(Read(r));
            return list;
        }

        public async Task<WaterCashReconciliationModel?> GetByIdAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwatercashreconciliation_getbyid(p_watercashreconciliationid => @Id::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Read(r) : null;
        }

        public async Task<List<WaterCashReconciliationModel>> GetByAccountAsync(int cashAccountId, string farmId)
        {
            var list = new List<WaterCashReconciliationModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwatercashreconciliation_getbyaccount(p_watercashaccountid => @AccountId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@AccountId", cashAccountId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(Read(r));
            return list;
        }

        public async Task<List<WaterCashAccountReconStatusModel>> GetAccountStatusAsync(string farmId)
        {
            var list = new List<WaterCashAccountReconStatusModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwatercashreconciliation_getaccountstatus(p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                list.Add(new WaterCashAccountReconStatusModel
                {
                    WaterCashAccountId    = r.GetInt32(r.GetOrdinal("WaterCashAccountId")),
                    AccountName           = r.GetString(r.GetOrdinal("AccountName")),
                    AccountType           = r.IsDBNull(r.GetOrdinal("AccountType")) ? null : r.GetString(r.GetOrdinal("AccountType")),
                    IsActive              = r.GetBoolean(r.GetOrdinal("IsActive")),
                    CurrentBalance        = r.GetDecimal(r.GetOrdinal("CurrentBalance")),
                    LedgerBalance         = r.GetDecimal(r.GetOrdinal("LedgerBalance")),
                    CacheDrift            = r.GetDecimal(r.GetOrdinal("CacheDrift")),
                    LastReconciledAt      = r.IsDBNull(r.GetOrdinal("LastReconciledAt")) ? null : r.GetDateTime(r.GetOrdinal("LastReconciledAt")),
                    LastReconciledBalance = r.IsDBNull(r.GetOrdinal("LastReconciledBalance")) ? null : r.GetDecimal(r.GetOrdinal("LastReconciledBalance")),
                    DaysSinceReconciled   = r.IsDBNull(r.GetOrdinal("DaysSinceReconciled")) ? null : r.GetInt32(r.GetOrdinal("DaysSinceReconciled")),
                    UnclearedCount        = r.GetInt64(r.GetOrdinal("UnclearedCount")),
                    UnclearedAmount       = r.GetDecimal(r.GetOrdinal("UnclearedAmount")),
                    OpenDraftId           = r.IsDBNull(r.GetOrdinal("OpenDraftId")) ? null : r.GetInt32(r.GetOrdinal("OpenDraftId")),
                });
            }
            return list;
        }

        public async Task<int> InsertAsync(string farmId, int cashAccountId, DateTime? date,
                                           decimal? actualBalance, string? reason, string? notes, string? createdBy)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT public.spwatercashreconciliation_insert(p_farmid => @FarmId::text, p_watercashaccountid => @AccountId::int, p_reconciliationdate => @Date::timestamp, p_actualbalance => @Actual::numeric, p_reason => @Reason::text, p_notes => @Notes::text, p_createdby => @CreatedBy::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@AccountId", cashAccountId);
            cmd.Parameters.AddWithValue("@Date", (object?)date ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Actual", (object?)actualBalance ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Reason", (object?)reason ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)createdBy ?? DBNull.Value);
            await c.OpenAsync();
            var o = await cmd.ExecuteScalarAsync();
            return o is null || o is DBNull ? 0 : Convert.ToInt32(o);
        }

        public async Task UpdateAsync(int id, string farmId, DateTime? date, decimal? actualBalance,
                                      string? reason, string? notes, string? updatedBy)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT public.spwatercashreconciliation_update(p_watercashreconciliationid => @Id::int, p_farmid => @FarmId::text, p_reconciliationdate => @Date::timestamp, p_actualbalance => @Actual::numeric, p_reason => @Reason::text, p_notes => @Notes::text, p_updatedby => @UpdatedBy::text)", c);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Date", (object?)date ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Actual", (object?)actualBalance ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Reason", (object?)reason ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@UpdatedBy", (object?)updatedBy ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteAsync(int id, string farmId, string? userId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT public.spwatercashreconciliation_delete(p_watercashreconciliationid => @Id::int, p_farmid => @FarmId::text, p_userid => @UserId::text)", c);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@UserId", (object?)userId ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<int?> PostAsync(int id, string farmId, string? postedBy,
                                          IEnumerable<int>? clearedTransactionIds)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT public.spwatercashreconciliation_post(p_watercashreconciliationid => @Id::int, p_farmid => @FarmId::text, p_postedby => @PostedBy::text, p_clearedtransactionidsjson => @Ids::text)", c);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@PostedBy", (object?)postedBy ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Ids", System.Text.Json.JsonSerializer.Serialize(
                clearedTransactionIds ?? Enumerable.Empty<int>()));
            await c.OpenAsync();
            var o = await cmd.ExecuteScalarAsync();
            // NULL is the balanced case: no adjustment transaction was needed.
            return o is null || o is DBNull ? (int?)null : Convert.ToInt32(o);
        }

        public async Task ReverseAsync(int id, string farmId, string? reason, string? reversedBy)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT public.spwatercashreconciliation_reverse(p_watercashreconciliationid => @Id::int, p_farmid => @FarmId::text, p_reason => @Reason::text, p_reversedby => @ReversedBy::text)", c);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Reason", (object?)reason ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ReversedBy", (object?)reversedBy ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<int> SetClearingAsync(string farmId, int cashAccountId, IEnumerable<int> transactionIds,
                                                string clearingStatus, string? notes, string? userId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT public.spwatercashtransaction_setclearing(p_farmid => @FarmId::text, p_watercashaccountid => @AccountId::int, p_transactionidsjson => @Ids::text, p_clearingstatus => @Status::text, p_clearingnotes => @Notes::text, p_userid => @UserId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@AccountId", cashAccountId);
            cmd.Parameters.AddWithValue("@Ids", System.Text.Json.JsonSerializer.Serialize(
                transactionIds ?? Enumerable.Empty<int>()));
            cmd.Parameters.AddWithValue("@Status", clearingStatus);
            cmd.Parameters.AddWithValue("@Notes", (object?)notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@UserId", (object?)userId ?? DBNull.Value);
            await c.OpenAsync();
            var o = await cmd.ExecuteScalarAsync();
            return o is null || o is DBNull ? 0 : Convert.ToInt32(o);
        }

        private static WaterCashReconciliationModel Read(NpgsqlDataReader r) => new()
        {
            WaterCashReconciliationId = r.GetInt32(r.GetOrdinal("WaterCashReconciliationId")),
            FarmId                    = r.GetString(r.GetOrdinal("FarmId")),
            WaterCashAccountId        = r.GetInt32(r.GetOrdinal("WaterCashAccountId")),
            AccountName               = r.IsDBNull(r.GetOrdinal("AccountName")) ? null : r.GetString(r.GetOrdinal("AccountName")),
            AccountType               = r.IsDBNull(r.GetOrdinal("AccountType")) ? null : r.GetString(r.GetOrdinal("AccountType")),
            ReferenceNo               = r.IsDBNull(r.GetOrdinal("ReferenceNo")) ? null : r.GetString(r.GetOrdinal("ReferenceNo")),
            ReconciliationDate        = r.GetDateTime(r.GetOrdinal("ReconciliationDate")),
            SystemBalance             = r.GetDecimal(r.GetOrdinal("SystemBalance")),
            SystemBalanceCached       = r.IsDBNull(r.GetOrdinal("SystemBalanceCached")) ? null : r.GetDecimal(r.GetOrdinal("SystemBalanceCached")),
            ActualBalance             = r.IsDBNull(r.GetOrdinal("ActualBalance")) ? null : r.GetDecimal(r.GetOrdinal("ActualBalance")),
            Difference                = r.GetDecimal(r.GetOrdinal("Difference")),
            AdjustmentTransactionId   = r.IsDBNull(r.GetOrdinal("AdjustmentTransactionId")) ? null : r.GetInt32(r.GetOrdinal("AdjustmentTransactionId")),
            ReversalTransactionId     = r.IsDBNull(r.GetOrdinal("ReversalTransactionId")) ? null : r.GetInt32(r.GetOrdinal("ReversalTransactionId")),
            ClearedCount              = r.GetInt32(r.GetOrdinal("ClearedCount")),
            ClearedAmount             = r.GetDecimal(r.GetOrdinal("ClearedAmount")),
            Reason                    = r.IsDBNull(r.GetOrdinal("Reason")) ? null : r.GetString(r.GetOrdinal("Reason")),
            Notes                     = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            Status                    = r.GetString(r.GetOrdinal("Status")),
            CreatedBy                 = r.IsDBNull(r.GetOrdinal("CreatedBy")) ? null : r.GetString(r.GetOrdinal("CreatedBy")),
            CreatedAt                 = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt                 = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
            PostedBy                  = r.IsDBNull(r.GetOrdinal("PostedBy")) ? null : r.GetString(r.GetOrdinal("PostedBy")),
            PostedAt                  = r.IsDBNull(r.GetOrdinal("PostedAt")) ? null : r.GetDateTime(r.GetOrdinal("PostedAt")),
            ReversedBy                = r.IsDBNull(r.GetOrdinal("ReversedBy")) ? null : r.GetString(r.GetOrdinal("ReversedBy")),
            ReversedAt                = r.IsDBNull(r.GetOrdinal("ReversedAt")) ? null : r.GetDateTime(r.GetOrdinal("ReversedAt")),
            ReversalReason            = r.IsDBNull(r.GetOrdinal("ReversalReason")) ? null : r.GetString(r.GetOrdinal("ReversalReason")),
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
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwatercashtransfer_getall(p_farmid => @FarmId::text, p_status => @Status::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(Read(r));
            return list;
        }

        public async Task<WaterCashTransferModel?> GetByIdAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwatercashtransfer_getbyid(p_watercashtransferid => @WaterCashTransferId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@WaterCashTransferId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Read(r) : null;
        }

        public async Task<int> InsertAsync(WaterCashTransferModel m)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwatercashtransfer_insert(p_farmid => @FarmId::text, p_fromwatercashaccountid => @FromWaterCashAccountId::int, p_towatercashaccountid => @ToWaterCashAccountId::int, p_amount => @Amount::numeric, p_transferdate => @TransferDate::timestamp, p_notes => @Notes::text, p_createdby => @CreatedBy::text)", c);
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
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwatercashtransfer_approve(p_watercashtransferid => @WaterCashTransferId::int, p_farmid => @FarmId::text, p_approvedby => @ApprovedBy::text)", c);
            cmd.Parameters.AddWithValue("@WaterCashTransferId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task CancelAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwatercashtransfer_cancel(p_watercashtransferid => @WaterCashTransferId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@WaterCashTransferId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static WaterCashTransferModel Read(NpgsqlDataReader r) => new()
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
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwaterexpense_getall(p_farmid => @FarmId::text, p_status => @Status::text, p_fromdate => @FromDate::timestamp, p_todate => @ToDate::timestamp)", c);
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
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwaterexpense_getbyid(p_waterexpenseid => @WaterExpenseId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@WaterExpenseId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Read(r) : null;
        }

        public async Task<int> InsertAsync(WaterExpenseModel m)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwaterexpense_insert(p_farmid => @FarmId::text, p_expensedate => @ExpenseDate::timestamp, p_waterexpensecategoryid => @WaterExpenseCategoryId::int, p_description => @Description::text, p_amount => @Amount::numeric, p_paidto => @PaidTo::text, p_paymentmethod => @PaymentMethod::text, p_watercashaccountid => @WaterCashAccountId::int, p_receipturl => @ReceiptUrl::text, p_linkedwatervehicleid => @LinkedWaterVehicleId::int, p_linkedwatermachineid => @LinkedWaterMachineId::int, p_linkedwaterproductionbatchid => @LinkedWaterProductionBatchId::int, p_notes => @Notes::text, p_createdby => @CreatedBy::text, p_supplierid => @SupplierId::int)", c);
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
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwaterexpense_submit(p_waterexpenseid => @WaterExpenseId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@WaterExpenseId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task ApproveAsync(int id, string farmId, string? approvedBy)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwaterexpense_approve(p_waterexpenseid => @WaterExpenseId::int, p_farmid => @FarmId::text, p_approvedby => @ApprovedBy::text)", c);
            cmd.Parameters.AddWithValue("@WaterExpenseId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task RejectAsync(int id, string farmId, string? approvedBy, string? reason)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwaterexpense_reject(p_waterexpenseid => @WaterExpenseId::int, p_farmid => @FarmId::text, p_approvedby => @ApprovedBy::text, p_reason => @Reason::text)", c);
            cmd.Parameters.AddWithValue("@WaterExpenseId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Reason", (object?)reason ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task CancelAsync(int id, string farmId, string? cancelledBy, string? reason)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwaterexpense_cancel(p_waterexpenseid => @WaterExpenseId::int, p_farmid => @FarmId::text, p_cancelledby => @CancelledBy::text, p_reason => @Reason::text)", c);
            cmd.Parameters.AddWithValue("@WaterExpenseId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@CancelledBy", (object?)cancelledBy ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Reason", (object?)reason ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwaterexpense_delete(p_waterexpenseid => @WaterExpenseId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@WaterExpenseId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<(int categoryCount, int cashAccountCount)> SeedDefaultsAsync(string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwaterfinance_seeddefaults(p_farmid => @FarmId::text)", c);
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

        private static WaterExpenseModel Read(NpgsqlDataReader r) => new()
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
        private static bool HasCol(NpgsqlDataReader r, string name)
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
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwatersupplier_listbyfarm(p_farmid => @FarmId::text, p_includeinactive => @IncludeInactive::boolean, p_includedeleted => @IncludeDeleted::boolean, p_search => @Search::text)", c);
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
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwatersupplier_getbyid(p_watersupplierid => @WaterSupplierId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@WaterSupplierId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? ReadSupplier(r) : null;
        }

        public async Task<int> InsertAsync(WaterSupplierModel m)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwatersupplier_insert(p_farmid => @FarmId::text, p_suppliername => @SupplierName::text, p_contactperson => @ContactPerson::text, p_phone => @Phone::text, p_email => @Email::text, p_address => @Address::text, p_suppliertype => @SupplierType::text, p_notes => @Notes::text, p_createdby => @CreatedBy::text)", c);
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
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwatersupplier_update(p_watersupplierid => @WaterSupplierId::int, p_farmid => @FarmId::text, p_suppliername => @SupplierName::text, p_contactperson => @ContactPerson::text, p_phone => @Phone::text, p_email => @Email::text, p_address => @Address::text, p_suppliertype => @SupplierType::text, p_notes => @Notes::text, p_isactive => @IsActive::boolean, p_updatedby => @UpdatedBy::text)", c);
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
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwatersupplier_delete(p_watersupplierid => @WaterSupplierId::int, p_farmid => @FarmId::text, p_deletedby => @DeletedBy::text)", c);
            cmd.Parameters.AddWithValue("@WaterSupplierId", id);
            cmd.Parameters.AddWithValue("@FarmId",          farmId);
            cmd.Parameters.AddWithValue("@DeletedBy",       (object?)deletedBy ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static WaterSupplierModel ReadSupplier(NpgsqlDataReader r) => new()
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
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwatercustomerledger_getforcustomer(p_farmid => @FarmId::text, p_watercustomerid => @WaterCustomerId::int)", c);
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
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwatercustomerledger_addentry(p_farmid => @FarmId::text, p_watercustomerid => @WaterCustomerId::int, p_transactiontype => @TransactionType::text, p_watersaleid => @WaterSaleId::int, p_waterpaymentid => @WaterPaymentId::int, p_debitamount => @DebitAmount::numeric, p_creditamount => @CreditAmount::numeric, p_description => @Description::text, p_createdby => @CreatedBy::text, p_transactiondate => @TransactionDate::timestamp)", c);
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
