// "Are there eggs from earlier days still waiting to be sorted?" -- an
// IActivityCheck for the Egg Sorting Workspace (migration 344).
//
// The rules live in sppoultryactivity_unsortedeggs: only when sorting is on and
// the farm's Daily Closing policy is not Off; only production from BEFORE the
// business date (sorting next morning is normal, so today never counts); and
// capped by what Unsorted actually holds, newest production first, so eggs sold
// unsorted are not reported as waiting. This class sends parameters and maps rows.

using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class PoultryUnsortedEggsCheck : IActivityCheck
    {
        public const string CheckKey = "poultry.eggs.unsorted";
        public const string Permission = "poultry.egg-sorting.view";
        public const int WindowDays = 30;

        private readonly string _cs;
        public PoultryUnsortedEggsCheck(string cs) => _cs = cs;

        public string Key => CheckKey;
        public string Module => "poultry";
        public string RequiredPermission => Permission;

        public async Task<ActivityCheckResult> RunAsync(ActivityCheckContext ctx)
        {
            var result = new ActivityCheckResult { Title = "Egg sorting", Status = ActivityCheckStatus.NotApplicable };

            using var c = new NpgsqlConnection(_cs);
            await c.OpenAsync();
            try
            {
                using var cmd = new NpgsqlCommand(
                    "SELECT * FROM sppoultryactivity_unsortedeggs(p_farmid => @FarmId::text, "
                    + "p_businessdate => @BusinessDate::date, p_windowdays => @Days::int)", c);
                cmd.Parameters.AddWithValue("@FarmId", ctx.FarmId);
                cmd.Parameters.AddWithValue("@BusinessDate", ctx.BusinessDate.HasValue ? ctx.BusinessDate.Value.Date : DBNull.Value);
                cmd.Parameters.AddWithValue("@Days", WindowDays);
                using var r = await cmd.ExecuteReaderAsync();
                var eggs = 0;
                while (await r.ReadAsync())
                {
                    var left = r.GetInt32(r.GetOrdinal("leftunsorted"));
                    eggs += left;
                    var severity = r.IsDBNull(r.GetOrdinal("severity")) ? null : r.GetString(r.GetOrdinal("severity"));
                    if (ActivitySeverity.Rank(severity) > ActivitySeverity.Rank(result.Severity)) result.Severity = severity;
                    var date = r.GetDateTime(r.GetOrdinal("productiondate"));
                    result.Items.Add(new ActivityCheckItem
                    {
                        SubjectType = "productionRecord",
                        SubjectId = r.GetInt32(r.GetOrdinal("productionrecordid")),
                        Label = $"{left:N0} eggs from {date:d MMM}",
                        GroupLabel = r.IsDBNull(r.GetOrdinal("flockname")) ? null : r.GetString(r.GetOrdinal("flockname")),
                        LocationLabel = r.IsDBNull(r.GetOrdinal("housename")) ? null : r.GetString(r.GetOrdinal("housename")),
                        State = ActivityItemState.Missing,
                        Severity = severity,
                        LastCompletedDate = date,
                        DaysOutstanding = r.GetInt32(r.GetOrdinal("daysoutstanding")),
                        RelatedRecordType = "productionRecord",
                        RelatedRecordId = r.GetInt32(r.GetOrdinal("productionrecordid")),
                    });
                }
                result.OutstandingCount = result.Items.Count;
                result.Counters["eggs"] = eggs;
                result.Counters["windowDays"] = WindowDays;
                result.Status = result.Items.Count == 0 ? ActivityCheckStatus.Complete : ActivityCheckStatus.Incomplete;
                if (result.Items.Count > 0)
                {
                    var oldest = result.Items.Max(i => i.DaysOutstanding);
                    result.SeverityReason = $"{eggs:N0} egg{(eggs == 1 ? "" : "s")} from earlier days are still unsorted"
                        + (oldest >= 3 ? $"; the oldest are {oldest} days old." : ".");
                }
            }
            catch (PostgresException ex) when (ex.SqlState == "42883") // 344 not applied
            {
                result.Status = ActivityCheckStatus.NotApplicable;
            }
            return result;
        }
    }
}
