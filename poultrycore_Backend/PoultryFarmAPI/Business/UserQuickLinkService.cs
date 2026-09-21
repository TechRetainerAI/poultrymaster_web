// User Quick Links (migration 318).
//
// Three calls over three SQL functions. The cleaning -- dropping blanks,
// non-strings, duplicates and anything that is not a path, and capping the
// length -- is deliberately NOT repeated here: 318's set() does it, and a
// second copy in C# is a second place for the rules to drift. This layer sends
// the array and maps what comes back.

using System.Text.Json;
using Npgsql;
using NpgsqlTypes;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IUserQuickLinkService
    {
        Task<UserQuickLinksModel> GetAsync(string userId, string farmId);
        Task<UserQuickLinksModel> SaveAsync(UserQuickLinksSaveRequest r);
        Task ResetAsync(string userId, string farmId);
    }

    public class UserQuickLinkService : IUserQuickLinkService
    {
        private readonly string _cs;
        public UserQuickLinkService(string cs) => _cs = cs;

        private static List<string> ReadHrefs(string? json)
        {
            if (string.IsNullOrWhiteSpace(json)) return new List<string>();
            try
            {
                return JsonSerializer.Deserialize<List<string>>(json) ?? new List<string>();
            }
            catch (JsonException)
            {
                // The column is CHECK-constrained to a JSON array, so this can
                // only happen if something bypassed the constraint. An unusable
                // preference is not worth a 500 on every page load -- the bar
                // falls back to its defaults instead.
                return new List<string>();
            }
        }

        public async Task<UserQuickLinksModel> GetAsync(string userId, string farmId)
        {
            var model = new UserQuickLinksModel { UserId = userId, FarmId = farmId };

            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spuserquicklinks_get(p_userid => @UserId::text, " +
                "p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@UserId", userId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();

            // NO ROW means never customised, which is not the same as an empty
            // bar. Customised stays false and the caller shows its defaults.
            if (await r.ReadAsync())
            {
                model.Customised = true;
                model.Hrefs = ReadHrefs(r.GetValue(r.GetOrdinal("hrefs"))?.ToString());
                var u = r.GetOrdinal("updatedat");
                model.UpdatedAt = r.IsDBNull(u) ? null : r.GetDateTime(u);
            }
            return model;
        }

        public async Task<UserQuickLinksModel> SaveAsync(UserQuickLinksSaveRequest req)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT spuserquicklinks_set(p_userid => @UserId::text, " +
                "p_farmid => @FarmId::text, p_hrefs => @Hrefs::jsonb)", c);
            cmd.Parameters.AddWithValue("@UserId", req.UserId);
            cmd.Parameters.AddWithValue("@FarmId", req.FarmId);
            cmd.Parameters.Add(new NpgsqlParameter("@Hrefs", NpgsqlDbType.Jsonb)
            {
                Value = JsonSerializer.Serialize(req.Hrefs ?? new List<string>()),
            });
            await c.OpenAsync();
            var cleaned = await cmd.ExecuteScalarAsync();

            // What comes back is what was STORED, not what was sent -- the
            // function may have dropped a duplicate or a junk entry, and the
            // dialog should redraw from the truth rather than from its own
            // optimism.
            return new UserQuickLinksModel
            {
                UserId = req.UserId,
                FarmId = req.FarmId,
                Customised = true,
                Hrefs = ReadHrefs(cleaned?.ToString()),
                UpdatedAt = DateTime.UtcNow,
            };
        }

        public async Task ResetAsync(string userId, string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT spuserquicklinks_reset(p_userid => @UserId::text, " +
                "p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@UserId", userId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }
    }
}
