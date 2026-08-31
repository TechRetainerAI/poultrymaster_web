// Poultry Cash Account services (port of the Water finance cash module).
// Each service maps 1:1 to its spPoultryCash* SP family (migration 129). The
// transactional SPs (transfer approve, adjust) handle multi-table writes inside
// SQL Server; the C# side just sends params.

using System.Data;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    // ====================================================================
    // Cash accounts (+ transactions read)
    // ====================================================================
    public interface IPoultryCashAccountService
    {
        Task<List<PoultryCashAccountModel>> GetAllAsync(string farmId);
        Task<PoultryCashAccountModel?>      GetByIdAsync(int id, string farmId);
        Task<int>  InsertAsync(PoultryCashAccountModel m);
        Task       UpdateAsync(PoultryCashAccountModel m);
        Task       DeleteAsync(int id, string farmId);
        Task       ReconcileBalanceAsync(string farmId);
        Task       AdjustAsync(int id, string farmId, decimal amount, string reason, string? createdBy);
        Task<List<PoultryCashTransactionModel>> GetTransactionsAsync(
            string farmId, int? cashAccountId, DateTime? fromDate, DateTime? toDate,
            string? clearingStatus = null);
    }

    public class PoultryCashAccountService : IPoultryCashAccountService
    {
        private readonly string _cs;
        public PoultryCashAccountService(string cs) => _cs = cs;

        public async Task<List<PoultryCashAccountModel>> GetAllAsync(string farmId)
        {
            var list = new List<PoultryCashAccountModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrycashaccount_getall(p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(Read(r));
            return list;
        }

        public async Task<PoultryCashAccountModel?> GetByIdAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrycashaccount_getbyid(p_poultrycashaccountid => @PoultryCashAccountId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@PoultryCashAccountId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Read(r) : null;
        }

        public async Task<int> InsertAsync(PoultryCashAccountModel m)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrycashaccount_insert(p_farmid => @FarmId::text, p_accountname => @AccountName::text, p_accounttype => @AccountType::text, p_openingbalance => @OpeningBalance::numeric, p_allownegativebalance => @AllowNegativeBalance::boolean, p_notes => @Notes::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@AccountName", m.AccountName);
            cmd.Parameters.AddWithValue("@AccountType", m.AccountType);
            cmd.Parameters.AddWithValue("@OpeningBalance", m.OpeningBalance);
            cmd.Parameters.AddWithValue("@AllowNegativeBalance", m.AllowNegativeBalance);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            await c.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateAsync(PoultryCashAccountModel m)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrycashaccount_update(p_poultrycashaccountid => @PoultryCashAccountId::int, p_farmid => @FarmId::text, p_accountname => @AccountName::text, p_accounttype => @AccountType::text, p_allownegativebalance => @AllowNegativeBalance::boolean, p_isactive => @IsActive::boolean, p_notes => @Notes::text)", c);
            cmd.Parameters.AddWithValue("@PoultryCashAccountId", m.PoultryCashAccountId);
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
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrycashaccount_delete(p_poultrycashaccountid => @PoultryCashAccountId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@PoultryCashAccountId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task ReconcileBalanceAsync(string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrycashaccount_reconcilebalance(p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task AdjustAsync(int id, string farmId, decimal amount, string reason, string? createdBy)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrycashaccount_adjust(p_poultrycashaccountid => @PoultryCashAccountId::int, p_farmid => @FarmId::text, p_amount => @Amount::numeric, p_reason => @Reason::text, p_createdby => @CreatedBy::text)", c);
            cmd.Parameters.AddWithValue("@PoultryCashAccountId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Amount", amount);
            cmd.Parameters.AddWithValue("@Reason", (object?)reason ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)createdBy ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // Reads through sppoultrycashtransaction_getledger (migration 223) rather
        // than the older sppoultrycashtransaction_getbyfarm: same first 15 columns,
        // plus clearing status. The old function is left in place untouched --
        // its Postgres body is not in this repo, so it cannot be safely altered.
        public async Task<List<PoultryCashTransactionModel>> GetTransactionsAsync(
            string farmId, int? cashAccountId, DateTime? fromDate, DateTime? toDate,
            string? clearingStatus = null)
        {
            var list = new List<PoultryCashTransactionModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrycashtransaction_getledger(p_farmid => @FarmId::text, p_poultrycashaccountid => @PoultryCashAccountId::int, p_fromdate => @FromDate::timestamp, p_todate => @ToDate::timestamp, p_clearingstatus => @ClearingStatus::text, p_poultrycashreconciliationid => NULL)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@PoultryCashAccountId", (object?)cashAccountId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ToDate",   (object?)toDate   ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ClearingStatus", (object?)clearingStatus ?? DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                list.Add(new PoultryCashTransactionModel
                {
                    PoultryCashTransactionId = r.GetInt32(r.GetOrdinal("PoultryCashTransactionId")),
                    FarmId                   = r.GetString(r.GetOrdinal("FarmId")),
                    PoultryCashAccountId     = r.GetInt32(r.GetOrdinal("PoultryCashAccountId")),
                    AccountName              = r.IsDBNull(r.GetOrdinal("AccountName")) ? null : r.GetString(r.GetOrdinal("AccountName")),
                    TransactionDate          = r.GetDateTime(r.GetOrdinal("TransactionDate")),
                    TransactionType          = r.GetString(r.GetOrdinal("TransactionType")),
                    SourceType               = r.IsDBNull(r.GetOrdinal("SourceType")) ? null : r.GetString(r.GetOrdinal("SourceType")),
                    SourceId                 = r.IsDBNull(r.GetOrdinal("SourceId")) ? null : r.GetInt32(r.GetOrdinal("SourceId")),
                    Amount                   = r.GetDecimal(r.GetOrdinal("Amount")),
                    BalanceAfterTransaction  = r.IsDBNull(r.GetOrdinal("BalanceAfterTransaction")) ? null : r.GetDecimal(r.GetOrdinal("BalanceAfterTransaction")),
                    Description              = r.IsDBNull(r.GetOrdinal("Description")) ? null : r.GetString(r.GetOrdinal("Description")),
                    CreatedBy                = r.IsDBNull(r.GetOrdinal("CreatedBy")) ? null : r.GetString(r.GetOrdinal("CreatedBy")),
                    ApprovedBy               = r.IsDBNull(r.GetOrdinal("ApprovedBy")) ? null : r.GetString(r.GetOrdinal("ApprovedBy")),
                    ApprovedAt               = r.IsDBNull(r.GetOrdinal("ApprovedAt")) ? null : r.GetDateTime(r.GetOrdinal("ApprovedAt")),
                    CreatedAt                = r.GetDateTime(r.GetOrdinal("CreatedAt")),
                    ClearingStatus           = r.IsDBNull(r.GetOrdinal("ClearingStatus")) ? null : r.GetString(r.GetOrdinal("ClearingStatus")),
                    ClearedDate              = r.IsDBNull(r.GetOrdinal("ClearedDate")) ? null : r.GetDateTime(r.GetOrdinal("ClearedDate")),
                    ClearedBy                = r.IsDBNull(r.GetOrdinal("ClearedBy")) ? null : r.GetString(r.GetOrdinal("ClearedBy")),
                    PoultryCashReconciliationId = r.IsDBNull(r.GetOrdinal("PoultryCashReconciliationId")) ? null : r.GetInt32(r.GetOrdinal("PoultryCashReconciliationId")),
                    ClearingNotes            = r.IsDBNull(r.GetOrdinal("ClearingNotes")) ? null : r.GetString(r.GetOrdinal("ClearingNotes")),
                    ReconciliationReference  = r.IsDBNull(r.GetOrdinal("ReconciliationReference")) ? null : r.GetString(r.GetOrdinal("ReconciliationReference")),
                });
            }
            return list;
        }

        private static PoultryCashAccountModel Read(NpgsqlDataReader r) => new()
        {
            PoultryCashAccountId = r.GetInt32(r.GetOrdinal("PoultryCashAccountId")),
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
    public interface IPoultryCashTransferService
    {
        Task<List<PoultryCashTransferModel>> GetAllAsync(string farmId, string? status);
        Task<PoultryCashTransferModel?>      GetByIdAsync(int id, string farmId);
        Task<int>  InsertAsync(PoultryCashTransferModel m);
        Task       ApproveAsync(int id, string farmId, string? approvedBy);
        Task       CancelAsync(int id, string farmId);
    }

    public class PoultryCashTransferService : IPoultryCashTransferService
    {
        private readonly string _cs;
        public PoultryCashTransferService(string cs) => _cs = cs;

        public async Task<List<PoultryCashTransferModel>> GetAllAsync(string farmId, string? status)
        {
            var list = new List<PoultryCashTransferModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrycashtransfer_getall(p_farmid => @FarmId::text, p_status => @Status::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(Read(r));
            return list;
        }

        public async Task<PoultryCashTransferModel?> GetByIdAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrycashtransfer_getbyid(p_poultrycashtransferid => @PoultryCashTransferId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@PoultryCashTransferId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Read(r) : null;
        }

        public async Task<int> InsertAsync(PoultryCashTransferModel m)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrycashtransfer_insert(p_farmid => @FarmId::text, p_frompoultrycashaccountid => @FromPoultryCashAccountId::int, p_topoultrycashaccountid => @ToPoultryCashAccountId::int, p_amount => @Amount::numeric, p_transferdate => @TransferDate::timestamp, p_notes => @Notes::text, p_createdby => @CreatedBy::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@FromPoultryCashAccountId", m.FromPoultryCashAccountId);
            cmd.Parameters.AddWithValue("@ToPoultryCashAccountId",   m.ToPoultryCashAccountId);
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
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrycashtransfer_approve(p_poultrycashtransferid => @PoultryCashTransferId::int, p_farmid => @FarmId::text, p_approvedby => @ApprovedBy::text)", c);
            cmd.Parameters.AddWithValue("@PoultryCashTransferId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task CancelAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrycashtransfer_cancel(p_poultrycashtransferid => @PoultryCashTransferId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@PoultryCashTransferId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static PoultryCashTransferModel Read(NpgsqlDataReader r) => new()
        {
            PoultryCashTransferId    = r.GetInt32(r.GetOrdinal("PoultryCashTransferId")),
            FarmId                   = r.GetString(r.GetOrdinal("FarmId")),
            FromPoultryCashAccountId = r.GetInt32(r.GetOrdinal("FromPoultryCashAccountId")),
            FromAccountName          = r.IsDBNull(r.GetOrdinal("FromAccountName")) ? null : r.GetString(r.GetOrdinal("FromAccountName")),
            ToPoultryCashAccountId   = r.GetInt32(r.GetOrdinal("ToPoultryCashAccountId")),
            ToAccountName            = r.IsDBNull(r.GetOrdinal("ToAccountName")) ? null : r.GetString(r.GetOrdinal("ToAccountName")),
            TransferDate             = r.GetDateTime(r.GetOrdinal("TransferDate")),
            Amount                   = r.GetDecimal(r.GetOrdinal("Amount")),
            Status                   = r.GetString(r.GetOrdinal("Status")),
            Notes                    = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            CreatedBy                = r.IsDBNull(r.GetOrdinal("CreatedBy")) ? null : r.GetString(r.GetOrdinal("CreatedBy")),
            ApprovedBy               = r.IsDBNull(r.GetOrdinal("ApprovedBy")) ? null : r.GetString(r.GetOrdinal("ApprovedBy")),
            ApprovedAt               = r.IsDBNull(r.GetOrdinal("ApprovedAt")) ? null : r.GetDateTime(r.GetOrdinal("ApprovedAt")),
            CreatedAt                = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt                = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };
    }

    // ====================================================================
    // Cash reconciliation (migration 223)
    // ====================================================================
    // A CASH COUNT: compare what was counted against what the ledger says and
    // post the difference. Not to be confused with
    // IPoultryCashAccountService.ReconcileBalancesAsync, which recomputes the
    // cached balance from the ledger and moves no money.
    public interface IPoultryCashReconciliationService
    {
        Task<List<PoultryCashReconciliationModel>> GetAllAsync(
            string farmId, int? cashAccountId, string? status, DateTime? fromDate, DateTime? toDate);
        Task<PoultryCashReconciliationModel?> GetByIdAsync(int id, string farmId);
        Task<List<PoultryCashReconciliationModel>> GetByAccountAsync(int cashAccountId, string farmId);
        Task<List<PoultryCashAccountReconStatusModel>> GetAccountStatusAsync(string farmId);
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

    public class PoultryCashReconciliationService : IPoultryCashReconciliationService
    {
        private readonly string _cs;
        public PoultryCashReconciliationService(string cs) => _cs = cs;

        public async Task<List<PoultryCashReconciliationModel>> GetAllAsync(
            string farmId, int? cashAccountId, string? status, DateTime? fromDate, DateTime? toDate)
        {
            var list = new List<PoultryCashReconciliationModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrycashreconciliation_getall(p_farmid => @FarmId::text, p_poultrycashaccountid => @AccountId::int, p_status => @Status::text, p_fromdate => @FromDate::timestamp, p_todate => @ToDate::timestamp)", c);
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

        public async Task<PoultryCashReconciliationModel?> GetByIdAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrycashreconciliation_getbyid(p_poultrycashreconciliationid => @Id::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Read(r) : null;
        }

        public async Task<List<PoultryCashReconciliationModel>> GetByAccountAsync(int cashAccountId, string farmId)
        {
            var list = new List<PoultryCashReconciliationModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrycashreconciliation_getbyaccount(p_poultrycashaccountid => @AccountId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@AccountId", cashAccountId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(Read(r));
            return list;
        }

        public async Task<List<PoultryCashAccountReconStatusModel>> GetAccountStatusAsync(string farmId)
        {
            var list = new List<PoultryCashAccountReconStatusModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrycashreconciliation_getaccountstatus(p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                list.Add(new PoultryCashAccountReconStatusModel
                {
                    PoultryCashAccountId    = r.GetInt32(r.GetOrdinal("PoultryCashAccountId")),
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
            using var cmd = new NpgsqlCommand("SELECT public.sppoultrycashreconciliation_insert(p_farmid => @FarmId::text, p_poultrycashaccountid => @AccountId::int, p_reconciliationdate => @Date::timestamp, p_actualbalance => @Actual::numeric, p_reason => @Reason::text, p_notes => @Notes::text, p_createdby => @CreatedBy::text)", c);
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
            using var cmd = new NpgsqlCommand("SELECT public.sppoultrycashreconciliation_update(p_poultrycashreconciliationid => @Id::int, p_farmid => @FarmId::text, p_reconciliationdate => @Date::timestamp, p_actualbalance => @Actual::numeric, p_reason => @Reason::text, p_notes => @Notes::text, p_updatedby => @UpdatedBy::text)", c);
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
            using var cmd = new NpgsqlCommand("SELECT public.sppoultrycashreconciliation_delete(p_poultrycashreconciliationid => @Id::int, p_farmid => @FarmId::text, p_userid => @UserId::text)", c);
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
            using var cmd = new NpgsqlCommand("SELECT public.sppoultrycashreconciliation_post(p_poultrycashreconciliationid => @Id::int, p_farmid => @FarmId::text, p_postedby => @PostedBy::text, p_clearedtransactionidsjson => @Ids::text)", c);
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
            using var cmd = new NpgsqlCommand("SELECT public.sppoultrycashreconciliation_reverse(p_poultrycashreconciliationid => @Id::int, p_farmid => @FarmId::text, p_reason => @Reason::text, p_reversedby => @ReversedBy::text)", c);
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
            using var cmd = new NpgsqlCommand("SELECT public.sppoultrycashtransaction_setclearing(p_farmid => @FarmId::text, p_poultrycashaccountid => @AccountId::int, p_transactionidsjson => @Ids::text, p_clearingstatus => @Status::text, p_clearingnotes => @Notes::text, p_userid => @UserId::text)", c);
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

        private static PoultryCashReconciliationModel Read(NpgsqlDataReader r) => new()
        {
            PoultryCashReconciliationId = r.GetInt32(r.GetOrdinal("PoultryCashReconciliationId")),
            FarmId                    = r.GetString(r.GetOrdinal("FarmId")),
            PoultryCashAccountId        = r.GetInt32(r.GetOrdinal("PoultryCashAccountId")),
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
}
