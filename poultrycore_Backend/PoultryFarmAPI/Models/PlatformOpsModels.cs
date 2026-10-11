// PROMPT 7: platform operations DTOs (errors, security, flags, releases,
// system health, briefs).

namespace PoultryFarmAPIWeb.Models
{
    public class ErrorGroupDto
    {
        public string Resource { get; set; } = "";
        public string Operation { get; set; } = "";
        public string Module { get; set; } = "Other";
        public long Count { get; set; }
        public int AffectedCompanies { get; set; }
        public bool IsCriticalOperation { get; set; }
    }

    public class ErrorDashboardDto
    {
        public int WindowHours { get; set; }
        public long TotalErrors { get; set; }
        public int AffectedOrganizations { get; set; }
        public int AffectedCompanies { get; set; }
        public long FailedBusinessOperations { get; set; }
        public List<ErrorGroupDto> TopErrorTypes { get; set; } = new();
        public List<CategoryCountDto> TopModules { get; set; } = new();
        public List<CategoryCountDto> ByRelease { get; set; } = new();   // failed vs total ops after release
        public List<ActivityTimePointDto> DailyTrend { get; set; } = new();
    }

    public class CompanyErrorRowDto
    {
        public string CorrelationId { get; set; } = "";
        public string Resource { get; set; } = "";
        public string Operation { get; set; } = "";
        public string Summary { get; set; } = "";
        public DateTime OccurredAtUtc { get; set; }
    }

    public class CompanyErrorsDto
    {
        public string CompanyId { get; set; } = "";
        public long Errors24h { get; set; }
        public long Errors7d { get; set; }
        public long FailedOperations7d { get; set; }
        public List<CompanyErrorRowDto> Recent { get; set; } = new();
        public string DeepLogsHint { get; set; } = "";
    }

    public class SecurityEventDto
    {
        public long Id { get; set; }
        public string EventType { get; set; } = "";
        public string Severity { get; set; } = "Info";
        public string? OrganizationId { get; set; }
        public string? CompanyId { get; set; }
        public string? UserId { get; set; }
        public string Title { get; set; } = "";
        public string? Detail { get; set; }
        public int Occurrences { get; set; }
        public DateTime FirstSeenAtUtc { get; set; }
        public DateTime LastSeenAtUtc { get; set; }
        public string Status { get; set; } = "Open";
    }

    public class FlagRuleDto
    {
        public string ScopeType { get; set; } = "Global";
        public string ScopeValue { get; set; } = "";
        public bool Enabled { get; set; }
        public string CreatedBy { get; set; } = "";
        public DateTime CreatedAtUtc { get; set; }
    }

    public class FeatureFlagDto
    {
        public int Id { get; set; }
        public string FlagKey { get; set; } = "";
        public string Name { get; set; } = "";
        public string? Description { get; set; }
        public bool Enabled { get; set; }
        public bool DefaultOn { get; set; }
        public string CreatedBy { get; set; } = "";
        public DateTime CreatedAtUtc { get; set; }
        public List<FlagRuleDto> Rules { get; set; } = new();
    }

    public class FeatureFlagRequest
    {
        public string FlagKey { get; set; } = "";
        public string Name { get; set; } = "";
        public string? Description { get; set; }
        public bool DefaultOn { get; set; }
        public string? Reason { get; set; }
    }

    public class FlagRuleRequest
    {
        public string ScopeType { get; set; } = "Global";
        public string? ScopeValue { get; set; }
        public bool Enabled { get; set; }
        public string? Reason { get; set; }
    }

    public class FlagAuditDto
    {
        public string FlagKey { get; set; } = "";
        public string Action { get; set; } = "";
        public string? ScopeType { get; set; }
        public string? ScopeValue { get; set; }
        public string? OldValue { get; set; }
        public string? NewValue { get; set; }
        public string ChangedBy { get; set; } = "";
        public string? Reason { get; set; }
        public DateTime AtUtc { get; set; }
    }

    public class FlagEvaluationDto
    {
        public string FlagKey { get; set; } = "";
        public bool Enabled { get; set; }
        public string MatchedScope { get; set; } = "Default";
    }

    public class ReleaseDto
    {
        public string Service { get; set; } = "";
        public string Version { get; set; } = "";
        public DateTime FirstSeenAtUtc { get; set; }
        public long? TotalOpsBefore { get; set; }
        public long? FailedOpsBefore { get; set; }
        public long? TotalOpsAfter { get; set; }
        public long? FailedOpsAfter { get; set; }
        public int? AffectedCompaniesAfter { get; set; }
    }

    public class SystemHealthDto
    {
        public bool DatabaseOk { get; set; }
        public long FailedRequests24h { get; set; }
        public long TotalRequests24h { get; set; }
        public long FailedPayments24h { get; set; }
        public DateTime? LastWebhookAtUtc { get; set; }
        public List<string> Notes { get; set; } = new();
    }

    // ---------------- management briefs ----------------

    public class BriefEntryDto
    {
        public string Label { get; set; } = "";
        public string Value { get; set; } = "";
        /// <summary>Portal deep link kind: intel|intelOrg|success|revenue|analytics|audit|none.</summary>
        public string LinkKind { get; set; } = "none";
        public string? LinkParam { get; set; }
    }

    public class BriefSectionDto
    {
        public string Title { get; set; } = "";
        public List<BriefEntryDto> Entries { get; set; } = new();
    }

    public class ManagementBriefDto
    {
        public string BriefType { get; set; } = "Daily";
        public DateOnly BriefDate { get; set; }
        public DateTime GeneratedAtUtc { get; set; }
        public string GeneratedBy { get; set; } = "";
        public List<BriefSectionDto> Sections { get; set; } = new();
        /// <summary>No AI/LLM summarization capability exists on this platform, so
        /// the deterministic brief IS the brief (spec 16 fallback). If one is added
        /// later it must summarize these stored metrics, never invent its own.</summary>
        public string? AiSummary { get; set; }
    }
}
