// "Has every flock that should report production today done so?" -- the first
// IActivityCheck (migration 332).
//
// All of the rules -- which flocks are eligible, what counts as recorded, how
// many days a flock is behind, and the severity -- live in
// sppoultryactivity_productioncompleteness and are documented in the migration
// header. This class sends parameters and maps rows. Keeping the rules in SQL
// is what lets the migration's self-test cover them, and means the count and
// the list come from the same statement.

using System.Data;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class PoultryProductionCompletenessCheck : IActivityCheck
    {
        public const string CheckKey = "poultry.production.daily";

        /// <summary>How far back "earlier days still missing" looks.</summary>
        public const int BacklogWindowDays = 30;

        private readonly string _cs;
        public PoultryProductionCompletenessCheck(string cs) => _cs = cs;

        public string Key => CheckKey;
        public string Module => "poultry";
        // The same key the production-record pages are mapped to: anyone who
        // may see production records may see which ones are missing.
        public const string Permission = "poultry.production-records.view";
        public string RequiredPermission => Permission;

        public async Task<ActivityCheckResult> RunAsync(ActivityCheckContext ctx)
        {
            var result = new ActivityCheckResult { Title = "Daily production" };

            using var c = new NpgsqlConnection(_cs);
            await c.OpenAsync();

            // Two reads, one snapshot. REPEATABLE READ means a record saved
            // between them cannot make the headline say 3 missing while the list
            // shows 2, and now() -- which decides "today" and the severity -- is
            // the transaction start time for both.
            await using var tx = await c.BeginTransactionAsync(IsolationLevel.RepeatableRead);

            using (var cmd = new NpgsqlCommand(
                       "SELECT * FROM sppoultryactivity_productioncompletenesssummary("
                       + "p_farmid => @FarmId::text, p_businessdate => @BusinessDate::date)", c, tx))
            {
                AddParams(cmd, ctx);
                using var r = await cmd.ExecuteReaderAsync();
                if (await r.ReadAsync())
                {
                    result.ExpectedCount = r.GetInt32(r.GetOrdinal("expectedcount"));
                    result.CompletedCount = r.GetInt32(r.GetOrdinal("completedcount"));
                    result.OutstandingCount = r.GetInt32(r.GetOrdinal("missingcount"));
                    result.Counters["awaitingPosting"] = r.GetInt32(r.GetOrdinal("awaitingpostingcount"));
                    result.Counters["duplicateFlocks"] = r.GetInt32(r.GetOrdinal("duplicateflockcount"));
                    result.Severity = NullableString(r, "severity");

                    var today = r.GetDateTime(r.GetOrdinal("companytoday")).Date;
                    var date = r.GetDateTime(r.GetOrdinal("businessdate")).Date;
                    var lastPick = r.GetString(r.GetOrdinal("lastpicktime"));
                    result.SeverityReason = result.Severity switch
                    {
                        ActivitySeverity.Critical when date < today =>
                            "This business day is over and production was not recorded.",
                        ActivitySeverity.Critical =>
                            "Some flocks have missed more than one day.",
                        ActivitySeverity.Warning =>
                            $"The farm's last egg pick ({lastPick}) has passed.",
                        ActivitySeverity.Information =>
                            $"Still within the picking day (last pick {lastPick}).",
                        _ => null,
                    };
                }
            }

            if (result.OutstandingCount > 0)
            {
                using var cmd = new NpgsqlCommand(
                    "SELECT * FROM sppoultryactivity_productioncompleteness("
                    + "p_farmid => @FarmId::text, p_businessdate => @BusinessDate::date) "
                    + "WHERE NOT hasproduction", c, tx);
                AddParams(cmd, ctx);
                using var r = await cmd.ExecuteReaderAsync();
                while (await r.ReadAsync())
                {
                    var pendingId = NullableInt(r, "pendingbatchrecordid");
                    result.Items.Add(new ActivityCheckItem
                    {
                        SubjectType = "flock",
                        SubjectId = r.GetInt32(r.GetOrdinal("flockid")),
                        Label = r.GetString(r.GetOrdinal("flockname")),
                        GroupLabel = NullableString(r, "batchname"),
                        LocationLabel = NullableString(r, "housename"),
                        State = pendingId.HasValue ? ActivityItemState.AwaitingPosting : ActivityItemState.Missing,
                        Severity = NullableString(r, "severity"),
                        LastCompletedDate = NullableDate(r, "lastproductiondate"),
                        DaysOutstanding = r.GetInt32(r.GetOrdinal("daysmissing")),
                        RelatedRecordType = pendingId.HasValue ? "productionBatchRecord" : null,
                        RelatedRecordId = pendingId,
                        RelatedRecordStatus = NullableString(r, "pendingbatchstatus"),
                    });
                }
            }

            // ---- Earlier days still missing (the backlog) ------------------------
            // The headline is ONE day. Without this, filling today's gap made the
            // card say "all recorded" while last week was still empty. Counted
            // with 334's farm-wide list -- the same rules as every other view.
            // Last in the transaction, so if 334 is not applied yet the failure
            // aborts nothing already read; the card simply shows no backlog.
            var backlogKnown = false;
            try
            {
                using var cmd = new NpgsqlCommand(
                    "SELECT count(*)::int AS flockdays, count(DISTINCT missingdate)::int AS dates, "
                    + "min(missingdate) AS oldest "
                    + "FROM sppoultryactivity_missingproductionbydate(p_farmid => @FarmId::text, "
                    + "p_businessdate => @BusinessDate::date, p_days => @Days::int) "
                    + "WHERE missingdate < businessdate", c, tx);
                AddParams(cmd, ctx);
                cmd.Parameters.AddWithValue("@Days", BacklogWindowDays);
                using var r = await cmd.ExecuteReaderAsync();
                if (await r.ReadAsync())
                {
                    result.Counters["backlogFlockDays"] = r.GetInt32(r.GetOrdinal("flockdays"));
                    result.Counters["backlogDates"] = r.GetInt32(r.GetOrdinal("dates"));
                    result.Counters["backlogWindowDays"] = BacklogWindowDays;
                    backlogKnown = true;
                }
            }
            catch (PostgresException ex) when (ex.SqlState == "42883") // function does not exist (334 not applied)
            {
                backlogKnown = false;
            }

            if (backlogKnown) await tx.CommitAsync();

            var backlogDates = result.Counters.GetValueOrDefault("backlogDates");
            if (backlogDates > 0)
            {
                // A day that is over and unrecorded is Critical -- the same rule the
                // SQL applies to a past business date.
                // One plain sentence -- replaces the day's own reason rather than
                // being appended to it, which read as the same thing said twice.
                var records = result.Counters.GetValueOrDefault("backlogFlockDays");
                result.Severity = ActivitySeverity.Critical;
                result.SeverityReason =
                    $"{records} production record{(records == 1 ? " is" : "s are")} still missing across "
                    + $"{backlogDates} earlier day{(backlogDates == 1 ? "" : "s")}.";
            }

            result.Status = result.ExpectedCount == 0 ? ActivityCheckStatus.NotApplicable
                          : result.OutstandingCount == 0 && backlogDates == 0 ? ActivityCheckStatus.Complete
                          : ActivityCheckStatus.Incomplete;
            return result;
        }

        private static void AddParams(NpgsqlCommand cmd, ActivityCheckContext ctx)
        {
            cmd.Parameters.AddWithValue("@FarmId", ctx.FarmId);
            cmd.Parameters.AddWithValue("@BusinessDate",
                ctx.BusinessDate.HasValue ? ctx.BusinessDate.Value.Date : DBNull.Value);
        }

        private static string? NullableString(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? null : r.GetString(i);
        }

        private static int? NullableInt(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? null : r.GetInt32(i);
        }

        private static DateTime? NullableDate(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? null : r.GetDateTime(i);
        }
    }

    /// <summary>
    /// The dropdown under each row on Farm Completeness: every missing day for
    /// one flock, not just the current run. Eligibility and expected-from come
    /// from the same SQL as the check (see sppoultryactivity_flockmissingdates).
    /// </summary>
    public interface IPoultryProductionGapService
    {
        /// <summary>Throws PostgresException P0001 for a future business date.</summary>
        Task<FlockMissingProductionDates> GetMissingDatesAsync(string farmId, int flockId, DateTime? businessDate, int days);

        /// <summary>Farm-wide (migration 334). Throws PostgresException P0001 for a future business date.</summary>
        Task<MissingProductionByDate> GetMissingByDateAsync(string farmId, DateTime? businessDate, int days);
    }

    public class PoultryProductionGapService : IPoultryProductionGapService
    {
        private readonly string _cs;
        public PoultryProductionGapService(string cs) => _cs = cs;

        public async Task<FlockMissingProductionDates> GetMissingDatesAsync(string farmId, int flockId, DateTime? businessDate, int days)
        {
            var window = Math.Clamp(days, 1, 366);
            var result = new FlockMissingProductionDates { FlockId = flockId, WindowDays = window };

            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryactivity_flockmissingdates(p_farmid => @FarmId::text, p_flockid => @FlockId::int, "
                + "p_businessdate => @Date::date, p_days => @Days::int)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@FlockId", flockId);
            cmd.Parameters.AddWithValue("@Date", businessDate.HasValue ? businessDate.Value.Date : DBNull.Value);
            cmd.Parameters.AddWithValue("@Days", window);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                result.BusinessDate = r.GetDateTime(r.GetOrdinal("businessdate"));
                var pi = r.GetOrdinal("pendingbatchrecordid");
                var ps = r.GetOrdinal("pendingbatchstatus");
                result.Dates.Add(new MissingProductionDate
                {
                    Date = r.GetDateTime(r.GetOrdinal("missingdate")),
                    PendingBatchRecordId = r.IsDBNull(pi) ? null : r.GetInt32(pi),
                    PendingBatchStatus = r.IsDBNull(ps) ? null : r.GetString(ps),
                });
            }
            return result;
        }

        public async Task<MissingProductionByDate> GetMissingByDateAsync(string farmId, DateTime? businessDate, int days)
        {
            var window = Math.Clamp(days, 1, 366);
            var result = new MissingProductionByDate { WindowDays = window };

            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryactivity_missingproductionbydate(p_farmid => @FarmId::text, "
                + "p_businessdate => @Date::date, p_days => @Days::int)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Date", businessDate.HasValue ? businessDate.Value.Date : DBNull.Value);
            cmd.Parameters.AddWithValue("@Days", window);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                result.BusinessDate = r.GetDateTime(r.GetOrdinal("businessdate"));
                string? S(string col) { var i = r.GetOrdinal(col); return r.IsDBNull(i) ? null : r.GetString(i); }
                var pi = r.GetOrdinal("pendingbatchrecordid");
                result.Entries.Add(new MissingProductionEntry
                {
                    Date = r.GetDateTime(r.GetOrdinal("missingdate")),
                    FlockId = r.GetInt32(r.GetOrdinal("flockid")),
                    FlockName = S("flockname") ?? string.Empty,
                    BatchName = S("batchname"),
                    HouseName = S("housename"),
                    PendingBatchRecordId = r.IsDBNull(pi) ? null : r.GetInt32(pi),
                    PendingBatchStatus = S("pendingbatchstatus"),
                });
            }
            return result;
        }
    }
}
