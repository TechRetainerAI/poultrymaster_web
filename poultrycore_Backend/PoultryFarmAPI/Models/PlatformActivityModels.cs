// PROMPT 1 (Platform Activity Foundation): DTOs for the normalized activity
// layer and the platform-admin analytics API.

namespace PoultryFarmAPIWeb.Models
{
    /// <summary>One activity event to record (write side).</summary>
    public class PlatformActivityRecordRequest
    {
        public string? CompanyId { get; set; }          // farms.farmid; null = organization-level
        public string? UserId { get; set; }
        public string? EmployeeId { get; set; }
        public string Category { get; set; } = "OPERATIONS";
        public string ActivityType { get; set; } = "";
        public string SourceModule { get; set; } = "Shared";
        public string? SourceRecordId { get; set; }
        public bool IsMeaningful { get; set; }
        public string? MetadataJson { get; set; }
        public string? CorrelationId { get; set; }      // set only where duplicates must collapse
        public DateTime? OccurredAtUtc { get; set; }    // default now()
    }

    /// <summary>Deterministic platform classification (section 12 of the spec).</summary>
    public enum PlatformActivityStatus
    {
        NoActivity,
        ActiveToday,
        Active7Days,
        Active30Days,
        Inactive30Plus,
    }

    /// <summary>Explainable trend: current period vs preceding equal-length period.</summary>
    public enum PlatformTrendStatus
    {
        NewActivity,   // previous = 0, current > 0
        Increasing,
        Stable,
        Declining,
        Inactive,      // current = 0
    }

    public class PlatformTrendDto
    {
        public long CurrentPeriodCount { get; set; }
        public long PreviousPeriodCount { get; set; }
        /// <summary>Null when the previous period was 0 (no Infinity).</summary>
        public double? PercentChange { get; set; }
        public string Status { get; set; } = nameof(PlatformTrendStatus.Inactive);
    }

    public class CompanyActivitySummaryDto
    {
        public string CompanyId { get; set; } = "";
        public string CompanyName { get; set; } = "";
        public string? CompanyFamily { get; set; }
        public string? BusinessTemplateCode { get; set; }
        public string? OrganizationId { get; set; }
        public string? TimeZoneId { get; set; }
        public DateTime? CreatedAtUtc { get; set; }
        public DateTime? FirstMeaningfulActivityAtUtc { get; set; }
        /// <summary>Billing plan for this company (companybillingstates.billingprofilecode).</summary>
        public string? PlanCode { get; set; }
        public string? BillingParticipation { get; set; }
        public DateTime? LastMeaningfulActivityAtUtc { get; set; }
        public DateTime? LastActivityAtUtc { get; set; }
        public long MeaningfulActivityCountToday { get; set; }
        public long MeaningfulActivityCount7d { get; set; }
        public long MeaningfulActivityCount30d { get; set; }
        public int ActiveDays7d { get; set; }
        public int ActiveDays30d { get; set; }
        public int ActiveUsers7d { get; set; }
        public int ActiveUsers30d { get; set; }
        public string ActivityStatus { get; set; } = nameof(PlatformActivityStatus.NoActivity);
        public PlatformTrendDto Trend { get; set; } = new();
        public List<CategoryCountDto> CategoryBreakdown { get; set; } = new();
        /// <summary>Failed audit-log requests in the last 7 days (RepeatedErrors signal).</summary>
        public int FailedRequests7d { get; set; }
        /// <summary>Milestone-based setup completion (Prompt 4; weighted).</summary>
        public int SetupPercent { get; set; }
        public int RequiredMilestonesComplete { get; set; }
        public int RequiredMilestonesTotal { get; set; }
        /// <summary>Titles of milestones not yet completed (explains the gap).</summary>
        public List<string> MissingMilestones { get; set; } = new();
        /// <summary>Essential setup done AND first meaningful transaction recorded.</summary>
        public bool Activated { get; set; }
        public double? TimeToActivationDays { get; set; }
        /// <summary>Prompt 3 Health Engine verdict (deterministic, explainable).</summary>
        public string? Health { get; set; }
        public List<string> HealthReasons { get; set; } = new();
    }

    public class OrganizationActivitySummaryDto
    {
        public string OrganizationId { get; set; } = "";     // owner user id
        public string? OrganizationName { get; set; }        // business office name
        public string? OwnerEmail { get; set; }
        public string? OrgCode { get; set; }
        /// <summary>Billing market (country) code from the billing account.</summary>
        public string? CountryCode { get; set; }
        public int CompanyCount { get; set; }
        public int ActiveCompanies30d { get; set; }
        public DateTime? FirstCompanyCreatedAtUtc { get; set; }
        public DateTime? FirstMeaningfulActivityAtUtc { get; set; }
        public DateTime? LastMeaningfulActivityAtUtc { get; set; }
        public long MeaningfulActivityCount30d { get; set; }
        public int ActiveUsers30d { get; set; }
        public string ActivityStatus { get; set; } = nameof(PlatformActivityStatus.NoActivity);
        public PlatformTrendDto Trend { get; set; } = new();
        /// <summary>None | Trial | Active | PastDue (+ raw account status) — from organizationbillingaccounts.</summary>
        public string SubscriptionStatus { get; set; } = "None";
        public bool HasPastDueInvoice { get; set; }
        public DateTime? TrialEndUtc { get; set; }
        /// <summary>Share of this org's companies with at least one meaningful event
        /// (initial deterministic setup proxy; refined by the Health Engine in Prompt 3).</summary>
        public int SetupPercent { get; set; }
        /// <summary>Prompt 3 Health Engine verdict for the organization.</summary>
        public string? Health { get; set; }
        public List<string> HealthReasons { get; set; } = new();
        /// <summary>A payment failed within the engine's recent window (7 days).</summary>
        public bool HasRecentFailedPayment { get; set; }
        /// <summary>Deterministic attention flags: GoingQuiet, PastDue, Inactive30Plus, TrialEndingSoon.</summary>
        public List<string> Attention { get; set; } = new();
        /// <summary>Per-company rollup — organization aggregates never hide company data.</summary>
        public List<CompanyActivitySummaryDto> Companies { get; set; } = new();
    }

    public class GoingQuietRowDto
    {
        public string CompanyId { get; set; } = "";
        public string CompanyName { get; set; } = "";
        public string? CompanyFamily { get; set; }
        public string? OrganizationId { get; set; }
        public string? OrganizationName { get; set; }
        public long BaselineMeaningfulCount { get; set; }   // prior window
        public long RecentMeaningfulCount { get; set; }     // current short window
        public DateTime? LastMeaningfulActivityAtUtc { get; set; }
    }

    public class NewCustomerRowDto
    {
        public string OrganizationId { get; set; } = "";
        public string? OrganizationName { get; set; }
        public DateTime? RegisteredAtUtc { get; set; }        // first company creation
        public string? FirstCompanyId { get; set; }
        public string? FirstCompanyName { get; set; }
        public string? FirstCompanyFamily { get; set; }
        public DateTime? FirstMeaningfulActivityAtUtc { get; set; }
        public int SetupPercent { get; set; }                  // placeholder proxy (see org summary)
        public string SubscriptionStatus { get; set; } = "None";
        public DateTime? TrialEndUtc { get; set; }
    }

    public class ModuleAdoptionRowDto
    {
        public string Category { get; set; } = "";
        public string CompanyFamily { get; set; } = "";
        public long MeaningfulCount { get; set; }
        public int ActiveCompanies { get; set; }
    }

    // ---------------- Prompt 3: Needs Attention queue ----------------

    public class AttentionItemDto
    {
        public long Id { get; set; }
        public string OrganizationId { get; set; } = "";
        public string? OrganizationName { get; set; }
        public string? CompanyId { get; set; }
        public string? CompanyName { get; set; }
        public string AttentionType { get; set; } = "";
        public string Severity { get; set; } = "Medium";
        public string Title { get; set; } = "";
        public string Reason { get; set; } = "";
        public string SourceRule { get; set; } = "";
        public string Status { get; set; } = "Open";
        public string? AssignedToUserId { get; set; }
        public string? AssignedToName { get; set; }
        public DateTime? FollowUpAtUtc { get; set; }
        public DateTime DetectedAtUtc { get; set; }
        public DateTime LastDetectedAtUtc { get; set; }
        public DateTime? ResolvedAtUtc { get; set; }
        public string? ResolvedBy { get; set; }
        public string? ResolutionNote { get; set; }
        public decimal? RevenueAtRisk { get; set; }   // filled by Prompt 6
        public List<AttentionNoteDto> Notes { get; set; } = new();
    }

    public class AttentionNoteDto
    {
        public long Id { get; set; }
        public string Note { get; set; } = "";
        public string CreatedBy { get; set; } = "";
        public DateTime CreatedAtUtc { get; set; }
    }

    public class HealthSweepResultDto
    {
        public int OrganizationsEvaluated { get; set; }
        public int CompaniesEvaluated { get; set; }
        public int ItemsUpserted { get; set; }
        public int ItemsAutoResolved { get; set; }
        public DateTime RanAtUtc { get; set; } = DateTime.UtcNow;
    }

    public class AttentionActionRequest
    {
        public string? UserId { get; set; }       // assign
        public string? Name { get; set; }         // assign display name
        public string? Note { get; set; }         // notes / resolve / dismiss reason
        public DateTime? FollowUpAtUtc { get; set; }
    }

    // ---------------- Prompt 4: onboarding / activation / adoption / cohorts ----------------

    public class MilestoneDto
    {
        public string Code { get; set; } = "";
        public string Title { get; set; } = "";
        public int Weight { get; set; }
        public bool Required { get; set; }
        public int SortOrder { get; set; }
        public bool Complete { get; set; }
    }

    public class FunnelStageDto
    {
        public string Key { get; set; } = "";
        public string Label { get; set; } = "";
        public int Count { get; set; }
        /// <summary>Conversion from the previous stage (null for the first).</summary>
        public double? PercentOfPrevious { get; set; }
        public double PercentOfTop { get; set; }
    }

    public class FeatureAdoptionDto
    {
        public string Feature { get; set; } = "";
        public string CompanyFamily { get; set; } = "";
        public int CompaniesUsed { get; set; }
        public int CompaniesTotal { get; set; }
        public double Percent { get; set; }
    }

    public class FeatureUsageDto
    {
        public string Feature { get; set; } = "";
        public string? CompanyId { get; set; }
        public string? CompanyName { get; set; }
        public DateTime? FirstUsedAtUtc { get; set; }
        public DateTime? LastUsedAtUtc { get; set; }
        public long UsageCount { get; set; }
        public int ActiveDaysUsingFeature { get; set; }
    }

    public class RetentionCohortDto
    {
        public string Cohort { get; set; } = "";       // 2026-09 or 2026-W37
        public int Subjects { get; set; }
        /// <summary>Retained counts for D1, D7, D30, D60, D90 windows.</summary>
        public int[] Retained { get; set; } = new int[5];
        public double?[] Percent { get; set; } = new double?[5];   // null = window not yet reached
    }

    public class CategoryCountDto
    {
        public string Key { get; set; } = "";   // category / family / template, per endpoint
        public long MeaningfulCount { get; set; }
        public long TotalCount { get; set; }
    }

    public class ActivityTimePointDto
    {
        public DateOnly BusinessDate { get; set; }
        public long MeaningfulCount { get; set; }
        public long TotalCount { get; set; }
        public int ActiveUsers { get; set; }
    }

    public class RecentActivityDto
    {
        public long Id { get; set; }
        public string? OrganizationId { get; set; }
        public string? CompanyId { get; set; }
        public string? CompanyName { get; set; }
        public string? CompanyFamily { get; set; }
        public string? UserId { get; set; }
        public string Category { get; set; } = "";
        public string ActivityType { get; set; } = "";
        public string SourceModule { get; set; } = "";
        public string? SourceRecordId { get; set; }
        public DateTime OccurredAtUtc { get; set; }
        public DateOnly? BusinessDate { get; set; }
        public bool IsMeaningful { get; set; }
        public string Source { get; set; } = "Runtime";
    }

    public class PlatformActivityOverviewDto
    {
        public int WindowDays { get; set; }
        public long MeaningfulEvents { get; set; }
        public long TotalEvents { get; set; }
        public int CompaniesActiveToday { get; set; }
        public int CompaniesActive7d { get; set; }
        public int CompaniesActive30d { get; set; }
        public int CompaniesInactive30Plus { get; set; }
        public int TotalCompanies { get; set; }
        public int TotalOrganizations { get; set; }
        public int ActiveUsers7d { get; set; }
        public int ActiveUsers30d { get; set; }
        public int NewOrganizationsThisMonth { get; set; }
        public int TrialOrganizations { get; set; }
        public int PayingOrganizations { get; set; }
        public int PastDueOrganizations { get; set; }
        public PlatformTrendDto Trend { get; set; } = new();
        public List<CategoryCountDto> ByCategory { get; set; } = new();
        public List<CategoryCountDto> ByCompanyFamily { get; set; } = new();
        public List<CategoryCountDto> ByBusinessTemplate { get; set; } = new();
    }
}
