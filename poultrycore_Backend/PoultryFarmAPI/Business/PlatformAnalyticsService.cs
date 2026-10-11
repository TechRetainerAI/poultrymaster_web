// PROMPT 4: onboarding & activation analytics, feature adoption and retention
// cohorts over the Prompt 1 foundation. The classification logic (feature
// catalog, funnel staging, cohort retention windows) is pure and unit-tested;
// SQL only fetches compact aggregates (never a per-row event scan per request).

using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    // ------------------------------------------------------------------
    // Feature catalog: features derive from normalized ActivityTypes and are
    // only compared where applicable (spec section 9). No page views.
    // ------------------------------------------------------------------
    public sealed record FeatureDef(string Feature, string[] ActivityTypes, string[] Families);

    public static class FeatureCatalog
    {
        private static readonly string[] AllFamilies = { "Poultry", "Water", "Hotel", "Restaurant", "Generic" };

        public static readonly FeatureDef[] All =
        {
            new("Production", new[] { "ProductionRecorded" }, new[] { "Poultry", "Water" }),
            new("Batch Production", new[] { "BatchProductionPosted", "FeedProductionPosted" }, new[] { "Poultry", "Water" }),
            new("Farm Setup", new[] { "FarmSetupCompleted", "CompanySetupCompleted" }, AllFamilies),
            new("Feed Usage", new[] { "FeedUsageRecorded" }, new[] { "Poultry" }),
            new("Medication", new[] { "MedicationRecorded" }, new[] { "Poultry" }),
            new("Sales", new[] { "SaleRecorded", "SaleCreated", "OrderCreated", "BookingCreated" }, AllFamilies),
            new("Customer Balances", new[] { "CustomerPaymentReceived", "PaymentRecorded" }, AllFamilies),
            new("Supplier Balances", new[] { "SupplierPaymentRecorded" }, AllFamilies),
            new("Expenses", new[] { "ExpenseCreated" }, AllFamilies),
            new("Inventory", new[] { "InventoryReceived", "InventoryMovementRecorded", "StockTakeCompleted" }, AllFamilies),
            new("Payroll", new[] { "PayrollApproved", "StaffPaymentRecorded" }, AllFamilies),
            new("Daily Closing", new[] { "DailyClosingCompleted", "NightAuditCompleted" }, AllFamilies),
            new("Cash Reconciliation", new[] { "CashReconciled" }, new[] { "Poultry", "Water", "Restaurant", "Generic" }),
            new("Driver Returns", new[] { "DriverReturnCompleted" }, new[] { "Poultry", "Water" }),
            new("Front Desk", new[] { "CheckInCompleted", "CheckOutCompleted" }, new[] { "Hotel" }),
            new("Subscriptions", new[] { "SubscriptionCreated", "SubscriptionBillingGenerated" }, new[] { "Generic" }),
        };

        /// <summary>The feature an activity type belongs to for a family; null when
        /// the type maps to no feature or the feature is not applicable there.</summary>
        public static string? Resolve(string activityType, string? family)
        {
            foreach (var def in All)
                if (def.ActivityTypes.Contains(activityType))
                    return family != null && def.Families.Contains(family) ? def.Feature : null;
            return null;
        }

        public static bool Applicable(string feature, string family) =>
            All.FirstOrDefault(d => d.Feature == feature)?.Families.Contains(family) == true;
    }

    // ------------------------------------------------------------------
    // Retention windows (documented definition, spec section 11):
    // retained at Day N = at least one meaningful-activity business day within
    //   D1  = days [1, 7)     D7  = [7, 30)     D30 = [30, 60)
    //   D60 = [60, 90)        D90 = [90, 120)
    // A window that the cohort has not fully reached yet reports null percent.
    // ------------------------------------------------------------------
    public static class RetentionMath
    {
        public static readonly int[] WindowStart = { 1, 7, 30, 60, 90 };
        public static readonly int[] WindowEnd = { 7, 30, 60, 90, 120 };
        public static readonly string[] WindowLabels = { "D1", "D7", "D30", "D60", "D90" };

        public static bool RetainedInWindow(DateOnly anchor, IReadOnlyCollection<DateOnly> activityDays, int window)
        {
            var from = anchor.AddDays(WindowStart[window]);
            var to = anchor.AddDays(WindowEnd[window]);
            return activityDays.Any(d => d >= from && d < to);
        }

        public static bool WindowReached(DateOnly anchor, DateOnly today, int window) =>
            today >= anchor.AddDays(WindowStart[window]);

        public static string MonthKey(DateOnly d) => $"{d.Year:D4}-{d.Month:D2}";

        public static string WeekKey(DateOnly d)
        {
            var cal = System.Globalization.ISOWeek.GetWeekOfYear(d.ToDateTime(TimeOnly.MinValue));
            var year = System.Globalization.ISOWeek.GetYear(d.ToDateTime(TimeOnly.MinValue));
            return $"{year:D4}-W{cal:D2}";
        }
    }

    // ------------------------------------------------------------------
    // Funnel staging (pure; spec section 7)
    // ------------------------------------------------------------------
    public sealed record OrgFunnelInput(
        bool HasCompany, bool EssentialSetupComplete, bool HasMeaningfulActivity,
        int DistinctActiveDays, bool Paid);

    public static class FunnelMath
    {
        public static List<FunnelStageDto> Build(IReadOnlyList<OrgFunnelInput> orgs)
        {
            var counts = new (string Key, string Label, int Count)[]
            {
                ("registered", "Organization registered", orgs.Count),
                ("firstCompany", "Created first company", orgs.Count(o => o.HasCompany)),
                ("setup", "Completed essential setup", orgs.Count(o => o.HasCompany && o.EssentialSetupComplete)),
                ("firstActivity", "First meaningful activity", orgs.Count(o => o.HasCompany && o.EssentialSetupComplete && o.HasMeaningfulActivity)),
                ("threeDays", "Active on 3 separate days", orgs.Count(o => o.HasCompany && o.EssentialSetupComplete && o.HasMeaningfulActivity && o.DistinctActiveDays >= 3)),
                ("paid", "Converted to paid", orgs.Count(o => o.HasCompany && o.EssentialSetupComplete && o.HasMeaningfulActivity && o.DistinctActiveDays >= 3 && o.Paid)),
            };
            var top = Math.Max(1, counts[0].Count);
            var stages = new List<FunnelStageDto>();
            for (var i = 0; i < counts.Length; i++)
            {
                var prev = i == 0 ? (int?)null : counts[i - 1].Count;
                stages.Add(new FunnelStageDto
                {
                    Key = counts[i].Key,
                    Label = counts[i].Label,
                    Count = counts[i].Count,
                    PercentOfPrevious = prev is null ? null
                        : prev == 0 ? 0 : Math.Round(100.0 * counts[i].Count / prev.Value, 1),
                    PercentOfTop = Math.Round(100.0 * counts[i].Count / top, 1),
                });
            }
            return stages;
        }
    }

    // ------------------------------------------------------------------
    // Service
    // ------------------------------------------------------------------
    public interface IPlatformAnalyticsService
    {
        Task<List<CompanyActivitySummaryDto>> GetOnboardingAsync(string? family, string? template, string? country);
        Task<List<MilestoneDto>> GetMilestonesAsync(string companyId);
        Task<List<FunnelStageDto>> GetFunnelAsync(string? month, string? family, string? template, string? country);
        Task<List<FeatureAdoptionDto>> GetFeatureAdoptionAsync(int? days);
        Task<List<FeatureUsageDto>> GetFeatureUsageAsync(string? companyId);
        Task<List<RetentionCohortDto>> GetRetentionAsync(string scope, string cohortBy, string? family, string? template, string? country);
    }

    public class PlatformAnalyticsService : IPlatformAnalyticsService
    {
        private readonly string _cs;
        private readonly IPlatformActivityService _activity;

        public PlatformAnalyticsService(string connectionString, IPlatformActivityService activity)
        {
            _cs = connectionString;
            _activity = activity;
        }

        // ---------------- onboarding & activation ----------------
        public async Task<List<CompanyActivitySummaryDto>> GetOnboardingAsync(
            string? family, string? template, string? country)
        {
            var orgs = await _activity.GetOrganizationSummariesAsync();
            return orgs
                .Where(o => country == null || o.CountryCode == country)
                .SelectMany(o => o.Companies)
                .Where(c => family == null || c.CompanyFamily == family)
                .Where(c => template == null || c.BusinessTemplateCode == template)
                .OrderBy(c => c.SetupPercent)
                .ToList();
        }

        public async Task<List<MilestoneDto>> GetMilestonesAsync(string companyId)
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            var list = new List<MilestoneDto>();
            await using var cmd = new NpgsqlCommand(@"
                SELECT milestonecode, title, weight, required, sortorder, complete
                FROM platform_company_milestones
                WHERE companyid = @C
                ORDER BY sortorder", conn);
            cmd.Parameters.AddWithValue("@C", companyId);
            await using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Add(new MilestoneDto
                {
                    Code = r.GetString(0),
                    Title = r.GetString(1),
                    Weight = Convert.ToInt32(r.GetValue(2)),
                    Required = r.GetBoolean(3),
                    SortOrder = Convert.ToInt32(r.GetValue(4)),
                    Complete = r.GetBoolean(5),
                });
            return list;
        }

        // ---------------- activation funnel ----------------
        public async Task<List<FunnelStageDto>> GetFunnelAsync(
            string? month, string? family, string? template, string? country)
        {
            var orgs = await _activity.GetOrganizationSummariesAsync();
            var activeDays = await QueryOrgActiveDayCountsAsync();

            var filtered = orgs.Where(o =>
            {
                if (country != null && o.CountryCode != country) return false;
                if (family != null && !o.Companies.Any(c => c.CompanyFamily == family)) return false;
                if (template != null && !o.Companies.Any(c => c.BusinessTemplateCode == template)) return false;
                if (month != null)
                {
                    if (o.FirstCompanyCreatedAtUtc is not DateTime created) return false;
                    if ($"{created.Year:D4}-{created.Month:D2}" != month) return false;
                }
                return true;
            }).ToList();

            var inputs = filtered.Select(o => new OrgFunnelInput(
                o.CompanyCount > 0,
                o.Companies.Any(c => c.RequiredMilestonesTotal > 0 && c.RequiredMilestonesComplete == c.RequiredMilestonesTotal),
                o.FirstMeaningfulActivityAtUtc != null,
                activeDays.TryGetValue(o.OrganizationId, out var d) ? d : 0,
                o.SubscriptionStatus == "Active")).ToList();

            return FunnelMath.Build(inputs);
        }

        private async Task<Dictionary<string, int>> QueryOrgActiveDayCountsAsync()
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            var map = new Dictionary<string, int>();
            await using var cmd = new NpgsqlCommand(@"
                SELECT f.owneruserid, count(DISTINCT d.businessdate)
                FROM companyusagedaily d
                JOIN farms f ON f.farmid = d.companyid
                WHERE d.meaningfulactivitycount > 0
                GROUP BY f.owneruserid", conn);
            await using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
                map[r.GetString(0)] = Convert.ToInt32(r.GetValue(1));
            return map;
        }

        // ---------------- feature adoption & first use ----------------
        private sealed record TypeAgg(string CompanyId, string? CompanyName, string? Family, string ActivityType,
            long Count, DateTime First, DateTime Last, int ActiveDays);

        private async Task<List<TypeAgg>> QueryTypeAggregatesAsync(int? days, string? companyId)
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            var list = new List<TypeAgg>();
            await using var cmd = new NpgsqlCommand(@"
                SELECT e.companyid, max(f.name), max(e.companyfamily), e.activitytype,
                       count(*), min(e.occurredatutc), max(e.occurredatutc),
                       count(DISTINCT e.businessdate)
                FROM platformactivityevents e
                LEFT JOIN farms f ON f.farmid = e.companyid
                WHERE e.ismeaningful AND e.companyid IS NOT NULL
                  AND (@D::int IS NULL OR e.occurredatutc > now() - make_interval(days => @D))
                  AND (@C::text IS NULL OR e.companyid = @C)
                GROUP BY e.companyid, e.activitytype", conn);
            cmd.Parameters.AddWithValue("@D", (object?)days ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@C", (object?)companyId ?? DBNull.Value);
            await using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Add(new TypeAgg(
                    r.GetString(0),
                    r.IsDBNull(1) ? null : r.GetString(1),
                    r.IsDBNull(2) ? null : r.GetString(2),
                    r.GetString(3),
                    r.GetInt64(4), r.GetDateTime(5), r.GetDateTime(6),
                    Convert.ToInt32(r.GetValue(7))));
            return list;
        }

        public async Task<List<FeatureAdoptionDto>> GetFeatureAdoptionAsync(int? days)
        {
            var aggs = await QueryTypeAggregatesAsync(days ?? 90, null);

            // Denominator: companies per family (applicable population).
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            var totals = new Dictionary<string, int>();
            await using (var cmd = new NpgsqlCommand(@"
                SELECT type, count(*) FROM farms
                WHERE coalesce(isdeleted, false) = false AND type IS DISTINCT FROM 'System'
                GROUP BY type", conn))
            {
                await using var r = await cmd.ExecuteReaderAsync();
                while (await r.ReadAsync())
                    totals[r.GetString(0)] = Convert.ToInt32(r.GetValue(1));
            }

            var used = new Dictionary<(string Feature, string Family), HashSet<string>>();
            foreach (var a in aggs)
            {
                var feature = FeatureCatalog.Resolve(a.ActivityType, a.Family);
                if (feature is null || a.Family is null) continue;
                var key = (feature, a.Family);
                if (!used.TryGetValue(key, out var set)) used[key] = set = new HashSet<string>();
                set.Add(a.CompanyId);
            }

            var rows = new List<FeatureAdoptionDto>();
            foreach (var def in FeatureCatalog.All)
                foreach (var fam in def.Families)
                {
                    if (!totals.TryGetValue(fam, out var total) || total == 0) continue;
                    var count = used.TryGetValue((def.Feature, fam), out var set) ? set.Count : 0;
                    rows.Add(new FeatureAdoptionDto
                    {
                        Feature = def.Feature,
                        CompanyFamily = fam,
                        CompaniesUsed = count,
                        CompaniesTotal = total,
                        Percent = Math.Round(100.0 * count / total, 1),
                    });
                }
            return rows;
        }

        public async Task<List<FeatureUsageDto>> GetFeatureUsageAsync(string? companyId)
        {
            var aggs = await QueryTypeAggregatesAsync(null, companyId);
            return aggs
                .Select(a => (Agg: a, Feature: FeatureCatalog.Resolve(a.ActivityType, a.Family)))
                .Where(x => x.Feature != null)
                .GroupBy(x => (x.Feature!, x.Agg.CompanyId))
                .Select(g => new FeatureUsageDto
                {
                    Feature = g.Key.Item1,
                    CompanyId = g.Key.CompanyId,
                    CompanyName = g.First().Agg.CompanyName,
                    FirstUsedAtUtc = g.Min(x => x.Agg.First),
                    LastUsedAtUtc = g.Max(x => x.Agg.Last),
                    UsageCount = g.Sum(x => x.Agg.Count),
                    // Upper-bounded sum of per-type distinct days (overlap between
                    // types of one feature on the same day is rare and documented).
                    ActiveDaysUsingFeature = g.Sum(x => x.Agg.ActiveDays),
                })
                .OrderBy(x => x.CompanyName).ThenBy(x => x.Feature)
                .ToList();
        }

        // ---------------- retention cohorts ----------------
        private sealed record SubjectDays(string SubjectId, string? Family, string? Template, string? Country,
            DateOnly? SignupDate, DateOnly? FirstMeaningful, List<DateOnly> ActivityDays);

        public async Task<List<RetentionCohortDto>> GetRetentionAsync(
            string scope, string cohortBy, string? family, string? template, string? country)
        {
            var orgs = await _activity.GetOrganizationSummariesAsync();
            var days = await QueryActivityDaysAsync();   // companyid -> business days with meaningful activity

            List<SubjectDays> subjects;
            if (string.Equals(scope, "company", StringComparison.OrdinalIgnoreCase))
            {
                subjects = orgs.SelectMany(o => o.Companies.Select(c => new SubjectDays(
                    c.CompanyId, c.CompanyFamily, c.BusinessTemplateCode, o.CountryCode,
                    c.CreatedAtUtc is DateTime cr ? DateOnly.FromDateTime(cr) : null,
                    c.FirstMeaningfulActivityAtUtc is DateTime fm ? DateOnly.FromDateTime(fm) : null,
                    days.TryGetValue(c.CompanyId, out var d) ? d : new List<DateOnly>()))).ToList();
            }
            else
            {
                subjects = orgs.Select(o => new SubjectDays(
                    o.OrganizationId,
                    o.Companies.Select(c => c.CompanyFamily).FirstOrDefault(),
                    o.Companies.Select(c => c.BusinessTemplateCode).FirstOrDefault(t => t != null),
                    o.CountryCode,
                    o.FirstCompanyCreatedAtUtc is DateTime cr ? DateOnly.FromDateTime(cr) : null,
                    o.FirstMeaningfulActivityAtUtc is DateTime fm ? DateOnly.FromDateTime(fm) : null,
                    o.Companies.SelectMany(c => days.TryGetValue(c.CompanyId, out var d) ? d : new List<DateOnly>())
                        .Distinct().ToList())).ToList();
            }

            var filtered = subjects.Where(s =>
                (family == null || s.Family == family ||
                 (scope != "company" && orgs.FirstOrDefault(o => o.OrganizationId == s.SubjectId)?.Companies.Any(c => c.CompanyFamily == family) == true))
                && (template == null || s.Template == template)
                && (country == null || s.Country == country)).ToList();

            var today = DateOnly.FromDateTime(DateTime.UtcNow);
            var byCohort = new Dictionary<string, List<(DateOnly Anchor, List<DateOnly> Days)>>();
            foreach (var s in filtered)
            {
                var anchor = string.Equals(cohortBy, "activationMonth", StringComparison.OrdinalIgnoreCase)
                    ? s.FirstMeaningful : s.SignupDate;
                if (anchor is not DateOnly a) continue;
                var key = string.Equals(cohortBy, "signupWeek", StringComparison.OrdinalIgnoreCase)
                    ? RetentionMath.WeekKey(a) : RetentionMath.MonthKey(a);
                if (!byCohort.TryGetValue(key, out var list)) byCohort[key] = list = new();
                list.Add((a, s.ActivityDays));
            }

            return byCohort
                .OrderByDescending(kv => kv.Key)
                .Select(kv =>
                {
                    var dto = new RetentionCohortDto { Cohort = kv.Key, Subjects = kv.Value.Count };
                    for (var w = 0; w < 5; w++)
                    {
                        var reached = kv.Value.Where(x => RetentionMath.WindowReached(x.Anchor, today, w)).ToList();
                        dto.Retained[w] = reached.Count(x => RetentionMath.RetainedInWindow(x.Anchor, x.Days, w));
                        dto.Percent[w] = reached.Count == 0 ? null
                            : Math.Round(100.0 * dto.Retained[w] / reached.Count, 1);
                    }
                    return dto;
                })
                .ToList();
        }

        private async Task<Dictionary<string, List<DateOnly>>> QueryActivityDaysAsync()
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            var map = new Dictionary<string, List<DateOnly>>();
            await using var cmd = new NpgsqlCommand(@"
                SELECT companyid, businessdate FROM companyusagedaily
                WHERE meaningfulactivitycount > 0", conn);
            await using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                var id = r.GetString(0);
                if (!map.TryGetValue(id, out var list)) map[id] = list = new();
                list.Add(DateOnly.FromDateTime(r.GetDateTime(1)));
            }
            return map;
        }
    }
}
