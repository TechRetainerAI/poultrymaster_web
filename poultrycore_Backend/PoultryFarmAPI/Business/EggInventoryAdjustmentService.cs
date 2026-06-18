using System.Data;
using Microsoft.Data.SqlClient;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class EggInventoryAdjustmentService : IEggInventoryAdjustmentService
    {
        private readonly string _connectionString;

        public EggInventoryAdjustmentService(string connectionString)
        {
            _connectionString = connectionString;
        }

        public async Task<List<EggInventoryAdjustmentModel>> GetAllAsync(string farmId)
        {
            var list = new List<EggInventoryAdjustmentModel>();
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spEggInventoryAdjustment_GetAll", conn)
            {
                CommandType = CommandType.StoredProcedure
            };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                list.Add(Read(reader));
            }
            return list;
        }

        public async Task<EggInventoryAdjustmentModel?> GetByIdAsync(int adjustmentId, string farmId)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spEggInventoryAdjustment_GetById", conn)
            {
                CommandType = CommandType.StoredProcedure
            };
            cmd.Parameters.AddWithValue("@AdjustmentId", adjustmentId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            if (await reader.ReadAsync())
                return Read(reader);
            return null;
        }

        public async Task<int> InsertAsync(EggInventoryAdjustmentModel model)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spEggInventoryAdjustment_Insert", conn)
            {
                CommandType = CommandType.StoredProcedure
            };
            cmd.Parameters.AddWithValue("@UserId", model.UserId);
            cmd.Parameters.AddWithValue("@FarmId", model.FarmId);
            cmd.Parameters.AddWithValue("@AdjustmentDate", model.AdjustmentDate);
            cmd.Parameters.AddWithValue("@AdjustmentType", model.AdjustmentType);
            cmd.Parameters.AddWithValue("@EggDelta", model.EggDelta);
            cmd.Parameters.AddWithValue("@Description", (object?)model.Description ?? DBNull.Value);
            await conn.OpenAsync();
            var result = await cmd.ExecuteScalarAsync();
            return Convert.ToInt32(result);
        }

        public async Task UpdateAsync(EggInventoryAdjustmentModel model)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spEggInventoryAdjustment_Update", conn)
            {
                CommandType = CommandType.StoredProcedure
            };
            cmd.Parameters.AddWithValue("@AdjustmentId", model.AdjustmentId);
            cmd.Parameters.AddWithValue("@FarmId", model.FarmId);
            cmd.Parameters.AddWithValue("@AdjustmentDate", model.AdjustmentDate);
            cmd.Parameters.AddWithValue("@AdjustmentType", model.AdjustmentType);
            cmd.Parameters.AddWithValue("@EggDelta", model.EggDelta);
            cmd.Parameters.AddWithValue("@Description", (object?)model.Description ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteAsync(int adjustmentId, string farmId)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spEggInventoryAdjustment_Delete", conn)
            {
                CommandType = CommandType.StoredProcedure
            };
            cmd.Parameters.AddWithValue("@AdjustmentId", adjustmentId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static EggInventoryAdjustmentModel Read(SqlDataReader reader)
        {
            return new EggInventoryAdjustmentModel
            {
                AdjustmentId = reader.GetInt32(0),
                UserId = reader.GetString(1),
                FarmId = reader.GetString(2),
                AdjustmentDate = reader.GetDateTime(3),
                AdjustmentType = reader.GetString(4),
                EggDelta = reader.GetInt32(5),
                Description = reader.IsDBNull(6) ? null : reader.GetString(6),
                CreatedDate = reader.GetDateTime(7),
            };
        }
    }
}
