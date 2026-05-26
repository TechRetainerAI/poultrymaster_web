using System.Data;
using System.Data.SqlClient;
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

        private static GenericCashTransactionModel ReadTxn(SqlDataReader r) => new()
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
    }
}
