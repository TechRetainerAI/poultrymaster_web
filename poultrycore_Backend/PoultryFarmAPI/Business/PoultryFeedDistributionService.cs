// Distribute Feed (migration 335). Orchestration only: every stock movement,
// lot draw, cost and consumption expense happens inside the database through
// spproductionrecord_update -- the same path as editing a flock's production
// record by hand. This file sends parameters and maps rows.

using System.Text.Json;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IPoultryFeedDistributionService
    {
        Task<FeedDistributionAvailability?> GetAvailabilityAsync(string farmId, int itemId);
        Task<IReadOnlyList<FeedDistributionCandidate>> GetCandidatesAsync(string farmId, DateTime businessDate, int itemId, int avgDays);
        /// <summary>Throws PostgresException P0003 (not enough stock), P0004 (flock cannot receive feed), P0001 (other refusal).</summary>
        Task<int> PostAsync(FeedDistributionPostRequest req, string postedBy);
        /// <summary>Throws PostgresException P0005 when a record was edited after posting, P0001 otherwise.</summary>
        Task ReverseAsync(int id, string farmId, string reason, string reversedBy);
        Task<IReadOnlyList<FeedDistribution>> GetAllAsync(string farmId, DateTime? from, DateTime? to);
        Task<IReadOnlyList<FeedDistributionLine>> GetLinesAsync(int id, string farmId);
        Task SetRateAsync(string farmId, int itemId, decimal? grams, string? rateUnit, string? updatedBy);
    }

    public class PoultryFeedDistributionService : IPoultryFeedDistributionService
    {
        private readonly string _cs;
        public PoultryFeedDistributionService(string cs) => _cs = cs;

        public async Task<FeedDistributionAvailability?> GetAvailabilityAsync(string farmId, int itemId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryfeeddistribution_availability(p_farmid => @FarmId::text, p_itemid => @ItemId::int)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ItemId", itemId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            if (!await r.ReadAsync()) return null;
            return new FeedDistributionAvailability
            {
                PoultryRawMaterialItemId = r.GetInt32(r.GetOrdinal("poultryrawmaterialitemid")),
                ItemName = Str(r, "itemname") ?? string.Empty,
                Category = Str(r, "category"),
                UnitOfMeasure = Str(r, "unitofmeasure"),
                UsageMethod = Str(r, "usagemethod") ?? "FIFO",
                AvailableKg = r.GetDecimal(r.GetOrdinal("availablekg")),
                CurrentQuantity = Dec(r, "currentquantity"),
                LotCount = r.GetInt32(r.GetOrdinal("lotcount")),
                CostRecognitionMethod = Str(r, "costrecognitionmethod"),
                GramsPerBirdPerDay = Dec(r, "gramsperbirdperday"),
                RateUnit = OptStr(r, "rateunit"),
            };
        }

        public async Task<IReadOnlyList<FeedDistributionCandidate>> GetCandidatesAsync(string farmId, DateTime businessDate, int itemId, int avgDays)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryfeeddistribution_candidates(p_farmid => @FarmId::text, "
                + "p_businessdate => @Date::date, p_itemid => @ItemId::int, p_avgdays => @Days::int)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Date", businessDate.Date);
            cmd.Parameters.AddWithValue("@ItemId", itemId);
            cmd.Parameters.AddWithValue("@Days", avgDays);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<FeedDistributionCandidate>();
            while (await r.ReadAsync())
            {
                list.Add(new FeedDistributionCandidate
                {
                    FlockId = r.GetInt32(r.GetOrdinal("flockid")),
                    FlockName = Str(r, "flockname") ?? string.Empty,
                    BatchName = Str(r, "batchname"),
                    HouseName = Str(r, "housename"),
                    RecordCount = r.GetInt32(r.GetOrdinal("recordcount")),
                    ProductionRecordId = Int(r, "productionrecordid"),
                    Birds = Int(r, "birds"),
                    ManualFeedKg = Dec(r, "manualfeedkg"),
                    StockFeedKg = Dec(r, "stockfeedkg") ?? 0,
                    ThisItemKg = Dec(r, "thisitemkg") ?? 0,
                    RecentAvgKg = Dec(r, "recentavgkg"),
                    RecentAvgDays = Int(r, "recentavgdays"),
                });
            }
            return list;
        }

        public async Task<int> PostAsync(FeedDistributionPostRequest req, string postedBy)
        {
            var lines = JsonSerializer.Serialize(req.Lines.Select(l => new
            {
                flockId = l.FlockId,
                actualKg = l.ActualKg,
                suggestedKg = l.SuggestedKg,
                birds = l.Birds,
                notes = l.Notes,
            }));

            using var c = new NpgsqlConnection(_cs);
            await c.OpenAsync();
            // One transaction: saving the rate and posting succeed or fail together.
            await using var tx = await c.BeginTransactionAsync();

            if (req.SaveRate && req.GramsPerBirdPerDay is > 0)
            {
                using var rate = new NpgsqlCommand(
                    "SELECT sppoultryfeedrate_set(p_farmid => @FarmId::text, p_itemid => @ItemId::int, "
                    + "p_grams => @Grams::numeric, p_updatedby => @By::text, p_rateunit => @Unit::text)", c, tx);
                rate.Parameters.AddWithValue("@Unit", (object?)req.RateUnit ?? "g_bird");
                rate.Parameters.AddWithValue("@FarmId", req.FarmId);
                rate.Parameters.AddWithValue("@ItemId", req.ItemId);
                rate.Parameters.AddWithValue("@Grams", req.GramsPerBirdPerDay.Value);
                rate.Parameters.AddWithValue("@By", postedBy);
                await rate.ExecuteNonQueryAsync();
            }

            using var cmd = new NpgsqlCommand(
                "SELECT sppoultryfeeddistribution_post(p_farmid => @FarmId::text, p_businessdate => @Date::date, "
                + "p_itemid => @ItemId::int, p_basis => @Basis::text, p_grams => @Grams::numeric, "
                + "p_notes => @Notes::text, p_linesjson => @Lines::text, p_postedby => @By::text)", c, tx);
            cmd.Parameters.AddWithValue("@FarmId", req.FarmId);
            cmd.Parameters.AddWithValue("@Date", req.BusinessDate.Date);
            cmd.Parameters.AddWithValue("@ItemId", req.ItemId);
            cmd.Parameters.AddWithValue("@Basis", (object?)req.Basis ?? "Manual");
            cmd.Parameters.AddWithValue("@Grams", req.GramsPerBirdPerDay.HasValue ? req.GramsPerBirdPerDay.Value : DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)req.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Lines", lines);
            cmd.Parameters.AddWithValue("@By", postedBy);
            var id = Convert.ToInt32(await cmd.ExecuteScalarAsync());

            // 336: which unit the rate was typed in, so history reads it back.
            if (req.GramsPerBirdPerDay.HasValue && !string.IsNullOrWhiteSpace(req.RateUnit))
            {
                using var unit = new NpgsqlCommand(
                    "SELECT sppoultryfeeddistribution_setrateunit(p_id => @Id::int, p_farmid => @FarmId::text, p_rateunit => @Unit::text)", c, tx);
                unit.Parameters.AddWithValue("@Id", id);
                unit.Parameters.AddWithValue("@FarmId", req.FarmId);
                unit.Parameters.AddWithValue("@Unit", req.RateUnit);
                await unit.ExecuteNonQueryAsync();
            }

            await tx.CommitAsync();
            return id;
        }

        public async Task ReverseAsync(int id, string farmId, string reason, string reversedBy)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sppoultryfeeddistribution_reverse(p_id => @Id::int, p_farmid => @FarmId::text, "
                + "p_reason => @Reason::text, p_reversedby => @By::text)", c);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Reason", reason);
            cmd.Parameters.AddWithValue("@By", reversedBy);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<IReadOnlyList<FeedDistribution>> GetAllAsync(string farmId, DateTime? from, DateTime? to)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryfeeddistribution_getall(p_farmid => @FarmId::text, p_fromdate => @From::date, p_todate => @To::date)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@From", from.HasValue ? from.Value.Date : DBNull.Value);
            cmd.Parameters.AddWithValue("@To", to.HasValue ? to.Value.Date : DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<FeedDistribution>();
            while (await r.ReadAsync())
            {
                list.Add(new FeedDistribution
                {
                    PoultryFeedDistributionId = r.GetInt32(r.GetOrdinal("poultryfeeddistributionid")),
                    BusinessDate = r.GetDateTime(r.GetOrdinal("businessdate")),
                    PoultryRawMaterialItemId = r.GetInt32(r.GetOrdinal("poultryrawmaterialitemid")),
                    ItemName = Str(r, "itemname"),
                    Basis = Str(r, "basis") ?? "Manual",
                    GramsPerBirdPerDay = Dec(r, "gramsperbirdperday"),
                    RateUnit = OptStr(r, "rateunit"),
                    TotalSuggestedKg = Dec(r, "totalsuggestedkg"),
                    TotalActualKg = r.GetDecimal(r.GetOrdinal("totalactualkg")),
                    TotalCost = Dec(r, "totalcost"),
                    FlockCount = r.GetInt32(r.GetOrdinal("flockcount")),
                    Status = Str(r, "status") ?? "Posted",
                    Notes = Str(r, "notes"),
                    PostedBy = Str(r, "postedby"),
                    PostedAtUtc = Utc(r, "postedatutc") ?? DateTime.UtcNow,
                    ReversedBy = Str(r, "reversedby"),
                    ReversedAtUtc = Utc(r, "reversedatutc"),
                    ReversalReason = Str(r, "reversalreason"),
                });
            }
            return list;
        }

        public async Task<IReadOnlyList<FeedDistributionLine>> GetLinesAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryfeeddistribution_lines(p_id => @Id::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<FeedDistributionLine>();
            while (await r.ReadAsync())
            {
                list.Add(new FeedDistributionLine
                {
                    PoultryFeedDistributionLineId = r.GetInt32(r.GetOrdinal("poultryfeeddistributionlineid")),
                    FlockId = r.GetInt32(r.GetOrdinal("flockid")),
                    FlockName = Str(r, "flockname"),
                    ProductionRecordId = r.GetInt32(r.GetOrdinal("productionrecordid")),
                    Birds = Int(r, "birds"),
                    SuggestedKg = Dec(r, "suggestedkg"),
                    ActualKg = r.GetDecimal(r.GetOrdinal("actualkg")),
                    UnitCost = Dec(r, "unitcost"),
                    TotalCost = Dec(r, "totalcost"),
                    Notes = Str(r, "notes"),
                    ReversalNote = Str(r, "reversalnote"),
                });
            }
            return list;
        }

        public async Task SetRateAsync(string farmId, int itemId, decimal? grams, string? rateUnit, string? updatedBy)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sppoultryfeedrate_set(p_farmid => @FarmId::text, p_itemid => @ItemId::int, "
                + "p_grams => @Grams::numeric, p_updatedby => @By::text, p_rateunit => @Unit::text)", c);
            cmd.Parameters.AddWithValue("@Unit", (object?)rateUnit ?? "g_bird");
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ItemId", itemId);
            cmd.Parameters.AddWithValue("@Grams", grams.HasValue ? grams.Value : DBNull.Value);
            cmd.Parameters.AddWithValue("@By", (object?)updatedBy ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static string? Str(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? null : r.GetValue(i).ToString();
        }

        /// <summary>A column added by a later migration: null when that migration is not applied yet.</summary>
        private static string? OptStr(NpgsqlDataReader r, string col)
        {
            for (var i = 0; i < r.FieldCount; i++)
                if (string.Equals(r.GetName(i), col, StringComparison.OrdinalIgnoreCase))
                    return r.IsDBNull(i) ? null : r.GetValue(i).ToString();
            return null;
        }

        private static int? Int(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? null : Convert.ToInt32(r.GetValue(i));
        }

        private static decimal? Dec(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? null : Convert.ToDecimal(r.GetValue(i));
        }

        private static DateTime? Utc(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            if (r.IsDBNull(i)) return null;
            var d = r.GetDateTime(i);
            return d.Kind == DateTimeKind.Utc ? d : DateTime.SpecifyKind(d.ToUniversalTime(), DateTimeKind.Utc);
        }
    }
}
