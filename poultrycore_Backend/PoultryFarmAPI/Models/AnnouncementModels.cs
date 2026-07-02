using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    // Prompt 4 — Business Office announcements / notifications.
    public class AnnouncementModel
    {
        public int AnnouncementId { get; set; }
        public string? OrgOwnerUserId { get; set; }   // NULL = platform-wide
        [Required] public string Title { get; set; } = string.Empty;
        public string Message { get; set; } = string.Empty;
        public string Type { get; set; } = "Info";     // Info|Success|Warning|Critical|Maintenance|FeatureUpdate|Payment|Security
        public int Priority { get; set; }
        public string? AudienceRole { get; set; }       // All|Admin|Staff
        public string? TargetFarmId { get; set; }
        public DateTime? StartDate { get; set; }
        public DateTime? EndDate { get; set; }
        public bool IsDismissible { get; set; } = true;
        public bool RequiresAck { get; set; }
        public string? ActionLabel { get; set; }
        public string? ActionUrl { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        // Per-user state (null on management list)
        public DateTime? ReadAt { get; set; }
        public DateTime? DismissedAt { get; set; }
        public DateTime? AcknowledgedAt { get; set; }
    }

    public class CreateAnnouncementRequest
    {
        public string? OrgOwnerUserId { get; set; }
        [Required] public string Title { get; set; } = string.Empty;
        public string? Message { get; set; }
        public string? Type { get; set; }
        public int Priority { get; set; }
        public string? AudienceRole { get; set; }
        public string? TargetFarmId { get; set; }
        public DateTime? StartDate { get; set; }
        public DateTime? EndDate { get; set; }
        public bool IsDismissible { get; set; } = true;
        public bool RequiresAck { get; set; }
        public string? ActionLabel { get; set; }
        public string? ActionUrl { get; set; }
        public string? CreatedBy { get; set; }
    }
}
