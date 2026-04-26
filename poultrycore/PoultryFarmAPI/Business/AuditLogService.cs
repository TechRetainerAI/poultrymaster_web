using System.Collections.Concurrent;
using System.Data;
using System.Data.SqlClient;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class AuditLogService : IAuditLogService
    {
        private readonly string _connectionString;

        /// <summary>
        /// Case-sensitive SQL Server databases may store the table as dbo.Auditlogs while code used dbo.AuditLogs.
        /// Resolved name comes from sys.tables (CI_AI match) and is quoted — safe to embed.
        /// </summary>
        private static readonly ConcurrentDictionary<string, string> _auditTableByDb = new();

        public AuditLogService(string connectionString)
        {
            _connectionString = connectionString;
        }

        private static string CellString(SqlDataReader reader, int ordinal) =>
            reader.IsDBNull(ordinal) ? string.Empty : reader.GetValue(ordinal)?.ToString() ?? string.Empty;

        private static string? CellStringNullable(SqlDataReader reader, int ordinal) =>
            reader.IsDBNull(ordinal) ? null : reader.GetValue(ordinal)?.ToString();

        private static DateTime CellDateTime(SqlDataReader reader, int ordinal)
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

        private async Task<string> ResolveAuditLogsQualifiedNameAsync(SqlConnection conn)
        {
            if (conn.State != ConnectionState.Open)
                await conn.OpenAsync();

            var cacheKey = $"{conn.DataSource}\u001f{conn.Database}";
            if (_auditTableByDb.TryGetValue(cacheKey, out var cached))
                return cached;

            using (var resolveCmd = new SqlCommand(@"
                SELECT TOP (1) QUOTENAME(SCHEMA_NAME(t.schema_id)) + N'.' + QUOTENAME(t.name)
                FROM sys.tables AS t
                WHERE t.schema_id = SCHEMA_ID(N'dbo')
                  AND t.name COLLATE Latin1_General_CI_AI = N'auditlogs';", conn))
            {
                var result = await resolveCmd.ExecuteScalarAsync();
                if (result is not string q || string.IsNullOrWhiteSpace(q))
                {
                    throw new InvalidOperationException(
                        "No audit log table found in dbo. Run Migrations/007_AddAuditLogsFarmId.sql or database/create-audit-logs-table.sql. " +
                        "On case-sensitive databases, run Migrations/008_RenameLegacyAuditlogsToAuditLogs.sql if the table is dbo.Auditlogs only.");
                }

                _auditTableByDb[cacheKey] = q;
                return q;
            }
        }

        private static AuditLogModel MapRow(SqlDataReader reader) =>
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
                Status = string.IsNullOrEmpty(CellString(reader, 11)) ? "Success" : CellString(reader, 11)
            };

        public async Task<List<AuditLogModel>> GetAllAsync(string? userId, string? farmId, string? status, DateTime? startDate, DateTime? endDate, int page, int pageSize)
        {
            var results = new List<AuditLogModel>();

            using var conn = new SqlConnection(_connectionString);
            await conn.OpenAsync();

            var table = await ResolveAuditLogsQualifiedNameAsync(conn);

            // FarmId: Migrations/007_AddAuditLogsFarmId.sql. Table name: resolve for case-sensitive collations.
            using var cmd = new SqlCommand($@"
                SELECT Id, UserId, UserName, FarmId, Action, Resource, ResourceId, Details, IpAddress, UserAgent, Timestamp, Status
                FROM {table}
                WHERE (@UserId IS NULL OR UserId = @UserId)
                  AND (@FarmId IS NULL OR FarmId = @FarmId)
                  AND (@Status IS NULL OR Status = @Status)
                  AND (@StartDate IS NULL OR Timestamp >= @StartDate)
                  AND (@EndDate IS NULL OR Timestamp <= @EndDate)
                ORDER BY Timestamp DESC
                OFFSET (@Offset) ROWS FETCH NEXT (@PageSize) ROWS ONLY;", conn);

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

            using var conn = new SqlConnection(_connectionString);
            await conn.OpenAsync();
            var table = await ResolveAuditLogsQualifiedNameAsync(conn);

            using var cmd = new SqlCommand($@"
                SELECT TOP (@Take) Id, UserId, UserName, FarmId, Action, Resource, ResourceId, Details, IpAddress, UserAgent, Timestamp, Status
                FROM {table}
                ORDER BY Timestamp DESC;", conn);
            cmd.Parameters.AddWithValue("@Take", cap);

            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
                results.Add(MapRow(reader));

            return results;
        }

        public async Task<AuditLogModel?> GetByIdAsync(string id)
        {
            using var conn = new SqlConnection(_connectionString);
            await conn.OpenAsync();
            var table = await ResolveAuditLogsQualifiedNameAsync(conn);
            using var cmd = new SqlCommand($@"
                SELECT Id, UserId, UserName, FarmId, Action, Resource, ResourceId, Details, IpAddress, UserAgent, Timestamp, Status
                FROM {table}
                WHERE CAST(Id AS NVARCHAR(128)) = @Id;", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            using var reader = await cmd.ExecuteReaderAsync();
            if (await reader.ReadAsync())
                return MapRow(reader);
            return null;
        }

        public async Task<string> InsertAsync(AuditLogModel log)
        {
            using var conn = new SqlConnection(_connectionString);
            await conn.OpenAsync();
            var table = await ResolveAuditLogsQualifiedNameAsync(conn);
            using var cmd = new SqlCommand($@"
                DECLARE @Inserted TABLE (Id NVARCHAR(128));
                INSERT INTO {table} (UserId, UserName, FarmId, Action, Resource, ResourceId, Details, IpAddress, UserAgent, Timestamp, Status)
                OUTPUT CAST(inserted.Id AS NVARCHAR(128)) INTO @Inserted(Id)
                VALUES (@UserId, @UserName, @FarmId, @Action, @Resource, @ResourceId, @Details, @IpAddress, @UserAgent, @Timestamp, @Status);
                SELECT TOP (1) Id FROM @Inserted;", conn);

            cmd.Parameters.AddWithValue("@UserId", log.UserId);
            cmd.Parameters.AddWithValue("@UserName", (object?)log.UserName ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FarmId", (object?)log.FarmId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Action", log.Action);
            cmd.Parameters.AddWithValue("@Resource", (object?)log.Resource ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ResourceId", (object?)log.ResourceId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Details", (object?)log.Details ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IpAddress", (object?)log.IpAddress ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@UserAgent", (object?)log.UserAgent ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Timestamp", log.Timestamp);
            cmd.Parameters.AddWithValue("@Status", log.Status);

            var id = await cmd.ExecuteScalarAsync();
            return id?.ToString() ?? string.Empty;
        }

        public async Task<(string Database, int RowCount)> GetDebugInfoAsync()
        {
            using var conn = new SqlConnection(_connectionString);
            await conn.OpenAsync();
            var dbName = conn.Database;
            var table = await ResolveAuditLogsQualifiedNameAsync(conn);
            using var cmd = new SqlCommand($"SELECT COUNT(1) FROM {table}", conn);
            int count = 0;
            try { count = Convert.ToInt32(await cmd.ExecuteScalarAsync()); }
            catch { count = -1; }
            return (dbName, count);
        }
    }
}


