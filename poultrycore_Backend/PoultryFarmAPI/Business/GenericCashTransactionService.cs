using System.Data;
using Npgsql;
using System.Text.Json;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class GenericCashTransactionService : IGenericCashTransactionService
    {
        private readonly string _connectionString;
        public GenericCashTransactionService(string connectionString) => _connectionString = connectionString;

        public async Task<List<GenericCashTransactionModel>> GetByAccountAsync(int accountId, string farmId, DateTime? fromDate, DateTime? toDate)
        {
            var list = new List<GenericCashTransactionModel>();
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericcashtransaction_getbyaccount(p_genericcashaccountid => @GenericCashAccountId::int, p_farmid => @FarmId::text, p_fromdate => @FromDate::timestamp, p_todate => @ToDate::timestamp)", conn);
            cmd.Parameters.AddWithValue("@GenericCashAccountId", accountId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ToDate",   (object?)toDate   ?? DBNull.Value);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync()) list.Add(ReadTxn(reader));
            return list;
        }

        public async Task<List<GenericCashTransactionModel>> GetByFarmAsync(string farmId, DateTime? fromDate, DateTime? toDate)
        {
            var list = new List<GenericCashTransactionModel>();
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericcashtransaction_getbyfarm(p_farmid => @FarmId::text, p_fromdate => @FromDate::timestamp, p_todate => @ToDate::timestamp)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ToDate",   (object?)toDate   ?? DBNull.Value);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync()) list.Add(ReadTxn(reader));
            return list;
        }

        public async Task<long> InsertAdjustmentAsync(string farmId, GenericCashAdjustmentRequest req, string? createdBy, string? approvedBy)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericcashtransaction_insertadjustment(p_farmid => @FarmId::text, p_genericcashaccountid => @GenericCashAccountId::int, p_amount => @Amount::numeric, p_reason => @Reason::text, p_transactiondate => @TransactionDate::timestamp, p_createdby => @CreatedBy::text, p_approvedby => @ApprovedBy::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@GenericCashAccountId", req.GenericCashAccountId);
            cmd.Parameters.AddWithValue("@Amount", req.Amount);
            cmd.Parameters.AddWithValue("@Reason", req.Reason);
            cmd.Parameters.AddWithValue("@TransactionDate", (object?)req.TransactionDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)createdBy ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            if (await reader.ReadAsync())
                return reader.GetInt64(reader.GetOrdinal("GenericCashTransactionId"));
            return 0;
        }

        public async Task<long> PostMovementAsync(string farmId, string direction, GenericCashMovementRequest req, string? createdBy, string? approvedBy)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericcashmovement_post(p_farmid => @FarmId::text, p_genericcashaccountid => @GenericCashAccountId::int, p_direction => @Direction::text, p_movementtype => @MovementType::text, p_amount => @Amount::numeric, p_description => @Description::text, p_reference => @Reference::text, p_transactiondate => @TransactionDate::timestamp, p_sourceid => @SourceId::int, p_createdby => @CreatedBy::text, p_approvedby => @ApprovedBy::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@GenericCashAccountId", req.GenericCashAccountId);
            cmd.Parameters.AddWithValue("@Direction", direction);
            cmd.Parameters.AddWithValue("@MovementType", req.MovementType);
            cmd.Parameters.AddWithValue("@Amount", req.Amount);
            cmd.Parameters.AddWithValue("@Description", (object?)req.Description ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Reference", (object?)req.Reference ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@TransactionDate", (object?)req.TransactionDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@SourceId", (object?)req.SourceId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)createdBy ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            if (await reader.ReadAsync())
                return reader.GetInt64(reader.GetOrdinal("GenericCashTransactionId"));
            return 0;
        }

        public async Task<int> CreateReconciliationAsync(string farmId, GenericCashReconciliationRequest req, string? requestedBy, string? approvedBy)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericcashreconciliation_create(p_farmid => @FarmId::text, p_genericcashaccountid => @GenericCashAccountId::int, p_actualbalance => @ActualBalance::numeric, p_reconciliationdate => @ReconciliationDate::timestamp, p_reason => @Reason::text, p_notes => @Notes::text, p_requestedby => @RequestedBy::text, p_approvedby => @ApprovedBy::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@GenericCashAccountId", req.GenericCashAccountId);
            cmd.Parameters.AddWithValue("@ActualBalance", req.ActualBalance);
            cmd.Parameters.AddWithValue("@ReconciliationDate", (object?)req.ReconciliationDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Reason", (object?)req.Reason ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)req.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@RequestedBy", (object?)requestedBy ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            if (await reader.ReadAsync())
                return reader.GetInt32(reader.GetOrdinal("GenericCashReconciliationId"));
            return 0;
        }

        public async Task<List<GenericCashReconciliationModel>> GetReconciliationsByAccountAsync(int accountId, string farmId)
        {
            var list = new List<GenericCashReconciliationModel>();
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericcashreconciliation_getbyaccount(p_genericcashaccountid => @GenericCashAccountId::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@GenericCashAccountId", accountId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                list.Add(ReadCount(reader));
            }
            return list;
        }

        private static T? N<T>(NpgsqlDataReader r, string col)
        {
            var o = r.GetOrdinal(col);
            return r.IsDBNull(o) ? default : r.GetFieldValue<T>(o);
        }

        private static GenericCashReconciliationModel ReadCount(NpgsqlDataReader r) => new()
        {
            GenericCashReconciliationId = r.GetInt32(r.GetOrdinal("GenericCashReconciliationId")),
            FarmId                  = r.GetString(r.GetOrdinal("FarmId")),
            GenericCashAccountId    = r.GetInt32(r.GetOrdinal("GenericCashAccountId")),
            AccountName             = N<string>(r, "AccountName"),
            AccountType             = N<string>(r, "AccountType"),
            ReferenceNo             = N<string>(r, "ReferenceNo"),
            ReconciliationDate      = r.GetDateTime(r.GetOrdinal("ReconciliationDate")),
            SystemBalance           = r.GetDecimal(r.GetOrdinal("SystemBalance")),
            SystemBalanceCached     = N<decimal?>(r, "SystemBalanceCached"),
            ActualBalance           = N<decimal?>(r, "ActualBalance"),
            Difference              = r.GetDecimal(r.GetOrdinal("Difference")),
            AdjustmentTransactionId = N<long?>(r, "AdjustmentTransactionId"),
            ReversalTransactionId   = N<long?>(r, "ReversalTransactionId"),
            Reason                  = N<string>(r, "Reason"),
            Notes                   = N<string>(r, "Notes"),
            Status                  = r.GetString(r.GetOrdinal("Status")),
            RequestedBy             = N<string>(r, "RequestedBy"),
            ApprovedBy              = N<string>(r, "ApprovedBy"),
            CreatedBy               = N<string>(r, "CreatedBy"),
            CreatedAt               = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt               = N<DateTime?>(r, "UpdatedAt"),
            PostedBy                = N<string>(r, "PostedBy"),
            PostedAt                = N<DateTime?>(r, "PostedAt"),
            ReversedBy              = N<string>(r, "ReversedBy"),
            ReversedAt              = N<DateTime?>(r, "ReversedAt"),
            ReversalReason          = N<string>(r, "ReversalReason"),
        };

        private NpgsqlCommand Cmd(NpgsqlConnection conn, string sql, params (string, object?)[] ps)
        {
            var cmd = new NpgsqlCommand(sql, conn);
            foreach (var (k, v) in ps) cmd.Parameters.AddWithValue(k, v ?? DBNull.Value);
            return cmd;
        }

        // ---- Draft -> edit -> post -> discard -> reverse (migration 456) ----
        public async Task<int> InsertCountAsync(string farmId, GenericCashCountInput req, string? createdBy)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = Cmd(conn, "SELECT spgenericcashreconciliation_insert(p_farmid => @FarmId::text, p_genericcashaccountid => @Acct::int, p_reconciliationdate => @Date::timestamp, p_actualbalance => @Actual::numeric, p_reason => @Reason::text, p_notes => @Notes::text, p_createdby => @By::text)",
                ("@FarmId", farmId), ("@Acct", req.GenericCashAccountId), ("@Date", req.ReconciliationDate),
                ("@Actual", req.ActualBalance), ("@Reason", req.Reason), ("@Notes", req.Notes), ("@By", createdBy));
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateCountAsync(int id, string farmId, GenericCashCountInput req, string? updatedBy)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = Cmd(conn, "SELECT spgenericcashreconciliation_update(p_genericcashreconciliationid => @Id::int, p_farmid => @FarmId::text, p_reconciliationdate => @Date::timestamp, p_actualbalance => @Actual::numeric, p_reason => @Reason::text, p_notes => @Notes::text, p_updatedby => @By::text)",
                ("@Id", id), ("@FarmId", farmId), ("@Date", req.ReconciliationDate),
                ("@Actual", req.ActualBalance), ("@Reason", req.Reason), ("@Notes", req.Notes), ("@By", updatedBy));
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteCountAsync(int id, string farmId, string? userId)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = Cmd(conn, "SELECT spgenericcashreconciliation_delete(p_genericcashreconciliationid => @Id::int, p_farmid => @FarmId::text, p_userid => @By::text)",
                ("@Id", id), ("@FarmId", farmId), ("@By", userId));
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<long?> PostCountAsync(int id, string farmId, string? postedBy)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = Cmd(conn, "SELECT spgenericcashreconciliation_post(p_genericcashreconciliationid => @Id::int, p_farmid => @FarmId::text, p_postedby => @By::text)",
                ("@Id", id), ("@FarmId", farmId), ("@By", postedBy));
            await conn.OpenAsync();
            var o = await cmd.ExecuteScalarAsync();
            return o is null || o is DBNull ? null : Convert.ToInt64(o);
        }

        public async Task ReverseCountAsync(int id, string farmId, string reason, string? reversedBy)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = Cmd(conn, "SELECT spgenericcashreconciliation_reverse(p_genericcashreconciliationid => @Id::int, p_farmid => @FarmId::text, p_reason => @Reason::text, p_reversedby => @By::text)",
                ("@Id", id), ("@FarmId", farmId), ("@Reason", reason), ("@By", reversedBy));
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<List<GenericCashAccountCountStatusModel>> GetCountStatusAsync(string farmId)
        {
            var list = new List<GenericCashAccountCountStatusModel>();
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = Cmd(conn, "SELECT * FROM spgenericcashreconciliation_getaccountstatus(p_farmid => @FarmId::text)", ("@FarmId", farmId));
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                list.Add(new GenericCashAccountCountStatusModel
                {
                    GenericCashAccountId  = r.GetInt32(r.GetOrdinal("GenericCashAccountId")),
                    AccountName           = N<string>(r, "AccountName") ?? string.Empty,
                    AccountType           = N<string>(r, "AccountType"),
                    IsActive              = r.GetBoolean(r.GetOrdinal("IsActive")),
                    CurrentBalance        = r.GetDecimal(r.GetOrdinal("CurrentBalance")),
                    LedgerBalance         = r.GetDecimal(r.GetOrdinal("LedgerBalance")),
                    CacheDrift            = r.GetDecimal(r.GetOrdinal("CacheDrift")),
                    LastReconciledAt      = N<DateTime?>(r, "LastReconciledAt"),
                    LastReconciledBalance = N<decimal?>(r, "LastReconciledBalance"),
                    DaysSinceReconciled   = N<int?>(r, "DaysSinceReconciled"),
                    UnclearedCount        = r.GetInt32(r.GetOrdinal("UnclearedCount")),
                    UnclearedAmount       = r.GetDecimal(r.GetOrdinal("UnclearedAmount")),
                    OpenDraftId           = N<int?>(r, "OpenDraftId"),
                });
            }
            return list;
        }

        // Recalculate: rebuild cached balances from the ledger. Moves no money.
        public async Task<int> RecalculateBalancesAsync(string farmId)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = Cmd(conn, "SELECT spgenericcashaccount_reconcilebalance(p_farmid => @FarmId::text)", ("@FarmId", farmId));
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpsertDefaultAsync(string farmId, string defaultKey, int accountId)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericcashaccountdefault_upsert(p_farmid => @FarmId::text, p_defaultkey => @DefaultKey::text, p_genericcashaccountid => @GenericCashAccountId::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@DefaultKey", defaultKey);
            cmd.Parameters.AddWithValue("@GenericCashAccountId", accountId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<List<GenericCashAccountDefaultModel>> GetDefaultsAsync(string farmId)
        {
            var list = new List<GenericCashAccountDefaultModel>();
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericcashaccountdefault_getall(p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                list.Add(new GenericCashAccountDefaultModel
                {
                    FarmId               = reader.GetString(reader.GetOrdinal("FarmId")),
                    DefaultKey           = reader.GetString(reader.GetOrdinal("DefaultKey")),
                    GenericCashAccountId = reader.GetInt32(reader.GetOrdinal("GenericCashAccountId")),
                    AccountName          = reader.IsDBNull(reader.GetOrdinal("AccountName")) ? null : reader.GetString(reader.GetOrdinal("AccountName")),
                    AccountType          = reader.IsDBNull(reader.GetOrdinal("AccountType")) ? null : reader.GetString(reader.GetOrdinal("AccountType")),
                    UpdatedAt            = reader.GetDateTime(reader.GetOrdinal("UpdatedAt")),
                });
            }
            return list;
        }

        public async Task<int> PostAllocationsAsync(string farmId, GenericCashAllocationsRequest req, string? createdBy, string? approvedBy)
        {
            var json = JsonSerializer.Serialize(req.Allocations);
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericcashallocations_post(p_farmid => @FarmId::text, p_sourcetype => @SourceType::text, p_sourceid => @SourceId::int, p_direction => @Direction::text, p_allocationsjson => @AllocationsJson::text, p_transactiondate => @TransactionDate::timestamp, p_createdby => @CreatedBy::text, p_approvedby => @ApprovedBy::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@SourceType", req.SourceType);
            cmd.Parameters.AddWithValue("@SourceId", req.SourceId);
            cmd.Parameters.AddWithValue("@Direction", req.Direction);
            cmd.Parameters.AddWithValue("@AllocationsJson", json);
            cmd.Parameters.AddWithValue("@TransactionDate", (object?)req.TransactionDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)createdBy ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            int count = 0;
            while (await reader.ReadAsync()) count++;
            return count;
        }

        public async Task<GenericCashAccountDetailsModel?> GetAccountDetailsAsync(int accountId, string farmId)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericcashaccount_getdetails(p_farmid => @FarmId::text, p_genericcashaccountid => @GenericCashAccountId::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@GenericCashAccountId", accountId);

            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            if (!await r.ReadAsync()) return null;
            return new GenericCashAccountDetailsModel
            {
                GenericCashAccountId  = r.GetInt32(r.GetOrdinal("GenericCashAccountId")),
                FarmId                = r.GetString(r.GetOrdinal("FarmId")),
                AccountName           = r.GetString(r.GetOrdinal("AccountName")),
                AccountType           = r.GetString(r.GetOrdinal("AccountType")),
                OpeningBalance        = r.GetDecimal(r.GetOrdinal("OpeningBalance")),
                CurrentBalance        = r.GetDecimal(r.GetOrdinal("CurrentBalance")),
                NegativeBalancePolicy = r.GetString(r.GetOrdinal("NegativeBalancePolicy")),
                NegativeBalanceLimit  = r.GetDecimal(r.GetOrdinal("NegativeBalanceLimit")),
                IsActive              = r.GetBoolean(r.GetOrdinal("IsActive")),
                LastReconciledAt      = r.IsDBNull(r.GetOrdinal("LastReconciledAt")) ? null : r.GetDateTime(r.GetOrdinal("LastReconciledAt")),
                LastReconciledBalance = r.IsDBNull(r.GetOrdinal("LastReconciledBalance")) ? null : r.GetDecimal(r.GetOrdinal("LastReconciledBalance")),
                TotalMoneyIn          = r.GetDecimal(r.GetOrdinal("TotalMoneyIn")),
                TotalMoneyOut         = r.GetDecimal(r.GetOrdinal("TotalMoneyOut")),
                TransferIn            = r.GetDecimal(r.GetOrdinal("TransferIn")),
                TransferOut           = r.GetDecimal(r.GetOrdinal("TransferOut")),
                TotalAdjustments      = r.GetDecimal(r.GetOrdinal("TotalAdjustments")),
                LedgerBalance         = r.GetDecimal(r.GetOrdinal("LedgerBalance")),
                UnreconciledCount     = r.GetInt32(r.GetOrdinal("UnreconciledCount")),
            };
        }

        public async Task<List<GenericCashLedgerReportRow>> GetLedgerReportAsync(string farmId)
        {
            var list = new List<GenericCashLedgerReportRow>();
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericcashledgerreport_get(p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                list.Add(new GenericCashLedgerReportRow
                {
                    GenericCashAccountId = r.GetInt32(r.GetOrdinal("GenericCashAccountId")),
                    AccountName          = r.GetString(r.GetOrdinal("AccountName")),
                    AccountType          = r.GetString(r.GetOrdinal("AccountType")),
                    CurrentBalance       = r.GetDecimal(r.GetOrdinal("CurrentBalance")),
                    LedgerBalance        = r.GetDecimal(r.GetOrdinal("LedgerBalance")),
                    Discrepancy          = r.GetDecimal(r.GetOrdinal("Discrepancy")),
                    LastReconciledAt     = r.IsDBNull(r.GetOrdinal("LastReconciledAt")) ? null : r.GetDateTime(r.GetOrdinal("LastReconciledAt")),
                    IsActive             = r.GetBoolean(r.GetOrdinal("IsActive")),
                });
            }
            return list;
        }

        public async Task<long> ReverseAsync(long transactionId, string farmId, string? reversedBy, string? reason)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericcashtransaction_reverse(p_genericcashtransactionid => @GenericCashTransactionId::bigint, p_farmid => @FarmId::text, p_reversedby => @ReversedBy::text, p_reason => @Reason::text)", conn);
            cmd.Parameters.AddWithValue("@GenericCashTransactionId", transactionId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ReversedBy", (object?)reversedBy ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Reason", (object?)reason ?? DBNull.Value);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            if (await reader.ReadAsync())
                return reader.GetInt64(reader.GetOrdinal("GenericCashTransactionId"));
            return 0;
        }

        private static GenericCashTransactionModel ReadTxn(NpgsqlDataReader r)
        {
            var m = new GenericCashTransactionModel
            {
                GenericCashTransactionId = r.GetInt64(r.GetOrdinal("GenericCashTransactionId")),
                FarmId                   = r.GetString(r.GetOrdinal("FarmId")),
                GenericCashAccountId     = r.GetInt32(r.GetOrdinal("GenericCashAccountId")),
                AccountName              = r.IsDBNull(r.GetOrdinal("AccountName")) ? null : r.GetString(r.GetOrdinal("AccountName")),
                TransactionDate          = r.GetDateTime(r.GetOrdinal("TransactionDate")),
                TransactionType          = r.GetString(r.GetOrdinal("TransactionType")),
                SourceType               = r.IsDBNull(r.GetOrdinal("SourceType")) ? null : r.GetString(r.GetOrdinal("SourceType")),
                SourceId                 = r.IsDBNull(r.GetOrdinal("SourceId")) ? null : r.GetInt32(r.GetOrdinal("SourceId")),
                Amount                   = r.GetDecimal(r.GetOrdinal("Amount")),
                BalanceAfterTransaction  = r.GetDecimal(r.GetOrdinal("BalanceAfterTransaction")),
                Description              = r.IsDBNull(r.GetOrdinal("Description")) ? null : r.GetString(r.GetOrdinal("Description")),
                CreatedBy                = r.IsDBNull(r.GetOrdinal("CreatedBy")) ? null : r.GetString(r.GetOrdinal("CreatedBy")),
                ApprovedBy               = r.IsDBNull(r.GetOrdinal("ApprovedBy")) ? null : r.GetString(r.GetOrdinal("ApprovedBy")),
                ApprovedAt               = r.IsDBNull(r.GetOrdinal("ApprovedAt")) ? null : r.GetDateTime(r.GetOrdinal("ApprovedAt")),
                CreatedAt                = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            };

            // New columns (migration 108) — tolerate older read procs during rollout.
            if (HasColumn(r, "Status") && !r.IsDBNull(r.GetOrdinal("Status")))
                m.Status = r.GetString(r.GetOrdinal("Status"));
            if (HasColumn(r, "ReversalOfTransactionId") && !r.IsDBNull(r.GetOrdinal("ReversalOfTransactionId")))
                m.ReversalOfTransactionId = r.GetInt64(r.GetOrdinal("ReversalOfTransactionId"));
            if (HasColumn(r, "ReversedBy") && !r.IsDBNull(r.GetOrdinal("ReversedBy")))
                m.ReversedBy = r.GetString(r.GetOrdinal("ReversedBy"));
            if (HasColumn(r, "ReversedAt") && !r.IsDBNull(r.GetOrdinal("ReversedAt")))
                m.ReversedAt = r.GetDateTime(r.GetOrdinal("ReversedAt"));
            if (HasColumn(r, "Notes") && !r.IsDBNull(r.GetOrdinal("Notes")))
                m.Notes = r.GetString(r.GetOrdinal("Notes"));

            return m;
        }

        private static bool HasColumn(NpgsqlDataReader r, string name)
        {
            for (int i = 0; i < r.FieldCount; i++)
                if (string.Equals(r.GetName(i), name, StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }
    }
}
