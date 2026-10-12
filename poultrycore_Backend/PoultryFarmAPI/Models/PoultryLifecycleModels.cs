using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    // =========================================================================
    // Flock Lifecycle Assistant (migration 347). Farm-defined plans, the
    // reminders they raise per flock, and their status history. The schedule
    // is derived on every read (fnpoultrylifecycle_schedule); only what a
    // person did is stored.
    // =========================================================================

    public static class LifecycleActionTypes
    {
        public const string FlockDetails = "FlockDetails";
        public const string FlockTransfer = "FlockTransfer";
        public const string MedicationCampaign = "MedicationCampaign";
        public const string Production = "Production";
        public const string Closeout = "Closeout";
    }

    public class LifecycleMilestoneModel
    {
        /// <summary>Null on a new milestone; set to keep an existing one (and its history).</summary>
        public int? MilestoneId { get; set; }
        /// <summary>"Day" | "Week".</summary>
        [Required] public string AgeUnit { get; set; } = "Week";
        [Range(0, 5000)] public int AgeValue { get; set; }
        /// <summary>Read-only: the age in days.</summary>
        public int AgeDays { get; set; }
        [Required, StringLength(200)] public string Title { get; set; } = string.Empty;
        [StringLength(1000)] public string? Description { get; set; }
        [StringLength(60)] public string? Category { get; set; }
        [Range(0, 365)] public int LeadTimeDays { get; set; } = 3;
        public string? ActionType { get; set; }
        public int SortOrder { get; set; }
    }

    public class LifecycleTemplateModel
    {
        public int TemplateId { get; set; }
        public string Name { get; set; } = string.Empty;
        public string? Breed { get; set; }
        public string? Description { get; set; }
        public bool IsActive { get; set; }
        public int MilestoneCount { get; set; }
        public int AssignedBatches { get; set; }
        public int AssignedFlocks { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public string? UpdatedBy { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public List<LifecycleMilestoneModel>? Milestones { get; set; }
    }

    public class LifecycleTemplateSaveRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required, StringLength(150)] public string Name { get; set; } = string.Empty;
        [StringLength(100)] public string? Breed { get; set; }
        [StringLength(1000)] public string? Description { get; set; }
        public bool IsActive { get; set; } = true;
        [Required, MinLength(1)] public List<LifecycleMilestoneModel> Milestones { get; set; } = new();
    }

    public class LifecycleAssignRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required] public int TemplateId { get; set; }
        /// <summary>Exactly one of BatchId / FlockId.</summary>
        public int? BatchId { get; set; }
        public int? FlockId { get; set; }
        /// <summary>The birds' age in days on the flock's start date. 0 = day-old.</summary>
        [Range(0, 5000)] public int AgeAtStartDays { get; set; }
    }

    public class LifecycleAssignmentModel
    {
        public int AssignmentId { get; set; }
        public int TemplateId { get; set; }
        public string TemplateName { get; set; } = string.Empty;
        public string? TemplateBreed { get; set; }
        public int? BatchId { get; set; }
        public string? BatchCode { get; set; }
        public string? BatchName { get; set; }
        public int? FlockId { get; set; }
        public string? FlockName { get; set; }
        public string? TargetBreed { get; set; }
        public int AgeAtStartDays { get; set; }
        public int FlockCount { get; set; }
        /// <summary>The plan names a breed and the batch/flock is a different one. A warning, never a block.</summary>
        public bool BreedMismatch { get; set; }
        public string? AssignedBy { get; set; }
        public DateTime AssignedAt { get; set; }
    }

    public class LifecycleTaskModel
    {
        public int FlockId { get; set; }
        public string FlockName { get; set; } = string.Empty;
        public int? BatchId { get; set; }
        public string? BatchCode { get; set; }
        public int? HouseId { get; set; }
        public string? Breed { get; set; }
        public DateTime FlockStartDate { get; set; }
        public bool FlockActive { get; set; }
        /// <summary>The flock's start date was derived during onboarding: every date here is an estimate.</summary>
        public bool IsEstimated { get; set; }
        public int AssignmentId { get; set; }
        /// <summary>"Batch" (inherited) | "Flock" (its own).</summary>
        public string AssignedVia { get; set; } = string.Empty;
        public int TemplateId { get; set; }
        public string TemplateName { get; set; } = string.Empty;
        public string? TemplateBreed { get; set; }
        public int AgeAtStartDays { get; set; }
        public int CurrentAgeDays { get; set; }
        public int MilestoneId { get; set; }
        public string Title { get; set; } = string.Empty;
        public string? Description { get; set; }
        public string? Category { get; set; }
        public string AgeUnit { get; set; } = string.Empty;
        public int AgeValue { get; set; }
        public int AgeDays { get; set; }
        public int LeadTimeDays { get; set; }
        public string? ActionType { get; set; }
        public DateTime DueDate { get; set; }
        public DateTime DueWindowEnd { get; set; }
        public DateTime VisibleFrom { get; set; }
        public int DaysUntilDue { get; set; }
        public int? TaskId { get; set; }
        /// <summary>Scheduled | Upcoming | Due | Overdue | Completed | Skipped.</summary>
        public string Status { get; set; } = string.Empty;
        public string? Note { get; set; }
        public string? ActedBy { get; set; }
        public DateTime? ActedAt { get; set; }
        /// <summary>The company's business date the statuses were worked out against.</summary>
        public DateTime Today { get; set; }
    }

    public class LifecycleSummaryModel
    {
        public int Upcoming { get; set; }
        public int Due { get; set; }
        public int Overdue { get; set; }
        public int CompletedLast30 { get; set; }
        public int SkippedLast30 { get; set; }
        public int EstimatedFlocks { get; set; }
        public int AssignedFlocks { get; set; }
        public DateTime Today { get; set; }
    }

    public class LifecycleTaskStatusRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required] public int FlockId { get; set; }
        [Required] public int MilestoneId { get; set; }
        /// <summary>"Completed" | "Skipped" | "Open" (undo).</summary>
        [Required] public string Status { get; set; } = string.Empty;
        [StringLength(1000)] public string? Note { get; set; }
    }

    public class LifecycleTaskEventModel
    {
        public long EventId { get; set; }
        public int FlockId { get; set; }
        public int MilestoneId { get; set; }
        public string Title { get; set; } = string.Empty;
        public string FromStatus { get; set; } = string.Empty;
        public string ToStatus { get; set; } = string.Empty;
        public string? Note { get; set; }
        public string? Actor { get; set; }
        public DateTime AtUtc { get; set; }
    }
}
