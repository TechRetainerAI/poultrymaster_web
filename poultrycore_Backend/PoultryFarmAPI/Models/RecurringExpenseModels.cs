using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    // =========================================================================
    // Recurring Expense Engine (migration 348) -- shared by every company type.
    // A template's supplier / cash account / category ids are the ids of the
    // company's OWN module (poultry, water, generic, hotel, restaurant).
    // =========================================================================

    public class RecurringExpenseTemplateRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required, StringLength(150)] public string Name { get; set; } = string.Empty;
        /// <summary>The module's category id (Water/Generic/Hotel/Restaurant).</summary>
        public int? CategoryId { get; set; }
        /// <summary>Poultry's free-text category (and a display copy for the others).</summary>
        [StringLength(100)] public string? CategoryName { get; set; }
        public int? SupplierId { get; set; }
        [StringLength(200)] public string? PayeeName { get; set; }
        [Range(0.01, double.MaxValue)] public decimal Amount { get; set; }
        /// <summary>The amount is an estimate (electricity, water bill); confirm it on each draft.</summary>
        public bool IsVariable { get; set; }
        /// <summary>Weekly | Biweekly | Monthly | Quarterly | SemiAnnual | Annual.</summary>
        [Required] public string Frequency { get; set; } = "Monthly";
        [Required] public DateTime StartDate { get; set; }
        public DateTime? EndDate { get; set; }
        /// <summary>Default for each occurrence. "Credit" posts it unpaid (a payable).</summary>
        [StringLength(30)] public string PaymentMethod { get; set; } = "Cash";
        public int? CashAccountId { get; set; }
        [StringLength(1000)] public string? Description { get; set; }
        /// <summary>"Draft" (default: review before posting) | "AutoPost".</summary>
        public string ApprovalMode { get; set; } = "Draft";
    }

    public class RecurringExpenseStatusRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        /// <summary>Pause | Resume | End.</summary>
        [Required] public string Action { get; set; } = string.Empty;
        [StringLength(500)] public string? Reason { get; set; }
    }

    public class RecurringExpenseTemplateModel
    {
        public int TemplateId { get; set; }
        public string Module { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public int? CategoryId { get; set; }
        public string? CategoryName { get; set; }
        public int? SupplierId { get; set; }
        public string? PayeeName { get; set; }
        public decimal Amount { get; set; }
        public bool IsVariable { get; set; }
        public string Frequency { get; set; } = string.Empty;
        public DateTime StartDate { get; set; }
        public DateTime? EndDate { get; set; }
        public DateTime GenerateFrom { get; set; }
        public string PaymentMethod { get; set; } = string.Empty;
        public int? CashAccountId { get; set; }
        public string? Description { get; set; }
        public string ApprovalMode { get; set; } = string.Empty;
        /// <summary>Active | Paused | Ended.</summary>
        public string Status { get; set; } = string.Empty;
        public DateTime? NextDueDate { get; set; }
        public int Drafts { get; set; }
        public int Posted { get; set; }
        public int Skipped { get; set; }
        public DateTime? LastPostedAt { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? EndedAt { get; set; }
        public string? EndReason { get; set; }
    }

    public class RecurringExpenseOccurrenceModel
    {
        public int OccurrenceId { get; set; }
        public int TemplateId { get; set; }
        public string TemplateName { get; set; } = string.Empty;
        public string Module { get; set; } = string.Empty;
        public int OccurrenceNo { get; set; }
        public DateTime ScheduledDate { get; set; }
        /// <summary>Draft | Posting | Posted | Skipped.</summary>
        public string Status { get; set; } = string.Empty;
        public decimal Amount { get; set; }
        public decimal TemplateAmount { get; set; }
        public bool IsVariable { get; set; }
        public DateTime ExpenseDate { get; set; }
        public string PaymentMethod { get; set; } = string.Empty;
        public int? CashAccountId { get; set; }
        public int? SupplierId { get; set; }
        public int? CategoryId { get; set; }
        public string? CategoryName { get; set; }
        public string? PayeeName { get; set; }
        public string? Description { get; set; }
        public string? Note { get; set; }
        public int? ExpenseId { get; set; }
        public string? PostedBy { get; set; }
        public DateTime? PostedAt { get; set; }
        public string? SkippedBy { get; set; }
        public DateTime? SkippedAt { get; set; }
        public string? SkipReason { get; set; }
        public string? ClaimedBy { get; set; }
        public DateTime? ClaimedAt { get; set; }
        /// <summary>A post began more than 10 minutes ago and never finished. Link or release it.</summary>
        public bool IsInterrupted { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    public class RecurringExpenseOccurrenceEditRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        [Range(0.01, double.MaxValue)] public decimal Amount { get; set; }
        [Required] public DateTime ExpenseDate { get; set; }
        [StringLength(30)] public string PaymentMethod { get; set; } = "Cash";
        public int? CashAccountId { get; set; }
        public int? SupplierId { get; set; }
        [StringLength(1000)] public string? Description { get; set; }
        [StringLength(1000)] public string? Note { get; set; }
    }

    public class RecurringExpenseReasonRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        [StringLength(500)] public string? Reason { get; set; }
        /// <summary>For linking an interrupted post to the expense it did create.</summary>
        public int? ExpenseId { get; set; }
    }

    public class RecurringExpenseUpcomingModel
    {
        public int TemplateId { get; set; }
        public string Name { get; set; } = string.Empty;
        public string? CategoryName { get; set; }
        public decimal Amount { get; set; }
        public bool IsVariable { get; set; }
        public string Frequency { get; set; } = string.Empty;
        public int OccurrenceNo { get; set; }
        public DateTime ScheduledDate { get; set; }
        public int DaysAway { get; set; }
        public DateTime Today { get; set; }
    }

    public class RecurringExpenseEventModel
    {
        public long EventId { get; set; }
        public int? OccurrenceId { get; set; }
        public string EventType { get; set; } = string.Empty;
        public string? Details { get; set; }
        public string? Actor { get; set; }
        public DateTime AtUtc { get; set; }
    }

    /// <summary>What a claimed occurrence hands the module's expense service.</summary>
    public class RecurringExpenseClaim
    {
        public Guid ClaimToken { get; set; }
        public int OccurrenceId { get; set; }
        public int TemplateId { get; set; }
        public string Module { get; set; } = string.Empty;
        public decimal Amount { get; set; }
        public DateTime ExpenseDate { get; set; }
        public string PaymentMethod { get; set; } = "Cash";
        public int? CashAccountId { get; set; }
        public int? SupplierId { get; set; }
        public int? CategoryId { get; set; }
        public string? CategoryName { get; set; }
        public string? PayeeName { get; set; }
        public string? Description { get; set; }
        public string? Note { get; set; }
        public bool IsCredit => string.Equals(PaymentMethod, "Credit", StringComparison.OrdinalIgnoreCase);
    }

    public class RecurringExpensePostResult
    {
        public int OccurrenceId { get; set; }
        public int ExpenseId { get; set; }
        public string Module { get; set; } = string.Empty;
        /// <summary>
        /// True where the module approves expenses itself (Water, Generic, Hotel):
        /// the expense now waits there, and cash moves when it is approved.
        /// </summary>
        public bool AwaitingModuleApproval { get; set; }
        public string Message { get; set; } = string.Empty;
    }

    public class RecurringExpenseGenerateResult
    {
        public int Generated { get; set; }
        public int AutoPosted { get; set; }
        public List<string> AutoPostFailures { get; set; } = new();
    }
}
