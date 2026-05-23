using System.Data;
using System.Data.SqlClient;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class WaterProductService : IWaterProductService
    {
        private readonly string _connectionString;

        public WaterProductService(string connectionString)
        {
            _connectionString = connectionString;
        }

        public async Task<int> Insert(WaterProductModel m)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spWaterProduct_Insert", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Name", m.Name);
            cmd.Parameters.AddWithValue("@Sku", (object?)m.Sku ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@SizeMl", (object?)m.SizeMl ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Unit", (object?)m.Unit ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@UnitPrice", m.UnitPrice);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);

            await conn.OpenAsync();
            var result = await cmd.ExecuteScalarAsync();
            return Convert.ToInt32(result);
        }

        public async Task Update(WaterProductModel m)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spWaterProduct_Update", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterProductId", m.WaterProductId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Name", m.Name);
            cmd.Parameters.AddWithValue("@Sku", (object?)m.Sku ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@SizeMl", (object?)m.SizeMl ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Unit", (object?)m.Unit ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@UnitPrice", m.UnitPrice);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<WaterProductModel?> GetById(int id, string farmId)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spWaterProduct_GetById", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterProductId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            if (await reader.ReadAsync()) return Read(reader);
            return null;
        }

        public async Task<List<WaterProductModel>> GetAll(string farmId)
        {
            var list = new List<WaterProductModel>();
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spWaterProduct_GetAll", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync()) list.Add(Read(reader));
            return list;
        }

        public async Task Delete(int id, string farmId)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spWaterProduct_Delete", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterProductId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static WaterProductModel Read(SqlDataReader r) => new()
        {
            WaterProductId = r.GetInt32(r.GetOrdinal("WaterProductId")),
            FarmId         = r.GetString(r.GetOrdinal("FarmId")),
            Name           = r.GetString(r.GetOrdinal("Name")),
            Sku            = r.IsDBNull(r.GetOrdinal("Sku")) ? null : r.GetString(r.GetOrdinal("Sku")),
            SizeMl         = r.IsDBNull(r.GetOrdinal("SizeMl")) ? null : r.GetInt32(r.GetOrdinal("SizeMl")),
            Unit           = r.IsDBNull(r.GetOrdinal("Unit")) ? null : r.GetString(r.GetOrdinal("Unit")),
            UnitPrice      = r.GetDecimal(r.GetOrdinal("UnitPrice")),
            IsActive       = r.GetBoolean(r.GetOrdinal("IsActive")),
            Notes          = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            CreatedDate    = r.GetDateTime(r.GetOrdinal("CreatedDate")),
            UpdatedDate    = r.IsDBNull(r.GetOrdinal("UpdatedDate")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedDate")),
            StockOnHand    = r.IsDBNull(r.GetOrdinal("StockOnHand")) ? 0 : Convert.ToInt32(r.GetValue(r.GetOrdinal("StockOnHand"))),
        };
    }
}
