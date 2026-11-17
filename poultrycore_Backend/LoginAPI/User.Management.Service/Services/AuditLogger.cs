using System.Collections.Concurrent;
using System.Data;
using Npgsql;
using System.Security.Claims;
using Microsoft.AspNetCore.Http;

namespace User.Management.Service.Services
{
    /// <summary>
    /// Mirrors PoultryFarmAPI.Business.AuditLogService.InsertAsync — same table,
    /// same columns, same dynamic table-name resolution (resolved against
    /// pg_catalog so a differently-cased public.auditlogs is still found).
    ///
    /// Constructed with a connection string at startup. We deliberately don't
    /// share AuditLogModel with the Farm API project (separate solutions; no
    /// project reference exists) — a flat row of parameters is easier to keep
    /// in sync via a single migration than a shared type.
    /// </summary>
    public class AuditLogger : IAuditLogger
    {
        private readonly string _connectionString;

        /// <summary>Cache the resolved table name per (server, database) to avoid one extra round-trip per insert.</summary>
        private static readonly ConcurrentDictionary<string, string> _auditTableByDb = new();

        public AuditLogger(string connectionString)
        {
            _connectionString = connectionString;
        }

        public Task LogAsync(
            HttpContext httpContext,
            string action,
            string resource,
            string? resourceId,
            string? farmId = null,
            string? details = null,
            string? data = null,
            string status = "Success")
        {
            // Capture every claim/header we need from the request synchronously,
            // then run the SQL insert on a background task so a slow DB never
            // blocks the originating response.
            var userId   = httpContext?.User?.FindFirst(ClaimTypes.NameIdentifier)?.Value ?? "Unknown";
            var userName = httpContext?.User?.Identity?.Name
                        ?? httpContext?.User?.FindFirst(ClaimTypes.Name)?.Value
                        ?? userId;
            var resolvedFarmId = farmId
                              ?? httpContext?.User?.FindFirst("FarmId")?.Value
                              ?? string.Empty;
            var ip = httpContext?.Connection?.RemoteIpAddress?.ToString();
            var ua = httpContext?.Request?.Headers["User-Agent"].FirstOrDefault();

            FireAndForgetInsert(userId, userName, resolvedFarmId, action, resource, resourceId, details, data, ip, ua, status);
            return Task.CompletedTask;
        }

        // Explicit-actor overload for flows that have no auth context yet — e.g.
        // public signup, where the account being created IS the actor, so its id
        // and name are passed in rather than read from (empty) request claims.
        public Task LogAsync(
            string userId,
            string userName,
            string action,
            string resource,
            string? resourceId = null,
            string? farmId = null,
            string? details = null,
            string status = "Success")
        {
            FireAndForgetInsert(userId, userName, farmId ?? string.Empty, action, resource, resourceId, details, null, null, null, status);
            return Task.CompletedTask;
        }

        // The one insert both overloads use — same table/columns as the Farm API's
        // AuditLogService.InsertAsync; best-effort on a background task.
        private void FireAndForgetInsert(
            string userId, string? userName, string? farmId,
            string action, string resource, string? resourceId,
            string? details, string? data, string? ip, string? ua, string status)
        {
            _ = Task.Run(async () =>
            {
                try
                {
                    using var conn = new NpgsqlConnection(_connectionString);
                    await conn.OpenAsync();
                    var table = await ResolveAuditLogsQualifiedNameAsync(conn);

                    using var cmd = new NpgsqlCommand($@"
                        INSERT INTO {table}
                            (userid, username, farmid, action, resource, resourceid,
                             details, data, ipaddress, useragent, timestamp, status)
                        VALUES
                            (@UserId, @UserName, @FarmId, @Action, @Resource, @ResourceId,
                             @Details, @Data, @IpAddress, @UserAgent, @Timestamp, @Status);", conn);

                    cmd.Parameters.AddWithValue("@UserId",     userId);
                    cmd.Parameters.AddWithValue("@UserName",   (object?)userName   ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@FarmId",     (object?)farmId     ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@Action",     action);
                    cmd.Parameters.AddWithValue("@Resource",   (object?)resource   ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@ResourceId", (object?)resourceId ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@Details",    (object?)details    ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@Data",       (object?)data       ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@IpAddress",  (object?)ip         ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@UserAgent",  (object?)ua         ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@Timestamp",  DateTime.UtcNow);
                    cmd.Parameters.AddWithValue("@Status",     status);

                    await cmd.ExecuteNonQueryAsync();
                }
                catch (Exception ex)
                {
                    // Don't blow up the caller's flow — audit logging is best-effort.
                    Console.WriteLine(
                        $"[AuditLogger] failed to insert {action} {resource} {resourceId}: {ex.Message}");
                }
            });
        }

        private static async Task<string> ResolveAuditLogsQualifiedNameAsync(NpgsqlConnection conn)
        {
            if (conn.State != ConnectionState.Open)
                await conn.OpenAsync();

            var cacheKey = $"{conn.DataSource}{conn.Database}";
            if (_auditTableByDb.TryGetValue(cacheKey, out var cached))
                return cached;

            using var resolveCmd = new NpgsqlCommand(@"
                SELECT quote_ident(n.nspname) || '.' || quote_ident(c.relname)
                FROM pg_catalog.pg_class AS c
                JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
                WHERE n.nspname = 'public'
                  AND c.relkind IN ('r', 'p')
                  AND lower(c.relname) = 'auditlogs'
                LIMIT 1;", conn);

            var result = await resolveCmd.ExecuteScalarAsync();
            if (result is not string q || string.IsNullOrWhiteSpace(q))
            {
                throw new InvalidOperationException(
                    "No audit log table found in schema public. Apply PoultryFarmAPI Migrations/007_AddAuditLogsFarmId.sql first.");
            }
            _auditTableByDb[cacheKey] = q;
            return q;
        }
    }
}
