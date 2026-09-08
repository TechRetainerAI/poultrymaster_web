using System.Data;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IFarmProductionSettingsService
    {
        Task<FarmProductionSettingsModel> Get(string farmId);
        Task<FarmProductionSettingsModel> Upsert(FarmProductionSettingsModel model);
    }

    // Thin ADO.NET wrapper over spFarmProductionSettings_* (migrations 153, 248).
    public class FarmProductionSettingsService : IFarmProductionSettingsService
    {
        private readonly string _connectionString;

        public FarmProductionSettingsService(string connectionString)
        {
            _connectionString = connectionString;
        }

        private static string? GetNullableString(NpgsqlDataReader reader, string name)
        {
            int o = reader.GetOrdinal(name);
            return reader.IsDBNull(o) ? null : reader.GetString(o);
        }

        /// <summary>
        /// True when the result set carries this column. The 5th/6th pick fields
        /// only exist once migration 248 is applied, and an API deployed ahead of
        /// its database should still be able to READ the four picks it has
        /// rather than throwing on a missing ordinal. Saving those two fields
        /// does need the migration — the SP signature changes with it.
        /// </summary>
        private static bool HasColumn(NpgsqlDataReader reader, string name)
        {
            for (int i = 0; i < reader.FieldCount; i++)
                if (string.Equals(reader.GetName(i), name, StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }

        private static string? GetOptionalString(NpgsqlDataReader reader, string name)
            => HasColumn(reader, name) ? GetNullableString(reader, name) : null;

        private static bool GetOptionalBool(NpgsqlDataReader reader, string name)
            => HasColumn(reader, name) && !reader.IsDBNull(reader.GetOrdinal(name)) && reader.GetBoolean(reader.GetOrdinal(name));

        private static FarmProductionSettingsModel Map(NpgsqlDataReader reader) => new()
        {
            Id = reader.GetInt32(reader.GetOrdinal("Id")),
            FarmId = reader.GetString(reader.GetOrdinal("FarmId")),
            FirstPickTime = GetNullableString(reader, "FirstPickTime"),
            SecondPickTime = GetNullableString(reader, "SecondPickTime"),
            ThirdPickTime = GetNullableString(reader, "ThirdPickTime"),
            FourthPickTime = GetNullableString(reader, "FourthPickTime"),
            FifthPickTime = GetOptionalString(reader, "FifthPickTime"),
            SixthPickTime = GetOptionalString(reader, "SixthPickTime"),
            EnableFourthPick = reader.GetBoolean(reader.GetOrdinal("EnableFourthPick")),
            EnableFifthPick = GetOptionalBool(reader, "EnableFifthPick"),
            EnableSixthPick = GetOptionalBool(reader, "EnableSixthPick"),
            CreatedBy = GetNullableString(reader, "CreatedBy"),
            CreatedDate = reader.IsDBNull(reader.GetOrdinal("CreatedDate")) ? (DateTime?)null : reader.GetDateTime(reader.GetOrdinal("CreatedDate")),
            UpdatedBy = GetNullableString(reader, "UpdatedBy"),
            UpdatedDate = reader.IsDBNull(reader.GetOrdinal("UpdatedDate")) ? (DateTime?)null : reader.GetDateTime(reader.GetOrdinal("UpdatedDate")),
        };

        public async Task<FarmProductionSettingsModel> Get(string farmId)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spfarmproductionsettings_get(p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            if (await reader.ReadAsync()) return Map(reader);
            // Should not happen (the proc always returns a defaults row), but be safe.
            return new FarmProductionSettingsModel
            {
                FarmId = farmId,
                FirstPickTime = "09:00", SecondPickTime = "12:00", ThirdPickTime = "16:00", FourthPickTime = "18:00",
                // The 5th and 6th have no default hour: an unset time reads as
                // "not set" rather than inventing a round of collection.
                EnableFourthPick = false, EnableFifthPick = false, EnableSixthPick = false,
            };
        }

        public async Task<FarmProductionSettingsModel> Upsert(FarmProductionSettingsModel model)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            // Named arguments throughout, so the 248 parameters can sit at the
            // end of the signature without this call caring about their order.
            using var cmd = new NpgsqlCommand("SELECT * FROM spfarmproductionsettings_upsert(p_farmid => @FarmId::text, p_firstpicktime => @FirstPickTime::text, p_secondpicktime => @SecondPickTime::text, p_thirdpicktime => @ThirdPickTime::text, p_fourthpicktime => @FourthPickTime::text, p_fifthpicktime => @FifthPickTime::text, p_sixthpicktime => @SixthPickTime::text, p_enablefourthpick => @EnableFourthPick::boolean, p_enablefifthpick => @EnableFifthPick::boolean, p_enablesixthpick => @EnableSixthPick::boolean, p_updatedby => @UpdatedBy::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", model.FarmId);
            cmd.Parameters.AddWithValue("@FirstPickTime", (object?)model.FirstPickTime ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@SecondPickTime", (object?)model.SecondPickTime ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ThirdPickTime", (object?)model.ThirdPickTime ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FourthPickTime", (object?)model.FourthPickTime ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FifthPickTime", (object?)model.FifthPickTime ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@SixthPickTime", (object?)model.SixthPickTime ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@EnableFourthPick", model.EnableFourthPick);
            cmd.Parameters.AddWithValue("@EnableFifthPick", model.EnableFifthPick);
            cmd.Parameters.AddWithValue("@EnableSixthPick", model.EnableSixthPick);
            cmd.Parameters.AddWithValue("@UpdatedBy", (object?)model.UpdatedBy ?? DBNull.Value);
            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            if (await reader.ReadAsync()) return Map(reader);
            return model;
        }
    }
}
