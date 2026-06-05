using System.Data;
using System.Data.SqlClient;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class GenericCashTransferService : IGenericCashTransferService
    {
        private readonly string _connectionString;
        public GenericCashTransferService(string connectionString) => _connectionString = connectionString;

        public async Task<List<GenericCashTransferModel>> GetAllAsync(string farmId, string? status)
        {
            var list = new List<GenericCashTransferModel>();
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericCashTransfer_GetAll", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync()) list.Add(ReadTransfer(reader));
            return list;
        }

        public async Task<GenericCashTransferModel?> GetByIdAsync(int id, string farmId)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericCashTransfer_GetById", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericCashTransferId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            return await reader.ReadAsync() ? ReadTransfer(reader) : null;
        }

        public async Task<int> InsertAsync(GenericCashTransferModel m)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericCashTransfer_Insert", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@FromGenericCashAccountId", m.FromGenericCashAccountId);
            cmd.Parameters.AddWithValue("@ToGenericCashAccountId", m.ToGenericCashAccountId);
            cmd.Parameters.AddWithValue("@Amount", m.Amount);
            cmd.Parameters.AddWithValue("@TransferDate",
                m.TransferDate == default ? (object)DBNull.Value : m.TransferDate);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)m.CreatedBy ?? DBNull.Value);

            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task ApproveAsync(int id, string farmId, string? approvedBy)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericCashTransfer_Approve", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericCashTransferId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task CancelAsync(int id, string farmId)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spGenericCashTransfer_Cancel", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@GenericCashTransferId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static GenericCashTransferModel ReadTransfer(SqlDataReader r) => new()
        {
            GenericCashTransferId    = r.GetInt32(r.GetOrdinal("GenericCashTransferId")),
            FarmId                   = r.GetString(r.GetOrdinal("FarmId")),
            FromGenericCashAccountId = r.GetInt32(r.GetOrdinal("FromGenericCashAccountId")),
            FromAccountName          = r.IsDBNull(r.GetOrdinal("FromAccountName")) ? null : r.GetString(r.GetOrdinal("FromAccountName")),
            ToGenericCashAccountId   = r.GetInt32(r.GetOrdinal("ToGenericCashAccountId")),
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
}
