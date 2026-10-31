// Feed Usage from stock (migration 389). Orchestration only: feed leaves stock
// inside the database, as feed lines on each flock's production record for the
// day (spproductionrecord_update), the same path as the production form and
// Distribute Feed. This file sends parameters and maps rows.

using System.Text.Json;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IPoultryFeedUsageEntryService
    {
        Task<IReadOnlyList<FeedUsageCandidate>> GetCandidatesAsync(string farmId, DateTime businessDate);
        /// <summary>Throws PostgresException P0003 (not enough stock), P0004 (flock cannot be fed), P0001 (other refusal).</summary>
        Task<int> PostAsync(FeedUsagePostRequest req, string postedBy);
        /// <summary>Throws PostgresException P0005 when a record was edited after posting, P0001 otherwise.</summary>
        Task ReverseAsync(int id, string farmId, string reason, string reversedBy);
        Task<IReadOnlyList<FeedUsageEntry>> GetAllAsync(string farmId, DateTime? from, DateTime? to);
        Task<IReadOnlyList<FeedUsageEntryLine>> GetLinesAsync(int id, string farmId);
        Task<IReadOnlyList<FeedUsageLogRow>> GetLogAsync(string farmId, DateTime? from, DateTime? to);
    }

    public class PoultryFeedUsageEntryService : IPoultryFeedUsageEntryService
    {
        private readonly string _cs;
        public PoultryFeedUsageEntryService(string cs) => _cs = cs;

        public async Task<IReadOnlyList<FeedUsageCandidate>> GetCandidatesAsync(string farmId, DateTime businessDate)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryfeedusage_candidates(p_farmid => @FarmId::text, p_businessdate => @Date::date)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Date", businessDate.Date);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<FeedUsageCandidate>();
            while (await r.ReadAsync())
            {
                list.Add(new FeedUsageCandidate
                {
                    FlockId = r.GetInt32(r.GetOrdinal("flockid")),
                    FlockName = Str(r, "flockname") ?? string.Empty,
                    BatchId = Int(r, "batchid"),
                    BatchName = Str(r, "batchname"),
                    HouseName = Str(r, "housename"),
                    RecordStatus = Str(r, "recordstatus") ?? "None",
                    ProductionRecordId = Int(r, "productionrecordid"),
                    Birds = Int(r, "birds"),
                    StockFeedKg = Dec(r, "stockfeedkg") ?? 0,
                    FeedLines = Str(r, "feedlines"),
                });
            }
            return list;
        }

        public async Task<int> PostAsync(FeedUsagePostRequest req, string postedBy)
        {
            var lines = JsonSerializer.Serialize(req.Lines.Select(l => new
            {
                flockId = l.FlockId,
                itemId = l.ItemId,
                qty = l.Qty,
                birds = l.Birds,
            }));

            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sppoultryfeedusage_post(p_farmid => @FarmId::text, p_businessdate => @Date::date, "
                + "p_scope => @Scope::text, p_batchid => @BatchId::int, p_splitbasis => @Split::text, "
                + "p_notes => @Notes::text, p_linesjson => @Lines::text, p_postedby => @By::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", req.FarmId);
            cmd.Parameters.AddWithValue("@Date", req.BusinessDate.Date);
            cmd.Parameters.AddWithValue("@Scope", string.IsNullOrWhiteSpace(req.Scope) ? "Flock" : req.Scope);
            cmd.Parameters.AddWithValue("@BatchId", req.BatchId.HasValue ? req.BatchId.Value : DBNull.Value);
            cmd.Parameters.AddWithValue("@Split", (object?)req.SplitBasis ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)req.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Lines", lines);
            cmd.Parameters.AddWithValue("@By", postedBy);
            await c.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task ReverseAsync(int id, string farmId, string reason, string reversedBy)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sppoultryfeedusage_reverse(p_id => @Id::int, p_farmid => @FarmId::text, "
                + "p_reason => @Reason::text, p_reversedby => @By::text)", c);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Reason", reason);
            cmd.Parameters.AddWithValue("@By", reversedBy);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<IReadOnlyList<FeedUsageEntry>> GetAllAsync(string farmId, DateTime? from, DateTime? to)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryfeedusage_getall(p_farmid => @FarmId::text, p_fromdate => @From::date, p_todate => @To::date)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@From", from.HasValue ? from.Value.Date : DBNull.Value);
            cmd.Parameters.AddWithValue("@To", to.HasValue ? to.Value.Date : DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<FeedUsageEntry>();
            while (await r.ReadAsync())
            {
                list.Add(new FeedUsageEntry
                {
                    PoultryFeedUsageEntryId = r.GetInt32(r.GetOrdinal("poultryfeedusageentryid")),
                    BusinessDate = r.GetDateTime(r.GetOrdinal("businessdate")),
                    Scope = Str(r, "scope") ?? "Flock",
                    BatchId = Int(r, "batchid"),
                    BatchName = Str(r, "batchname"),
                    SplitBasis = Str(r, "splitbasis"),
                    TotalKg = Dec(r, "totalkg") ?? 0,
                    TotalCost = Dec(r, "totalcost"),
                    FlockCount = Int(r, "flockcount") ?? 0,
                    FeedOnlyRecords = Int(r, "feedonlyrecords") ?? 0,
                    Status = Str(r, "status") ?? "Posted",
                    Notes = Str(r, "notes"),
                    PostedBy = Str(r, "postedby"),
                    PostedAtUtc = Utc(r, "postedatutc"),
                    ReversedBy = Str(r, "reversedby"),
                    ReversedAtUtc = Utc(r, "reversedatutc"),
                    ReversalReason = Str(r, "reversalreason"),
                });
            }
            return list;
        }

        public async Task<IReadOnlyList<FeedUsageEntryLine>> GetLinesAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryfeedusage_lines(p_id => @Id::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<FeedUsageEntryLine>();
            while (await r.ReadAsync())
            {
                list.Add(new FeedUsageEntryLine
                {
                    PoultryFeedUsageLineId = r.GetInt32(r.GetOrdinal("poultryfeedusagelineid")),
                    FlockId = r.GetInt32(r.GetOrdinal("flockid")),
                    FlockName = Str(r, "flockname"),
                    ProductionRecordId = r.GetInt32(r.GetOrdinal("productionrecordid")),
                    CreatedRecord = r.GetBoolean(r.GetOrdinal("createdrecord")),
                    ItemId = r.GetInt32(r.GetOrdinal("poultryrawmaterialitemid")),
                    ItemName = Str(r, "itemname"),
                    QuantityKg = Dec(r, "quantitykg") ?? 0,
                    UnitCost = Dec(r, "unitcost"),
                    TotalCost = Dec(r, "totalcost"),
                    Birds = Int(r, "birds"),
                    ReversalNote = Str(r, "reversalnote"),
                });
            }
            return list;
        }

        public async Task<IReadOnlyList<FeedUsageLogRow>> GetLogAsync(string farmId, DateTime? from, DateTime? to)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryfeedusage_log(p_farmid => @FarmId::text, p_fromdate => @From::date, p_todate => @To::date)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@From", from.HasValue ? from.Value.Date : DBNull.Value);
            cmd.Parameters.AddWithValue("@To", to.HasValue ? to.Value.Date : DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<FeedUsageLogRow>();
            while (await r.ReadAsync())
            {
                list.Add(new FeedUsageLogRow
                {
                    UsageDate = r.GetDateTime(r.GetOrdinal("usagedate")),
                    FlockId = Int(r, "flockid") ?? 0,
                    FlockName = Str(r, "flockname"),
                    ProductionRecordId = Int(r, "productionrecordid"),
                    RecordSource = Str(r, "recordsource"),
                    FeedOnly = !r.IsDBNull(r.GetOrdinal("feedonly")) && r.GetBoolean(r.GetOrdinal("feedonly")),
                    ItemId = Int(r, "itemid"),
                    ItemName = Str(r, "itemname"),
                    QuantityKg = Dec(r, "quantitykg") ?? 0,
                    UnitCost = Dec(r, "unitcost"),
                    TotalCost = Dec(r, "totalcost"),
                    EntryId = Int(r, "entryid"),
                    DistributionId = Int(r, "distributionid"),
                    LegacyFeedUsageId = Int(r, "legacyfeedusageid"),
                });
            }
            return list;
        }

        private static string? Str(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? null : r.GetValue(i).ToString();
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
