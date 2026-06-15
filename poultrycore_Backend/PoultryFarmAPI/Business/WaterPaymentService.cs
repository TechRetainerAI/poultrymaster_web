using System.Data;
using Microsoft.Data.SqlClient;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class WaterPaymentService : IWaterPaymentService
    {
        private readonly string _connectionString;

        public WaterPaymentService(string connectionString)
        {
            _connectionString = connectionString;
        }

        public async Task<int> Record(WaterPaymentModel m)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spWaterPayment_Record", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@WaterSaleId", m.WaterSaleId);
            cmd.Parameters.AddWithValue("@Amount", m.Amount);
            cmd.Parameters.AddWithValue("@PaymentMethod", (object?)m.PaymentMethod ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PaymentDate", m.PaymentDate == default ? DBNull.Value : (object)m.PaymentDate);
            cmd.Parameters.AddWithValue("@Reference", (object?)m.Reference ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Note", (object?)m.Note ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)m.CreatedBy ?? DBNull.Value);

            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task<List<WaterPaymentModel>> GetBySale(int saleId, string farmId)
        {
            var list = new List<WaterPaymentModel>();
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spWaterPayment_GetBySale", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterSaleId", saleId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync()) list.Add(Read(reader, includeCustomerName: false));
            return list;
        }

        public async Task<List<WaterPaymentModel>> GetAll(string farmId)
        {
            var list = new List<WaterPaymentModel>();
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spWaterPayment_GetAll", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync()) list.Add(Read(reader, includeCustomerName: true));
            return list;
        }

        private static WaterPaymentModel Read(SqlDataReader r, bool includeCustomerName) => new()
        {
            WaterPaymentId = r.GetInt32(r.GetOrdinal("WaterPaymentId")),
            FarmId         = r.GetString(r.GetOrdinal("FarmId")),
            WaterSaleId    = r.GetInt32(r.GetOrdinal("WaterSaleId")),
            Amount         = r.GetDecimal(r.GetOrdinal("Amount")),
            PaymentMethod  = r.IsDBNull(r.GetOrdinal("PaymentMethod")) ? null : r.GetString(r.GetOrdinal("PaymentMethod")),
            PaymentDate    = r.GetDateTime(r.GetOrdinal("PaymentDate")),
            Reference      = r.IsDBNull(r.GetOrdinal("Reference")) ? null : r.GetString(r.GetOrdinal("Reference")),
            Note           = r.IsDBNull(r.GetOrdinal("Note")) ? null : r.GetString(r.GetOrdinal("Note")),
            CreatedDate    = r.GetDateTime(r.GetOrdinal("CreatedDate")),
            CreatedBy      = r.IsDBNull(r.GetOrdinal("CreatedBy")) ? null : r.GetString(r.GetOrdinal("CreatedBy")),
            CustomerName   = includeCustomerName && !r.IsDBNull(r.GetOrdinal("CustomerName")) ? r.GetString(r.GetOrdinal("CustomerName")) : null,
        };
    }
}
