using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Npgsql;
using PoultryFarmAPIWeb.Helpers;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    /// <summary>
    /// The ten server-side hotel reports added in migration 299.
    ///
    /// SELF-CONTAINED ON PURPOSE. Every other Hotel controller takes the
    /// connection string straight from IConfiguration and talks to Npgsql
    /// itself (see HotelOperationsController), rather than going through a
    /// registered service the way the Restaurant module does. Following the
    /// module's own convention here means Program.cs needs no new registration,
    /// so nothing in the existing dependency graph can be disturbed by adding
    /// this file.
    ///
    /// Route is api/Hotel/reports/*. That does not collide with the existing
    /// api/Hotel + [HttpGet("reports/daily-closings")] action on
    /// HotelOperationsController, because no action here is named daily-closings.
    /// </summary>
    [ApiController]
    [Authorize]
    [Route("api/Hotel/reports")]
    public class HotelReportController : ControllerBase
    {
        private readonly string _cs;
        public HotelReportController(IConfiguration config)
            => _cs = config.GetConnectionString("PoultryConn") ?? "";

        // ---------------------------------------------------------------------
        // Two helpers carry the Npgsql ceremony so each endpoint below is just
        // its column mapping -- the only part that can actually be wrong.
        // ---------------------------------------------------------------------

        private async Task<List<T>> RangeRowsAsync<T>(
            string fn, string farmId, DateTime from, DateTime to,
            Func<System.Data.Common.DbDataReader, T> map)
        {
            await using var conn = new NpgsqlConnection(_cs);
            await using var cmd = new NpgsqlCommand(
                $"SELECT * FROM {fn}(p_farmid=>@f::text,p_from=>@a::date,p_to=>@b::date)", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            cmd.Parameters.AddWithValue("@a", from.Date);
            cmd.Parameters.AddWithValue("@b", to.Date);
            await conn.OpenAsync();
            await using var r = await cmd.ExecuteReaderAsync();
            var list = new List<T>();
            while (await r.ReadAsync()) list.Add(map(r));
            return list;
        }

        /// <summary>
        /// For the one function that returns exactly one row. Returns a
        /// default-constructed T on an empty range rather than null, so the
        /// frontend renders honest zeroes instead of handling a null.
        /// </summary>
        private async Task<T> RangeOneAsync<T>(
            string fn, string farmId, DateTime from, DateTime to,
            Func<System.Data.Common.DbDataReader, T> map) where T : new()
        {
            var rows = await RangeRowsAsync(fn, farmId, from, to, map);
            return rows.Count > 0 ? rows[0] : new T();
        }

        // ---------------------------------------------------------------------
        // Endpoints. Every one keeps the farm-ownership check the rest of the
        // Hotel module uses: farmId arrives as a query parameter, so without it
        // any authenticated user could read any hotel's takings by editing the
        // URL. There is no unguarded endpoint here.
        // ---------------------------------------------------------------------

        [HttpGet("source-of-business")]
        public async Task<IActionResult> SourceOfBusiness([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await RangeRowsAsync("sphotel_report_source_of_business", farmId, from, to, r => new SourceOfBusinessRow
            {
                SourceLabel = r.GetString(0), BookingCount = r.GetInt64(1), RoomNights = r.GetInt64(2),
                GuestCount = r.GetInt64(3), RevenueTotal = r.GetDecimal(4), Adr = r.GetDecimal(5),
                SharePct = r.GetDecimal(6), AvgLeadDays = r.GetDecimal(7),
            }));
        }

        [HttpGet("booking-pace")]
        public async Task<IActionResult> BookingPace([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await RangeRowsAsync("sphotel_report_booking_pace", farmId, from, to, r => new BookingPaceRow
            {
                LeadBucket = r.GetString(0), BucketOrder = r.GetInt32(1), BookingCount = r.GetInt64(2),
                RoomNights = r.GetInt64(3), RevenueTotal = r.GetDecimal(4), Adr = r.GetDecimal(5),
                SharePct = r.GetDecimal(6),
            }));
        }

        [HttpGet("room-type-performance")]
        public async Task<IActionResult> RoomTypePerformance([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await RangeRowsAsync("sphotel_report_room_type_performance", farmId, from, to, r => new RoomTypePerformanceRow
            {
                TypeLabel = r.GetString(0), RoomsInType = r.GetInt64(1), BookingCount = r.GetInt64(2),
                RoomNights = r.GetInt64(3), RevenueTotal = r.GetDecimal(4), Adr = r.GetDecimal(5),
                Revpar = r.GetDecimal(6), OccupancyPct = r.GetDecimal(7), SharePct = r.GetDecimal(8),
            }));
        }

        [HttpGet("performance-kpis")]
        public async Task<IActionResult> PerformanceKpis([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await RangeOneAsync("sphotel_report_performance_kpis", farmId, from, to, r => new HotelPerformanceKpis
            {
                DaysCounted = r.GetInt64(0), AvailableRoomNights = r.GetInt64(1), OccupiedRoomNights = r.GetInt64(2),
                OccupancyPct = r.GetDecimal(3), RoomRevenue = r.GetDecimal(4), FnbRevenue = r.GetDecimal(5),
                OtherRevenue = r.GetDecimal(6), TotalRevenue = r.GetDecimal(7), TotalExpenses = r.GetDecimal(8),
                GrossOperatingProfit = r.GetDecimal(9), Adr = r.GetDecimal(10), Revpar = r.GetDecimal(11),
                Trevpar = r.GetDecimal(12), Goppar = r.GetDecimal(13), NoshowCount = r.GetInt64(14),
            }));
        }

        /// <summary>The one report with no date range: a ledger is a position, not a period.</summary>
        [HttpGet("guest-ledger")]
        public async Task<IActionResult> GuestLedger([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            await using var conn = new NpgsqlConnection(_cs);
            await using var cmd = new NpgsqlCommand("SELECT * FROM sphotel_report_guest_ledger(p_farmid=>@f::text)", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            await conn.OpenAsync();
            await using var r = await cmd.ExecuteReaderAsync();
            var list = new List<GuestLedgerRow>();
            while (await r.ReadAsync()) list.Add(new()
            {
                InvoiceRef = r.GetString(0), GuestLabel = r.GetString(1), IssuedOn = r.GetDateTime(2),
                DueOn = r.IsDBNull(3) ? null : r.GetDateTime(3), InvoiceState = r.GetString(4),
                TotalAmount = r.GetDecimal(5), PaidAmount = r.GetDecimal(6), BalanceDue = r.GetDecimal(7),
                DaysOutstanding = r.GetInt64(8), AgeBucket = r.GetString(9),
            });
            return Ok(list);
        }

        [HttpGet("ancillary-revenue")]
        public async Task<IActionResult> AncillaryRevenue([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await RangeRowsAsync("sphotel_report_ancillary_revenue", farmId, from, to, r => new AncillaryRevenueRow
            {
                ChargeLabel = r.GetString(0), ChargeCount = r.GetInt64(1), QtyTotal = r.GetInt64(2),
                RevenueTotal = r.GetDecimal(3), AvgCharge = r.GetDecimal(4), SharePct = r.GetDecimal(5),
                StaysTouched = r.GetInt64(6),
            }));
        }

        [HttpGet("cancellations")]
        public async Task<IActionResult> Cancellations([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await RangeRowsAsync("sphotel_report_cancellations", farmId, from, to, r => new HotelCancellationRow
            {
                SourceLabel = r.GetString(0), CancelledCount = r.GetInt64(1), NightsLost = r.GetInt64(2),
                ValueLost = r.GetDecimal(3), SharePct = r.GetDecimal(4), AvgLeadDays = r.GetDecimal(5),
                BookedCount = r.GetInt64(6), CancelRatePct = r.GetDecimal(7),
            }));
        }

        [HttpGet("length-of-stay")]
        public async Task<IActionResult> LengthOfStay([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await RangeRowsAsync("sphotel_report_length_of_stay", farmId, from, to, r => new LengthOfStayRow
            {
                LosBucket = r.GetString(0), BucketOrder = r.GetInt32(1), BookingCount = r.GetInt64(2),
                RoomNights = r.GetInt64(3), RevenueTotal = r.GetDecimal(4), Adr = r.GetDecimal(5),
                SharePct = r.GetDecimal(6),
            }));
        }

        [HttpGet("housekeeping-productivity")]
        public async Task<IActionResult> HousekeepingProductivity([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await RangeRowsAsync("sphotel_report_housekeeping_productivity", farmId, from, to, r => new HousekeepingProductivityRow
            {
                AttendantLabel = r.GetString(0), TasksTotal = r.GetInt64(1), TasksCompleted = r.GetInt64(2),
                TimedCount = r.GetInt64(3), AvgMinutes = r.GetDecimal(4), FastestMinutes = r.GetDecimal(5),
                SlowestMinutes = r.GetDecimal(6), RoomsPerShift = r.GetDecimal(7), InspectedCount = r.GetInt64(8),
            }));
        }

        [HttpGet("loyalty")]
        public async Task<IActionResult> Loyalty([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await RangeRowsAsync("sphotel_report_loyalty", farmId, from, to, r => new HotelLoyaltyRow
            {
                TierLabel = r.GetString(0), MemberCount = r.GetInt64(1), ActiveMembers = r.GetInt64(2),
                PointsBalance = r.GetInt64(3), LifetimePoints = r.GetInt64(4), EarnedInPeriod = r.GetInt64(5),
                RedeemedInPeriod = r.GetInt64(6), SharePct = r.GetDecimal(7),
            }));
        }
    }
}
