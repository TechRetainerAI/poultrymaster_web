// Missing Activity Detector (migration 332).
//
// One vocabulary for "an expected activity has not been done yet", shared by
// every check. Production completeness is the first check; driver returns,
// cash reconciliation, unposted batches, pending approvals and daily closing are
// meant to plug in later as further IActivityCheck implementations WITHOUT
// changing these shapes -- which is why nothing here names a flock or an egg.
//
// Everything is DERIVED on read. None of these types is persisted; a future
// notification that needs acknowledgement or history would store a reference to
// a result (check key + business date + subject), not a copy of it.

namespace PoultryFarmAPIWeb.Models
{
    public static class ActivitySeverity
    {
        public const string Information = "Information";
        public const string Warning = "Warning";
        public const string Critical = "Critical";

        /// <summary>Higher is worse; null (no issue) is 0.</summary>
        public static int Rank(string? s) => s switch
        {
            Critical => 3,
            Warning => 2,
            Information => 1,
            _ => 0,
        };
    }

    public static class ActivityCheckStatus
    {
        public const string Complete = "Complete";
        public const string Incomplete = "Incomplete";
        /// <summary>Nothing was expected (e.g. no active flocks).</summary>
        public const string NotApplicable = "NotApplicable";
    }

    public static class ActivityItemState
    {
        /// <summary>Nothing has been started for this subject.</summary>
        public const string Missing = "Missing";
        /// <summary>Work exists but has not reached its final state (e.g. an unposted batch).</summary>
        public const string AwaitingPosting = "AwaitingPosting";
    }

    /// <summary>What one check found for one company and business date.</summary>
    public class ActivityCheckResult
    {
        /// <summary>Stable id, e.g. "poultry.production.daily". Safe to persist.</summary>
        public string Key { get; set; } = string.Empty;
        /// <summary>poultry | water | generic -- the company type the check belongs to.</summary>
        public string Module { get; set; } = string.Empty;
        public string Title { get; set; } = string.Empty;
        /// <summary>The permission the caller needed to see this check.</summary>
        public string RequiredPermission { get; set; } = string.Empty;

        public string Status { get; set; } = ActivityCheckStatus.NotApplicable;
        /// <summary>Worst severity across the outstanding items; null when complete.</summary>
        public string? Severity { get; set; }

        public int ExpectedCount { get; set; }
        public int CompletedCount { get; set; }
        public int OutstandingCount { get; set; }

        /// <summary>
        /// Check-specific counters that do not fit Expected/Completed, e.g.
        /// "awaitingPosting" or "duplicateSubjects". Additive by design.
        /// </summary>
        public Dictionary<string, int> Counters { get; set; } = new();

        /// <summary>
        /// The deterministic rule behind Severity, in words, so the UI can say
        /// WHY something is a Warning rather than asserting it.
        /// </summary>
        public string? SeverityReason { get; set; }

        /// <summary>Only the OUTSTANDING subjects. Complete ones are counted, not listed.</summary>
        public List<ActivityCheckItem> Items { get; set; } = new();
    }

    /// <summary>One outstanding subject (a flock, a driver return, a closing...).</summary>
    public class ActivityCheckItem
    {
        /// <summary>e.g. "flock", "driverReturn". Pairs with SubjectId.</summary>
        public string SubjectType { get; set; } = string.Empty;
        public int SubjectId { get; set; }
        public string Label { get; set; } = string.Empty;
        /// <summary>Grouping shown beside the label -- the bird batch, for a flock.</summary>
        public string? GroupLabel { get; set; }
        /// <summary>Where it is -- the house/pen, for a flock.</summary>
        public string? LocationLabel { get; set; }

        public string State { get; set; } = ActivityItemState.Missing;
        public string? Severity { get; set; }

        /// <summary>When this activity was last completed for the subject, if ever.</summary>
        public DateTime? LastCompletedDate { get; set; }
        /// <summary>Consecutive business days outstanding, ending on the business date.</summary>
        public int DaysOutstanding { get; set; }

        /// <summary>
        /// A record already in flight for this subject (e.g. an unposted batch
        /// production entry) -- the fix is to finish THAT, not start again.
        /// </summary>
        public string? RelatedRecordType { get; set; }
        public int? RelatedRecordId { get; set; }
        public string? RelatedRecordStatus { get; set; }
    }

    /// <summary>All checks the caller may see, for one company and business date.</summary>
    public class ActivityCompletenessReport
    {
        public string FarmId { get; set; } = string.Empty;
        public string? Module { get; set; }
        /// <summary>The company-local date the checks were evaluated for.</summary>
        public DateTime BusinessDate { get; set; }
        /// <summary>The company's today (may differ from BusinessDate when a past date was asked for).</summary>
        public DateTime CompanyToday { get; set; }
        public DateTime CompanyLocalDateTime { get; set; }
        public string TimeZoneId { get; set; } = "UTC";
        public DateTime GeneratedAtUtc { get; set; }

        /// <summary>Worst severity across all checks; null when everything is complete.</summary>
        public string? Severity { get; set; }
        public List<ActivityCheckResult> Checks { get; set; } = new();

        /// <summary>
        /// Checks that apply to this company but were withheld because the
        /// caller lacks their permission (only ever non-zero under enforcement).
        /// </summary>
        public int HiddenCheckCount { get; set; }
    }

    /// <summary>What a check is asked to evaluate.</summary>
    public class ActivityCheckContext
    {
        public string FarmId { get; set; } = string.Empty;
        /// <summary>Null means "the company's today".</summary>
        public DateTime? BusinessDate { get; set; }
    }

    /// <summary>Every unrecorded production day for one flock within a window (newest first).</summary>
    public class FlockMissingProductionDates
    {
        public int FlockId { get; set; }
        public DateTime BusinessDate { get; set; }
        /// <summary>How far back the list looks (clamped 1..366).</summary>
        public int WindowDays { get; set; }
        public List<MissingProductionDate> Dates { get; set; } = new();
    }

    public class MissingProductionDate
    {
        public DateTime Date { get; set; }
        /// <summary>An unposted batch production entry for this flock and date, if any.</summary>
        public int? PendingBatchRecordId { get; set; }
        public string? PendingBatchStatus { get; set; }
    }

    /// <summary>
    /// Every (date, flock) with no production record in a window, farm-wide
    /// (migration 334) -- the "By date" view, where one day missing for many
    /// flocks is fixed with one Batch Production Entry.
    /// </summary>
    public class MissingProductionByDate
    {
        public DateTime BusinessDate { get; set; }
        public int WindowDays { get; set; }
        /// <summary>Newest date first.</summary>
        public List<MissingProductionEntry> Entries { get; set; } = new();
    }

    public class MissingProductionEntry
    {
        public DateTime Date { get; set; }
        public int FlockId { get; set; }
        public string FlockName { get; set; } = string.Empty;
        public string? BatchName { get; set; }
        public string? HouseName { get; set; }
        public int? PendingBatchRecordId { get; set; }
        public string? PendingBatchStatus { get; set; }
    }
}
