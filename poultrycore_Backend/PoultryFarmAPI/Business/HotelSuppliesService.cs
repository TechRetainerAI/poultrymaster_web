// =============================================================================
// Hotel supply purchases, Internal Use and Deferred inventory cost (migration 334).
//
// A thin caller of the 334 Postgres functions: stock, lots, cash and the
// supplier ledger all move inside one function call. Rows come back by column
// NAME with camelCase keys (the same shapes the Restaurant API returns, so the
// pages are the same). Refusals (P0001) become a 400 via HotelBusinessRuleFilter.
// =============================================================================

using System.Text.Json;
using Npgsql;

namespace PoultryFarmAPIWeb.Business
{
    public class HotelSupplyPurchaseInput
    {
        public int ItemId { get; set; }
        public decimal Quantity { get; set; }
        public decimal TotalCost { get; set; }
        public DateTime? PurchaseDate { get; set; }
        public int? SupplierId { get; set; }
        public string? SupplierName { get; set; }
        public string? PaymentMethod { get; set; }
        public decimal? AmountPaid { get; set; }
        public int? CashAccountId { get; set; }
        public DateTime? DueDate { get; set; }
        public string? Notes { get; set; }
    }

    public class HotelInternalUseInput
    {
        public DateTime? UsageDate { get; set; }
        public string Category { get; set; } = "";
        public string? Reason { get; set; }
        public string? RecipientName { get; set; }
        public int? StaffCount { get; set; }
        public string? Notes { get; set; }
        public List<JsonElement> Items { get; set; } = new();
    }

    public interface IHotelSuppliesService
    {
        Task<List<Dictionary<string, object?>>> PurchasesAsync(string farmId, DateTime? from, DateTime? to, int? supplierId, int? itemId, int? purchaseId);
        Task<int> CreatePurchaseAsync(string farmId, HotelSupplyPurchaseInput i, string by);
        Task ReversePurchaseAsync(string farmId, int id, string? reason, string by);
        Task<List<Dictionary<string, object?>>> CostModesAsync(string farmId);
        Task SetCostModeAsync(string farmId, string category, string costMode, string by);
        Task<object> DeferredAsync(string farmId, string? scope, int? itemId, int? supplierId, string? category, DateTime? from, DateTime? to, string? search);
        Task<List<Dictionary<string, object?>>> DeferredHistoryAsync(string farmId, int purchaseId);

        Task<List<Dictionary<string, object?>>> InternalUseListAsync(string farmId);
        Task<Dictionary<string, object?>?> InternalUseGetAsync(string farmId, int id);
        Task<List<Dictionary<string, object?>>> InternalUseItemsAsync(string farmId);
        Task<int> InternalUseCreateAsync(string farmId, HotelInternalUseInput i, string by);
        Task InternalUseUpdateAsync(string farmId, int id, HotelInternalUseInput i, string by);
        Task InternalUseDeleteAsync(string farmId, int id, string by);
        Task InternalUsePostAsync(string farmId, int id, string by);
        Task InternalUseReverseAsync(string farmId, int id, string? reason, string by);
    }

    public class HotelSuppliesService : IHotelSuppliesService
    {
        private readonly string _cs;
        public HotelSuppliesService(string connectionString) { _cs = connectionString; }

        // lowercase column name -> the camelCase key the frontend reads.
        private static readonly Dictionary<string, string> Keys = new[]
        {
            "purchaseId", "purchaseDate", "itemId", "itemName", "category", "unit", "supplierId", "supplierName",
            "quantity", "unitCost", "totalCost", "paymentMethod", "amountPaid", "allocated", "balance", "paymentStatus",
            "dueDate", "cashAccountId", "cashAccountName", "costMode", "remainingQuantity", "deferredTotalCost",
            "deferredRemainingCost", "notes", "status", "createdBy", "createdAt", "reversedBy", "reversedAt",
            "reversalReason", "itemCount", "isConfigured", "updatedBy", "updatedAt", "purchasedQuantity",
            "consumedQuantity", "operationalCost", "recognizedCost", "recognitionPercent", "allocatedRecognizedCost",
            "recognitionDrift", "costRecognitionMethod", "recognitionMethodLabel", "exceptionReason",
            "recognitionEvents", "lastRecognitionDate", "costingMethod", "queuePosition", "quantityAheadInQueue",
            "remainingDeferredCost", "deferredBasis", "purchaseCount", "deferredPurchases", "fullyRecognized",
            "notRecognized", "exceptions", "exceptionDrift", "blockedPurchases", "blockedCost", "drawId", "usedDate",
            "sourceType", "sourceLabel", "quantityDrawn", "unitCostAtDraw", "recognitionOutcome", "isReversed",
            "internalUsageId", "farmId", "usageDate", "referenceNo", "reason", "recipientName", "staffCount",
            "totalCostValue", "plCost", "postedBy", "postedAt", "itemType", "name", "onHand", "suggestedUnitCost",
        }.ToDictionary(k => k.ToLowerInvariant(), k => k);

        private static object Db(object? v) => v ?? DBNull.Value;
        private static string? Blank(string? s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();

        private async Task<List<Dictionary<string, object?>>> RowsAsync(string sql, params (string n, object? v)[] ps)
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            await using var cmd = new NpgsqlCommand(sql, conn);
            foreach (var (n, v) in ps) cmd.Parameters.AddWithValue(n, Db(v));
            await using var r = await cmd.ExecuteReaderAsync();
            var list = new List<Dictionary<string, object?>>();
            while (await r.ReadAsync())
            {
                var d = new Dictionary<string, object?>();
                for (var i = 0; i < r.FieldCount; i++)
                {
                    var name = r.GetName(i);
                    object? val = r.IsDBNull(i) ? null : r.GetValue(i);
                    if (name == "itemsjson")
                    {
                        d["items"] = JsonSerializer.Deserialize<JsonElement>(val?.ToString() ?? "[]");
                        continue;
                    }
                    d[Keys.TryGetValue(name, out var k) ? k : name] = val;
                }
                list.Add(d);
            }
            return list;
        }

        private async Task<object?> ScalarAsync(string sql, params (string n, object? v)[] ps)
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            await using var cmd = new NpgsqlCommand(sql, conn);
            foreach (var (n, v) in ps) cmd.Parameters.AddWithValue(n, Db(v));
            return await cmd.ExecuteScalarAsync();
        }

        // ── Purchases & cost recognition ─────────────────────────────────────
        public Task<List<Dictionary<string, object?>>> PurchasesAsync(string farmId, DateTime? from, DateTime? to, int? supplierId, int? itemId, int? purchaseId) =>
            RowsAsync("SELECT * FROM sphotelsupplypurchase_list(@f::text, @a::date, @b::date, @s::int, @i::int, @p::int)",
                ("f", farmId), ("a", from?.Date), ("b", to?.Date), ("s", supplierId), ("i", itemId), ("p", purchaseId));

        public async Task<int> CreatePurchaseAsync(string farmId, HotelSupplyPurchaseInput i, string by) =>
            Convert.ToInt32(await ScalarAsync(
                "SELECT sphotelsupplypurchase_create(p_farmid => @f::text, p_itemid => @i::int, p_quantity => @q::numeric, " +
                "p_totalcost => @t::numeric, p_purchasedate => @d::date, p_supplierid => @s::int, p_suppliername => @sn::text, " +
                "p_paymentmethod => @m::text, p_amountpaid => @p::numeric, p_cashaccountid => @a::int, p_duedate => @due::date, " +
                "p_notes => @n::text, p_createdby => @by::text)",
                ("f", farmId), ("i", i.ItemId), ("q", i.Quantity), ("t", i.TotalCost), ("d", i.PurchaseDate?.Date),
                ("s", i.SupplierId), ("sn", Blank(i.SupplierName)), ("m", Blank(i.PaymentMethod) ?? "Cash"),
                ("p", i.AmountPaid), ("a", i.CashAccountId), ("due", i.DueDate?.Date), ("n", Blank(i.Notes)), ("by", by)));

        public async Task ReversePurchaseAsync(string farmId, int id, string? reason, string by) =>
            await ScalarAsync("SELECT sphotelsupplypurchase_reverse(@f::text, @i::int, @r::text, @by::text)",
                ("f", farmId), ("i", id), ("r", reason), ("by", by));

        public Task<List<Dictionary<string, object?>>> CostModesAsync(string farmId) =>
            RowsAsync("SELECT * FROM sphotelsupply_costmode_list(@f::text)", ("f", farmId));

        public async Task SetCostModeAsync(string farmId, string category, string costMode, string by) =>
            await ScalarAsync("SELECT sphotelsupply_costmode_set(@f::text, @c::text, @m::text, @by::text)",
                ("f", farmId), ("c", category), ("m", costMode), ("by", by));

        public async Task<object> DeferredAsync(string farmId, string? scope, int? itemId, int? supplierId, string? category,
                                                DateTime? from, DateTime? to, string? search)
        {
            var ps = new (string, object?)[] { ("f", farmId), ("sc", scope ?? "DEFERRED"), ("i", itemId), ("s", supplierId),
                ("c", Blank(category)), ("a", from?.Date), ("b", to?.Date), ("q", Blank(search)) };
            const string args = "(@f::text, @sc::text, @i::int, @s::int, @c::text, @a::date, @b::date, @q::text)";
            var summary = (await RowsAsync("SELECT * FROM sphotelsupply_deferred_summary" + args, ps)).FirstOrDefault();
            var purchases = await RowsAsync("SELECT * FROM sphotelsupply_deferred_getall" + args, ps);
            return new { summary, purchases };
        }

        public Task<List<Dictionary<string, object?>>> DeferredHistoryAsync(string farmId, int purchaseId) =>
            RowsAsync("SELECT * FROM sphotelsupply_deferred_history(@f::text, @p::int)", ("f", farmId), ("p", purchaseId));

        // ── Internal Use ─────────────────────────────────────────────────────
        public Task<List<Dictionary<string, object?>>> InternalUseListAsync(string farmId) =>
            RowsAsync("SELECT * FROM sphotelinternalusage_getall(@f::text)", ("f", farmId));

        public async Task<Dictionary<string, object?>?> InternalUseGetAsync(string farmId, int id) =>
            (await RowsAsync("SELECT * FROM sphotelinternalusage_getbyid(@i::int, @f::text)", ("i", id), ("f", farmId))).FirstOrDefault();

        public Task<List<Dictionary<string, object?>>> InternalUseItemsAsync(string farmId) =>
            RowsAsync("SELECT * FROM sphotelinternalusage_items(@f::text)", ("f", farmId));

        private static string ItemsJson(HotelInternalUseInput i) => JsonSerializer.Serialize(i.Items);

        public async Task<int> InternalUseCreateAsync(string farmId, HotelInternalUseInput i, string by) =>
            Convert.ToInt32(await ScalarAsync(
                "SELECT sphotelinternalusage_insert(@f::text, @d::date, @c::text, @r::text, @rn::text, @sc::int, @n::text, @j::text, @by::text)",
                ("f", farmId), ("d", i.UsageDate?.Date), ("c", i.Category), ("r", Blank(i.Reason)), ("rn", Blank(i.RecipientName)),
                ("sc", i.StaffCount), ("n", Blank(i.Notes)), ("j", ItemsJson(i)), ("by", by)));

        public async Task InternalUseUpdateAsync(string farmId, int id, HotelInternalUseInput i, string by) =>
            await ScalarAsync(
                "SELECT sphotelinternalusage_update(@id::int, @f::text, @d::date, @c::text, @r::text, @rn::text, @sc::int, @n::text, @j::text, @by::text)",
                ("id", id), ("f", farmId), ("d", i.UsageDate?.Date), ("c", i.Category), ("r", Blank(i.Reason)),
                ("rn", Blank(i.RecipientName)), ("sc", i.StaffCount), ("n", Blank(i.Notes)), ("j", ItemsJson(i)), ("by", by));

        public async Task InternalUseDeleteAsync(string farmId, int id, string by) =>
            await ScalarAsync("SELECT sphotelinternalusage_delete(@id::int, @f::text, @by::text)", ("id", id), ("f", farmId), ("by", by));

        public async Task InternalUsePostAsync(string farmId, int id, string by) =>
            await ScalarAsync("SELECT sphotelinternalusage_post(@id::int, @f::text, @by::text)", ("id", id), ("f", farmId), ("by", by));

        public async Task InternalUseReverseAsync(string farmId, int id, string? reason, string by) =>
            await ScalarAsync("SELECT sphotelinternalusage_reverse(@id::int, @f::text, @r::text, @by::text)",
                ("id", id), ("f", farmId), ("r", reason), ("by", by));
    }
}
