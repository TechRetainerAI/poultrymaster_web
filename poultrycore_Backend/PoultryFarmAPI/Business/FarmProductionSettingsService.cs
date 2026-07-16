using System.Data;
using Microsoft.Data.SqlClient;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IFarmProductionSettingsService
    {
        Task<FarmProductionSettingsModel> Get(string farmId);
        Task<FarmProductionSettingsModel> Upsert(FarmProductionSettingsModel model);
    }

    // Thin ADO.NET wrapper over spFarmProductionSettings_* (migration 153).
    public class FarmProductionSettingsService : IFarmProductionSettingsService
    {
        private readonly string _connectionString;

        public FarmProductionSettingsService(string connectionString)
        {
            _connectionString = connectionString;
        }

        private static string? GetNullableString(SqlDataReader reader, string name)
        {
            int o = reader.GetOrdinal(name);
            return reader.IsDBNull(o) ? null : reader.GetString(o);
        }

        private static FarmProductionSettingsModel Map(SqlDataReader reader) => new()
        {
            Id = reader.GetInt32(reader.GetOrdinal("Id")),
            FarmId = reader.GetString(reader.GetOrdinal("FarmId")),
            FirstPickTime = GetNullableString(reader, "FirstPickTime"),
            SecondPickTime = GetNullableString(reader, "SecondPickTime"),
            ThirdPickTime = GetNullableString(reader, "ThirdPickTime"),
            FourthPickTime = GetNullableString(reader, "FourthPickTime"),
            EnableFourthPick = reader.GetBoolean(reader.GetOrdinal("EnableFourthPick")),
            CreatedBy = GetNullableString(reader, "CreatedBy"),
            CreatedDate = reader.IsDBNull(reader.GetOrdinal("CreatedDate")) ? (DateTime?)null : reader.GetDateTime(reader.GetOrdinal("CreatedDate")),
            UpdatedBy = GetNullableString(reader, "UpdatedBy"),
            UpdatedDate = reader.IsDBNull(reader.GetOrdinal("UpdatedDate")) ? (DateTime?)null : reader.GetDateTime(reader.GetOrdinal("UpdatedDate")),
        };

        public async Task<FarmProductionSettingsModel> Get(string farmId)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spFarmProductionSettings_Get", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            if (await reader.ReadAsync()) return Map(reader);
            // Should not happen (the proc always returns a defaults row), but be safe.
            return new FarmProductionSettingsModel
            {
                FarmId = farmId,
                FirstPickTime = "09:00", SecondPickTime = "12:00", ThirdPickTime = "16:00", FourthPickTime = "18:00",
                EnableFourthPick = false,
            };
        }

        public async Task<FarmProductionSettingsModel> Upsert(FarmProductionSettingsModel model)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spFarmProductionSettings_Upsert", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", model.FarmId);
            cmd.Parameters.AddWithValue("@FirstPickTime", (object?)model.FirstPickTime ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@SecondPickTime", (object?)model.SecondPickTime ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ThirdPickTime", (object?)model.ThirdPickTime ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FourthPickTime", (object?)model.FourthPickTime ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@EnableFourthPick", model.EnableFourthPick);
            cmd.Parameters.AddWithValue("@UpdatedBy", (object?)model.UpdatedBy ?? DBNull.Value);
            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            if (await reader.ReadAsync()) return Map(reader);
            return model;
        }
    }
}
