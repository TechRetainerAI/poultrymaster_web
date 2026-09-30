// Daily Farm Closing / management control (migration 333).
//
// The workspace (sections + checklist for one business date) is built in SQL as
// ONE jsonb document by sppoultrydailyclosing_workspace, and a close stores that
// same document as the snapshot. It is passed through as a JsonElement rather
// than re-typed here so the live state and the state at closing can never drift
// into different shapes: whatever the SQL writes, both sides carry.

using System.Text.Json;

namespace PoultryFarmAPIWeb.Models
{
    /// <summary>Everything the Daily Closing page shows for one date.</summary>
    public class PoultryClosingDayView
    {
        public string FarmId { get; set; } = string.Empty;
        public DateTime BusinessDate { get; set; }

        /// <summary>The closing row, or null when nobody has started one for this date.</summary>
        public PoultryClosingRecord? Closing { get; set; }

        /// <summary>Current Corrected State: recomputed now from the records.</summary>
        public JsonElement Live { get; set; }

        /// <summary>
        /// State At Closing: the snapshot the most recent close stored. Kept after
        /// a reopen, so a reopened day still shows what it was closed with.
        /// </summary>
        public JsonElement? AtClose { get; set; }

        public List<PoultryClosingEvent> History { get; set; } = new();
    }

    public class PoultryClosingRecord
    {
        public int PoultryDailyClosingId { get; set; }
        public DateTime ClosingDate { get; set; }
        /// <summary>Draft | Submitted | Approved | Rejected. Approved means closed.</summary>
        public string Status { get; set; } = "Draft";
        public bool IsClosed => Status == "Approved";
        public string? ManagerNotes { get; set; }
        public string? RejectionReason { get; set; }
        public string? CreatedBy { get; set; }
        public string? SubmittedBy { get; set; }
        public DateTime? SubmittedAt { get; set; }
        public DateTime? ClosedAtUtc { get; set; }
        public string? ClosedBy { get; set; }
        public int CloseVersion { get; set; }
        public int? WarningsAtClose { get; set; }
        public DateTime? LastReopenedAtUtc { get; set; }
        public string? LastReopenedBy { get; set; }
        public string? LastReopenReason { get; set; }
    }

    public class PoultryClosingEvent
    {
        public long EventId { get; set; }
        public int PoultryDailyClosingId { get; set; }
        /// <summary>Created | Submitted | Rejected | Closed | Reopened | Recreated | Deleted</summary>
        public string EventType { get; set; } = string.Empty;
        public string? FromStatus { get; set; }
        public string? ToStatus { get; set; }
        public string? Actor { get; set; }
        public string? Reason { get; set; }
        public int? CloseVersion { get; set; }
        public int? WarningCount { get; set; }
        public DateTime OccurredAtUtc { get; set; }
        public bool HasSnapshot { get; set; }
    }

    public class PoultryClosingHistoryRow
    {
        public int PoultryDailyClosingId { get; set; }
        public DateTime ClosingDate { get; set; }
        public string Status { get; set; } = "Draft";
        public bool IsClosed => Status == "Approved";
        public DateTime? ClosedAtUtc { get; set; }
        public string? ClosedBy { get; set; }
        public int CloseVersion { get; set; }
        public int? WarningsAtClose { get; set; }
        public int ReopenCount { get; set; }
        public DateTime? LastReopenedAtUtc { get; set; }
        public string? LastReopenReason { get; set; }
        // Headline figures AS CLOSED (null for a day never closed).
        public decimal? Revenue { get; set; }
        public decimal? MoneyIn { get; set; }
        public decimal? MoneyOut { get; set; }
        public decimal? NetCashFlow { get; set; }
        public decimal? EggsProduced { get; set; }
        public int? MissingFlocks { get; set; }
        public bool HasSnapshot { get; set; }
    }

    public class PoultryClosingPolicy
    {
        public string FarmId { get; set; } = string.Empty;
        /// <summary>Blocking | Warning</summary>
        public string MissingProduction { get; set; } = "Blocking";
        public string UnpostedProduction { get; set; } = "Blocking";
        public string ImpossibleBirdCounts { get; set; } = "Blocking";
        public string PendingDriverReturns { get; set; } = "Warning";
        public string NegativeStock { get; set; } = "Warning";
        public string CashDifference { get; set; } = "Warning";
        public decimal CashDifferenceTolerance { get; set; }
        public bool RequireCashCount { get; set; }
        public decimal LowFeedDays { get; set; } = 3;
        public decimal UnusualMortalityPct { get; set; } = 1;
        public bool IsCustomised { get; set; }
        public string? UpdatedBy { get; set; }
        public DateTime? UpdatedAtUtc { get; set; }
    }

    public class PoultryCloseDayRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public DateTime BusinessDate { get; set; }
        public string? Notes { get; set; }
    }

    public class PoultryCloseDayResult
    {
        public int PoultryDailyClosingId { get; set; }
        public int CloseVersion { get; set; }
        public int WarningCount { get; set; }
        public DateTime ClosedAtUtc { get; set; }
    }

    /// <summary>
    /// One company's closing state for a date, in terms any module can answer --
    /// what a Business Office row ("Poultry Farm A -- Today: Closed") needs.
    /// </summary>
    public class DailyClosingStatus
    {
        public string FarmId { get; set; } = string.Empty;
        public string Module { get; set; } = string.Empty;
        public DateTime BusinessDate { get; set; }
        public DateTime CompanyToday { get; set; }
        /// <summary>Closed | Open | NotSupported</summary>
        public string ClosingStatus { get; set; } = "Open";
        /// <summary>The module's own workflow state, e.g. NotStarted | Draft | Submitted | Approved.</summary>
        public string? WorkflowStatus { get; set; }
        public DateTime? ClosedAtUtc { get; set; }
        public string? ClosedBy { get; set; }
    }
}
