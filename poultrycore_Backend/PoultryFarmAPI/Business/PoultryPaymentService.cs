using System.Data;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IPoultryPaymentService
    {
        Task<int> Record(PoultryPaymentModel m);
        Task<List<PoultryPaymentModel>> GetBySale(int saleId, string farmId);
        Task<List<PoultryPaymentModel>> GetAll(string farmId);
    }

    // Port of WaterPaymentService for poultry. Records payments against a Sale
    // and returns them; the record proc recomputes Sale.AmountPaid/Paid + cash.
    public class PoultryPaymentService : IPoultryPaymentService
    {
        private readonly string _connectionString;

        public PoultryPaymentService(string connectionString)
        {
            _connectionString = connectionString;
        }

        public async Task<int> Record(PoultryPaymentModel m)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrypayment_record(p_farmid => @FarmId::text, p_saleid => @SaleId::int, p_amount => @Amount::numeric, p_paymentmethod => @PaymentMethod::text, p_paymentdate => @PaymentDate::timestamp, p_reference => @Reference::text, p_note => @Note::text, p_createdby => @CreatedBy::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@SaleId", m.SaleId);
            cmd.Parameters.AddWithValue("@Amount", m.Amount);
            cmd.Parameters.AddWithValue("@PaymentMethod", (object?)m.PaymentMethod ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PaymentDate", m.PaymentDate == default ? DBNull.Value : (object)m.PaymentDate);
            cmd.Parameters.AddWithValue("@Reference", (object?)m.Reference ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Note", (object?)m.Note ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)m.CreatedBy ?? DBNull.Value);

            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task<List<PoultryPaymentModel>> GetBySale(int saleId, string farmId)
        {
            var list = new List<PoultryPaymentModel>();
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrypayment_getbysale(p_saleid => @SaleId::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@SaleId", saleId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync()) list.Add(Read(reader, includeCustomerName: false));
            return list;
        }

        public async Task<List<PoultryPaymentModel>> GetAll(string farmId)
        {
            var list = new List<PoultryPaymentModel>();
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrypayment_getall(p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync()) list.Add(Read(reader, includeCustomerName: true));
            return list;
        }

        private static PoultryPaymentModel Read(NpgsqlDataReader r, bool includeCustomerName) => new()
        {
            PoultryPaymentId = r.GetInt32(r.GetOrdinal("PoultryPaymentId")),
            FarmId           = r.GetString(r.GetOrdinal("FarmId")),
            SaleId           = r.GetInt32(r.GetOrdinal("SaleId")),
            Amount           = r.GetDecimal(r.GetOrdinal("Amount")),
            PaymentMethod    = r.IsDBNull(r.GetOrdinal("PaymentMethod")) ? null : r.GetString(r.GetOrdinal("PaymentMethod")),
            PaymentDate      = r.GetDateTime(r.GetOrdinal("PaymentDate")),
            Reference        = r.IsDBNull(r.GetOrdinal("Reference")) ? null : r.GetString(r.GetOrdinal("Reference")),
            Note             = r.IsDBNull(r.GetOrdinal("Note")) ? null : r.GetString(r.GetOrdinal("Note")),
            CreatedDate      = r.GetDateTime(r.GetOrdinal("CreatedDate")),
            CreatedBy        = r.IsDBNull(r.GetOrdinal("CreatedBy")) ? null : r.GetString(r.GetOrdinal("CreatedBy")),
            CustomerName     = includeCustomerName && !r.IsDBNull(r.GetOrdinal("CustomerName")) ? r.GetString(r.GetOrdinal("CustomerName")) : null,
        };
    }
}
