// =============================================================================
// Restaurant Internal Use (migration 330). Every rule lives in the
// sprestaurant_internalusage_* functions (each one transaction: the stock
// movements, the FIFO draws and the header commit together). This class passes
// parameters and reads rows back by column NAME. Refusals (P0001) become a 400
// through RestaurantBusinessRuleFilter.
// =============================================================================

using System.Text.Json;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IRestaurantInternalUseService
    {
        Task<List<RestaurantInternalUseRecord>> ListAsync(string farmId, string? status, string? category, DateTime? from, DateTime? to);
        Task<RestaurantInternalUseRecord?> GetAsync(string farmId, int id);
        Task<List<RestaurantInternalUseOption>> OptionsAsync(string farmId);
        Task<int> CreateAsync(RestaurantInternalUseSaveRequest r, string by);
        Task UpdateAsync(int id, RestaurantInternalUseSaveRequest r, string by);
        Task DeleteAsync(string farmId, int id, string by);
        Task PostAsync(string farmId, int id, string by);
        Task ReverseAsync(string farmId, int id, string? reason, string by);
    }

    public class RestaurantInternalUseService : IRestaurantInternalUseService
    {
        private readonly string _cs;
        public RestaurantInternalUseService(string connectionString) { _cs = connectionString; }

        private static readonly JsonSerializerOptions Camel = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };
        private static string? Blank(string? s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();

        private static string ItemsJson(List<RestaurantInternalUseItem> items) =>
            JsonSerializer.Serialize(items.Select(i => new
            {
                i.ItemType, i.IngredientId, i.MenuItemId, i.EntryQuantity, i.EntryUnit,
                i.QuantityPerStaff, i.EntryUnitCost, i.ItemNotes,
            }), Camel);

        public async Task<List<RestaurantInternalUseRecord>> ListAsync(string farmId, string? status, string? category, DateTime? from, DateTime? to)
        {
            var rows = await RowsAsync(
                "SELECT * FROM sprestaurant_internalusage_getall(p_farmid => @f::text, p_status => @s::text, " +
                "p_category => @c::text, p_fromdate => @a::date, p_todate => @b::date)",
                ("f", farmId), ("s", Blank(status)), ("c", Blank(category)), ("a", from?.Date), ("b", to?.Date));
            return rows.Select(Map).ToList();
        }

        public async Task<RestaurantInternalUseRecord?> GetAsync(string farmId, int id)
        {
            var rows = await RowsAsync("SELECT * FROM sprestaurant_internalusage_getbyid(p_internalusageid => @i::int, p_farmid => @f::text)",
                                       ("i", id), ("f", farmId));
            return rows.Select(Map).FirstOrDefault();
        }

        public async Task<List<RestaurantInternalUseOption>> OptionsAsync(string farmId)
        {
            var rows = await RowsAsync("SELECT * FROM sprestaurant_internalusage_items(p_farmid => @f::text)", ("f", farmId));
            return rows.Select(r => new RestaurantInternalUseOption
            {
                ItemType = S(r, "itemtype") ?? "Ingredient",
                ItemId = I(r, "itemid"),
                Name = S(r, "name") ?? "",
                Category = S(r, "category"),
                Unit = S(r, "unit"),
                OnHand = D(r, "onhand"),
                SuggestedUnitCost = D(r, "suggestedunitcost"),
                CostMode = S(r, "costmode"),
            }).ToList();
        }

        public async Task<int> CreateAsync(RestaurantInternalUseSaveRequest r, string by)
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            await using var cmd = Command(conn,
                "SELECT sprestaurant_internalusage_insert(p_farmid => @f::text, p_usagedate => @d::date, p_category => @c::text, " +
                "p_reason => @r::text, p_recipientname => @rn::text, p_responsiblestaffid => @st::int, p_staffcount => @sc::int, " +
                "p_notes => @n::text, p_itemsjson => @j::text, p_createdby => @by::text)",
                ("f", r.FarmId), ("d", r.UsageDate.Date), ("c", r.Category), ("r", Blank(r.Reason)), ("rn", Blank(r.RecipientName)),
                ("st", r.ResponsibleStaffId), ("sc", r.StaffCount), ("n", Blank(r.Notes)), ("j", ItemsJson(r.Items)), ("by", by));
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public Task UpdateAsync(int id, RestaurantInternalUseSaveRequest r, string by) =>
            ExecAsync("SELECT sprestaurant_internalusage_update(p_internalusageid => @i::int, p_farmid => @f::text, p_usagedate => @d::date, " +
                      "p_category => @c::text, p_reason => @r::text, p_recipientname => @rn::text, p_responsiblestaffid => @st::int, " +
                      "p_staffcount => @sc::int, p_notes => @n::text, p_itemsjson => @j::text, p_updatedby => @by::text)",
                      ("i", id), ("f", r.FarmId), ("d", r.UsageDate.Date), ("c", r.Category), ("r", Blank(r.Reason)),
                      ("rn", Blank(r.RecipientName)), ("st", r.ResponsibleStaffId), ("sc", r.StaffCount), ("n", Blank(r.Notes)),
                      ("j", ItemsJson(r.Items)), ("by", by));

        public Task DeleteAsync(string farmId, int id, string by) =>
            ExecAsync("SELECT sprestaurant_internalusage_delete(p_internalusageid => @i::int, p_farmid => @f::text, p_userid => @by::text)",
                      ("i", id), ("f", farmId), ("by", by));

        public Task PostAsync(string farmId, int id, string by) =>
            ExecAsync("SELECT sprestaurant_internalusage_post(p_internalusageid => @i::int, p_farmid => @f::text, p_postedby => @by::text)",
                      ("i", id), ("f", farmId), ("by", by));

        public Task ReverseAsync(string farmId, int id, string? reason, string by) =>
            ExecAsync("SELECT sprestaurant_internalusage_reverse(p_internalusageid => @i::int, p_farmid => @f::text, " +
                      "p_reason => @r::text, p_reversedby => @by::text)",
                      ("i", id), ("f", farmId), ("r", Blank(reason)), ("by", by));

        // ── Mapping & plumbing (same as RestaurantSupplierService) ────────

        private static RestaurantInternalUseRecord Map(Dictionary<string, object?> r)
        {
            var items = new List<RestaurantInternalUseItem>();
            var json = S(r, "itemsjson");
            if (!string.IsNullOrWhiteSpace(json))
                items = JsonSerializer.Deserialize<List<RestaurantInternalUseItem>>(json,
                            new JsonSerializerOptions { PropertyNameCaseInsensitive = true }) ?? new();
            return new RestaurantInternalUseRecord
            {
                InternalUsageId = I(r, "internalusageid"),
                FarmId = S(r, "farmid") ?? "",
                UsageDate = Dt(r, "usagedate") ?? DateTime.MinValue,
                ReferenceNo = S(r, "referenceno"),
                Category = S(r, "category") ?? "",
                Reason = S(r, "reason"),
                RecipientName = S(r, "recipientname"),
                ResponsibleStaffId = r.TryGetValue("responsiblestaffid", out var rs) && rs != null ? Convert.ToInt32(rs) : null,
                StaffCount = r.TryGetValue("staffcount", out var sc) && sc != null ? Convert.ToInt32(sc) : null,
                Status = S(r, "status") ?? "Draft",
                TotalCostValue = D(r, "totalcostvalue"),
                PlCost = D(r, "plcost"),
                Notes = S(r, "notes"),
                PostedBy = S(r, "postedby"),
                PostedAt = Dt(r, "postedat"),
                ReversedBy = S(r, "reversedby"),
                ReversedAt = Dt(r, "reversedat"),
                ReversalReason = S(r, "reversalreason"),
                CreatedBy = S(r, "createdby"),
                CreatedAt = Dt(r, "createdat") ?? DateTime.MinValue,
                UpdatedAt = Dt(r, "updatedat"),
                Items = items,
            };
        }

        private static int I(Dictionary<string, object?> r, string k) => r.TryGetValue(k, out var v) && v != null ? Convert.ToInt32(v) : 0;
        private static decimal D(Dictionary<string, object?> r, string k) => r.TryGetValue(k, out var v) && v != null ? Convert.ToDecimal(v) : 0m;
        private static string? S(Dictionary<string, object?> r, string k) => r.TryGetValue(k, out var v) && v != null ? v.ToString() : null;
        private static DateTime? Dt(Dictionary<string, object?> r, string k)
        {
            if (!r.TryGetValue(k, out var v) || v == null) return null;
            return v switch { DateOnly d => d.ToDateTime(TimeOnly.MinValue), DateTime t => t, _ => Convert.ToDateTime(v) };
        }

        private static NpgsqlCommand Command(NpgsqlConnection conn, string sql, params (string name, object? value)[] ps)
        {
            var cmd = new NpgsqlCommand(sql, conn);
            foreach (var (name, value) in ps) cmd.Parameters.AddWithValue("@" + name, value ?? DBNull.Value);
            return cmd;
        }

        private async Task ExecAsync(string sql, params (string, object?)[] ps)
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            await using var cmd = Command(conn, sql, ps);
            await cmd.ExecuteNonQueryAsync();
        }

        private async Task<List<Dictionary<string, object?>>> RowsAsync(string sql, params (string, object?)[] ps)
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            await using var cmd = Command(conn, sql, ps);
            await using var rd = await cmd.ExecuteReaderAsync();
            var list = new List<Dictionary<string, object?>>();
            while (await rd.ReadAsync())
            {
                var d = new Dictionary<string, object?>(StringComparer.OrdinalIgnoreCase);
                for (var i = 0; i < rd.FieldCount; i++) d[rd.GetName(i)] = rd.IsDBNull(i) ? null : rd.GetValue(i);
                list.Add(d);
            }
            return list;
        }
    }
}
