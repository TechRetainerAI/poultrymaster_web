// PROMPT 1 (Platform Activity Foundation): login engagement tracking.
//
// Called ONLY after a fully verified login (password success for non-2FA
// users, OTP success for 2FA users) — never on token refresh or background
// API calls, so logincount/lastloginatutc stay honest engagement signals.
//
// All work happens in platform_record_login (migration 346 on the shared
// database): bumps aspnetusers.lastloginatutc / logincount, upserts
// userlogindays (ActiveUserDays), and emits a non-meaningful AUTHENTICATION
// activity event. Fire-and-forget: a missing function or unreachable database
// must never break a login.

using Npgsql;

namespace User.Management.API.Helpers
{
    public static class LoginActivityRecorder
    {
        public static void Record(string? connectionString, ILogger logger, string? userId)
        {
            if (string.IsNullOrWhiteSpace(connectionString) || string.IsNullOrWhiteSpace(userId))
                return;

            _ = Task.Run(async () =>
            {
                try
                {
                    await using var conn = new NpgsqlConnection(connectionString);
                    await conn.OpenAsync();
                    await using var cmd = new NpgsqlCommand("SELECT platform_record_login(@U)", conn);
                    cmd.Parameters.AddWithValue("@U", userId);
                    await cmd.ExecuteNonQueryAsync();
                }
                catch (Exception ex)
                {
                    logger.LogWarning(ex, "Login activity not recorded for user {UserId}", userId);
                }
            });
        }
    }
}
