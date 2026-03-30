using System.Data;
using System.Data.SqlClient;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class AuditLogService : IAuditLogService
    {
        private readonly string _connectionString;

        public AuditLogService(string connectionString)
        {
            _connectionString = connectionString;
        }

        public async Task<List<AuditLogModel>> GetAllAsync(string? userId, string? farmId, string? status, DateTime? startDate, DateTime? endDate, int page, int pageSize)
        {
            var results = new List<AuditLogModel>();

            using var conn = new SqlConnection(_connectionString);
            await conn.OpenAsync();

            // Query WITH FarmId filter for farm-scoped logs
            using var cmd = new SqlCommand(@"
                SELECT Id, UserId, UserName, FarmId, Action, Resource, ResourceId, Details, IpAddress, UserAgent, Timestamp, Status
                FROM [dbo].[Auditlogs]
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
            {
                results.Add(new AuditLogModel
                {
                    Id = reader[0].ToString() ?? string.Empty,
                    UserId = reader.GetString(1),
                    UserName = reader.IsDBNull(2) ? string.Empty : reader.GetString(2),
                    FarmId = reader.IsDBNull(3) ? string.Empty : reader.GetString(3),
                    Action = reader.IsDBNull(4) ? string.Empty : reader.GetString(4),
                    Resource = reader.IsDBNull(5) ? string.Empty : reader.GetString(5),
                    ResourceId = reader.IsDBNull(6) ? null : reader.GetString(6),
                    Details = reader.IsDBNull(7) ? null : reader.GetString(7),
                    IpAddress = reader.IsDBNull(8) ? null : reader.GetString(8),
                    UserAgent = reader.IsDBNull(9) ? null : reader.GetString(9),
                    Timestamp = reader.GetDateTime(10),
                    Status = reader.IsDBNull(11) ? "Success" : reader.GetString(11)
                });
            }

            return results;
        }

        public async Task<AuditLogModel?> GetByIdAsync(int id)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand(@"
                SELECT Id, UserId, UserName, FarmId, Action, Resource, ResourceId, Details, IpAddress, UserAgent, Timestamp, Status
                FROM [dbo].[Auditlogs]
                WHERE Id = @Id;", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            if (await reader.ReadAsync())
            {
                return new AuditLogModel
                {
                    Id = reader[0].ToString() ?? string.Empty,
                    UserId = reader.GetString(1),
                    UserName = reader.IsDBNull(2) ? string.Empty : reader.GetString(2),
                    FarmId = reader.IsDBNull(3) ? string.Empty : reader.GetString(3),
                    Action = reader.IsDBNull(4) ? string.Empty : reader.GetString(4),
                    Resource = reader.IsDBNull(5) ? string.Empty : reader.GetString(5),
                    ResourceId = reader.IsDBNull(6) ? null : reader.GetString(6),
                    Details = reader.IsDBNull(7) ? null : reader.GetString(7),
                    IpAddress = reader.IsDBNull(8) ? null : reader.GetString(8),
                    UserAgent = reader.IsDBNull(9) ? null : reader.GetString(9),
                    Timestamp = reader.GetDateTime(10),
                    Status = reader.IsDBNull(11) ? "Success" : reader.GetString(11)
                };
            }
            return null;
        }

        public async Task<int> InsertAsync(AuditLogModel log)
        {
            using var conn = new SqlConnection(_connectionString);
            await conn.OpenAsync();
            using var cmd = new SqlCommand(@"
                INSERT INTO [dbo].[Auditlogs] (UserId, UserName, FarmId, Action, Resource, ResourceId, Details, IpAddress, UserAgent, Timestamp, Status)
                VALUES (@UserId, @UserName, @FarmId, @Action, @Resource, @ResourceId, @Details, @IpAddress, @UserAgent, @Timestamp, @Status);
                SELECT CAST(SCOPE_IDENTITY() as int);", conn);

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
            return Convert.ToInt32(id);
        }

        public async Task<(string Database, int RowCount)> GetDebugInfoAsync()
        {
            using var conn = new SqlConnection(_connectionString);
            await conn.OpenAsync();
            var dbName = conn.Database;
            using var cmd = new SqlCommand("SELECT COUNT(1) FROM [dbo].[Auditlogs]", conn);
            int count = 0;
            try { count = Convert.ToInt32(await cmd.ExecuteScalarAsync()); }
            catch { count = -1; }
            return (dbName, count);
        }
    }
}


