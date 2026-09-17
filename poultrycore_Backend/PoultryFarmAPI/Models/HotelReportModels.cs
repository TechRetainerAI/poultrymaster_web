namespace PoultryFarmAPIWeb.Models
{
    // =========================================================================
    // Row shapes for the hotel report functions added in migration 299.
    //
    // Typed classes rather than the Dictionary<string, object?> that the older
    // hotel controllers return. The dictionary helper lowercases only the FIRST
    // character of each column name, and Postgres folds unquoted identifiers to
    // lower case -- so `revenue_total` would reach the browser as
    // "revenue_total" while every other API in the app speaks camelCase. Typed
    // models get correct camelCase from System.Text.Json for free, and the
    // frontend gets real types.
    //
    // Property order mirrors each function's RETURNS TABLE order, because the
    // controller reads these by ordinal. Reorder one, reorder the other.
    // =========================================================================

    /// <summary>sphotel_report_source_of_business</summary>
    public class SourceOfBusinessRow
    {
        public string SourceLabel { get; set; } = "";
        public long BookingCount { get; set; }
        public long RoomNights { get; set; }
        public long GuestCount { get; set; }
        public decimal RevenueTotal { get; set; }
        public decimal Adr { get; set; }
        public decimal SharePct { get; set; }
        public decimal AvgLeadDays { get; set; }
    }

    /// <summary>sphotel_report_booking_pace</summary>
    public class BookingPaceRow
    {
        public string LeadBucket { get; set; } = "";
        public int BucketOrder { get; set; }
        public long BookingCount { get; set; }
        public long RoomNights { get; set; }
        public decimal RevenueTotal { get; set; }
        public decimal Adr { get; set; }
        public decimal SharePct { get; set; }
    }

    /// <summary>sphotel_report_room_type_performance</summary>
    public class RoomTypePerformanceRow
    {
        public string TypeLabel { get; set; } = "";
        public long RoomsInType { get; set; }
        public long BookingCount { get; set; }
        public long RoomNights { get; set; }
        public decimal RevenueTotal { get; set; }
        public decimal Adr { get; set; }
        public decimal Revpar { get; set; }
        public decimal OccupancyPct { get; set; }
        public decimal SharePct { get; set; }
    }

    /// <summary>sphotel_report_performance_kpis — always exactly one row.</summary>
    public class HotelPerformanceKpis
    {
        public long DaysCounted { get; set; }
        public long AvailableRoomNights { get; set; }
        public long OccupiedRoomNights { get; set; }
        public decimal OccupancyPct { get; set; }
        public decimal RoomRevenue { get; set; }
        public decimal FnbRevenue { get; set; }
        public decimal OtherRevenue { get; set; }
        public decimal TotalRevenue { get; set; }
        public decimal TotalExpenses { get; set; }
        public decimal GrossOperatingProfit { get; set; }
        public decimal Adr { get; set; }
        public decimal Revpar { get; set; }
        public decimal Trevpar { get; set; }
        public decimal Goppar { get; set; }
        public long NoshowCount { get; set; }
    }

    /// <summary>sphotel_report_guest_ledger — a position, so no date range.</summary>
    public class GuestLedgerRow
    {
        public string InvoiceRef { get; set; } = "";
        public string GuestLabel { get; set; } = "";
        public DateTime IssuedOn { get; set; }
        public DateTime? DueOn { get; set; }
        public string InvoiceState { get; set; } = "";
        public decimal TotalAmount { get; set; }
        public decimal PaidAmount { get; set; }
        public decimal BalanceDue { get; set; }
        public long DaysOutstanding { get; set; }
        public string AgeBucket { get; set; } = "";
    }

    /// <summary>sphotel_report_ancillary_revenue</summary>
    public class AncillaryRevenueRow
    {
        public string ChargeLabel { get; set; } = "";
        public long ChargeCount { get; set; }
        public long QtyTotal { get; set; }
        public decimal RevenueTotal { get; set; }
        public decimal AvgCharge { get; set; }
        public decimal SharePct { get; set; }
        public long StaysTouched { get; set; }
    }

    /// <summary>sphotel_report_cancellations</summary>
    public class HotelCancellationRow
    {
        public string SourceLabel { get; set; } = "";
        public long CancelledCount { get; set; }
        public long NightsLost { get; set; }
        public decimal ValueLost { get; set; }
        public decimal SharePct { get; set; }
        public decimal AvgLeadDays { get; set; }
        public long BookedCount { get; set; }
        public decimal CancelRatePct { get; set; }
    }

    /// <summary>sphotel_report_length_of_stay</summary>
    public class LengthOfStayRow
    {
        public string LosBucket { get; set; } = "";
        public int BucketOrder { get; set; }
        public long BookingCount { get; set; }
        public long RoomNights { get; set; }
        public decimal RevenueTotal { get; set; }
        public decimal Adr { get; set; }
        public decimal SharePct { get; set; }
    }

    /// <summary>sphotel_report_housekeeping_productivity</summary>
    public class HousekeepingProductivityRow
    {
        public string AttendantLabel { get; set; } = "";
        public long TasksTotal { get; set; }
        public long TasksCompleted { get; set; }
        public long TimedCount { get; set; }
        public decimal AvgMinutes { get; set; }
        public decimal FastestMinutes { get; set; }
        public decimal SlowestMinutes { get; set; }
        public decimal RoomsPerShift { get; set; }
        public long InspectedCount { get; set; }
    }

    /// <summary>sphotel_report_loyalty</summary>
    public class HotelLoyaltyRow
    {
        public string TierLabel { get; set; } = "";
        public long MemberCount { get; set; }
        public long ActiveMembers { get; set; }
        public long PointsBalance { get; set; }
        public long LifetimePoints { get; set; }
        public long EarnedInPeriod { get; set; }
        public long RedeemedInPeriod { get; set; }
        public decimal SharePct { get; set; }
    }
}
