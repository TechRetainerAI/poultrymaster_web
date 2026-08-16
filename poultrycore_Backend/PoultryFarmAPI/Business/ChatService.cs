using System.Data;
using Npgsql;
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
                
            using var conn = new NpgsqlConnection(_connectionString);
            // Use case-insensitive comparison to handle userId format differences
            using var cmd = new NpgsqlCommand("SELECT 1 FROM chatparticipants WHERE threadid=@t AND LOWER(userid)=LOWER(@u)", conn);
            cmd.Parameters.AddWithValue("@t", threadId);
            cmd.Parameters.AddWithValue("@u", userId);
            await conn.OpenAsync();
            var r = await cmd.ExecuteScalarAsync();
            return r != null;
        }

        public async Task<ChatThreadModel> CreateOrGetThreadAsync(string farmId, string userId, string otherUserId)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();

            // Try to find existing thread for these two participants in same farm
            var findCmd = new NpgsqlCommand(@"
                SELECT t.threadid, t.farmid, t.createdby, t.createdat
                FROM chatthreads t
                JOIN chatparticipants p1 ON p1.threadid = t.threadid AND p1.userid = @u1
                JOIN chatparticipants p2 ON p2.threadid = t.threadid AND p2.userid = @u2
                WHERE t.farmid = @farm
                ORDER BY t.createdat DESC
                LIMIT 1", conn);
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
            var insertThread = new NpgsqlCommand("INSERT INTO chatthreads(threadid,farmid,createdby) VALUES(@t,@f,@c)", conn);
            insertThread.Parameters.AddWithValue("@t", threadId);
            insertThread.Parameters.AddWithValue("@f", farmId);
            insertThread.Parameters.AddWithValue("@c", userId);
            await insertThread.ExecuteNonQueryAsync();

            var insertP1 = new NpgsqlCommand("INSERT INTO chatparticipants(threadid,userid,role) VALUES(@t,@u,'user')", conn);
            insertP1.Parameters.AddWithValue("@t", threadId);
            insertP1.Parameters.AddWithValue("@u", userId);
            await insertP1.ExecuteNonQueryAsync();

            var insertP2 = new NpgsqlCommand("INSERT INTO chatparticipants(threadid,userid,role) VALUES(@t,@u,'user')", conn);
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
            using var conn = new NpgsqlConnection(_connectionString);
            // NULLS LAST keeps SQL Server's ordering for threads that have no messages yet
            // (SQL Server sorts NULLs last under DESC; PostgreSQL would sort them first).
            var cmd = new NpgsqlCommand(@"
                SELECT t.threadid, t.farmid, t.createdby, t.createdat,
                       (SELECT content FROM chatmessages m WHERE m.threadid=t.threadid ORDER BY createdat DESC LIMIT 1) AS lastmsg,
                       (SELECT createdat FROM chatmessages m2 WHERE m2.threadid=t.threadid ORDER BY createdat DESC LIMIT 1) AS lastat,
                       (SELECT COUNT(1)::int FROM chatmessages m3
                          LEFT JOIN chatparticipants p ON p.threadid=t.threadid AND p.userid=@u
                          WHERE m3.threadid=t.threadid AND m3.userid<>@u AND (p.lastreadat IS NULL OR m3.createdat>p.lastreadat)) AS unread,
                       (SELECT userid FROM chatparticipants p2 WHERE p2.threadid=t.threadid AND p2.userid<>@u LIMIT 1) AS otheruserid,
                       u.username AS otherusername,
                       u.firstname AS otheruserfirstname,
                       u.lastname AS otheruserlastname
                FROM chatthreads t
                JOIN chatparticipants p ON p.threadid=t.threadid AND p.userid=@u
                LEFT JOIN aspnetusers u ON u.id = (SELECT userid FROM chatparticipants p2 WHERE p2.threadid=t.threadid AND p2.userid<>@u LIMIT 1)
                WHERE t.farmid=@f
                ORDER BY lastat DESC NULLS LAST", conn);
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
            using var conn = new NpgsqlConnection(_connectionString);
            var cmd = new NpgsqlCommand(@"
                SELECT messageid, threadid, userid, content, createdat, isread
                FROM chatmessages
                WHERE threadid=@t AND (@before IS NULL OR createdat < @before)
                ORDER BY createdat DESC
                LIMIT @take", conn);
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
            using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();
            var msgId = Guid.NewGuid();
            var cmd = new NpgsqlCommand("INSERT INTO chatmessages(messageid,threadid,userid,content) VALUES(@m,@t,@u,@c)", conn);
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
            using var conn = new NpgsqlConnection(_connectionString);
            var cmd = new NpgsqlCommand("UPDATE chatparticipants SET lastreadat=now() WHERE threadid=@t AND userid=@u", conn);
            cmd.Parameters.AddWithValue("@t", threadId);
            cmd.Parameters.AddWithValue("@u", userId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }
    }
}


