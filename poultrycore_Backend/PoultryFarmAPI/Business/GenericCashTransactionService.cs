using System.Data;
using System.Data.SqlClient;
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
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericCashTransaction_GetByAccount", conn) { CommandType = CommandType.StoredProcedure };
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
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericCashTransaction_GetByFarm", conn) { CommandType = CommandType.StoredProcedure };
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
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericCashTransaction_InsertAdjustment", conn) { CommandType = CommandType.StoredProcedure };
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
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericCashMovement_Post", conn) { CommandType = CommandType.StoredProcedure };
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
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericCashReconciliation_Create", conn) { CommandType = CommandType.StoredProcedure };
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
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericCashReconciliation_GetByAccount", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericCashAccountId", accountId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                list.Add(new GenericCashReconciliationModel
                {
                    GenericCashReconciliationId = reader.GetInt32(reader.GetOrdinal("GenericCashReconciliationId")),
                    FarmId                  = reader.GetString(reader.GetOrdinal("FarmId")),
                    GenericCashAccountId    = reader.GetInt32(reader.GetOrdinal("GenericCashAccountId")),
                    AccountName             = reader.IsDBNull(reader.GetOrdinal("AccountName")) ? null : reader.GetString(reader.GetOrdinal("AccountName")),
                    ReconciliationDate      = reader.GetDateTime(reader.GetOrdinal("ReconciliationDate")),
                    SystemBalance           = reader.GetDecimal(reader.GetOrdinal("SystemBalance")),
                    ActualBalance           = reader.GetDecimal(reader.GetOrdinal("ActualBalance")),
                    Difference              = reader.GetDecimal(reader.GetOrdinal("Difference")),
                    AdjustmentTransactionId = reader.IsDBNull(reader.GetOrdinal("AdjustmentTransactionId")) ? null : reader.GetInt64(reader.GetOrdinal("AdjustmentTransactionId")),
                    Reason                  = reader.IsDBNull(reader.GetOrdinal("Reason")) ? null : reader.GetString(reader.GetOrdinal("Reason")),
                    Notes                   = reader.IsDBNull(reader.GetOrdinal("Notes")) ? null : reader.GetString(reader.GetOrdinal("Notes")),
                    Status                  = reader.GetString(reader.GetOrdinal("Status")),
                    RequestedBy             = reader.IsDBNull(reader.GetOrdinal("RequestedBy")) ? null : reader.GetString(reader.GetOrdinal("RequestedBy")),
                    ApprovedBy              = reader.IsDBNull(reader.GetOrdinal("ApprovedBy")) ? null : reader.GetString(reader.GetOrdinal("ApprovedBy")),
                    CreatedAt               = reader.GetDateTime(reader.GetOrdinal("CreatedAt")),
                });
            }
            return list;
        }

        public async Task UpsertDefaultAsync(string farmId, string defaultKey, int accountId)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericCashAccountDefault_Upsert", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@DefaultKey", defaultKey);
            cmd.Parameters.AddWithValue("@GenericCashAccountId", accountId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<List<GenericCashAccountDefaultModel>> GetDefaultsAsync(string farmId)
        {
            var list = new List<GenericCashAccountDefaultModel>();
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericCashAccountDefault_GetAll", conn) { CommandType = CommandType.StoredProcedure };
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
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericCashAllocations_Post", conn) { CommandType = CommandType.StoredProcedure };
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
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericCashAccount_GetDetails", conn) { CommandType = CommandType.StoredProcedure };
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
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericCashLedgerReport_Get", conn) { CommandType = CommandType.StoredProcedure };
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
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericCashTransaction_Reverse", conn) { CommandType = CommandType.StoredProcedure };
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

        private static GenericCashTransactionModel ReadTxn(SqlDataReader r)
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

        private static bool HasColumn(SqlDataReader r, string name)
        {
            for (int i = 0; i < r.FieldCount; i++)
                if (string.Equals(r.GetName(i), name, StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }
    }
}
