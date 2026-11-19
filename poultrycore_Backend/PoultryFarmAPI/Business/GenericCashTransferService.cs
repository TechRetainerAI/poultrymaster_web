using System.Data;
using Npgsql;
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
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericcashtransfer_getall(p_farmid => @FarmId::text, p_status => @Status::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync()) list.Add(ReadTransfer(reader));
            return list;
        }

        public async Task<GenericCashTransferModel?> GetByIdAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericcashtransfer_getbyid(p_genericcashtransferid => @GenericCashTransferId::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@GenericCashTransferId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            return await reader.ReadAsync() ? ReadTransfer(reader) : null;
        }

        public async Task<int> InsertAsync(GenericCashTransferModel m)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericcashtransfer_insert(p_farmid => @FarmId::text, p_fromgenericcashaccountid => @FromGenericCashAccountId::int, p_togenericcashaccountid => @ToGenericCashAccountId::int, p_amount => @Amount::numeric, p_transferdate => @TransferDate::timestamp, p_notes => @Notes::text, p_createdby => @CreatedBy::text, p_referencenumber => @ReferenceNumber::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@FromGenericCashAccountId", m.FromGenericCashAccountId);
            cmd.Parameters.AddWithValue("@ToGenericCashAccountId", m.ToGenericCashAccountId);
            cmd.Parameters.AddWithValue("@Amount", m.Amount);
            cmd.Parameters.AddWithValue("@TransferDate",
                m.TransferDate == default ? (object)DBNull.Value : m.TransferDate);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)m.CreatedBy ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ReferenceNumber", (object?)m.ReferenceNumber ?? DBNull.Value);

            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        // Create + approve in ONE database call (migration 456): a refused
        // approval (not enough money) leaves no Draft behind.
        public async Task<int> RecordAsync(GenericCashTransferModel m)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT spgenericcashtransfer_record(p_farmid => @FarmId::text, p_fromgenericcashaccountid => @From::int, p_togenericcashaccountid => @To::int, p_amount => @Amount::numeric, p_transferdate => @TransferDate::timestamp, p_referencenumber => @Ref::text, p_notes => @Notes::text, p_by => @By::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@From", m.FromGenericCashAccountId);
            cmd.Parameters.AddWithValue("@To", m.ToGenericCashAccountId);
            cmd.Parameters.AddWithValue("@Amount", m.Amount);
            cmd.Parameters.AddWithValue("@TransferDate", m.TransferDate == default ? (object)DBNull.Value : m.TransferDate);
            cmd.Parameters.AddWithValue("@Ref", (object?)m.ReferenceNumber ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@By", (object?)m.CreatedBy ?? DBNull.Value);

            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task ReverseAsync(int id, string farmId, string reason, string? reversedBy)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT spgenericcashtransfer_reverse(p_genericcashtransferid => @Id::int, p_farmid => @FarmId::text, p_reason => @Reason::text, p_reversedby => @By::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Reason", reason);
            cmd.Parameters.AddWithValue("@By", (object?)reversedBy ?? DBNull.Value);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task ApproveAsync(int id, string farmId, string? approvedBy)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericcashtransfer_approve(p_genericcashtransferid => @GenericCashTransferId::int, p_farmid => @FarmId::text, p_approvedby => @ApprovedBy::text)", conn);
            cmd.Parameters.AddWithValue("@GenericCashTransferId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task CancelAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericcashtransfer_cancel(p_genericcashtransferid => @GenericCashTransferId::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@GenericCashTransferId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static GenericCashTransferModel ReadTransfer(NpgsqlDataReader r) => new()
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
            TransferNumber           = r.IsDBNull(r.GetOrdinal("TransferNumber")) ? null : r.GetString(r.GetOrdinal("TransferNumber")),
            ReferenceNumber          = r.IsDBNull(r.GetOrdinal("ReferenceNumber")) ? null : r.GetString(r.GetOrdinal("ReferenceNumber")),
            ReversedBy               = r.IsDBNull(r.GetOrdinal("ReversedBy")) ? null : r.GetString(r.GetOrdinal("ReversedBy")),
            ReversedAt               = r.IsDBNull(r.GetOrdinal("ReversedAt")) ? null : r.GetDateTime(r.GetOrdinal("ReversedAt")),
            ReversalReason           = r.IsDBNull(r.GetOrdinal("ReversalReason")) ? null : r.GetString(r.GetOrdinal("ReversalReason")),
        };
    }
}
