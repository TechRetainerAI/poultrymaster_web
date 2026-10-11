// PROMPT 7: deterministic management briefs — data first. Every number comes
// from the trusted analytics services built in prompts 1-6, the structured
// brief is stored (platformbriefs.metricsjson) and entries deep-link into the
// Admin pages. No AI/LLM capability exists on this platform, so no AI summary
// is produced; if one is added later it must summarize THESE stored metrics.

using System.Text.Json;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IPlatformBriefService
    {
        Task<ManagementBriefDto> GenerateAsync(string briefType, string actor);
        Task<ManagementBriefDto?> GetLatestAsync(string briefType);
    }

    public class PlatformBriefService : IPlatformBriefService
    {
        private readonly string _cs;
        private readonly IPlatformActivityService _activity;
        private readonly IPlatformHealthService _healthSvc;
        private readonly IPlatformAnalyticsService _analytics;
        private readonly IPlatformRevenueService _revenue;
        private readonly IPlatformOpsService _ops;

        public PlatformBriefService(string connectionString, IPlatformActivityService activity,
            IPlatformHealthService healthSvc, IPlatformAnalyticsService analytics,
            IPlatformRevenueService revenue, IPlatformOpsService ops)
        {
            _cs = connectionString;
            _activity = activity;
            _healthSvc = healthSvc;
            _analytics = analytics;
            _revenue = revenue;
            _ops = ops;
        }

        public async Task<ManagementBriefDto> GenerateAsync(string briefType, string actor)
        {
            var weekly = string.Equals(briefType, "Weekly", StringComparison.OrdinalIgnoreCase);
            var windowDays = weekly ? 7 : 1;
            var brief = new ManagementBriefDto
            {
                BriefType = weekly ? "Weekly" : "Daily",
                BriefDate = DateOnly.FromDateTime(DateTime.UtcNow),
                GeneratedAtUtc = DateTime.UtcNow,
                GeneratedBy = actor,
            };

            var overview = await _activity.GetOverviewAsync(30);
            var orgs = await _activity.GetOrganizationSummariesAsync();
            var quiet = await _activity.GetGoingQuietAsync();
            var newCustomers = await _activity.GetNewCustomersAsync(windowDays);
            var queue = await _healthSvc.GetQueueAsync(null, includeNotes: false);
            var adoption = await _analytics.GetFeatureAdoptionAsync(30);
            var revenue = await _revenue.GetDashboardAsync();
            var errors = await _ops.GetErrorDashboardAsync(windowDays * 24);
            var releases = await _ops.GetReleasesAsync();

            string Money(IEnumerable<(string Cur, decimal Amt)> rows) =>
                string.Join(" · ", rows.Where(x => x.Amt != 0).Select(x => $"{x.Cur} {x.Amt:N2}")) is { Length: > 0 } s ? s : "0";

            // CUSTOMERS
            var atRiskOrgs = orgs.Count(o => o.Health is "At Risk" or "Inactive");
            var activatedRecently = orgs.SelectMany(o => o.Companies)
                .Count(c => c.Activated && c.FirstMeaningfulActivityAtUtc >= DateTime.UtcNow.AddDays(-windowDays));
            brief.Sections.Add(new BriefSectionDto
            {
                Title = "Customers",
                Entries =
                {
                    new() { Label = $"New organizations ({windowDays}d)", Value = newCustomers.Count.ToString(), LinkKind = "intel" },
                    new() { Label = $"Companies activated ({windowDays}d)", Value = activatedRecently.ToString(), LinkKind = "analytics" },
                    new() { Label = "Companies active 7d", Value = overview.CompaniesActive7d.ToString(), LinkKind = "intel" },
                    new() { Label = "Going quiet", Value = quiet.Count.ToString(), LinkKind = "success" },
                    new() { Label = "Organizations at risk / inactive", Value = atRiskOrgs.ToString(), LinkKind = "intel" },
                },
            });

            // TRIALS
            brief.Sections.Add(new BriefSectionDto
            {
                Title = "Trials",
                Entries =
                {
                    new() { Label = "Trials ending within 7 days", Value = revenue.Trials.TrialEnding7d.ToString(), LinkKind = "revenue" },
                    new() { Label = "Highly engaged trials not paid", Value = revenue.Trials.HighEngagementTrialsNotPaid.Count.ToString(), LinkKind = "revenue" },
                    new() { Label = "Conversions this month", Value = revenue.Trials.ConvertedThisMonth.ToString(), LinkKind = "revenue" },
                },
            });

            // BILLING (per currency — never summed across)
            brief.Sections.Add(new BriefSectionDto
            {
                Title = "Billing",
                Entries =
                {
                    new() { Label = "MRR", Value = Money(revenue.ByCurrency.Select(b => (b.CurrencyCode, b.Mrr))), LinkKind = "revenue" },
                    new() { Label = "New MRR (month over month)", Value = Money(revenue.ByCurrency.Select(b => (b.CurrencyCode, b.NewMrr))), LinkKind = "revenue" },
                    new() { Label = "Failed payments (30d)", Value = revenue.ByCurrency.Sum(b => b.FailedPaymentsCount30d).ToString(), LinkKind = "revenue" },
                    new() { Label = "Past due", Value = Money(revenue.ByCurrency.Select(b => (b.CurrencyCode, b.PastDueAmount))), LinkKind = "revenue" },
                    new() { Label = "Revenue at risk", Value = Money(revenue.RevenueAtRisk.GroupBy(o => o.CurrencyCode)
                        .Select(g => (g.Key, g.Sum(x => x.RevenueAtRisk)))), LinkKind = "revenue" },
                },
            });

            // PRODUCT
            var topFeatures = adoption.GroupBy(a => a.Feature)
                .Select(g => (Feature: g.Key, Used: g.Sum(x => x.CompaniesUsed)))
                .OrderByDescending(x => x.Used).Take(3).ToList();
            var lowFeatures = adoption.Where(a => a.CompaniesTotal >= 2 && a.Percent < 25)
                .GroupBy(a => a.Feature).Select(g => g.Key).Take(3).ToList();
            brief.Sections.Add(new BriefSectionDto
            {
                Title = "Product",
                Entries =
                {
                    new() { Label = "Top used features (30d)", Value = topFeatures.Count == 0 ? "—"
                        : string.Join(", ", topFeatures.Select(f => $"{f.Feature} ({f.Used})")), LinkKind = "analytics" },
                    new() { Label = "Low-adoption features", Value = lowFeatures.Count == 0 ? "—" : string.Join(", ", lowFeatures), LinkKind = "analytics" },
                    new() { Label = "Activity by vertical (meaningful, 30d)", Value = string.Join(" · ",
                        overview.ByCompanyFamily.Where(f => f.Key != "(none)").Select(f => $"{f.Key} {f.MeaningfulCount}")), LinkKind = "analytics" },
                },
            });

            // OPERATIONS
            var latestRelease = releases.FirstOrDefault(x => x.Service == "farm-api");
            brief.Sections.Add(new BriefSectionDto
            {
                Title = "Operations",
                Entries =
                {
                    new() { Label = $"Errors ({windowDays * 24}h)", Value = errors.TotalErrors.ToString(), LinkKind = "audit" },
                    new() { Label = "Failed business operations", Value = errors.FailedBusinessOperations.ToString(), LinkKind = "audit" },
                    new() { Label = "Affected customers", Value = $"{errors.AffectedOrganizations} orgs / {errors.AffectedCompanies} companies", LinkKind = "audit" },
                    new() { Label = "Open attention items", Value = queue.Count.ToString(), LinkKind = "success" },
                    new() { Label = "Current farm-api release", Value = latestRelease is null ? "not registered yet"
                        : $"{latestRelease.Version} (since {latestRelease.FirstSeenAtUtc:yyyy-MM-dd})", LinkKind = "none" },
                },
            });

            // Store the structured brief (retention: 400 days; see migration 352).
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            await using var cmd = new NpgsqlCommand(@"
                INSERT INTO platformbriefs (brieftype, briefdate, generatedby, metricsjson)
                VALUES (@T, @D, @By, @J)
                ON CONFLICT (brieftype, briefdate) DO UPDATE
                SET generatedby = excluded.generatedby,
                    metricsjson = excluded.metricsjson,
                    generatedatutc = now()", conn);
            cmd.Parameters.AddWithValue("@T", brief.BriefType);
            cmd.Parameters.AddWithValue("@D", brief.BriefDate.ToDateTime(TimeOnly.MinValue));
            cmd.Parameters.AddWithValue("@By", actor);
            cmd.Parameters.AddWithValue("@J", JsonSerializer.Serialize(brief));
            await cmd.ExecuteNonQueryAsync();

            return brief;
        }

        public async Task<ManagementBriefDto?> GetLatestAsync(string briefType)
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            await using var cmd = new NpgsqlCommand(@"
                SELECT metricsjson FROM platformbriefs
                WHERE brieftype = @T ORDER BY briefdate DESC LIMIT 1", conn);
            cmd.Parameters.AddWithValue("@T",
                string.Equals(briefType, "Weekly", StringComparison.OrdinalIgnoreCase) ? "Weekly" : "Daily");
            var json = await cmd.ExecuteScalarAsync() as string;
            if (json is null) return null;
            try { return JsonSerializer.Deserialize<ManagementBriefDto>(json); }
            catch { return null; }
        }
    }
}
