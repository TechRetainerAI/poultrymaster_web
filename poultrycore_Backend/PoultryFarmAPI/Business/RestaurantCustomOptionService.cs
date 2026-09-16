using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class RestaurantCustomOptionService : IRestaurantCustomOptionService
    {
        private readonly string _cs;
        public RestaurantCustomOptionService(string cs) => _cs = cs;
        public string GetConnectionString() => _cs;

        private static RestaurantCustomOptionModel Read(NpgsqlDataReader r) => new()
        {
            CustomOptionId = r.GetInt32(r.GetOrdinal("customoptionid")),
            FarmId         = r.GetString(r.GetOrdinal("farmid")),
            ListKey        = r.GetString(r.GetOrdinal("listkey")),
            Value          = r.GetString(r.GetOrdinal("value")),
            SortOrder      = r.IsDBNull(r.GetOrdinal("sortorder")) ? 500 : r.GetInt32(r.GetOrdinal("sortorder")),
            IsActive       = !r.IsDBNull(r.GetOrdinal("isactive")) && r.GetBoolean(r.GetOrdinal("isactive")),
            CreatedAt      = r.IsDBNull(r.GetOrdinal("createdat")) ? null : r.GetDateTime(r.GetOrdinal("createdat")),
            CreatedBy      = r.IsDBNull(r.GetOrdinal("createdby")) ? null : r.GetString(r.GetOrdinal("createdby")),
        };

        public async Task<List<RestaurantCustomOptionModel>> ListAsync(string farmId, string listKey)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sprestaurant_customoption_list(" +
                "p_farmid => @FarmId::text, p_listkey => @ListKey::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ListKey", listKey);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<RestaurantCustomOptionModel>();
            while (await r.ReadAsync()) list.Add(Read(r));
            return list;
        }

        public async Task<List<RestaurantCustomOptionModel>> ListAllAsync(string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sprestaurant_customoption_list_all(p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<RestaurantCustomOptionModel>();
            while (await r.ReadAsync()) list.Add(Read(r));
            return list;
        }

        public async Task<RestaurantCustomOptionModel?> InsertAsync(string farmId, string listKey, string value, string? createdBy)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sprestaurant_customoption_insert(" +
                "p_farmid => @FarmId::text, p_listkey => @ListKey::text, " +
                "p_value => @Value::text, p_createdby => @CreatedBy::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ListKey", listKey);
            cmd.Parameters.AddWithValue("@Value", value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)createdBy ?? DBNull.Value);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            // The proc is idempotent: re-saving an existing value returns that row.
            return await r.ReadAsync() ? Read(r) : null;
        }

        public async Task<bool> DeleteAsync(string farmId, int customOptionId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_customoption_delete(" +
                "p_farmid => @FarmId::text, p_customoptionid => @Id::integer)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Id", customOptionId);
            await conn.OpenAsync();
            var rows = await cmd.ExecuteScalarAsync();
            return rows is int n && n > 0;
        }
    }
}
