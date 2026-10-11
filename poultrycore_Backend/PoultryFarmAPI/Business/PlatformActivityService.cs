// PROMPT 1 (Platform Activity Foundation): the shared aggregation service the
// Admin app's current and future dashboards consume, plus the single C# write
// path onto platform_activity_record (migration 346).
//
// Reads prefer companyusagedaily (the trigger-maintained derived cache) over
// scanning platformactivityevents, so dashboards stay cheap as event volume
// grows; last-activity timestamps use the events table's partial meaningful
// index. No N+1: company summaries come back in ONE lateral-join query.
//
// Activity-status thresholds and the trend stability band are centralized here
// (configurable via the "PlatformActivity" appsettings section) — the UI never
// hardcodes them.

using Npgsql;
using NpgsqlTypes;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class PlatformActivityOptions
    {
        public const string Section = "PlatformActivity";
        public int ShortWindowDays { get; set; } = 7;
        public int LongWindowDays { get; set; } = 30;
        /// <summary>Trend counts within ±this percent are "Stable".</summary>
        public double StablePercentBand { get; set; } = 10.0;
        // "Going Quiet" (Prompt 2, section 11): previously active (baseline window
        // before the recent one had >= QuietBaselineMin meaningful events) but the
        // recent window has <= QuietRecentMax. Deterministic — NOT a churn verdict.
        public int QuietBaselineDays { get; set; } = 30;
        public int QuietRecentDays { get; set; } = 14;
        public int QuietBaselineMin { get; set; } = 10;
        public int QuietRecentMax { get; set; } = 2;
        public int TrialEndingSoonDays { get; set; } = 7;
    }

    /// <summary>Pure, testable trend/status math (sections 12-13 of the spec).</summary>
    public static class ActivityMath
    {
        public static PlatformTrendDto ComputeTrend(long current, long previous, double stableBand)
        {
            var dto = new PlatformTrendDto { CurrentPeriodCount = current, PreviousPeriodCount = previous };
            if (current == 0)
            {
                dto.Status = nameof(PlatformTrendStatus.Inactive);
                dto.PercentChange = previous == 0 ? null : -100.0;
                return dto;
            }
            if (previous == 0)
            {
                // No Infinity: percent change is undefined, status says it all.
                dto.Status = nameof(PlatformTrendStatus.NewActivity);
                dto.PercentChange = null;
                return dto;
            }
            var pct = (current - previous) * 100.0 / previous;
            dto.PercentChange = Math.Round(pct, 1);
            dto.Status = pct >= stableBand ? nameof(PlatformTrendStatus.Increasing)
                       : pct <= -stableBand ? nameof(PlatformTrendStatus.Declining)
                       : nameof(PlatformTrendStatus.Stable);
            return dto;
        }

        /// <summary>
        /// activeToday is evaluated against the COMPANY's business date (its own
        /// timezone); the 7/30-day windows use UTC timestamps.
        /// </summary>
        public static PlatformActivityStatus ClassifyStatus(
            bool activeToday, DateTime? lastMeaningfulUtc, DateTime nowUtc, int shortDays, int longDays)
        {
            if (activeToday) return PlatformActivityStatus.ActiveToday;
            if (lastMeaningfulUtc is null) return PlatformActivityStatus.NoActivity;
            var age = nowUtc - lastMeaningfulUtc.Value;
            if (age <= TimeSpan.FromDays(shortDays)) return PlatformActivityStatus.Active7Days;
            if (age <= TimeSpan.FromDays(longDays)) return PlatformActivityStatus.Active30Days;
            return PlatformActivityStatus.Inactive30Plus;
        }

        /// <summary>"Going Quiet" rule (deterministic, not churn): meaningfully active
        /// in the baseline window, nearly silent in the recent one.</summary>
        public static bool IsGoingQuiet(long baselineCount, long recentCount, int baselineMin, int recentMax)
            => baselineCount >= baselineMin && recentCount <= recentMax;
    }

    public interface IPlatformActivityService
    {
        /// <summary>Records one normalized activity event. Never throws (analytics
        /// must never break a business operation); returns the event id, or null
        /// when skipped as a duplicate or on failure.</summary>
        Task<long?> RecordAsync(PlatformActivityRecordRequest request);

        Task<PlatformActivityOverviewDto> GetOverviewAsync(int? days);
        Task<List<OrganizationActivitySummaryDto>> GetOrganizationSummariesAsync();
        Task<OrganizationActivitySummaryDto?> GetOrganizationAsync(string organizationId);
        Task<CompanyActivitySummaryDto?> GetCompanyAsync(string companyId);
        Task<List<ActivityTimePointDto>> GetTimeSeriesAsync(string? organizationId, string? companyId, string? companyFamily, int? days);
        Task<List<CategoryCountDto>> GetCategoryBreakdownAsync(string? organizationId, string? companyId, int? days);
        Task<List<RecentActivityDto>> GetRecentMeaningfulAsync(int limit, string? companyFamily, string? organizationId, string? companyId);
        Task<List<GoingQuietRowDto>> GetGoingQuietAsync();
        Task<List<NewCustomerRowDto>> GetNewCustomersAsync(int? days);
        Task<List<ModuleAdoptionRowDto>> GetModuleAdoptionAsync(int? days);
    }

    public class PlatformActivityService : IPlatformActivityService
    {
        private readonly string _cs;
        private readonly PlatformActivityOptions _opt;
        private readonly PlatformHealthOptions _health;
        private readonly ILogger<PlatformActivityService>? _log;

        public PlatformActivityService(string connectionString, PlatformActivityOptions? options = null,
            ILogger<PlatformActivityService>? log = null, PlatformHealthOptions? healthOptions = null)
        {
            _cs = connectionString;
            _opt = options ?? new PlatformActivityOptions();
            _health = healthOptions ?? new PlatformHealthOptions();
            _log = log;
        }

        // ------------------------------------------------------------------
        // Write side
        // ------------------------------------------------------------------
        public async Task<long?> RecordAsync(PlatformActivityRecordRequest r)
        {
            try
            {
                await using var conn = new NpgsqlConnection(_cs);
                await conn.OpenAsync();
                await using var cmd = new NpgsqlCommand(@"
                    SELECT platform_activity_record(
                        p_companyid      => @CompanyId,
                        p_userid         => @UserId,
                        p_category       => @Category,
                        p_type           => @Type,
                        p_sourcemodule   => @Module,
                        p_sourcerecordid => @SourceRecordId,
                        p_ismeaningful   => @Meaningful,
                        p_metadatajson   => @Metadata,
                        p_correlationid  => @Correlation,
                        p_occurredatutc  => @Occurred,
                        p_employeeid     => @EmployeeId)", conn);
                cmd.Parameters.AddWithValue("@CompanyId", (object?)Clean(r.CompanyId) ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@UserId", (object?)Clean(r.UserId) ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@Category", r.Category);
                cmd.Parameters.AddWithValue("@Type", r.ActivityType);
                cmd.Parameters.AddWithValue("@Module", r.SourceModule);
                cmd.Parameters.AddWithValue("@SourceRecordId", (object?)Clean(r.SourceRecordId) ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@Meaningful", r.IsMeaningful);
                cmd.Parameters.AddWithValue("@Metadata", (object?)Clean(r.MetadataJson) ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@Correlation", (object?)Clean(r.CorrelationId) ?? DBNull.Value);
                cmd.Parameters.Add(new NpgsqlParameter("@Occurred", NpgsqlDbType.TimestampTz)
                { Value = r.OccurredAtUtc ?? DateTime.UtcNow });
                cmd.Parameters.AddWithValue("@EmployeeId", (object?)Clean(r.EmployeeId) ?? DBNull.Value);

                var result = await cmd.ExecuteScalarAsync();
                return result is long id ? id : (long?)null;
            }
            catch (Exception ex)
            {
                _log?.LogWarning(ex, "Platform activity event dropped: {Type} for company {CompanyId}",
                    r.ActivityType, r.CompanyId);
                return null;
            }
        }

        private static string? Clean(string? v) => string.IsNullOrWhiteSpace(v) ? null : v.Trim();

        // ------------------------------------------------------------------
        // Company summaries — one query, no N+1
        // ------------------------------------------------------------------
        private const string CompanySummarySql = @"
SELECT f.farmid,
       coalesce(f.name, '')                                   AS name,
       f.type                                                 AS family,
       f.owneruserid,
       nullif(f.timezoneid, '')                               AS tz,
       g.template                                             AS template,
       lm.lastmeaningful,
       la.lastany,
       coalesce(u.m_today, 0)                                 AS m_today,
       coalesce(u.m_short, 0)                                 AS m_short,
       coalesce(u.m_long, 0)                                  AS m_long,
       coalesce(u.d_short, 0)                                 AS d_short,
       coalesce(u.d_long, 0)                                  AS d_long,
       coalesce(au_s.c, 0)                                    AS users_short,
       coalesce(au_l.c, 0)                                    AS users_long,
       coalesce(prev.m_prev, 0)                               AS m_prev,
       f.createdat                                            AS createdat,
       lm.firstmeaningful                                     AS firstmeaningful,
       cbs.billingprofilecode                                 AS plancode,
       cbs.participationstatus                                AS participation
FROM farms f
LEFT JOIN LATERAL (
    SELECT nullif(p.genericbusinesstemplate, '') AS template
    FROM genericcompanyprofiles p
    WHERE p.farmid = f.farmid
    ORDER BY p.genericcompanyprofileid DESC LIMIT 1) g ON true
LEFT JOIN LATERAL (
    SELECT max(e.occurredatutc) AS lastmeaningful,
           min(e.occurredatutc) AS firstmeaningful
    FROM platformactivityevents e
    WHERE e.companyid = f.farmid AND e.ismeaningful) lm ON true
LEFT JOIN LATERAL (
    SELECT s.billingprofilecode, s.participationstatus
    FROM companybillingstates s
    WHERE s.farmid = f.farmid AND s.archivedatutc IS NULL
    ORDER BY s.updatedatutc DESC NULLS LAST LIMIT 1) cbs ON true
LEFT JOIN LATERAL (
    SELECT max(e.occurredatutc) AS lastany
    FROM platformactivityevents e
    WHERE e.companyid = f.farmid) la ON true
LEFT JOIN LATERAL (
    SELECT sum(d.meaningfulactivitycount) FILTER (
               WHERE d.businessdate = (now() AT TIME ZONE coalesce(nullif(f.timezoneid, ''), 'UTC'))::date) AS m_today,
           sum(d.meaningfulactivitycount) FILTER (WHERE d.businessdate > current_date - @Short) AS m_short,
           sum(d.meaningfulactivitycount) FILTER (WHERE d.businessdate > current_date - @Long)  AS m_long,
           count(*) FILTER (WHERE d.businessdate > current_date - @Short AND d.meaningfulactivitycount > 0) AS d_short,
           count(*) FILTER (WHERE d.businessdate > current_date - @Long  AND d.meaningfulactivitycount > 0) AS d_long
    FROM companyusagedaily d
    WHERE d.companyid = f.farmid) u ON true
LEFT JOIN LATERAL (
    SELECT count(DISTINCT x.userid) AS c FROM companyusagedailyusers x
    WHERE x.companyid = f.farmid AND x.businessdate > current_date - @Short) au_s ON true
LEFT JOIN LATERAL (
    SELECT count(DISTINCT x.userid) AS c FROM companyusagedailyusers x
    WHERE x.companyid = f.farmid AND x.businessdate > current_date - @Long) au_l ON true
LEFT JOIN LATERAL (
    SELECT sum(d.meaningfulactivitycount) AS m_prev
    FROM companyusagedaily d
    WHERE d.companyid = f.farmid
      AND d.businessdate > current_date - (@Long * 2)
      AND d.businessdate <= current_date - @Long) prev ON true
WHERE coalesce(f.isdeleted, false) = false
  AND f.type IS DISTINCT FROM 'System'
  AND (@CompanyId::text IS NULL OR f.farmid = @CompanyId)
  AND (@OrgId::text IS NULL OR f.owneruserid = @OrgId)
ORDER BY lm.lastmeaningful DESC NULLS LAST, f.name";

        private async Task<List<CompanyActivitySummaryDto>> QueryCompaniesAsync(
            NpgsqlConnection conn, string? companyId, string? orgId)
        {
            var list = new List<CompanyActivitySummaryDto>();
            await using var cmd = new NpgsqlCommand(CompanySummarySql, conn);
            cmd.Parameters.AddWithValue("@Short", _opt.ShortWindowDays);
            cmd.Parameters.AddWithValue("@Long", _opt.LongWindowDays);
            cmd.Parameters.AddWithValue("@CompanyId", (object?)companyId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@OrgId", (object?)orgId ?? DBNull.Value);
            await using var r = await cmd.ExecuteReaderAsync();
            var now = DateTime.UtcNow;
            while (await r.ReadAsync())
            {
                var lastMeaningful = r.IsDBNull(6) ? (DateTime?)null : r.GetDateTime(6);
                var mToday = r.IsDBNull(8) ? 0L : Convert.ToInt64(r.GetValue(8));
                var dto = new CompanyActivitySummaryDto
                {
                    CompanyId = r.GetString(0),
                    CompanyName = r.GetString(1),
                    CompanyFamily = r.IsDBNull(2) ? null : r.GetString(2),
                    OrganizationId = r.IsDBNull(3) ? null : r.GetString(3),
                    TimeZoneId = r.IsDBNull(4) ? null : r.GetString(4),
                    BusinessTemplateCode = r.IsDBNull(5) ? null : r.GetString(5),
                    LastMeaningfulActivityAtUtc = lastMeaningful,
                    LastActivityAtUtc = r.IsDBNull(7) ? null : r.GetDateTime(7),
                    MeaningfulActivityCountToday = mToday,
                    MeaningfulActivityCount7d = Convert.ToInt64(r.GetValue(9)),
                    MeaningfulActivityCount30d = Convert.ToInt64(r.GetValue(10)),
                    ActiveDays7d = Convert.ToInt32(r.GetValue(11)),
                    ActiveDays30d = Convert.ToInt32(r.GetValue(12)),
                    ActiveUsers7d = Convert.ToInt32(r.GetValue(13)),
                    ActiveUsers30d = Convert.ToInt32(r.GetValue(14)),
                    CreatedAtUtc = r.IsDBNull(16) ? null : r.GetDateTime(16),
                    FirstMeaningfulActivityAtUtc = r.IsDBNull(17) ? null : r.GetDateTime(17),
                    PlanCode = r.IsDBNull(18) ? null : r.GetString(18),
                    BillingParticipation = r.IsDBNull(19) ? null : r.GetString(19),
                };
                dto.Trend = ActivityMath.ComputeTrend(
                    dto.MeaningfulActivityCount30d, Convert.ToInt64(r.GetValue(15)), _opt.StablePercentBand);
                dto.ActivityStatus = ActivityMath.ClassifyStatus(
                    mToday > 0, lastMeaningful, now, _opt.ShortWindowDays, _opt.LongWindowDays).ToString();
                list.Add(dto);
            }
            return list;
        }

        public async Task<CompanyActivitySummaryDto?> GetCompanyAsync(string companyId)
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            var one = (await QueryCompaniesAsync(conn, companyId, null)).FirstOrDefault();
            if (one is null) return null;
            one.CategoryBreakdown = await QueryCategoryBreakdownAsync(conn, null, companyId, _opt.LongWindowDays);
            return one;
        }

        // ------------------------------------------------------------------
        // Organization aggregation: rolls companies up, preserves per-company data
        // ------------------------------------------------------------------
        public async Task<List<OrganizationActivitySummaryDto>> GetOrganizationSummariesAsync()
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            var companies = await QueryCompaniesAsync(conn, null, null);
            var orgs = BuildOrganizationRollups(companies);
            await DecorateOrganizationsAsync(conn, orgs);
            return orgs;
        }

        public async Task<OrganizationActivitySummaryDto?> GetOrganizationAsync(string organizationId)
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            var companies = await QueryCompaniesAsync(conn, null, organizationId);
            if (companies.Count == 0) return null;
            var org = BuildOrganizationRollups(companies).First();
            await DecorateOrganizationsAsync(conn, new List<OrganizationActivitySummaryDto> { org });
            return org;
        }

        private List<OrganizationActivitySummaryDto> BuildOrganizationRollups(
            List<CompanyActivitySummaryDto> companies)
        {
            var now = DateTime.UtcNow;
            return companies
                .GroupBy(c => c.OrganizationId ?? "")
                .Select(g =>
                {
                    var lastMeaningful = g.Max(c => c.LastMeaningfulActivityAtUtc);
                    var cur = g.Sum(c => c.MeaningfulActivityCount30d);
                    var prev = g.Sum(c => c.Trend.PreviousPeriodCount);
                    var activeToday = g.Any(c => c.ActivityStatus == nameof(PlatformActivityStatus.ActiveToday));
                    var activated = g.Count(c => c.FirstMeaningfulActivityAtUtc != null);
                    return new OrganizationActivitySummaryDto
                    {
                        OrganizationId = g.Key,
                        CompanyCount = g.Count(),
                        ActiveCompanies30d = g.Count(c => c.MeaningfulActivityCount30d > 0),
                        FirstCompanyCreatedAtUtc = g.Min(c => c.CreatedAtUtc),
                        FirstMeaningfulActivityAtUtc = g.Min(c => c.FirstMeaningfulActivityAtUtc),
                        LastMeaningfulActivityAtUtc = lastMeaningful,
                        MeaningfulActivityCount30d = cur,
                        // Initial deterministic setup proxy: share of companies that have
                        // produced at least one meaningful event. Prompt 3's Health Engine
                        // replaces this with a real setup-completeness model.
                        SetupPercent = g.Count() == 0 ? 0 : (int)Math.Round(100.0 * activated / g.Count()),
                        Trend = ActivityMath.ComputeTrend(cur, prev, _opt.StablePercentBand),
                        ActivityStatus = ActivityMath.ClassifyStatus(
                            activeToday, lastMeaningful, now, _opt.ShortWindowDays, _opt.LongWindowDays).ToString(),
                        Companies = g.ToList(),
                    };
                })
                .OrderByDescending(o => o.LastMeaningfulActivityAtUtc ?? DateTime.MinValue)
                .ToList();
        }

        /// <summary>Fills owner names, billing/subscription state, exact distinct active
        /// users and deterministic attention flags per organization.</summary>
        private async Task DecorateOrganizationsAsync(
            NpgsqlConnection conn, List<OrganizationActivitySummaryDto> orgs)
        {
            var ids = orgs.Select(o => o.OrganizationId).Where(i => i != "").Distinct().ToArray();
            if (ids.Length == 0) return;

            await using (var cmd = new NpgsqlCommand(@"
                SELECT id,
                       coalesce(nullif(businessofficename, ''),
                                nullif(trim(coalesce(firstname,'') || ' ' || coalesce(lastname,'')), ''),
                                username) AS orgname,
                       email, nullif(organizationcode, '')
                FROM aspnetusers WHERE id = ANY(@Ids)", conn))
            {
                cmd.Parameters.AddWithValue("@Ids", ids);
                await using var r = await cmd.ExecuteReaderAsync();
                var names = new Dictionary<string, (string? Name, string? Email, string? Code)>();
                while (await r.ReadAsync())
                    names[r.GetString(0)] = (r.IsDBNull(1) ? null : r.GetString(1),
                        r.IsDBNull(2) ? null : r.GetString(2), r.IsDBNull(3) ? null : r.GetString(3));
                foreach (var o in orgs)
                    if (names.TryGetValue(o.OrganizationId, out var n))
                    { o.OrganizationName = n.Name; o.OwnerEmail = n.Email; o.OrgCode = n.Code; }
            }

            await using (var cmd = new NpgsqlCommand(@"
                SELECT f.owneruserid, count(DISTINCT x.userid)
                FROM companyusagedailyusers x
                JOIN farms f ON f.farmid = x.companyid
                WHERE f.owneruserid = ANY(@Ids) AND x.businessdate > current_date - 30
                GROUP BY f.owneruserid", conn))
            {
                cmd.Parameters.AddWithValue("@Ids", ids);
                await using var r = await cmd.ExecuteReaderAsync();
                var counts = new Dictionary<string, int>();
                while (await r.ReadAsync())
                    counts[r.GetString(0)] = Convert.ToInt32(r.GetValue(1));
                foreach (var o in orgs)
                    o.ActiveUsers30d = counts.TryGetValue(o.OrganizationId, out var c) ? c : 0;
            }

            // Billing account: subscription status, market (country), past-due invoices.
            await using (var cmd = new NpgsqlCommand(@"
                SELECT a.owneruserid, a.status, a.billingmarketcode, a.orgcode, a.trialendutc,
                       EXISTS (SELECT 1 FROM platforminvoices i
                                WHERE i.accountid = a.id AND i.balance > 0
                                  AND i.duedate < current_date
                                  AND i.status NOT IN ('Paid', 'Void')) AS pastdue
                FROM organizationbillingaccounts a
                WHERE a.owneruserid = ANY(@Ids)", conn))
            {
                cmd.Parameters.AddWithValue("@Ids", ids);
                await using var r = await cmd.ExecuteReaderAsync();
                var billing = new Dictionary<string, (string Status, string? Market, string? Code, DateTime? TrialEnd, bool PastDue)>();
                while (await r.ReadAsync())
                    billing[r.GetString(0)] = (
                        r.IsDBNull(1) ? "None" : r.GetString(1),
                        r.IsDBNull(2) ? null : r.GetString(2),
                        r.IsDBNull(3) ? null : r.GetString(3),
                        r.IsDBNull(4) ? null : r.GetDateTime(4),
                        r.GetBoolean(5));
                foreach (var o in orgs)
                {
                    if (billing.TryGetValue(o.OrganizationId, out var b))
                    {
                        o.SubscriptionStatus = b.PastDue ? "PastDue" : b.Status;
                        o.CountryCode = b.Market;
                        o.OrgCode ??= b.Code;
                        o.TrialEndUtc = b.TrialEnd;
                        o.HasPastDueInvoice = b.PastDue;
                    }
                }
            }

            // Milestone-based setup completion (Prompt 4) — replaces the Prompt 2
            // activation proxy so health, attention rules and the onboarding page
            // all consume ONE centralized definition.
            await using (var cmd = new NpgsqlCommand(@"
                SELECT companyid, setuppercent, requiredcomplete, requiredtotal, missingtitles
                FROM platform_setup_summary()", conn))
            {
                await using var r = await cmd.ExecuteReaderAsync();
                var byCompany = new Dictionary<string, (int Pct, int ReqC, int ReqT, string[] Missing)>();
                while (await r.ReadAsync())
                    byCompany[r.GetString(0)] = (Convert.ToInt32(r.GetValue(1)), Convert.ToInt32(r.GetValue(2)),
                        Convert.ToInt32(r.GetValue(3)), r.IsDBNull(4) ? Array.Empty<string>() : (string[])r.GetValue(4));
                foreach (var o in orgs)
                {
                    foreach (var c in o.Companies)
                    {
                        if (!byCompany.TryGetValue(c.CompanyId, out var m)) continue;
                        c.SetupPercent = m.Pct;
                        c.RequiredMilestonesComplete = m.ReqC;
                        c.RequiredMilestonesTotal = m.ReqT;
                        c.MissingMilestones = m.Missing.ToList();
                        c.Activated = m.ReqT > 0 && m.ReqC == m.ReqT && c.FirstMeaningfulActivityAtUtc != null;
                        if (c.FirstMeaningfulActivityAtUtc is DateTime fm && c.CreatedAtUtc is DateTime cr && fm >= cr)
                            c.TimeToActivationDays = Math.Round((fm - cr).TotalDays, 1);
                    }
                    if (o.Companies.Count > 0)
                        o.SetupPercent = (int)Math.Round(o.Companies.Average(c => (double)c.SetupPercent));
                }
            }

            // Recent failed payments (health signal, 7 days).
            await using (var cmd = new NpgsqlCommand(@"
                SELECT DISTINCT a.owneruserid
                FROM platformpayments p
                JOIN organizationbillingaccounts a ON a.id = p.accountid
                WHERE a.owneruserid = ANY(@Ids) AND p.status = 'Failed'
                  AND coalesce(p.paymentdateutc, p.createdatutc) > now() - interval '7 days'", conn))
            {
                cmd.Parameters.AddWithValue("@Ids", ids);
                await using var r = await cmd.ExecuteReaderAsync();
                var failed = new HashSet<string>();
                while (await r.ReadAsync()) failed.Add(r.GetString(0));
                foreach (var o in orgs)
                    o.HasRecentFailedPayment = failed.Contains(o.OrganizationId);
            }

            // Failed requests per company (RepeatedErrors health signal, 7 days).
            await using (var cmd = new NpgsqlCommand(@"
                SELECT lower(farmid), count(*)
                FROM auditlogs
                WHERE status = 'Failed' AND ""timestamp"" > now() - interval '7 days'
                  AND farmid IS NOT NULL AND farmid <> '' AND farmid <> 'Unknown'
                GROUP BY lower(farmid)", conn))
            {
                await using var r = await cmd.ExecuteReaderAsync();
                var byFarm = new Dictionary<string, int>();
                while (await r.ReadAsync())
                    byFarm[r.GetString(0)] = Convert.ToInt32(r.GetValue(1));
                foreach (var o in orgs)
                    foreach (var c in o.Companies)
                        c.FailedRequests7d = byFarm.TryGetValue(c.CompanyId.ToLowerInvariant(), out var n) ? n : 0;
            }

            // Deterministic attention flags (kept from Prompt 2) + Prompt 3 health.
            var quietCompanies = await QueryGoingQuietCompanyIdsAsync(conn);
            var now = DateTime.UtcNow;
            foreach (var o in orgs)
            {
                if (o.HasPastDueInvoice) o.Attention.Add("PastDue");
                if (o.Companies.Any(c => quietCompanies.Contains(c.CompanyId))) o.Attention.Add("GoingQuiet");
                if (o.ActivityStatus is nameof(PlatformActivityStatus.Inactive30Plus)) o.Attention.Add("Inactive30Plus");
                if (o.SubscriptionStatus == "Trial" && o.TrialEndUtc is DateTime te
                    && te > now && te <= now.AddDays(_opt.TrialEndingSoonDays))
                    o.Attention.Add("TrialEndingSoon");

                // Health Engine (Prompt 3): explainable verdict per company, then per org.
                var evaluated = new List<(CompanyHealthInput Input, HealthResult Result)>();
                foreach (var c in o.Companies)
                {
                    var input = ToHealthInput(c);
                    var result = HealthEngine.EvaluateCompany(input, _health, now);
                    c.Health = result.LevelName;
                    c.HealthReasons = result.Reasons.ToList();
                    evaluated.Add((input, result));
                }
                var orgResult = HealthEngine.EvaluateOrganization(evaluated, new OrganizationHealthSignals(
                    o.FirstCompanyCreatedAtUtc, o.SubscriptionStatus, o.TrialEndUtc,
                    o.HasPastDueInvoice, o.HasRecentFailedPayment, o.MeaningfulActivityCount30d), _health, now);
                o.Health = orgResult.LevelName;
                o.HealthReasons = orgResult.Reasons.ToList();
            }
        }

        public static CompanyHealthInput ToHealthInput(CompanyActivitySummaryDto c) => new(
            c.CompanyId, string.IsNullOrWhiteSpace(c.CompanyName) ? c.CompanyId : c.CompanyName,
            c.CreatedAtUtc, c.FirstMeaningfulActivityAtUtc, c.LastMeaningfulActivityAtUtc,
            c.ActiveDays30d, c.MeaningfulActivityCount30d, c.Trend.PreviousPeriodCount,
            c.ActiveUsers30d, c.Trend.Status, c.Trend.PercentChange, c.FailedRequests7d);

        // ------------------------------------------------------------------
        // Going Quiet (Prompt 2, section 11) — deterministic, not churn
        // ------------------------------------------------------------------
        private const string GoingQuietSql = @"
            SELECT d.companyid,
                   max(coalesce(f.name, ''))      AS name,
                   max(f.type)                    AS family,
                   max(f.owneruserid)             AS org,
                   coalesce(sum(d.meaningfulactivitycount) FILTER (
                       WHERE d.businessdate >  current_date - (@Recent + @Baseline)
                         AND d.businessdate <= current_date - @Recent), 0) AS baseline,
                   coalesce(sum(d.meaningfulactivitycount) FILTER (
                       WHERE d.businessdate > current_date - @Recent), 0)  AS recent,
                   max(e.lastmeaningful)          AS lastmeaningful
            FROM companyusagedaily d
            JOIN farms f ON f.farmid = d.companyid
            LEFT JOIN LATERAL (
                SELECT max(occurredatutc) AS lastmeaningful
                FROM platformactivityevents pe
                WHERE pe.companyid = d.companyid AND pe.ismeaningful) e ON true
            WHERE coalesce(f.isdeleted, false) = false AND f.type IS DISTINCT FROM 'System'
            GROUP BY d.companyid";

        private async Task<HashSet<string>> QueryGoingQuietCompanyIdsAsync(NpgsqlConnection conn)
        {
            var rows = await QueryGoingQuietAsync(conn);
            return rows.Select(x => x.CompanyId).ToHashSet();
        }

        private async Task<List<GoingQuietRowDto>> QueryGoingQuietAsync(NpgsqlConnection conn)
        {
            var list = new List<GoingQuietRowDto>();
            await using var cmd = new NpgsqlCommand(GoingQuietSql, conn);
            cmd.Parameters.AddWithValue("@Recent", _opt.QuietRecentDays);
            cmd.Parameters.AddWithValue("@Baseline", _opt.QuietBaselineDays);
            await using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                var baseline = Convert.ToInt64(r.GetValue(4));
                var recent = Convert.ToInt64(r.GetValue(5));
                if (!ActivityMath.IsGoingQuiet(baseline, recent, _opt.QuietBaselineMin, _opt.QuietRecentMax))
                    continue;
                list.Add(new GoingQuietRowDto
                {
                    CompanyId = r.GetString(0),
                    CompanyName = r.GetString(1),
                    CompanyFamily = r.IsDBNull(2) ? null : r.GetString(2),
                    OrganizationId = r.IsDBNull(3) ? null : r.GetString(3),
                    BaselineMeaningfulCount = baseline,
                    RecentMeaningfulCount = recent,
                    LastMeaningfulActivityAtUtc = r.IsDBNull(6) ? null : r.GetDateTime(6),
                });
            }
            return list.OrderByDescending(x => x.BaselineMeaningfulCount).ToList();
        }

        public async Task<List<GoingQuietRowDto>> GetGoingQuietAsync()
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            var rows = await QueryGoingQuietAsync(conn);
            if (rows.Count == 0) return rows;

            var orgIds = rows.Select(x => x.OrganizationId).Where(x => x != null).Distinct().ToArray();
            await using var cmd = new NpgsqlCommand(@"
                SELECT id, coalesce(nullif(businessofficename, ''), username)
                FROM aspnetusers WHERE id = ANY(@Ids)", conn);
            cmd.Parameters.AddWithValue("@Ids", orgIds);
            await using var r = await cmd.ExecuteReaderAsync();
            var names = new Dictionary<string, string>();
            while (await r.ReadAsync())
                names[r.GetString(0)] = r.IsDBNull(1) ? "" : r.GetString(1);
            foreach (var row in rows)
                if (row.OrganizationId != null && names.TryGetValue(row.OrganizationId, out var n))
                    row.OrganizationName = n;
            return rows;
        }

        // ------------------------------------------------------------------
        // New customers (Prompt 2, section 12)
        // ------------------------------------------------------------------
        public async Task<List<NewCustomerRowDto>> GetNewCustomersAsync(int? days)
        {
            var window = Math.Clamp(days ?? 31, 1, 366);
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            var list = new List<NewCustomerRowDto>();
            await using var cmd = new NpgsqlCommand(@"
                WITH orgs AS (
                    SELECT f.owneruserid, min(f.createdat) AS firstat, count(*) AS n
                    FROM farms f
                    WHERE coalesce(f.isdeleted, false) = false AND f.type IS DISTINCT FROM 'System'
                    GROUP BY f.owneruserid
                ), firstco AS (
                    SELECT DISTINCT ON (f.owneruserid) f.owneruserid, f.farmid, f.name, f.type
                    FROM farms f
                    WHERE coalesce(f.isdeleted, false) = false AND f.type IS DISTINCT FROM 'System'
                    ORDER BY f.owneruserid, f.createdat ASC NULLS LAST
                )
                SELECT o.owneruserid,
                       coalesce(nullif(u.businessofficename, ''), u.username),
                       o.firstat, fc.farmid, fc.name, fc.type,
                       (SELECT min(e.occurredatutc) FROM platformactivityevents e
                         WHERE e.organizationid = o.owneruserid AND e.ismeaningful),
                       (SELECT count(*) FROM farms f2
                         WHERE f2.owneruserid = o.owneruserid AND coalesce(f2.isdeleted, false) = false
                           AND f2.type IS DISTINCT FROM 'System'
                           AND EXISTS (SELECT 1 FROM platformactivityevents e2
                                        WHERE e2.companyid = f2.farmid AND e2.ismeaningful)),
                       o.n, a.status, a.trialendutc
                FROM orgs o
                JOIN firstco fc ON fc.owneruserid = o.owneruserid
                LEFT JOIN aspnetusers u ON u.id = o.owneruserid
                LEFT JOIN organizationbillingaccounts a ON a.owneruserid = o.owneruserid
                WHERE o.firstat >= now() - make_interval(days => @D)
                ORDER BY o.firstat DESC", conn);
            cmd.Parameters.AddWithValue("@D", window);
            await using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                var total = Convert.ToInt32(r.GetValue(8));
                var activated = Convert.ToInt32(r.GetValue(7));
                list.Add(new NewCustomerRowDto
                {
                    OrganizationId = r.GetString(0),
                    OrganizationName = r.IsDBNull(1) ? null : r.GetString(1),
                    RegisteredAtUtc = r.IsDBNull(2) ? null : r.GetDateTime(2),
                    FirstCompanyId = r.IsDBNull(3) ? null : r.GetString(3),
                    FirstCompanyName = r.IsDBNull(4) ? null : r.GetString(4),
                    FirstCompanyFamily = r.IsDBNull(5) ? null : r.GetString(5),
                    FirstMeaningfulActivityAtUtc = r.IsDBNull(6) ? null : r.GetDateTime(6),
                    SetupPercent = total == 0 ? 0 : (int)Math.Round(100.0 * activated / total),
                    SubscriptionStatus = r.IsDBNull(9) ? "None" : r.GetString(9),
                    TrialEndUtc = r.IsDBNull(10) ? null : r.GetDateTime(10),
                });
            }
            return list;
        }

        // ------------------------------------------------------------------
        // Module adoption by vertical (Prompt 2, section 13)
        // ------------------------------------------------------------------
        public async Task<List<ModuleAdoptionRowDto>> GetModuleAdoptionAsync(int? days)
        {
            var window = Math.Clamp(days ?? _opt.LongWindowDays, 1, 366);
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            var list = new List<ModuleAdoptionRowDto>();
            await using var cmd = new NpgsqlCommand(@"
                SELECT activitycategory, coalesce(companyfamily, '(none)'),
                       count(*), count(DISTINCT companyid)
                FROM platformactivityevents
                WHERE ismeaningful AND occurredatutc > now() - make_interval(days => @D)
                GROUP BY 1, 2 ORDER BY 1, 2", conn);
            cmd.Parameters.AddWithValue("@D", window);
            await using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Add(new ModuleAdoptionRowDto
                {
                    Category = r.GetString(0),
                    CompanyFamily = r.GetString(1),
                    MeaningfulCount = r.GetInt64(2),
                    ActiveCompanies = Convert.ToInt32(r.GetValue(3)),
                });
            return list;
        }

        // ------------------------------------------------------------------
        // Platform overview
        // ------------------------------------------------------------------
        public async Task<PlatformActivityOverviewDto> GetOverviewAsync(int? days)
        {
            var window = Math.Clamp(days ?? _opt.LongWindowDays, 1, 366);
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();

            var companies = await QueryCompaniesAsync(conn, null, null);
            var dto = new PlatformActivityOverviewDto
            {
                WindowDays = window,
                TotalCompanies = companies.Count,
                TotalOrganizations = companies.Select(c => c.OrganizationId).Where(o => o != null).Distinct().Count(),
                CompaniesActiveToday = companies.Count(c => c.ActivityStatus == nameof(PlatformActivityStatus.ActiveToday)),
                CompaniesActive7d = companies.Count(c => c.ActivityStatus is nameof(PlatformActivityStatus.ActiveToday)
                    or nameof(PlatformActivityStatus.Active7Days)),
                CompaniesActive30d = companies.Count(c => c.ActivityStatus is nameof(PlatformActivityStatus.ActiveToday)
                    or nameof(PlatformActivityStatus.Active7Days) or nameof(PlatformActivityStatus.Active30Days)),
                CompaniesInactive30Plus = companies.Count(c => c.ActivityStatus is nameof(PlatformActivityStatus.Inactive30Plus)
                    or nameof(PlatformActivityStatus.NoActivity)),
            };

            await using (var cmd = new NpgsqlCommand(@"
                SELECT count(*) FILTER (WHERE ismeaningful AND occurredatutc > now() - make_interval(days => @D)),
                       count(*) FILTER (WHERE occurredatutc > now() - make_interval(days => @D)),
                       count(*) FILTER (WHERE ismeaningful
                                          AND occurredatutc > now() - make_interval(days => @D * 2)
                                          AND occurredatutc <= now() - make_interval(days => @D))
                FROM platformactivityevents", conn))
            {
                cmd.Parameters.AddWithValue("@D", window);
                await using var r = await cmd.ExecuteReaderAsync();
                if (await r.ReadAsync())
                {
                    dto.MeaningfulEvents = r.GetInt64(0);
                    dto.TotalEvents = r.GetInt64(1);
                    dto.Trend = ActivityMath.ComputeTrend(dto.MeaningfulEvents, r.GetInt64(2), _opt.StablePercentBand);
                }
            }

            await using (var cmd = new NpgsqlCommand(@"
                SELECT count(DISTINCT userid) FILTER (WHERE businessdate > current_date - @Short),
                       count(DISTINCT userid) FILTER (WHERE businessdate > current_date - @Long)
                FROM companyusagedailyusers", conn))
            {
                cmd.Parameters.AddWithValue("@Short", _opt.ShortWindowDays);
                cmd.Parameters.AddWithValue("@Long", _opt.LongWindowDays);
                await using var r = await cmd.ExecuteReaderAsync();
                if (await r.ReadAsync())
                {
                    dto.ActiveUsers7d = Convert.ToInt32(r.GetValue(0));
                    dto.ActiveUsers30d = Convert.ToInt32(r.GetValue(1));
                }
            }

            // Billing / lifecycle KPIs (subscription truth stays in the billing tables;
            // this is read-only aggregation, enforcement remains off).
            await using (var cmd = new NpgsqlCommand(@"
                SELECT
                    (SELECT count(*) FROM organizationbillingaccounts WHERE status = 'Trial'),
                    (SELECT count(*) FROM organizationbillingaccounts WHERE status = 'Active'),
                    (SELECT count(DISTINCT a.id)
                       FROM organizationbillingaccounts a
                       JOIN platforminvoices i ON i.accountid = a.id
                      WHERE i.balance > 0 AND i.duedate < current_date
                        AND i.status NOT IN ('Paid', 'Void')),
                    (SELECT count(*) FROM (
                        SELECT owneruserid FROM farms
                        WHERE coalesce(isdeleted, false) = false AND type IS DISTINCT FROM 'System'
                        GROUP BY owneruserid
                        HAVING min(createdat) >= date_trunc('month', now())) x)", conn))
            {
                await using var r = await cmd.ExecuteReaderAsync();
                if (await r.ReadAsync())
                {
                    dto.TrialOrganizations = Convert.ToInt32(r.GetValue(0));
                    dto.PayingOrganizations = Convert.ToInt32(r.GetValue(1));
                    dto.PastDueOrganizations = Convert.ToInt32(r.GetValue(2));
                    dto.NewOrganizationsThisMonth = Convert.ToInt32(r.GetValue(3));
                }
            }

            dto.ByCategory = await QueryCategoryBreakdownAsync(conn, null, null, window);
            dto.ByCompanyFamily = await QueryGroupedAsync(conn, "companyfamily", window);
            dto.ByBusinessTemplate = await QueryGroupedAsync(conn, "businesstemplatecode", window);
            return dto;
        }

        private static async Task<List<CategoryCountDto>> QueryGroupedAsync(
            NpgsqlConnection conn, string column, int days)
        {
            // column is a fixed identifier chosen by this class, never caller input.
            var list = new List<CategoryCountDto>();
            await using var cmd = new NpgsqlCommand($@"
                SELECT coalesce({column}, '(none)') AS k,
                       count(*) FILTER (WHERE ismeaningful),
                       count(*)
                FROM platformactivityevents
                WHERE occurredatutc > now() - make_interval(days => @D)
                GROUP BY 1 ORDER BY 2 DESC", conn);
            cmd.Parameters.AddWithValue("@D", days);
            await using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Add(new CategoryCountDto
                {
                    Key = r.GetString(0),
                    MeaningfulCount = r.GetInt64(1),
                    TotalCount = r.GetInt64(2),
                });
            return list;
        }

        // ------------------------------------------------------------------
        // Category breakdown / time series / recent feed
        // ------------------------------------------------------------------
        public async Task<List<CategoryCountDto>> GetCategoryBreakdownAsync(
            string? organizationId, string? companyId, int? days)
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            return await QueryCategoryBreakdownAsync(conn, organizationId, companyId,
                Math.Clamp(days ?? _opt.LongWindowDays, 1, 366));
        }

        private static async Task<List<CategoryCountDto>> QueryCategoryBreakdownAsync(
            NpgsqlConnection conn, string? organizationId, string? companyId, int days)
        {
            var list = new List<CategoryCountDto>();
            await using var cmd = new NpgsqlCommand(@"
                SELECT activitycategory,
                       count(*) FILTER (WHERE ismeaningful),
                       count(*)
                FROM platformactivityevents
                WHERE occurredatutc > now() - make_interval(days => @D)
                  AND (@Org::text IS NULL OR organizationid = @Org)
                  AND (@Company::text IS NULL OR companyid = @Company)
                GROUP BY activitycategory ORDER BY 2 DESC, 3 DESC", conn);
            cmd.Parameters.AddWithValue("@D", days);
            cmd.Parameters.AddWithValue("@Org", (object?)organizationId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Company", (object?)companyId ?? DBNull.Value);
            await using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Add(new CategoryCountDto
                {
                    Key = r.GetString(0),
                    MeaningfulCount = r.GetInt64(1),
                    TotalCount = r.GetInt64(2),
                });
            return list;
        }

        public async Task<List<ActivityTimePointDto>> GetTimeSeriesAsync(
            string? organizationId, string? companyId, string? companyFamily, int? days)
        {
            var window = Math.Clamp(days ?? 90, 1, 366);
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            var list = new List<ActivityTimePointDto>();
            await using var cmd = new NpgsqlCommand(@"
                SELECT d.businessdate,
                       sum(d.meaningfulactivitycount),
                       sum(d.totalactivitycount),
                       (SELECT count(DISTINCT x.userid)
                          FROM companyusagedailyusers x
                          JOIN farms xf ON xf.farmid = x.companyid
                         WHERE x.businessdate = d.businessdate
                           AND (@Org::text IS NULL OR xf.owneruserid = @Org)
                           AND (@Company::text IS NULL OR x.companyid = @Company)
                           AND (@Family::text IS NULL OR xf.type = @Family))
                FROM companyusagedaily d
                JOIN farms f ON f.farmid = d.companyid
                WHERE d.businessdate > current_date - @D
                  AND (@Org::text IS NULL OR f.owneruserid = @Org)
                  AND (@Company::text IS NULL OR d.companyid = @Company)
                  AND (@Family::text IS NULL OR f.type = @Family)
                GROUP BY d.businessdate
                ORDER BY d.businessdate", conn);
            cmd.Parameters.AddWithValue("@D", window);
            cmd.Parameters.AddWithValue("@Org", (object?)organizationId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Company", (object?)companyId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Family", (object?)companyFamily ?? DBNull.Value);
            await using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Add(new ActivityTimePointDto
                {
                    BusinessDate = DateOnly.FromDateTime(r.GetDateTime(0)),
                    MeaningfulCount = Convert.ToInt64(r.GetValue(1)),
                    TotalCount = Convert.ToInt64(r.GetValue(2)),
                    ActiveUsers = Convert.ToInt32(r.GetValue(3)),
                });
            return list;
        }

        public async Task<List<RecentActivityDto>> GetRecentMeaningfulAsync(
            int limit, string? companyFamily, string? organizationId, string? companyId)
        {
            limit = Math.Clamp(limit, 1, 500);
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            var list = new List<RecentActivityDto>();
            await using var cmd = new NpgsqlCommand(@"
                SELECT e.id, e.organizationid, e.companyid, f.name, e.companyfamily,
                       e.userid, e.activitycategory, e.activitytype, e.sourcemodule,
                       e.sourcerecordid, e.occurredatutc, e.businessdate, e.ismeaningful, e.source
                FROM platformactivityevents e
                LEFT JOIN farms f ON f.farmid = e.companyid
                WHERE e.ismeaningful
                  AND (@Family::text IS NULL OR e.companyfamily = @Family)
                  AND (@Org::text IS NULL OR e.organizationid = @Org)
                  AND (@Company::text IS NULL OR e.companyid = @Company)
                ORDER BY e.occurredatutc DESC
                LIMIT @Limit", conn);
            cmd.Parameters.AddWithValue("@Family", (object?)companyFamily ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Org", (object?)organizationId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Company", (object?)companyId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Limit", limit);
            await using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Add(new RecentActivityDto
                {
                    Id = r.GetInt64(0),
                    OrganizationId = r.IsDBNull(1) ? null : r.GetString(1),
                    CompanyId = r.IsDBNull(2) ? null : r.GetString(2),
                    CompanyName = r.IsDBNull(3) ? null : r.GetString(3),
                    CompanyFamily = r.IsDBNull(4) ? null : r.GetString(4),
                    UserId = r.IsDBNull(5) ? null : r.GetString(5),
                    Category = r.GetString(6),
                    ActivityType = r.GetString(7),
                    SourceModule = r.GetString(8),
                    SourceRecordId = r.IsDBNull(9) ? null : r.GetString(9),
                    OccurredAtUtc = r.GetDateTime(10),
                    BusinessDate = r.IsDBNull(11) ? null : DateOnly.FromDateTime(r.GetDateTime(11)),
                    IsMeaningful = r.GetBoolean(12),
                    Source = r.GetString(13),
                });
            return list;
        }
    }
}
