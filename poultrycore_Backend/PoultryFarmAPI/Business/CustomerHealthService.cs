// PROMPT 3: the Needs Attention workflow. The sweep turns Health Engine
// verdicts + raw billing/usage signals into customerattentionitems through the
// SQL upsert (duplicate-suppressed), auto-resolves items whose condition
// cleared ("Auto Resolved — Customer Reactivated"), and records health history.
// Queue actions (assign / contacted / note / follow-up / resolve / dismiss)
// each leave an append-only note, and the HTTP layer is also captured by the
// global audit filter.
//
// There is no background scheduler on this platform, so the sweep runs
// on demand: the Admin portal triggers it when the queue page loads, and
// POST api/PlatformHealth/evaluate runs it explicitly.

using Npgsql;
using NpgsqlTypes;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IPlatformHealthService
    {
        Task<HealthSweepResultDto> RunSweepAsync();
        Task<List<AttentionItemDto>> GetQueueAsync(string? status, bool includeNotes);
        Task<AttentionItemDto?> AssignAsync(long id, string actor, string? userId, string? name);
        Task<AttentionItemDto?> MarkContactedAsync(long id, string actor);
        Task<AttentionItemDto?> AddNoteAsync(long id, string actor, string note);
        Task<AttentionItemDto?> SetFollowUpAsync(long id, string actor, DateTime? followUpAtUtc);
        Task<AttentionItemDto?> ResolveAsync(long id, string actor, string? note);
        Task<AttentionItemDto?> DismissAsync(long id, string actor, string reason);
    }

    public class CustomerHealthService : IPlatformHealthService
    {
        private readonly string _cs;
        private readonly PlatformHealthOptions _opt;
        private readonly IPlatformActivityService _activity;
        private readonly ILogger<CustomerHealthService>? _log;

        // Company-level rules whose items auto-resolve with the reactivation note.
        private static readonly string[] ReactivationRules =
            { "PreviouslyActiveNowInactive", "NoActivityAfterSignup" };
        // Other auto-managed company rules.
        private static readonly string[] CompanyRules =
            { "PreviouslyActiveNowInactive", "UsageDownSignificantly", "RepeatedErrors", "NoActiveUsers",
              "FailedCriticalOperations" };
        private static readonly string[] OrgRules =
            { "PastDue", "PaymentFailed", "TrialEndingSoonHighEngagement", "TrialEndingSoonLowEngagement",
              "NoActivityAfterSignup", "SetupIncomplete" };

        public CustomerHealthService(string connectionString, IPlatformActivityService activity,
            PlatformHealthOptions? options = null, ILogger<CustomerHealthService>? log = null)
        {
            _cs = connectionString;
            _activity = activity;
            _opt = options ?? new PlatformHealthOptions();
            _log = log;
        }

        // ------------------------------------------------------------------
        // Sweep
        // ------------------------------------------------------------------
        public async Task<HealthSweepResultDto> RunSweepAsync()
        {
            var orgs = await _activity.GetOrganizationSummariesAsync();  // health already computed
            var result = new HealthSweepResultDto { OrganizationsEvaluated = orgs.Count };
            var now = DateTime.UtcNow;

            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();

            // Prompt 7: failed CRITICAL business operations per company+resource (7d).
            // Only operations whose success would be meaningful activity count —
            // harmless validation noise on reports/settings never raises attention.
            var failedCritical = new Dictionary<string, List<(string Resource, int Count)>>();
            await using (var fc = new NpgsqlCommand(@"
                SELECT lower(farmid), resource, count(*)
                FROM auditlogs
                WHERE status = 'Failed' AND action = 'POST'
                  AND ""timestamp"" > now() - interval '7 days'
                  AND farmid IS NOT NULL AND farmid <> '' AND farmid <> 'Unknown'
                GROUP BY lower(farmid), resource", conn))
            {
                await using var r = await fc.ExecuteReaderAsync();
                while (await r.ReadAsync())
                {
                    var resource = r.IsDBNull(1) ? "" : r.GetString(1);
                    var count = Convert.ToInt32(r.GetValue(2));
                    if (!ActivityClassifier.IsCriticalResource(resource)) continue;
                    if (count < _opt.FailedCriticalOpsMin7d) continue;
                    var key = r.GetString(0);
                    if (!failedCritical.TryGetValue(key, out var list)) failedCritical[key] = list = new();
                    list.Add((resource, count));
                }
            }

            foreach (var o in orgs)
            {
                if (string.IsNullOrEmpty(o.OrganizationId)) continue;
                var orgName = o.OrganizationName ?? o.OrganizationId;
                var triggeredOrg = new List<string>();

                // ---- organization-level rules ----
                if (o.HasPastDueInvoice)
                {
                    triggeredOrg.Add("PastDue");
                    result.ItemsUpserted += await UpsertAsync(conn, o.OrganizationId, null, "PastDue", "High",
                        $"{orgName}: invoice past due",
                        "Has at least one unpaid invoice past its due date.", "PastDue");
                }
                if (o.HasRecentFailedPayment)
                {
                    triggeredOrg.Add("PaymentFailed");
                    result.ItemsUpserted += await UpsertAsync(conn, o.OrganizationId, null, "PaymentFailed", "High",
                        $"{orgName}: payment failed",
                        "A subscription payment failed within the last 7 days.", "PaymentFailed");
                }
                if (o.SubscriptionStatus == "Trial" && o.TrialEndUtc is DateTime te && te > now)
                {
                    var daysLeft = (int)Math.Ceiling((te - now).TotalDays);
                    if (daysLeft <= _opt.TrialEndingSoonDays)
                    {
                        var high = o.MeaningfulActivityCount30d >= _opt.HighEngagementMin30d;
                        var type = high ? "TrialEndingSoonHighEngagement" : "TrialEndingSoonLowEngagement";
                        triggeredOrg.Add(type);
                        result.ItemsUpserted += await UpsertAsync(conn, o.OrganizationId, null, type,
                            high ? "High" : "Medium",
                            high
                                ? $"{orgName}: highly engaged trial ends in {daysLeft} day{(daysLeft == 1 ? "" : "s")}"
                                : $"{orgName}: trial ends in {daysLeft} day{(daysLeft == 1 ? "" : "s")} with low engagement",
                            high
                                ? $"Trial ends in {daysLeft} day(s); {o.MeaningfulActivityCount30d} meaningful actions in the last 30 days and no payment set up — strong sales opportunity."
                                : $"Trial ends in {daysLeft} day(s); only {o.MeaningfulActivityCount30d} meaningful actions in the last 30 days and no payment set up.",
                            type);
                    }
                }
                if (o.FirstMeaningfulActivityAtUtc is null && o.FirstCompanyCreatedAtUtc is DateTime created
                    && (now - created).TotalDays >= _opt.NoActivityAfterSignupDays)
                {
                    triggeredOrg.Add("NoActivityAfterSignup");
                    result.ItemsUpserted += await UpsertAsync(conn, o.OrganizationId, null, "NoActivityAfterSignup", "Medium",
                        $"{orgName}: no activity since signup",
                        $"Signed up {(int)(now - created).TotalDays} days ago and no company has recorded meaningful activity yet.",
                        "NoActivityAfterSignup");
                }
                else if (o.SetupPercent < 100 && o.CompanyCount > 0 && o.FirstMeaningfulActivityAtUtc != null
                    && o.FirstCompanyCreatedAtUtc is DateTime c0 && (now - c0).TotalDays >= _opt.NewAccountDays)
                {
                    var idle = o.Companies.Where(c => c.FirstMeaningfulActivityAtUtc is null)
                        .Select(c => c.CompanyName).ToList();
                    if (idle.Count > 0)
                    {
                        triggeredOrg.Add("SetupIncomplete");
                        result.ItemsUpserted += await UpsertAsync(conn, o.OrganizationId, null, "SetupIncomplete", "Low",
                            $"{orgName}: setup incomplete ({o.SetupPercent}%)",
                            $"Companies never activated: {string.Join(", ", idle)}.", "SetupIncomplete");
                    }
                }

                // Auto-resolve org rules that no longer hold.
                result.ItemsAutoResolved += await AutoResolveAsync(conn, o.OrganizationId, null,
                    OrgRules.Where(t => !triggeredOrg.Contains(t) && ReactivationRules.Contains(t)).ToArray(),
                    "Auto Resolved — Customer Reactivated");
                result.ItemsAutoResolved += await AutoResolveAsync(conn, o.OrganizationId, null,
                    OrgRules.Where(t => !triggeredOrg.Contains(t) && !ReactivationRules.Contains(t)).ToArray(),
                    "Auto Resolved — condition no longer detected");

                await RecordHealthAsync(conn, "Organization", o.OrganizationId, o.Health, o.HealthReasons);

                // ---- company-level rules ----
                foreach (var c in o.Companies)
                {
                    result.CompaniesEvaluated++;
                    var cname = string.IsNullOrWhiteSpace(c.CompanyName) ? c.CompanyId : c.CompanyName;
                    var triggered = new List<string>();

                    var previouslyActiveNowSilent =
                        c.FirstMeaningfulActivityAtUtc != null && c.LastMeaningfulActivityAtUtc is DateTime last
                        && (now - last).TotalDays >= _opt.AtRiskDaysSince;
                    if (previouslyActiveNowSilent)
                    {
                        var days = (int)(now - c.LastMeaningfulActivityAtUtc!.Value).TotalDays;
                        triggered.Add("PreviouslyActiveNowInactive");
                        result.ItemsUpserted += await UpsertAsync(conn, o.OrganizationId, c.CompanyId,
                            "PreviouslyActiveNowInactive", "High",
                            $"{cname}: previously active, now silent",
                            $"No meaningful activity for {days} days; previously recorded {c.Trend.PreviousPeriodCount} meaningful actions in the prior 30-day window.",
                            "PreviouslyActiveNowInactive");
                    }

                    if (c.Trend.Status == nameof(PlatformTrendStatus.Declining)
                        && c.Trend.PercentChange is double pct && pct <= -_opt.UsageDropPercent)
                    {
                        triggered.Add("UsageDownSignificantly");
                        result.ItemsUpserted += await UpsertAsync(conn, o.OrganizationId, c.CompanyId,
                            "UsageDownSignificantly", "Medium",
                            $"{cname}: usage down {Math.Abs(pct):0}%",
                            $"Meaningful activity fell from {c.Trend.PreviousPeriodCount} to {c.Trend.CurrentPeriodCount} over the last 30 days.",
                            "UsageDownSignificantly");
                    }

                    if (c.FailedRequests7d >= _opt.RepeatedErrorsMin7d)
                    {
                        triggered.Add("RepeatedErrors");
                        result.ItemsUpserted += await UpsertAsync(conn, o.OrganizationId, c.CompanyId,
                            "RepeatedErrors", "Medium",
                            $"{cname}: repeated errors",
                            $"{c.FailedRequests7d} failed requests in the last 7 days.", "RepeatedErrors");
                    }

                    if (failedCritical.TryGetValue(c.CompanyId.ToLowerInvariant(), out var fails))
                    {
                        triggered.Add("FailedCriticalOperations");
                        var worst = fails.OrderByDescending(f => f.Count).First();
                        result.ItemsUpserted += await UpsertAsync(conn, o.OrganizationId, c.CompanyId,
                            "FailedCriticalOperations", "High",
                            $"{cname}: {worst.Count} failed {worst.Resource} operations",
                            string.Join("; ", fails.Select(f => $"{f.Count} failed {f.Resource} attempts in the last 7 days")),
                            "FailedCriticalOperations");
                    }

                    if (o.SubscriptionStatus == "Active" && c.FirstMeaningfulActivityAtUtc != null
                        && c.ActiveUsers30d == 0)
                    {
                        triggered.Add("NoActiveUsers");
                        result.ItemsUpserted += await UpsertAsync(conn, o.OrganizationId, c.CompanyId,
                            "NoActiveUsers", "Medium",
                            $"{cname}: paying but no active users",
                            "Subscription is active but no user has produced activity in the last 30 days.",
                            "NoActiveUsers");
                    }

                    result.ItemsAutoResolved += await AutoResolveAsync(conn, o.OrganizationId, c.CompanyId,
                        CompanyRules.Where(t => !triggered.Contains(t) && ReactivationRules.Contains(t)).ToArray(),
                        "Auto Resolved — Customer Reactivated");
                    result.ItemsAutoResolved += await AutoResolveAsync(conn, o.OrganizationId, c.CompanyId,
                        CompanyRules.Where(t => !triggered.Contains(t) && !ReactivationRules.Contains(t)).ToArray(),
                        "Auto Resolved — condition no longer detected");

                    await RecordHealthAsync(conn, "Company", c.CompanyId, c.Health, c.HealthReasons);
                }
            }

            return result;
        }

        private static async Task<int> UpsertAsync(NpgsqlConnection conn, string org, string? company,
            string type, string severity, string title, string reason, string rule)
        {
            await using var cmd = new NpgsqlCommand(
                "SELECT platform_attention_upsert(@Org, @Company, @Type, @Sev, @Title, @Reason, @Rule)", conn);
            cmd.Parameters.AddWithValue("@Org", org);
            cmd.Parameters.AddWithValue("@Company", (object?)company ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Type", type);
            cmd.Parameters.AddWithValue("@Sev", severity);
            cmd.Parameters.AddWithValue("@Title", title);
            cmd.Parameters.AddWithValue("@Reason", reason);
            cmd.Parameters.AddWithValue("@Rule", rule);
            await cmd.ExecuteScalarAsync();
            return 1;
        }

        private static async Task<int> AutoResolveAsync(NpgsqlConnection conn, string org, string? company,
            string[] types, string note)
        {
            if (types.Length == 0) return 0;
            await using var cmd = new NpgsqlCommand(
                "SELECT platform_attention_autoresolve(@Org, @Company, @Types, @Note)", conn);
            cmd.Parameters.AddWithValue("@Org", org);
            cmd.Parameters.AddWithValue("@Company", (object?)company ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Types", types);
            cmd.Parameters.AddWithValue("@Note", note);
            var n = await cmd.ExecuteScalarAsync();
            return n is int i ? i : Convert.ToInt32(n ?? 0);
        }

        private static async Task RecordHealthAsync(NpgsqlConnection conn, string scope, string subject,
            string? health, List<string> reasons)
        {
            if (string.IsNullOrEmpty(health)) return;
            await using var cmd = new NpgsqlCommand(
                "SELECT platform_health_record(@Scope, @Subject, @Health, @Reasons)", conn);
            cmd.Parameters.AddWithValue("@Scope", scope);
            cmd.Parameters.AddWithValue("@Subject", subject);
            cmd.Parameters.AddWithValue("@Health", health);
            cmd.Parameters.AddWithValue("@Reasons", string.Join("; ", reasons));
            await cmd.ExecuteNonQueryAsync();
        }

        // ------------------------------------------------------------------
        // Queue
        // ------------------------------------------------------------------
        public async Task<List<AttentionItemDto>> GetQueueAsync(string? status, bool includeNotes)
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            var list = new List<AttentionItemDto>();
            await using (var cmd = new NpgsqlCommand(@"
                SELECT i.id, i.organizationid,
                       coalesce(nullif(u.businessofficename, ''), u.username),
                       i.companyid, f.name,
                       i.attentiontype, i.severity, i.title, i.reason, i.sourcerule, i.status,
                       i.assignedtouserid, i.assignedtoname, i.followupatutc,
                       i.detectedatutc, i.lastdetectedatutc,
                       i.resolvedatutc, i.resolvedby, i.resolutionnote, i.revenueatrisk
                FROM customerattentionitems i
                LEFT JOIN aspnetusers u ON u.id = i.organizationid
                LEFT JOIN farms f ON f.farmid = i.companyid
                WHERE (@Status::text IS NULL AND i.status IN ('Open', 'Assigned', 'Contacted'))
                   OR (@Status::text = 'All')
                   OR (i.status = @Status)
                ORDER BY CASE i.severity WHEN 'High' THEN 0 WHEN 'Medium' THEN 1 ELSE 2 END,
                         i.lastdetectedatutc DESC
                LIMIT 500", conn))
            {
                cmd.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);
                await using var r = await cmd.ExecuteReaderAsync();
                while (await r.ReadAsync())
                {
                    list.Add(new AttentionItemDto
                    {
                        Id = r.GetInt64(0),
                        OrganizationId = r.GetString(1),
                        OrganizationName = r.IsDBNull(2) ? null : r.GetString(2),
                        CompanyId = r.IsDBNull(3) ? null : r.GetString(3),
                        CompanyName = r.IsDBNull(4) ? null : r.GetString(4),
                        AttentionType = r.GetString(5),
                        Severity = r.GetString(6),
                        Title = r.GetString(7),
                        Reason = r.GetString(8),
                        SourceRule = r.GetString(9),
                        Status = r.GetString(10),
                        AssignedToUserId = r.IsDBNull(11) ? null : r.GetString(11),
                        AssignedToName = r.IsDBNull(12) ? null : r.GetString(12),
                        FollowUpAtUtc = r.IsDBNull(13) ? null : r.GetDateTime(13),
                        DetectedAtUtc = r.GetDateTime(14),
                        LastDetectedAtUtc = r.GetDateTime(15),
                        ResolvedAtUtc = r.IsDBNull(16) ? null : r.GetDateTime(16),
                        ResolvedBy = r.IsDBNull(17) ? null : r.GetString(17),
                        ResolutionNote = r.IsDBNull(18) ? null : r.GetString(18),
                        RevenueAtRisk = r.IsDBNull(19) ? null : r.GetDecimal(19),
                    });
                }
            }

            if (includeNotes && list.Count > 0)
            {
                var ids = list.Select(i => i.Id).ToArray();
                await using var cmd = new NpgsqlCommand(@"
                    SELECT itemid, id, note, createdby, createdatutc
                    FROM customerattentionnotes WHERE itemid = ANY(@Ids)
                    ORDER BY createdatutc", conn);
                cmd.Parameters.AddWithValue("@Ids", ids);
                await using var r = await cmd.ExecuteReaderAsync();
                var byItem = list.ToDictionary(i => i.Id);
                while (await r.ReadAsync())
                {
                    if (byItem.TryGetValue(r.GetInt64(0), out var item))
                        item.Notes.Add(new AttentionNoteDto
                        {
                            Id = r.GetInt64(1),
                            Note = r.GetString(2),
                            CreatedBy = r.GetString(3),
                            CreatedAtUtc = r.GetDateTime(4),
                        });
                }
            }
            return list;
        }

        // ------------------------------------------------------------------
        // Actions — each leaves an append-only note (plus the HTTP audit trail)
        // ------------------------------------------------------------------
        public Task<AttentionItemDto?> AssignAsync(long id, string actor, string? userId, string? name) =>
            MutateAsync(id, actor,
                "UPDATE customerattentionitems SET status = 'Assigned', assignedtouserid = @P1, assignedtoname = @P2, updatedatutc = now() WHERE id = @Id AND status IN ('Open','Assigned','Contacted')",
                new object?[] { userId ?? actor, name ?? userId ?? actor },
                $"Assigned to {name ?? userId ?? actor}");

        public Task<AttentionItemDto?> MarkContactedAsync(long id, string actor) =>
            MutateAsync(id, actor,
                "UPDATE customerattentionitems SET status = 'Contacted', updatedatutc = now() WHERE id = @Id AND status IN ('Open','Assigned','Contacted')",
                Array.Empty<object?>(), "Marked contacted");

        public Task<AttentionItemDto?> AddNoteAsync(long id, string actor, string note) =>
            MutateAsync(id, actor, null, Array.Empty<object?>(), note);

        public Task<AttentionItemDto?> SetFollowUpAsync(long id, string actor, DateTime? followUpAtUtc) =>
            MutateAsync(id, actor,
                "UPDATE customerattentionitems SET followupatutc = @P1, updatedatutc = now() WHERE id = @Id",
                new object?[] { followUpAtUtc },
                followUpAtUtc is DateTime f ? $"Follow-up set for {f:yyyy-MM-dd}" : "Follow-up cleared");

        public Task<AttentionItemDto?> ResolveAsync(long id, string actor, string? note) =>
            MutateAsync(id, actor,
                "UPDATE customerattentionitems SET status = 'Resolved', resolvedatutc = now(), resolvedby = @Actor, resolutionnote = @P1, updatedatutc = now() WHERE id = @Id AND status IN ('Open','Assigned','Contacted')",
                new object?[] { note },
                $"Resolved{(string.IsNullOrWhiteSpace(note) ? "" : $": {note}")}");

        public Task<AttentionItemDto?> DismissAsync(long id, string actor, string reason) =>
            MutateAsync(id, actor,
                "UPDATE customerattentionitems SET status = 'Dismissed', resolvedatutc = now(), resolvedby = @Actor, resolutionnote = @P1, updatedatutc = now() WHERE id = @Id AND status IN ('Open','Assigned','Contacted')",
                new object?[] { reason },
                $"Dismissed: {reason}");

        private async Task<AttentionItemDto?> MutateAsync(long id, string actor, string? sql,
            object?[] args, string note)
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            await using var tx = await conn.BeginTransactionAsync();

            if (sql != null)
            {
                await using var cmd = new NpgsqlCommand(sql, conn, (NpgsqlTransaction)tx);
                cmd.Parameters.AddWithValue("@Id", id);
                if (sql.Contains("@Actor")) cmd.Parameters.AddWithValue("@Actor", actor);
                for (var i = 0; i < args.Length; i++)
                {
                    if (args[i] is DateTime dt)
                        cmd.Parameters.Add(new NpgsqlParameter($"@P{i + 1}", NpgsqlDbType.TimestampTz) { Value = dt });
                    else
                        cmd.Parameters.AddWithValue($"@P{i + 1}", (object?)args[i] ?? DBNull.Value);
                }
                var n = await cmd.ExecuteNonQueryAsync();
                if (n == 0 && !sql.Contains("followupatutc"))
                {
                    await tx.RollbackAsync();
                    return null;   // not found or already closed
                }
            }

            await using (var noteCmd = new NpgsqlCommand(@"
                INSERT INTO customerattentionnotes (itemid, note, createdby)
                SELECT @Id, @Note, @Actor WHERE EXISTS (SELECT 1 FROM customerattentionitems WHERE id = @Id)",
                conn, (NpgsqlTransaction)tx))
            {
                noteCmd.Parameters.AddWithValue("@Id", id);
                noteCmd.Parameters.AddWithValue("@Note", note);
                noteCmd.Parameters.AddWithValue("@Actor", actor);
                var inserted = await noteCmd.ExecuteNonQueryAsync();
                if (inserted == 0)
                {
                    await tx.RollbackAsync();
                    return null;
                }
            }
            await tx.CommitAsync();

            var all = await GetQueueAsync("All", includeNotes: true);
            return all.FirstOrDefault(i => i.Id == id);
        }
    }
}
