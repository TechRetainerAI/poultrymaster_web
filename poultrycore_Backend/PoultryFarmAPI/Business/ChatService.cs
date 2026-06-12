using System.Data;
using System.Data.SqlClient;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class ChatService : IChatService
    {
        private readonly string _connectionString;
        public ChatService(string connectionString)
        {
            _connectionString = connectionString;
        }

        public async Task<bool> IsParticipantAsync(Guid threadId, string userId)
        {
            if (string.IsNullOrEmpty(userId))
                return false;
                
            using var conn = new SqlConnection(_connectionString);
            // Use case-insensitive comparison to handle userId format differences
            using var cmd = new SqlCommand("SELECT 1 FROM [dbo].[ChatParticipants] WHERE ThreadId=@t AND LOWER(UserId)=LOWER(@u)", conn);
            cmd.Parameters.AddWithValue("@t", threadId);
            cmd.Parameters.AddWithValue("@u", userId);
            await conn.OpenAsync();
            var r = await cmd.ExecuteScalarAsync();
            return r != null;
        }

        public async Task<ChatThreadModel> CreateOrGetThreadAsync(string farmId, string userId, string otherUserId)
        {
            using var conn = new SqlConnection(_connectionString);
            await conn.OpenAsync();

            // Try to find existing thread for these two participants in same farm
            var findCmd = new SqlCommand(@"
                SELECT TOP 1 t.ThreadId, t.FarmId, t.CreatedBy, t.CreatedAt
                FROM [dbo].[ChatThreads] t
                JOIN [dbo].[ChatParticipants] p1 ON p1.ThreadId = t.ThreadId AND p1.UserId = @u1
                JOIN [dbo].[ChatParticipants] p2 ON p2.ThreadId = t.ThreadId AND p2.UserId = @u2
                WHERE t.FarmId = @farm
                ORDER BY t.CreatedAt DESC", conn);
            findCmd.Parameters.AddWithValue("@u1", userId);
            findCmd.Parameters.AddWithValue("@u2", otherUserId);
            findCmd.Parameters.AddWithValue("@farm", farmId);
            using (var reader = await findCmd.ExecuteReaderAsync())
            {
                if (await reader.ReadAsync())
                {
                    return new ChatThreadModel
                    {
                        ThreadId = reader.GetGuid(0),
                        FarmId = reader.GetString(1),
                        CreatedBy = reader.GetString(2),
                        CreatedAt = reader.GetDateTime(3),
                        OtherUserId = otherUserId
                    };
                }
            }

            // Create if not exists
            var threadId = Guid.NewGuid();
            var insertThread = new SqlCommand("INSERT INTO [dbo].[ChatThreads](ThreadId,FarmId,CreatedBy) VALUES(@t,@f,@c)", conn);
            insertThread.Parameters.AddWithValue("@t", threadId);
            insertThread.Parameters.AddWithValue("@f", farmId);
            insertThread.Parameters.AddWithValue("@c", userId);
            await insertThread.ExecuteNonQueryAsync();

            var insertP1 = new SqlCommand("INSERT INTO [dbo].[ChatParticipants](ThreadId,UserId,Role) VALUES(@t,@u,'user')", conn);
            insertP1.Parameters.AddWithValue("@t", threadId);
            insertP1.Parameters.AddWithValue("@u", userId);
            await insertP1.ExecuteNonQueryAsync();

            var insertP2 = new SqlCommand("INSERT INTO [dbo].[ChatParticipants](ThreadId,UserId,Role) VALUES(@t,@u,'user')", conn);
            insertP2.Parameters.AddWithValue("@t", threadId);
            insertP2.Parameters.AddWithValue("@u", otherUserId);
            await insertP2.ExecuteNonQueryAsync();

            return new ChatThreadModel
            {
                ThreadId = threadId,
                FarmId = farmId,
                CreatedBy = userId,
                CreatedAt = DateTime.UtcNow,
                OtherUserId = otherUserId
            };
        }

        public async Task<List<ChatThreadModel>> GetThreadsAsync(string userId, string farmId)
        {
            var list = new List<ChatThreadModel>();
            using var conn = new SqlConnection(_connectionString);
            var cmd = new SqlCommand(@"
                SELECT t.ThreadId, t.FarmId, t.CreatedBy, t.CreatedAt,
                       (SELECT TOP 1 Content FROM [dbo].[ChatMessages] m WHERE m.ThreadId=t.ThreadId ORDER BY CreatedAt DESC) AS LastMsg,
                       (SELECT TOP 1 CreatedAt FROM [dbo].[ChatMessages] m2 WHERE m2.ThreadId=t.ThreadId ORDER BY CreatedAt DESC) AS LastAt,
                       (SELECT COUNT(1) FROM [dbo].[ChatMessages] m3
                          LEFT JOIN [dbo].[ChatParticipants] p ON p.ThreadId=t.ThreadId AND p.UserId=@u
                          WHERE m3.ThreadId=t.ThreadId AND m3.UserId<>@u AND (p.LastReadAt IS NULL OR m3.CreatedAt>p.LastReadAt)) AS Unread,
                       (SELECT TOP 1 UserId FROM [dbo].[ChatParticipants] p2 WHERE p2.ThreadId=t.ThreadId AND p2.UserId<>@u) AS OtherUserId,
                       u.UserName AS OtherUserName,
                       u.FirstName AS OtherUserFirstName,
                       u.LastName AS OtherUserLastName
                FROM [dbo].[ChatThreads] t
                JOIN [dbo].[ChatParticipants] p ON p.ThreadId=t.ThreadId AND p.UserId=@u
                LEFT JOIN [dbo].[AspNetUsers] u ON u.Id = (SELECT TOP 1 UserId FROM [dbo].[ChatParticipants] p2 WHERE p2.ThreadId=t.ThreadId AND p2.UserId<>@u)
                WHERE t.FarmId=@f
                ORDER BY LastAt DESC", conn);
            cmd.Parameters.AddWithValue("@u", userId);
            cmd.Parameters.AddWithValue("@f", farmId);
            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                list.Add(new ChatThreadModel
                {
                    ThreadId = reader.GetGuid(0),
                    FarmId = reader.GetString(1),
                    CreatedBy = reader.GetString(2),
                    CreatedAt = reader.GetDateTime(3),
                    LastMessagePreview = reader.IsDBNull(4) ? null : reader.GetString(4),
                    LastMessageAt = reader.IsDBNull(5) ? null : reader.GetDateTime(5),
                    UnreadCount = reader.IsDBNull(6) ? 0 : Convert.ToInt32(reader.GetValue(6)),
                    OtherUserId = reader.IsDBNull(7) ? string.Empty : reader.GetString(7),
                    OtherUserName = reader.IsDBNull(8) ? null : reader.GetString(8),
                    OtherUserFirstName = reader.IsDBNull(9) ? null : reader.GetString(9),
                    OtherUserLastName = reader.IsDBNull(10) ? null : reader.GetString(10)
                });
            }
            return list;
        }

        public async Task<List<ChatMessageModel>> GetMessagesAsync(Guid threadId, int take = 50, DateTime? before = null)
        {
            var list = new List<ChatMessageModel>();
            using var conn = new SqlConnection(_connectionString);
            var cmd = new SqlCommand(@"
                SELECT TOP (@take) MessageId, ThreadId, UserId, Content, CreatedAt, IsRead
                FROM [dbo].[ChatMessages]
                WHERE ThreadId=@t AND (@before IS NULL OR CreatedAt < @before)
                ORDER BY CreatedAt DESC", conn);
            cmd.Parameters.AddWithValue("@take", take);
            cmd.Parameters.AddWithValue("@t", threadId);
            cmd.Parameters.AddWithValue("@before", (object?)before ?? DBNull.Value);
            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                list.Add(new ChatMessageModel
                {
                    MessageId = reader.GetGuid(0),
                    ThreadId = reader.GetGuid(1),
                    UserId = reader.GetString(2),
                    Content = reader.GetString(3),
                    CreatedAt = reader.GetDateTime(4),
                    IsRead = reader.GetBoolean(5)
                });
            }
            // return chronologically
            list.Reverse();
            return list;
        }

        public async Task<ChatMessageModel> SendMessageAsync(Guid threadId, string userId, string content)
        {
            using var conn = new SqlConnection(_connectionString);
            await conn.OpenAsync();
            var msgId = Guid.NewGuid();
            var cmd = new SqlCommand("INSERT INTO [dbo].[ChatMessages](MessageId,ThreadId,UserId,Content) VALUES(@m,@t,@u,@c)", conn);
            cmd.Parameters.AddWithValue("@m", msgId);
            cmd.Parameters.AddWithValue("@t", threadId);
            cmd.Parameters.AddWithValue("@u", userId);
            cmd.Parameters.AddWithValue("@c", content);
            await cmd.ExecuteNonQueryAsync();

            return new ChatMessageModel
            {
                MessageId = msgId,
                ThreadId = threadId,
                UserId = userId,
                Content = content,
                CreatedAt = DateTime.UtcNow,
                IsRead = false
            };
        }

        public async Task MarkReadAsync(Guid threadId, string userId)
        {
            using var conn = new SqlConnection(_connectionString);
            var cmd = new SqlCommand("UPDATE [dbo].[ChatParticipants] SET LastReadAt=SYSDATETIME() WHERE ThreadId=@t AND UserId=@u", conn);
            cmd.Parameters.AddWithValue("@t", threadId);
            cmd.Parameters.AddWithValue("@u", userId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }
    }
}


