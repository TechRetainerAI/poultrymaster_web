// PROMPT 7: platform operations — customer-impact error intelligence (derived
// from the existing auditlogs trail; deep logs stay in GCP Cloud Logging),
// deterministic security monitoring, scoped feature flags with full audit,
// release tracking and system health. No observability platform is rebuilt
// here and no infrastructure secrets are exposed.

using System.Text;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    // ------------------------------------------------------------------
    // Feature flag resolution — pure, most-specific-scope-wins (unit-tested).
    // Precedence: User > Company > Organization > BusinessTemplate >
    //             CompanyFamily > Market > Global rule > flag default.
    // The master switch (enabled=false) always wins with OFF.
    // ------------------------------------------------------------------
    public sealed record FlagRule(string ScopeType, string ScopeValue, bool Enabled);
    public sealed record FlagContext(string? UserId, string? CompanyId, string? OrganizationId,
        string? BusinessTemplate, string? CompanyFamily, string? Market);

    public static class FlagMath
    {
        private static readonly string[] Precedence =
            { "User", "Company", "Organization", "BusinessTemplate", "CompanyFamily", "Market", "Global" };

        public static (bool Enabled, string MatchedScope) Resolve(
            bool masterEnabled, bool defaultOn, IReadOnlyList<FlagRule> rules, FlagContext ctx)
        {
            if (!masterEnabled) return (false, "MasterOff");
            foreach (var scope in Precedence)
            {
                var value = scope switch
                {
                    "User" => ctx.UserId,
                    "Company" => ctx.CompanyId,
                    "Organization" => ctx.OrganizationId,
                    "BusinessTemplate" => ctx.BusinessTemplate,
                    "CompanyFamily" => ctx.CompanyFamily,
                    "Market" => ctx.Market,
                    _ => "",
                };
                if (value is null) continue;
                var rule = rules.FirstOrDefault(r =>
                    string.Equals(r.ScopeType, scope, StringComparison.OrdinalIgnoreCase)
                    && string.Equals(r.ScopeValue, value, StringComparison.OrdinalIgnoreCase));
                if (rule != null) return (rule.Enabled, scope);
            }
            return (defaultOn, "Default");
        }
    }

    public interface IPlatformOpsService
    {
        Task<ErrorDashboardDto> GetErrorDashboardAsync(int hours);
        Task<CompanyErrorsDto> GetCompanyErrorsAsync(string companyId);
        Task<int> RunSecuritySweepAsync();
        Task<List<SecurityEventDto>> GetSecurityEventsAsync(bool refresh);
        Task<List<FeatureFlagDto>> GetFlagsAsync();
        Task<FeatureFlagDto> CreateFlagAsync(FeatureFlagRequest req, string actor);
        Task<FeatureFlagDto?> SetFlagEnabledAsync(string flagKey, bool enabled, string actor, string? reason);
        Task<FeatureFlagDto?> SetRuleAsync(string flagKey, FlagRuleRequest req, string actor);
        Task<FeatureFlagDto?> RemoveRuleAsync(string flagKey, string scopeType, string scopeValue, string actor, string? reason);
        Task<List<FlagAuditDto>> GetFlagAuditAsync(string? flagKey);
        Task<FlagEvaluationDto> EvaluateFlagAsync(string flagKey, string? userId, string? companyId);
        Task RegisterReleaseAsync(string service, string version);
        Task<List<ReleaseDto>> GetReleasesAsync();
        Task<SystemHealthDto> GetSystemHealthAsync();
        Task<string> ExportCsvAsync(string dataset);
    }

    public class PlatformOpsService : IPlatformOpsService
    {
        private readonly string _cs;
        private readonly IPlatformActivityService _activity;
        private readonly ILogger<PlatformOpsService>? _log;

        public PlatformOpsService(string connectionString, IPlatformActivityService activity,
            ILogger<PlatformOpsService>? log = null)
        {
            _cs = connectionString;
            _activity = activity;
            _log = log;
        }

        // ------------------------------------------------------------------
        // Error intelligence (from auditlogs; GCP Cloud Logging holds the rest)
        // ------------------------------------------------------------------
        public async Task<ErrorDashboardDto> GetErrorDashboardAsync(int hours)
        {
            hours = Math.Clamp(hours, 1, 24 * 30);
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            var dto = new ErrorDashboardDto { WindowHours = hours };

            await using (var cmd = new NpgsqlCommand(@"
                SELECT count(*),
                       count(DISTINCT lower(a.farmid)) FILTER (WHERE a.farmid <> '' AND a.farmid <> 'Unknown'),
                       count(DISTINCT f.owneruserid)
                FROM auditlogs a
                LEFT JOIN farms f ON f.farmid = a.farmid
                WHERE a.status = 'Failed' AND a.""timestamp"" > now() - make_interval(hours => @H)", conn))
            {
                cmd.Parameters.AddWithValue("@H", hours);
                await using var r = await cmd.ExecuteReaderAsync();
                if (await r.ReadAsync())
                {
                    dto.TotalErrors = Convert.ToInt64(r.GetValue(0));
                    dto.AffectedCompanies = Convert.ToInt32(r.GetValue(1));
                    dto.AffectedOrganizations = Convert.ToInt32(r.GetValue(2));
                }
            }

            await using (var cmd = new NpgsqlCommand(@"
                SELECT resource, action, count(*),
                       count(DISTINCT lower(farmid)) FILTER (WHERE farmid <> '' AND farmid <> 'Unknown')
                FROM auditlogs
                WHERE status = 'Failed' AND ""timestamp"" > now() - make_interval(hours => @H)
                GROUP BY resource, action ORDER BY 3 DESC LIMIT 25", conn))
            {
                cmd.Parameters.AddWithValue("@H", hours);
                await using var r = await cmd.ExecuteReaderAsync();
                while (await r.ReadAsync())
                {
                    var resource = r.IsDBNull(0) ? "" : r.GetString(0);
                    var row = new ErrorGroupDto
                    {
                        Resource = resource,
                        Operation = $"{(r.IsDBNull(1) ? "?" : r.GetString(1))} {resource}",
                        Module = ActivityClassifier.ModuleForResource(resource) ?? "Other",
                        Count = Convert.ToInt64(r.GetValue(2)),
                        AffectedCompanies = Convert.ToInt32(r.GetValue(3)),
                        IsCriticalOperation = ActivityClassifier.IsCriticalResource(resource),
                    };
                    dto.TopErrorTypes.Add(row);
                }
            }
            dto.FailedBusinessOperations = dto.TopErrorTypes.Where(t => t.IsCriticalOperation).Sum(t => t.Count);
            dto.TopModules = dto.TopErrorTypes
                .GroupBy(t => t.Module)
                .Select(g => new CategoryCountDto { Key = g.Key, MeaningfulCount = g.Sum(x => x.Count), TotalCount = g.Sum(x => x.Count) })
                .OrderByDescending(x => x.MeaningfulCount).ToList();

            // Trend: errors per day over the window (max 14 points).
            await using (var cmd = new NpgsqlCommand(@"
                SELECT (""timestamp"" AT TIME ZONE 'UTC')::date, count(*)
                FROM auditlogs
                WHERE status = 'Failed' AND ""timestamp"" > now() - make_interval(hours => @H)
                GROUP BY 1 ORDER BY 1", conn))
            {
                cmd.Parameters.AddWithValue("@H", Math.Max(hours, 24 * 14));
                await using var r = await cmd.ExecuteReaderAsync();
                while (await r.ReadAsync())
                    dto.DailyTrend.Add(new ActivityTimePointDto
                    {
                        BusinessDate = DateOnly.FromDateTime(r.GetDateTime(0)),
                        MeaningfulCount = Convert.ToInt64(r.GetValue(1)),
                        TotalCount = Convert.ToInt64(r.GetValue(1)),
                    });
            }

            // Errors by release (releases registered since migration 352; errors are
            // attributed by time window between release first-seen stamps).
            var releases = await GetReleasesAsync();
            foreach (var rel in releases.Where(x => x.Service == "farm-api").Take(5))
                dto.ByRelease.Add(new CategoryCountDto
                {
                    Key = rel.Version,
                    MeaningfulCount = rel.FailedOpsAfter ?? 0,
                    TotalCount = rel.TotalOpsAfter ?? 0,
                });
            return dto;
        }

        public async Task<CompanyErrorsDto> GetCompanyErrorsAsync(string companyId)
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            var dto = new CompanyErrorsDto { CompanyId = companyId };
            await using (var cmd = new NpgsqlCommand(@"
                SELECT count(*) FILTER (WHERE ""timestamp"" > now() - interval '24 hours'),
                       count(*) FILTER (WHERE ""timestamp"" > now() - interval '7 days'),
                       count(*) FILTER (WHERE ""timestamp"" > now() - interval '7 days' AND action = 'POST')
                FROM auditlogs
                WHERE status = 'Failed' AND lower(farmid) = lower(@C)", conn))
            {
                cmd.Parameters.AddWithValue("@C", companyId);
                await using var r = await cmd.ExecuteReaderAsync();
                if (await r.ReadAsync())
                {
                    dto.Errors24h = Convert.ToInt64(r.GetValue(0));
                    dto.Errors7d = Convert.ToInt64(r.GetValue(1));
                    dto.FailedOperations7d = Convert.ToInt64(r.GetValue(2));
                }
            }
            await using (var cmd = new NpgsqlCommand(@"
                SELECT id, resource, action, details, ""timestamp""
                FROM auditlogs
                WHERE status = 'Failed' AND lower(farmid) = lower(@C)
                ORDER BY ""timestamp"" DESC LIMIT 20", conn))
            {
                cmd.Parameters.AddWithValue("@C", companyId);
                await using var r = await cmd.ExecuteReaderAsync();
                while (await r.ReadAsync())
                    dto.Recent.Add(new CompanyErrorRowDto
                    {
                        CorrelationId = r.GetValue(0)?.ToString() ?? "",   // audit row id doubles as the correlation handle
                        Resource = r.IsDBNull(1) ? "" : r.GetString(1),
                        Operation = r.IsDBNull(2) ? "" : r.GetString(2),
                        Summary = r.IsDBNull(3) ? "" : Truncate(r.GetString(3), 140),
                        OccurredAtUtc = r.GetDateTime(4),
                    });
            }
            dto.DeepLogsHint = "Full technical logs: GCP Cloud Logging (project project-0d67b82a…, service poultrymaster-farm-api) — requires GCP access.";
            return dto;
        }

        private static string Truncate(string s, int n) => s.Length <= n ? s : s[..n] + "…";

        // ------------------------------------------------------------------
        // Security monitoring — deterministic detections, flagged for review
        // ------------------------------------------------------------------
        public async Task<int> RunSecuritySweepAsync()
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            var raised = 0;

            // Repeated failed logins (Identity lockout counters).
            await using (var cmd = new NpgsqlCommand(@"
                SELECT id, coalesce(nullif(username, ''), email), accessfailedcount
                FROM aspnetusers WHERE accessfailedcount >= 3", conn))
            {
                await using var r = await cmd.ExecuteReaderAsync();
                var rows = new List<(string Id, string Name, int Count)>();
                while (await r.ReadAsync())
                    rows.Add((r.GetString(0), r.IsDBNull(1) ? "?" : r.GetString(1), Convert.ToInt32(r.GetValue(2))));
                foreach (var row in rows)
                    raised += await RaiseAsync(conn, "RepeatedFailedLogins",
                        row.Count >= 5 ? "Critical" : "Warning", null, null, row.Id,
                        $"Repeated failed logins: {row.Name}",
                        $"{row.Count} consecutive failed login attempts (Identity lockout counter). Review — not an automatic fraud claim.");
            }

            // Platform-admin IAM changes + attempted-but-denied platform-admin operations (audit trail).
            await using (var cmd = new NpgsqlCommand(@"
                SELECT userid, username, resource, status, count(*)
                FROM auditlogs
                WHERE ""timestamp"" > now() - interval '7 days'
                  AND resource IN ('Iam', 'PlatformBillingAdmin', 'PlatformBillingAdminApp', 'PlatformFarms')
                GROUP BY userid, username, resource, status", conn))
            {
                await using var r = await cmd.ExecuteReaderAsync();
                var rows = new List<(string? User, string? Name, string Resource, string Status, long Count)>();
                while (await r.ReadAsync())
                    rows.Add((r.IsDBNull(0) ? null : r.GetString(0), r.IsDBNull(1) ? null : r.GetString(1),
                        r.IsDBNull(2) ? "" : r.GetString(2), r.IsDBNull(3) ? "" : r.GetString(3), Convert.ToInt64(r.GetValue(4))));
                foreach (var row in rows)
                {
                    if (row.Status == "Failed")
                        raised += await RaiseAsync(conn, "AdminSurfaceDenied", "Warning", null, null, row.User,
                            $"Failed platform-admin operations: {row.Name ?? row.User ?? "unknown"}",
                            $"{row.Count} failed request(s) against {row.Resource} in 7 days — possible unauthorized attempt, review.");
                    else if (row.Resource == "Iam")
                        raised += await RaiseAsync(conn, "PermissionChange", "Warning", null, null, row.User,
                            $"IAM changes by {row.Name ?? row.User ?? "unknown"}",
                            $"{row.Count} role/permission change request(s) in 7 days (see Platform Activity Audit for the rows).");
                    else
                        raised += await RaiseAsync(conn, "PaymentConfigChange", "Warning", null, null, row.User,
                            $"Billing administration by {row.Name ?? row.User ?? "unknown"}",
                            $"{row.Count} {row.Resource} change(s) in 7 days (prices/discounts/credits/company state).");
                }
            }

            // Billing market changes (customer-initiated; Info).
            await using (var cmd = new NpgsqlCommand(@"
                SELECT owneruserid, pendingmarketcode, pendingmarketeffective
                FROM organizationbillingaccounts WHERE pendingmarketcode IS NOT NULL", conn))
            {
                await using var r = await cmd.ExecuteReaderAsync();
                var rows = new List<(string Owner, string Market, DateTime? Eff)>();
                while (await r.ReadAsync())
                    rows.Add((r.GetString(0), r.GetString(1), r.IsDBNull(2) ? null : r.GetDateTime(2)));
                foreach (var row in rows)
                    raised += await RaiseAsync(conn, "BillingMarketChange", "Info", row.Owner, null, null,
                        "Billing market change pending",
                        $"Change to {row.Market} effective {row.Eff:yyyy-MM-dd} — verify pricing and tax are intended.");
            }

            // NOTE: support impersonation events do not exist (view-as was deliberately
            // not implemented — see Prompt 5); mass-export events come from the audited
            // export endpoint and appear in auditlogs under PlatformOps.
            return raised;
        }

        private static async Task<int> RaiseAsync(NpgsqlConnection conn, string type, string severity,
            string? org, string? company, string? user, string title, string detail)
        {
            await using var cmd = new NpgsqlCommand(
                "SELECT platform_security_event(@T, @S, @O, @C, @U, @Title, @Detail)", conn);
            cmd.Parameters.AddWithValue("@T", type);
            cmd.Parameters.AddWithValue("@S", severity);
            cmd.Parameters.AddWithValue("@O", (object?)org ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@C", (object?)company ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@U", (object?)user ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Title", title);
            cmd.Parameters.AddWithValue("@Detail", detail);
            await cmd.ExecuteScalarAsync();
            return 1;
        }

        public async Task<List<SecurityEventDto>> GetSecurityEventsAsync(bool refresh)
        {
            if (refresh) await RunSecuritySweepAsync();
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            var list = new List<SecurityEventDto>();
            await using var cmd = new NpgsqlCommand(@"
                SELECT id, eventtype, severity, organizationid, companyid, userid,
                       title, detail, occurrences, firstseenatutc, lastseenatutc, status
                FROM platformsecurityevents
                ORDER BY CASE severity WHEN 'Critical' THEN 0 WHEN 'Warning' THEN 1 ELSE 2 END,
                         lastseenatutc DESC
                LIMIT 300", conn);
            await using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Add(new SecurityEventDto
                {
                    Id = r.GetInt64(0),
                    EventType = r.GetString(1),
                    Severity = r.GetString(2),
                    OrganizationId = r.IsDBNull(3) ? null : r.GetString(3),
                    CompanyId = r.IsDBNull(4) ? null : r.GetString(4),
                    UserId = r.IsDBNull(5) ? null : r.GetString(5),
                    Title = r.GetString(6),
                    Detail = r.IsDBNull(7) ? null : r.GetString(7),
                    Occurrences = Convert.ToInt32(r.GetValue(8)),
                    FirstSeenAtUtc = r.GetDateTime(9),
                    LastSeenAtUtc = r.GetDateTime(10),
                    Status = r.GetString(11),
                });
            return list;
        }

        // ------------------------------------------------------------------
        // Feature flags (product rollout only — never auth/payment integrity)
        // ------------------------------------------------------------------
        public async Task<List<FeatureFlagDto>> GetFlagsAsync()
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            return await LoadFlagsAsync(conn, null);
        }

        private static async Task<List<FeatureFlagDto>> LoadFlagsAsync(NpgsqlConnection conn, string? key)
        {
            var flags = new List<FeatureFlagDto>();
            await using (var cmd = new NpgsqlCommand(@"
                SELECT id, flagkey, name, description, enabled, defaulton, createdby, createdatutc
                FROM platformfeatureflags
                WHERE @K::text IS NULL OR flagkey = @K
                ORDER BY flagkey", conn))
            {
                cmd.Parameters.AddWithValue("@K", (object?)key ?? DBNull.Value);
                await using var r = await cmd.ExecuteReaderAsync();
                while (await r.ReadAsync())
                    flags.Add(new FeatureFlagDto
                    {
                        Id = Convert.ToInt32(r.GetValue(0)),
                        FlagKey = r.GetString(1),
                        Name = r.GetString(2),
                        Description = r.IsDBNull(3) ? null : r.GetString(3),
                        Enabled = r.GetBoolean(4),
                        DefaultOn = r.GetBoolean(5),
                        CreatedBy = r.GetString(6),
                        CreatedAtUtc = r.GetDateTime(7),
                    });
            }
            if (flags.Count == 0) return flags;
            var ids = flags.Select(f => f.Id).ToArray();
            await using (var cmd = new NpgsqlCommand(@"
                SELECT flagid, scopetype, scopevalue, enabled, createdby, createdatutc
                FROM platformfeatureflagrules WHERE flagid = ANY(@Ids) ORDER BY id", conn))
            {
                cmd.Parameters.AddWithValue("@Ids", ids);
                await using var r = await cmd.ExecuteReaderAsync();
                var byId = flags.ToDictionary(f => f.Id);
                while (await r.ReadAsync())
                    if (byId.TryGetValue(Convert.ToInt32(r.GetValue(0)), out var f))
                        f.Rules.Add(new FlagRuleDto
                        {
                            ScopeType = r.GetString(1),
                            ScopeValue = r.GetString(2),
                            Enabled = r.GetBoolean(3),
                            CreatedBy = r.GetString(4),
                            CreatedAtUtc = r.GetDateTime(5),
                        });
            }
            return flags;
        }

        public async Task<FeatureFlagDto> CreateFlagAsync(FeatureFlagRequest req, string actor)
        {
            if (string.IsNullOrWhiteSpace(req.FlagKey)) throw new ArgumentException("flagKey is required");
            if (string.IsNullOrWhiteSpace(req.Name)) throw new ArgumentException("name is required");
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            await using (var cmd = new NpgsqlCommand(@"
                INSERT INTO platformfeatureflags (flagkey, name, description, enabled, defaulton, createdby)
                VALUES (@K, @N, @D, false, @Def, @By)
                ON CONFLICT (flagkey) DO NOTHING", conn))
            {
                cmd.Parameters.AddWithValue("@K", req.FlagKey.Trim());
                cmd.Parameters.AddWithValue("@N", req.Name.Trim());
                cmd.Parameters.AddWithValue("@D", (object?)req.Description ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@Def", req.DefaultOn);
                cmd.Parameters.AddWithValue("@By", actor);
                if (await cmd.ExecuteNonQueryAsync() == 0)
                    throw new ArgumentException($"Flag '{req.FlagKey}' already exists.");
            }
            await AuditFlagAsync(conn, req.FlagKey.Trim(), "Created", null, null, null, "false", actor, req.Reason);
            return (await LoadFlagsAsync(conn, req.FlagKey.Trim())).First();
        }

        public async Task<FeatureFlagDto?> SetFlagEnabledAsync(string flagKey, bool enabled, string actor, string? reason)
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            await using (var cmd = new NpgsqlCommand(@"
                UPDATE platformfeatureflags SET enabled = @E, updatedatutc = now() WHERE flagkey = @K", conn))
            {
                cmd.Parameters.AddWithValue("@K", flagKey);
                cmd.Parameters.AddWithValue("@E", enabled);
                if (await cmd.ExecuteNonQueryAsync() == 0) return null;
            }
            await AuditFlagAsync(conn, flagKey, enabled ? "Enabled" : "Disabled", null, null,
                (!enabled).ToString(), enabled.ToString(), actor, reason);
            return (await LoadFlagsAsync(conn, flagKey)).FirstOrDefault();
        }

        public async Task<FeatureFlagDto?> SetRuleAsync(string flagKey, FlagRuleRequest req, string actor)
        {
            var validScopes = new[] { "Global", "Market", "CompanyFamily", "BusinessTemplate", "Organization", "Company", "User" };
            if (!validScopes.Contains(req.ScopeType, StringComparer.OrdinalIgnoreCase))
                throw new ArgumentException($"Unknown scope '{req.ScopeType}'");
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            await using (var cmd = new NpgsqlCommand(@"
                INSERT INTO platformfeatureflagrules (flagid, scopetype, scopevalue, enabled, createdby)
                SELECT id, @S, @V, @E, @By FROM platformfeatureflags WHERE flagkey = @K
                ON CONFLICT (flagid, scopetype, scopevalue)
                DO UPDATE SET enabled = excluded.enabled, createdby = excluded.createdby, createdatutc = now()", conn))
            {
                cmd.Parameters.AddWithValue("@K", flagKey);
                cmd.Parameters.AddWithValue("@S", validScopes.First(s => string.Equals(s, req.ScopeType, StringComparison.OrdinalIgnoreCase)));
                cmd.Parameters.AddWithValue("@V", req.ScopeValue ?? "");
                cmd.Parameters.AddWithValue("@E", req.Enabled);
                cmd.Parameters.AddWithValue("@By", actor);
                if (await cmd.ExecuteNonQueryAsync() == 0) return null;
            }
            await AuditFlagAsync(conn, flagKey, "RuleSet", req.ScopeType, req.ScopeValue, null,
                req.Enabled.ToString(), actor, req.Reason);
            return (await LoadFlagsAsync(conn, flagKey)).FirstOrDefault();
        }

        public async Task<FeatureFlagDto?> RemoveRuleAsync(string flagKey, string scopeType, string scopeValue, string actor, string? reason)
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            await using (var cmd = new NpgsqlCommand(@"
                DELETE FROM platformfeatureflagrules r USING platformfeatureflags f
                WHERE r.flagid = f.id AND f.flagkey = @K AND r.scopetype = @S AND r.scopevalue = @V", conn))
            {
                cmd.Parameters.AddWithValue("@K", flagKey);
                cmd.Parameters.AddWithValue("@S", scopeType);
                cmd.Parameters.AddWithValue("@V", scopeValue ?? "");
                if (await cmd.ExecuteNonQueryAsync() == 0) return null;
            }
            await AuditFlagAsync(conn, flagKey, "RuleRemoved", scopeType, scopeValue, null, null, actor, reason);
            return (await LoadFlagsAsync(conn, flagKey)).FirstOrDefault();
        }

        private static async Task AuditFlagAsync(NpgsqlConnection conn, string key, string action,
            string? scopeType, string? scopeValue, string? oldValue, string? newValue, string actor, string? reason)
        {
            await using var cmd = new NpgsqlCommand(@"
                INSERT INTO platformfeatureflagaudit
                    (flagkey, action, scopetype, scopevalue, oldvalue, newvalue, changedby, reason)
                VALUES (@K, @A, @S, @V, @O, @N, @By, @R)", conn);
            cmd.Parameters.AddWithValue("@K", key);
            cmd.Parameters.AddWithValue("@A", action);
            cmd.Parameters.AddWithValue("@S", (object?)scopeType ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@V", (object?)scopeValue ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@O", (object?)oldValue ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@N", (object?)newValue ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@By", actor);
            cmd.Parameters.AddWithValue("@R", (object?)reason ?? DBNull.Value);
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<List<FlagAuditDto>> GetFlagAuditAsync(string? flagKey)
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            var list = new List<FlagAuditDto>();
            await using var cmd = new NpgsqlCommand(@"
                SELECT flagkey, action, scopetype, scopevalue, oldvalue, newvalue, changedby, reason, atutc
                FROM platformfeatureflagaudit
                WHERE @K::text IS NULL OR flagkey = @K
                ORDER BY atutc DESC LIMIT 200", conn);
            cmd.Parameters.AddWithValue("@K", (object?)flagKey ?? DBNull.Value);
            await using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Add(new FlagAuditDto
                {
                    FlagKey = r.GetString(0),
                    Action = r.GetString(1),
                    ScopeType = r.IsDBNull(2) ? null : r.GetString(2),
                    ScopeValue = r.IsDBNull(3) ? null : r.GetString(3),
                    OldValue = r.IsDBNull(4) ? null : r.GetString(4),
                    NewValue = r.IsDBNull(5) ? null : r.GetString(5),
                    ChangedBy = r.GetString(6),
                    Reason = r.IsDBNull(7) ? null : r.GetString(7),
                    AtUtc = r.GetDateTime(8),
                });
            return list;
        }

        public async Task<FlagEvaluationDto> EvaluateFlagAsync(string flagKey, string? userId, string? companyId)
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            var flags = await LoadFlagsAsync(conn, flagKey);
            if (flags.Count == 0)
                return new FlagEvaluationDto { FlagKey = flagKey, Enabled = false, MatchedScope = "FlagNotFound" };
            var flag = flags[0];

            string? org = null, family = null, template = null, market = null;
            if (!string.IsNullOrWhiteSpace(companyId))
            {
                await using var cmd = new NpgsqlCommand(@"
                    SELECT f.owneruserid, f.type,
                           (SELECT nullif(p.genericbusinesstemplate, '') FROM genericcompanyprofiles p
                             WHERE p.farmid = f.farmid ORDER BY p.genericcompanyprofileid DESC LIMIT 1),
                           (SELECT a.billingmarketcode FROM organizationbillingaccounts a
                             WHERE a.owneruserid = f.owneruserid LIMIT 1)
                    FROM farms f WHERE f.farmid = @C LIMIT 1", conn);
                cmd.Parameters.AddWithValue("@C", companyId);
                await using var r = await cmd.ExecuteReaderAsync();
                if (await r.ReadAsync())
                {
                    org = r.IsDBNull(0) ? null : r.GetString(0);
                    family = r.IsDBNull(1) ? null : r.GetString(1);
                    template = r.IsDBNull(2) ? null : r.GetString(2);
                    market = r.IsDBNull(3) ? null : r.GetString(3);
                }
            }
            var rules = flag.Rules.Select(x => new FlagRule(x.ScopeType, x.ScopeValue, x.Enabled)).ToList();
            var (enabled, scope) = FlagMath.Resolve(flag.Enabled, flag.DefaultOn, rules,
                new FlagContext(userId, companyId, org, template, family, market));
            return new FlagEvaluationDto { FlagKey = flagKey, Enabled = enabled, MatchedScope = scope };
        }

        // ------------------------------------------------------------------
        // Release tracking + system health
        // ------------------------------------------------------------------
        public async Task RegisterReleaseAsync(string service, string version)
        {
            try
            {
                await using var conn = new NpgsqlConnection(_cs);
                await conn.OpenAsync();
                await using var cmd = new NpgsqlCommand(@"
                    INSERT INTO platformreleases (service, version)
                    VALUES (@S, @V) ON CONFLICT (service, version) DO NOTHING", conn);
                cmd.Parameters.AddWithValue("@S", service);
                cmd.Parameters.AddWithValue("@V", version);
                await cmd.ExecuteNonQueryAsync();
            }
            catch (Exception ex)
            {
                _log?.LogWarning(ex, "Release registration skipped");
            }
        }

        public async Task<List<ReleaseDto>> GetReleasesAsync()
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            var list = new List<ReleaseDto>();
            await using (var cmd = new NpgsqlCommand(@"
                SELECT service, version, firstseenatutc FROM platformreleases
                ORDER BY firstseenatutc DESC LIMIT 20", conn))
            {
                await using var r = await cmd.ExecuteReaderAsync();
                while (await r.ReadAsync())
                    list.Add(new ReleaseDto
                    {
                        Service = r.GetString(0),
                        Version = r.GetString(1),
                        FirstSeenAtUtc = r.GetDateTime(2),
                    });
            }
            // Before/after impact: failed vs total mutating requests in the 72h windows
            // around first-seen (real metrics; windows shorter when data is younger).
            foreach (var rel in list.Where(x => x.Service == "farm-api"))
            {
                await using var cmd = new NpgsqlCommand(@"
                    SELECT count(*) FILTER (WHERE ""timestamp"" < @T AND ""timestamp"" >= @T - interval '72 hours'),
                           count(*) FILTER (WHERE ""timestamp"" < @T AND ""timestamp"" >= @T - interval '72 hours' AND status = 'Failed'),
                           count(*) FILTER (WHERE ""timestamp"" >= @T AND ""timestamp"" < @T + interval '72 hours'),
                           count(*) FILTER (WHERE ""timestamp"" >= @T AND ""timestamp"" < @T + interval '72 hours' AND status = 'Failed'),
                           count(DISTINCT lower(farmid)) FILTER (WHERE ""timestamp"" >= @T AND status = 'Failed' AND farmid <> '' AND farmid <> 'Unknown')
                    FROM auditlogs", conn);
                cmd.Parameters.AddWithValue("@T", rel.FirstSeenAtUtc);
                await using var r = await cmd.ExecuteReaderAsync();
                if (await r.ReadAsync())
                {
                    rel.TotalOpsBefore = Convert.ToInt64(r.GetValue(0));
                    rel.FailedOpsBefore = Convert.ToInt64(r.GetValue(1));
                    rel.TotalOpsAfter = Convert.ToInt64(r.GetValue(2));
                    rel.FailedOpsAfter = Convert.ToInt64(r.GetValue(3));
                    rel.AffectedCompaniesAfter = Convert.ToInt32(r.GetValue(4));
                }
            }
            return list;
        }

        public async Task<SystemHealthDto> GetSystemHealthAsync()
        {
            var dto = new SystemHealthDto();
            try
            {
                await using var conn = new NpgsqlConnection(_cs);
                await conn.OpenAsync();
                dto.DatabaseOk = true;
                await using (var cmd = new NpgsqlCommand(@"
                    SELECT (SELECT count(*) FROM auditlogs WHERE status = 'Failed' AND ""timestamp"" > now() - interval '24 hours'),
                           (SELECT count(*) FROM auditlogs WHERE ""timestamp"" > now() - interval '24 hours'),
                           (SELECT count(*) FROM platformpayments WHERE status = 'Failed'
                              AND coalesce(paymentdateutc, createdatutc) > now() - interval '24 hours'),
                           (SELECT max(createdatutc) FROM billingwebhookevents)", conn))
                {
                    await using var r = await cmd.ExecuteReaderAsync();
                    if (await r.ReadAsync())
                    {
                        dto.FailedRequests24h = Convert.ToInt64(r.GetValue(0));
                        dto.TotalRequests24h = Convert.ToInt64(r.GetValue(1));
                        dto.FailedPayments24h = Convert.ToInt64(r.GetValue(2));
                        dto.LastWebhookAtUtc = r.IsDBNull(3) ? null : r.GetDateTime(3);
                    }
                }
            }
            catch (Exception ex)
            {
                dto.DatabaseOk = false;
                dto.Notes.Add($"Database check failed: {ex.Message}");
            }
            dto.Notes.Add("There is no background scheduler on this platform — billing maintenance and health sweeps run on demand (known TODO).");
            dto.Notes.Add("Deep infrastructure metrics live in GCP Cloud Monitoring/Logging; no secrets are surfaced here.");
            return dto;
        }

        // ------------------------------------------------------------------
        // Audited high-level export (CSV; no secrets, no raw user data)
        // ------------------------------------------------------------------
        public async Task<string> ExportCsvAsync(string dataset)
        {
            var sb = new StringBuilder();
            switch (dataset.ToLowerInvariant())
            {
                case "organizations":
                {
                    var orgs = await _activity.GetOrganizationSummariesAsync();
                    sb.AppendLine("OrganizationId,Name,Country,Companies,ActiveCompanies30d,ActiveUsers30d,Meaningful30d,SetupPercent,Subscription,Health,LastMeaningfulUtc");
                    foreach (var o in orgs)
                        sb.AppendLine(string.Join(",",
                            Csv(o.OrganizationId), Csv(o.OrganizationName), Csv(o.CountryCode),
                            o.CompanyCount, o.ActiveCompanies30d, o.ActiveUsers30d,
                            o.MeaningfulActivityCount30d, o.SetupPercent,
                            Csv(o.SubscriptionStatus), Csv(o.Health), Csv(o.LastMeaningfulActivityAtUtc?.ToString("o"))));
                    break;
                }
                case "companies":
                {
                    var orgs = await _activity.GetOrganizationSummariesAsync();
                    sb.AppendLine("CompanyId,Company,Organization,Family,Template,SetupPercent,Activated,Meaningful30d,ActiveUsers30d,Health,LastMeaningfulUtc");
                    foreach (var o in orgs)
                        foreach (var c in o.Companies)
                            sb.AppendLine(string.Join(",",
                                Csv(c.CompanyId), Csv(c.CompanyName), Csv(o.OrganizationName),
                                Csv(c.CompanyFamily), Csv(c.BusinessTemplateCode), c.SetupPercent,
                                c.Activated, c.MeaningfulActivityCount30d, c.ActiveUsers30d,
                                Csv(c.Health), Csv(c.LastMeaningfulActivityAtUtc?.ToString("o"))));
                    break;
                }
                default:
                    throw new ArgumentException("Unknown dataset. Available: organizations, companies.");
            }
            return sb.ToString();
        }

        private static string Csv(object? v)
        {
            var s = v?.ToString() ?? "";
            return s.Contains(',') || s.Contains('"') ? $"\"{s.Replace("\"", "\"\"")}\"" : s;
        }
    }
}
