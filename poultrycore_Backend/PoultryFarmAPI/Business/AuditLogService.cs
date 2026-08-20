using System.Collections.Concurrent;
using System.Data;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class AuditLogService : IAuditLogService
    {
        private readonly string _connectionString;

        /// <summary>
        /// PostgreSQL identifiers are case-sensitive, so a legacy database may hold the table as
        /// "Auditlogs" / "AuditLogs" while this code wants auditlogs.
        /// Resolved name comes from the pg_class catalog (case-insensitive match, schema public), so the
        /// value embedded in the SQL below can only ever be a real table name read back from the catalog —
        /// never caller input — which is what keeps the string interpolation injection-safe.
        /// </summary>
        private static readonly ConcurrentDictionary<string, string> _auditTableByDb = new();

        public AuditLogService(string connectionString)
        {
            _connectionString = connectionString;
        }

        private static string CellString(NpgsqlDataReader reader, int ordinal) =>
            reader.IsDBNull(ordinal) ? string.Empty : reader.GetValue(ordinal)?.ToString() ?? string.Empty;

        private static string? CellStringNullable(NpgsqlDataReader reader, int ordinal) =>
            reader.IsDBNull(ordinal) ? null : reader.GetValue(ordinal)?.ToString();

        private static DateTime CellDateTime(NpgsqlDataReader reader, int ordinal)
        {
            if (reader.IsDBNull(ordinal))
                return default;
            var v = reader.GetValue(ordinal);
            if (v is DateTime dt)
                return dt;
            return DateTime.TryParse(v?.ToString(), System.Globalization.CultureInfo.InvariantCulture,
                System.Globalization.DateTimeStyles.RoundtripKind, out var parsed)
                ? parsed
                : default;
        }

        private async Task<string> ResolveAuditLogsTableNameAsync(NpgsqlConnection conn)
        {
            if (conn.State != ConnectionState.Open)
                await conn.OpenAsync();

            var cacheKey = $"{conn.DataSource}\u001f{conn.Database}";
            if (_auditTableByDb.TryGetValue(cacheKey, out var cached))
                return cached;

            using (var resolveCmd = new NpgsqlCommand(@"
                SELECT c.relname::text
                FROM pg_class c
                JOIN pg_namespace n ON n.oid = c.relnamespace
                WHERE n.nspname = 'public'
                  AND c.relkind IN ('r','p')
                  AND lower(c.relname) = lower(@Name)
                LIMIT 1;", conn))
            {
                resolveCmd.Parameters.AddWithValue("@Name", "auditlogs");

                var result = await resolveCmd.ExecuteScalarAsync();
                if (result is not string q || string.IsNullOrWhiteSpace(q))
                {
                    throw new InvalidOperationException(
                        "No audit log table found in schema public. Run Migrations/007_AddAuditLogsFarmId.sql or database/create-audit-logs-table.sql. " +
                        "If the table exists under a different letter case, rename it to lowercase auditlogs.");
                }

                _auditTableByDb[cacheKey] = q;
                return q;
            }
        }

        private static AuditLogModel MapRow(NpgsqlDataReader reader) =>
            new AuditLogModel
            {
                Id = reader[0]?.ToString() ?? string.Empty,
                UserId = CellString(reader, 1),
                UserName = CellString(reader, 2),
                FarmId = CellString(reader, 3),
                Action = CellString(reader, 4),
                Resource = CellString(reader, 5),
                ResourceId = CellStringNullable(reader, 6),
                Details = CellStringNullable(reader, 7),
                IpAddress = CellStringNullable(reader, 8),
                UserAgent = CellStringNullable(reader, 9),
                Timestamp = CellDateTime(reader, 10),
                Status = string.IsNullOrEmpty(CellString(reader, 11)) ? "Success" : CellString(reader, 11),
                Data = reader.FieldCount > 12 ? CellStringNullable(reader, 12) : null
            };

        public async Task<List<AuditLogModel>> GetAllAsync(string? userId, string? farmId, string? status, DateTime? startDate, DateTime? endDate, int page, int pageSize)
        {
            var results = new List<AuditLogModel>();

            using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();

            var table = await ResolveAuditLogsTableNameAsync(conn);

            // FarmId: Migrations/007_AddAuditLogsFarmId.sql. Table name: resolved from the catalog above.
            using var cmd = new NpgsqlCommand($@"
                SELECT id, userid, username, farmid, action, resource, resourceid, details, ipaddress, useragent, timestamp, status, data
                FROM {table}
                WHERE (@UserId::text IS NULL OR userid = @UserId::text)
                  AND (@FarmId::text IS NULL OR farmid = @FarmId::text)
                  AND (@Status::text IS NULL OR status = @Status::text)
                  AND (@StartDate::timestamp IS NULL OR timestamp >= @StartDate::timestamp)
                  AND (@EndDate::timestamp IS NULL OR timestamp <= @EndDate::timestamp)
                ORDER BY timestamp DESC
                OFFSET @Offset::int LIMIT @PageSize::int;", conn);

            cmd.Parameters.AddWithValue("@UserId", (object?)userId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FarmId", (object?)farmId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@StartDate", (object?)startDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@EndDate", (object?)endDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Offset", Math.Max(0, (page - 1) * pageSize));
            cmd.Parameters.AddWithValue("@PageSize", Math.Max(1, pageSize));

            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
                results.Add(MapRow(reader));

            return results;
        }

        /// <summary>
        /// Recent rows across all farms (developer / platform dashboards). Caller must authorize SystemAdmin or PlatformOwner.
        /// </summary>
        public async Task<List<AuditLogModel>> GetPlatformRecentAsync(int take)
        {
            var cap = Math.Clamp(take, 1, 2000);
            var results = new List<AuditLogModel>();

            using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();
            var table = await ResolveAuditLogsTableNameAsync(conn);

            using var cmd = new NpgsqlCommand($@"
                SELECT id, userid, username, farmid, action, resource, resourceid, details, ipaddress, useragent, timestamp, status, data
                FROM {table}
                ORDER BY timestamp DESC
                LIMIT @Take::int;", conn);
            cmd.Parameters.AddWithValue("@Take", cap);

            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
                results.Add(MapRow(reader));

            return results;
        }

        public async Task<AuditLogModel?> GetByIdAsync(string id)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();
            var table = await ResolveAuditLogsTableNameAsync(conn);
            // lower(...) on both sides reproduces SQL Server's case-insensitive match on the GUID text
            // (SQL Server rendered uniqueidentifier uppercase; PostgreSQL renders uuid lowercase).
            using var cmd = new NpgsqlCommand($@"
                SELECT id, userid, username, farmid, action, resource, resourceid, details, ipaddress, useragent, timestamp, status, data
                FROM {table}
                WHERE lower(id::text) = lower(@Id);", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            using var reader = await cmd.ExecuteReaderAsync();
            if (await reader.ReadAsync())
                return MapRow(reader);
            return null;
        }

        public async Task<string> InsertAsync(AuditLogModel log)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();
            var table = await ResolveAuditLogsTableNameAsync(conn);
            // PostgreSQL has no table variables: RETURNING hands the generated id straight back to ExecuteScalar.
            using var cmd = new NpgsqlCommand($@"
                INSERT INTO {table} (userid, username, farmid, action, resource, resourceid, details, data, ipaddress, useragent, timestamp, status)
                VALUES (@UserId::text, @UserName, @FarmId::text, @Action, @Resource, @ResourceId, @Details, @Data, @IpAddress, @UserAgent, @Timestamp, @Status::text)
                RETURNING id::text;", conn);

            cmd.Parameters.AddWithValue("@UserId", log.UserId);
            cmd.Parameters.AddWithValue("@UserName", (object?)log.UserName ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FarmId", (object?)log.FarmId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Action", log.Action);
            cmd.Parameters.AddWithValue("@Resource", (object?)log.Resource ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ResourceId", (object?)log.ResourceId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Details", (object?)log.Details ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Data", (object?)log.Data ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IpAddress", (object?)log.IpAddress ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@UserAgent", (object?)log.UserAgent ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Timestamp", log.Timestamp);
            cmd.Parameters.AddWithValue("@Status", log.Status);

            var id = await cmd.ExecuteScalarAsync();
            return id?.ToString() ?? string.Empty;
        }

        public async Task<(string Database, int RowCount)> GetDebugInfoAsync()
        {
            using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();
            var dbName = conn.Database;
            var table = await ResolveAuditLogsTableNameAsync(conn);
            using var cmd = new NpgsqlCommand($"SELECT COUNT(1)::int FROM {table}", conn);
            int count = 0;
            try { count = Convert.ToInt32(await cmd.ExecuteScalarAsync()); }
            catch { count = -1; }
            return (dbName, count);
        }
    }
}


