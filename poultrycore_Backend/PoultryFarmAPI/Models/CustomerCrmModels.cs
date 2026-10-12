// PROMPT 5: DTOs for Organization/Company 360 and the Customer Success CRM.

namespace PoultryFarmAPIWeb.Models
{
    public class TimelineEventDto
    {
        public DateTime AtUtc { get; set; }
        public string Kind { get; set; } = "";       // Registered|CompanyCreated|FirstMeaningful|FirstSale|TrialEnds|Billing|InvoicePaid|PaymentFailed|HealthChanged|Attention|Reactivated|Note|Contacted
        public string Title { get; set; } = "";
        public string? Detail { get; set; }
        public string? CompanyId { get; set; }
        public string? CompanyName { get; set; }
        public string? Actor { get; set; }
    }

    public class CrmNoteDto
    {
        public long Id { get; set; }
        public string OrganizationId { get; set; } = "";
        public string? CompanyId { get; set; }
        public string? CompanyName { get; set; }
        public string Category { get; set; } = "General";
        public string? ContactType { get; set; }
        public string Note { get; set; } = "";
        public DateTime? FollowUpAtUtc { get; set; }
        public string? AssignedToName { get; set; }
        public string? Outcome { get; set; }
        public long? AttentionItemId { get; set; }
        public string CreatedBy { get; set; } = "";
        public DateTime CreatedAtUtc { get; set; }
    }

    public class CrmNoteRequest
    {
        public string OrganizationId { get; set; } = "";
        public string? CompanyId { get; set; }
        public string Category { get; set; } = "General";
        public string? ContactType { get; set; }
        public string Note { get; set; } = "";
        public DateTime? FollowUpAtUtc { get; set; }
        public string? AssignedToName { get; set; }
        public long? AttentionItemId { get; set; }
        public string? Outcome { get; set; }
    }

    public class ProductFeedbackDto
    {
        public long Id { get; set; }
        public string OrganizationId { get; set; } = "";
        public string? CompanyId { get; set; }
        public string? CompanyName { get; set; }
        public string? CompanyFamily { get; set; }
        public string Category { get; set; } = "FeatureRequest";
        public string? Module { get; set; }
        public string Severity { get; set; } = "Medium";
        public string Title { get; set; } = "";
        public string? Detail { get; set; }
        public string Status { get; set; } = "Open";
        public string CreatedBy { get; set; } = "";
        public DateTime CreatedAtUtc { get; set; }
    }

    public class ProductFeedbackRequest
    {
        public string OrganizationId { get; set; } = "";
        public string? CompanyId { get; set; }
        public string? CompanyFamily { get; set; }
        public string Category { get; set; } = "FeatureRequest";
        public string? Module { get; set; }
        public string Severity { get; set; } = "Medium";
        public string Title { get; set; } = "";
        public string? Detail { get; set; }
    }

    public class CancellationReasonDto
    {
        public long Id { get; set; }
        public string OrganizationId { get; set; } = "";
        public string ReasonCode { get; set; } = "Other";
        public string? Note { get; set; }
        public string CreatedBy { get; set; } = "";
        public DateTime CreatedAtUtc { get; set; }
    }

    public class CancellationReasonRequest
    {
        public string OrganizationId { get; set; } = "";
        public string ReasonCode { get; set; } = "Other";
        public string? Note { get; set; }
    }

    public class VerticalSummaryDto
    {
        public string CompanyId { get; set; } = "";
        public string? CompanyFamily { get; set; }
        public List<VerticalSummaryItemDto> Items { get; set; } = new();
    }

    public class VerticalSummaryItemDto
    {
        public string Label { get; set; } = "";
        public string Value { get; set; } = "";
    }

    public class OrgActivityWindowDto
    {
        public int Days { get; set; }
        public long MeaningfulCount { get; set; }
        public int ActiveDays { get; set; }
        public int ActiveUsers { get; set; }
    }

    public class OrgActivitySummaryDto
    {
        public List<OrgActivityWindowDto> Windows { get; set; } = new();
        public List<CategoryCountDto> TopCategories { get; set; } = new();   // 90d
        /// <summary>Next billing period end from the billing account, when present.</summary>
        public DateTime? NextBillingUtc { get; set; }
    }
}
