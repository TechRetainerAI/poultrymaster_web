// Company time (migration 298): the one place that answers "what day is it for
// this company?".
//
// WHY THIS IS A SERVICE AND NOT A HELPER
// ======================================
// The answer depends on a row in `farms`, so it cannot be a static utility. But
// the important reason is that having ONE service makes the eventual sweep
// tractable: the ~41 SPs that still call CURRENT_DATE, and every C# path that
// still calls DateTime.Today, can be converted to point here one at a time.
//
// All the logic lives in the SPs. This file sends parameters and maps rows --
// it deliberately does NOT do timezone arithmetic in C#. TimeZoneInfo on Linux
// reads the same tz database Postgres does, but the two can be at different
// versions in the same deployment, and a business day that depends on which
// process you ask is exactly the bug this programme exists to remove.

using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface ICompanyTimeService
    {
        /// <summary>
        /// A company that has no timezone reads back as UTC with
        /// TimeZoneConfirmed = false -- which is exactly how the platform
        /// behaved before 298, so adopting this cannot change a boundary.
        /// </summary>
        Task<CompanyTimeContextModel> GetContextAsync(string farmId);

        /// <summary>Today, for this company. The one definition.</summary>
        Task<DateTime> GetBusinessDateAsync(string farmId);

        /// <summary>
        /// Sets and marks confirmed. Throws PostgresException (SqlState P0001)
        /// if the company does not exist, or the id is not one
        /// fncompany_isvalidtimezone accepts -- which refuses fixed offsets and
        /// abbreviations ('EST', 'Etc/GMT+5') as well as unknown ids.
        /// </summary>
        Task<CompanyTimeZoneUpdateResult> SetTimeZoneAsync(CompanyTimeZoneUpdateRequest r);

        /// <summary>The zones a company may choose.</summary>
        Task<IReadOnlyList<CompanyTimeZoneOption>> GetZonesAsync(string? search);
    }

    public class CompanyTimeService : ICompanyTimeService
    {
        private readonly string _cs;
        public CompanyTimeService(string cs) => _cs = cs;

        public async Task<CompanyTimeContextModel> GetContextAsync(string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spcompany_timecontext(p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();

            // The SP always returns exactly one row -- an unknown company comes
            // back as UTC rather than as no rows -- so an empty reader would mean
            // something is wrong. Fall back to the same safe answer anyway rather
            // than throwing: a page that cannot render a date picker is a worse
            // failure than one that renders it in UTC.
            if (!await r.ReadAsync())
                return new CompanyTimeContextModel
                {
                    FarmId = farmId,
                    TimeZoneId = "UTC",
                    TimeZoneConfirmed = false,
                    BusinessDate = DateTime.UtcNow.Date,
                    CompanyLocalDateTime = DateTime.UtcNow,
                    UtcNow = DateTime.UtcNow,
                };

            return new CompanyTimeContextModel
            {
                FarmId = r.GetString(r.GetOrdinal("farmid")),
                TimeZoneId = r.GetString(r.GetOrdinal("timezoneid")),
                TimeZoneConfirmed = r.GetBoolean(r.GetOrdinal("timezoneconfirmed")),
                BusinessDate = r.GetDateTime(r.GetOrdinal("businessdate")),
                CompanyLocalDateTime = r.GetDateTime(r.GetOrdinal("companylocaldatetime")),
                // utcnow is timestamptz; Npgsql hands it back as a DateTime whose
                // Kind depends on EnableLegacyTimestampBehavior. Normalise here so
                // callers never have to care which setting is in force.
                UtcNow = DateTime.SpecifyKind(
                    r.GetDateTime(r.GetOrdinal("utcnow")).ToUniversalTime(), DateTimeKind.Utc),
            };
        }

        public async Task<DateTime> GetBusinessDateAsync(string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT fncompany_businessdate(p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            var v = await cmd.ExecuteScalarAsync();
            // fncompany_businessdate coalesces an unknown company to UTC, so this
            // should never be null. Guarding anyway keeps a NULL from becoming a
            // 01/01/0001 that silently poisons a report range.
            return v is DateTime d ? d : DateTime.UtcNow.Date;
        }

        public async Task<CompanyTimeZoneUpdateResult> SetTimeZoneAsync(CompanyTimeZoneUpdateRequest q)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spcompany_settimezone("
                + "p_farmid => @FarmId::text,"
                + "p_timezoneid => @TimeZoneId::text,"
                + "p_updatedby => @UpdatedBy::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", q.FarmId);
            cmd.Parameters.AddWithValue("@TimeZoneId", q.TimeZoneId);
            cmd.Parameters.AddWithValue("@UpdatedBy", (object?)q.UpdatedBy ?? DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            if (!await r.ReadAsync())
                throw new InvalidOperationException("Setting the timezone returned no result.");

            return new CompanyTimeZoneUpdateResult
            {
                TimeZoneId = r.GetString(r.GetOrdinal("timezoneid")),
                TimeZoneConfirmed = r.GetBoolean(r.GetOrdinal("timezoneconfirmed")),
                BusinessDate = r.GetDateTime(r.GetOrdinal("businessdate")),
            };
        }

        /// <summary>
        /// Calls spcompany_timezones (migration 299) rather than filtering
        /// pg_timezone_names here.
        ///
        /// The first version of this method DID filter here, and that was the
        /// bug: the C# list excluded abbreviations, but spcompany_settimezone
        /// only checked membership of pg_timezone_names -- which contains 'EST',
        /// 'MST', 'GMT' and 35 Etc/ fixed offsets. So the picker refused to
        /// offer 'EST' while the setter happily accepted it, and the contract
        /// depended on which door you came through. A company set to 'EST' is an
        /// hour wrong every summer, silently, because it has no daylight-saving
        /// rules.
        ///
        /// Both sides now share fncompany_isvalidtimezone, so they cannot drift
        /// apart again. Do not reintroduce a filter here.
        /// </summary>
        public async Task<IReadOnlyList<CompanyTimeZoneOption>> GetZonesAsync(string? search)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spcompany_timezones(p_search => @Search::text)", c);
            cmd.Parameters.AddWithValue("@Search",
                string.IsNullOrWhiteSpace(search) ? DBNull.Value : search.Trim());
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();

            var list = new List<CompanyTimeZoneOption>();
            while (await r.ReadAsync())
            {
                var offset = r.GetTimeSpan(r.GetOrdinal("utcoffset"));
                list.Add(new CompanyTimeZoneOption
                {
                    TimeZoneId = r.GetString(r.GetOrdinal("timezoneid")),
                    // Formatted here rather than in the UI so every caller shows
                    // the same thing, and so the sign is never lost: TimeSpan
                    // formatting drops the leading '+'.
                    UtcOffset = string.Format("{0}{1:00}:{2:00}",
                        offset < TimeSpan.Zero ? "-" : "+",
                        Math.Abs(offset.Hours), Math.Abs(offset.Minutes)),
                    IsDst = r.GetBoolean(r.GetOrdinal("isdst")),
                });
            }
            return list;
        }
    }
}
