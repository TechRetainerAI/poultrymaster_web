using System.Data;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class FeedInventoryAdjustmentService : IFeedInventoryAdjustmentService
    {
        private readonly string _connectionString;

        public FeedInventoryAdjustmentService(string connectionString)
        {
            _connectionString = connectionString;
        }

        public async Task<List<FeedInventoryAdjustmentModel>> GetAllAsync(string farmId)
        {
            var list = new List<FeedInventoryAdjustmentModel>();
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spfeedinventoryadjustment_getall(p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                list.Add(Read(reader));
            }
            return list;
        }

        public async Task<FeedInventoryAdjustmentModel?> GetByIdAsync(int adjustmentId, string farmId)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spfeedinventoryadjustment_getbyid(p_adjustmentid => @AdjustmentId::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@AdjustmentId", adjustmentId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            if (await reader.ReadAsync())
                return Read(reader);
            return null;
        }

        public async Task<int> InsertAsync(FeedInventoryAdjustmentModel model)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spfeedinventoryadjustment_insert(p_userid => @UserId::text, p_farmid => @FarmId::text, p_adjustmentdate => @AdjustmentDate::timestamp, p_adjustmenttype => @AdjustmentType::text, p_feeddeltakg => @FeedDeltaKg::numeric, p_description => @Description::text)", conn);
            cmd.Parameters.AddWithValue("@UserId", model.UserId);
            cmd.Parameters.AddWithValue("@FarmId", model.FarmId);
            cmd.Parameters.AddWithValue("@AdjustmentDate", model.AdjustmentDate);
            cmd.Parameters.AddWithValue("@AdjustmentType", model.AdjustmentType);
            cmd.Parameters.AddWithValue("@FeedDeltaKg", model.FeedDeltaKg);
            cmd.Parameters.AddWithValue("@Description", (object?)model.Description ?? DBNull.Value);
            await conn.OpenAsync();
            var result = await cmd.ExecuteScalarAsync();
            return Convert.ToInt32(result);
        }

        public async Task UpdateAsync(FeedInventoryAdjustmentModel model)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spfeedinventoryadjustment_update(p_adjustmentid => @AdjustmentId::int, p_farmid => @FarmId::text, p_adjustmentdate => @AdjustmentDate::timestamp, p_adjustmenttype => @AdjustmentType::text, p_feeddeltakg => @FeedDeltaKg::numeric, p_description => @Description::text)", conn);
            cmd.Parameters.AddWithValue("@AdjustmentId", model.AdjustmentId);
            cmd.Parameters.AddWithValue("@FarmId", model.FarmId);
            cmd.Parameters.AddWithValue("@AdjustmentDate", model.AdjustmentDate);
            cmd.Parameters.AddWithValue("@AdjustmentType", model.AdjustmentType);
            cmd.Parameters.AddWithValue("@FeedDeltaKg", model.FeedDeltaKg);
            cmd.Parameters.AddWithValue("@Description", (object?)model.Description ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteAsync(int adjustmentId, string farmId)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spfeedinventoryadjustment_delete(p_adjustmentid => @AdjustmentId::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@AdjustmentId", adjustmentId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static FeedInventoryAdjustmentModel Read(NpgsqlDataReader reader)
        {
            return new FeedInventoryAdjustmentModel
            {
                AdjustmentId = reader.GetInt32(0),
                UserId = reader.GetString(1),
                FarmId = reader.GetString(2),
                AdjustmentDate = reader.GetDateTime(3),
                AdjustmentType = reader.GetString(4),
                FeedDeltaKg = reader.GetDecimal(5),
                Description = reader.IsDBNull(6) ? null : reader.GetString(6),
                CreatedDate = reader.GetDateTime(7),
            };
        }
    }
}
