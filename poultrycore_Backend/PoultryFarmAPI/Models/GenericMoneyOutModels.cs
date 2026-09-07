using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    // Shapes for the Generic company's money-out side (migration 249):
    // recurring expenses, staff and contractor payments, and owner money.
    //
    // All three end in the same two places -- an expense and a cash movement --
    // which is why they share a migration and a service. What separates them is
    // what they MEAN: a recurring expense is a cost that repeats, a staff
    // payment is a cost with a person attached, and owner money is neither a
    // cost nor revenue, just the owner moving their own money in or out.

    public static class RecurringFrequencies
    {
        public const string Weekly = "Weekly";
        public const string Monthly = "Monthly";
        public const string Quarterly = "Quarterly";
        public const string SemiAnnual = "SemiAnnual";
        public const string Annual = "Annual";
    }

    public static class GenericWorkerTypes
    {
        public const string Employee = "Employee";
        public const string Contractor = "Contractor";
        public const string Consultant = "Consultant";
        public const string Other = "Other";
    }

    public static class OwnerEntryTypes
    {
        /// <summary>Money the owner puts in. Increases cash; NOT revenue.</summary>
        public const string Contribution = "Contribution";
        /// <summary>Money the owner takes out. Decreases cash; NOT an expense.</summary>
        public const string Draw = "Draw";
    }

    // ---------------------------------------------------------------- recurring

    public class GenericRecurringExpenseRow
    {
        public int GenericRecurringExpenseId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public string ExpenseName { get; set; } = string.Empty;
        public int GenericExpenseCategoryId { get; set; }
        public string? CategoryName { get; set; }
        public int? GenericSupplierId { get; set; }
        public string? SupplierName { get; set; }
        public decimal Amount { get; set; }
        public string Frequency { get; set; } = string.Empty;
        public DateTime StartDate { get; set; }
        public DateTime? EndDate { get; set; }
        public DateTime? NextDueDate { get; set; }
        public DateTime? LastGeneratedDate { get; set; }
        public string? PaymentMethod { get; set; }
        public int? DefaultCashAccountId { get; set; }
        /// <summary>Mark the generated expense paid and move the cash, or raise it as a bill.</summary>
        public bool AutoPayOnGenerate { get; set; }
        public bool ReminderEnabled { get; set; }
        /// <summary>Active | Paused | Cancelled | Expired.</summary>
        public string Status { get; set; } = string.Empty;
        public string? Notes { get; set; }
        /// <summary>Due on or before today, and still Active.</summary>
        public bool IsDue { get; set; }
        public int GeneratedCount { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime? CreatedAt { get; set; }
    }

    public class CreateRecurringExpenseRequest
    {
        public string FarmId { get; set; } = string.Empty;
        [Required, StringLength(200)] public string ExpenseName { get; set; } = string.Empty;
        [Range(1, int.MaxValue, ErrorMessage = "An expense category is required.")]
        public int GenericExpenseCategoryId { get; set; }
        [Range(0.01, double.MaxValue, ErrorMessage = "The amount must be greater than 0.")]
        public decimal Amount { get; set; }
        [Required] public string Frequency { get; set; } = RecurringFrequencies.Monthly;
        [Required] public DateTime StartDate { get; set; }
        public int? GenericSupplierId { get; set; }
        public DateTime? EndDate { get; set; }
        public string? PaymentMethod { get; set; }
        public int? DefaultCashAccountId { get; set; }
        public bool AutoPayOnGenerate { get; set; } = true;
        public bool ReminderEnabled { get; set; } = true;
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
    }

    public class SetRecurringExpenseStatusRequest
    {
        public string FarmId { get; set; } = string.Empty;
        [Required] public string Status { get; set; } = string.Empty;
        /// <summary>Required when cancelling. The SP enforces that, not this layer.</summary>
        public string? Reason { get; set; }
        public string? By { get; set; }
    }

    /// <summary>One line of "what generating now would raise".</summary>
    public class RecurringExpensePreviewRow
    {
        public int GenericRecurringExpenseId { get; set; }
        public string ExpenseName { get; set; } = string.Empty;
        public string? CategoryName { get; set; }
        public string? SupplierName { get; set; }
        public decimal Amount { get; set; }
        public string Frequency { get; set; } = string.Empty;
        public DateTime PeriodStart { get; set; }
        public DateTime PeriodEnd { get; set; }
        /// <summary>True when this period already exists, so generate will skip it.</summary>
        public bool AlreadyGenerated { get; set; }
    }

    public class GenerateRecurringRequest
    {
        public string FarmId { get; set; } = string.Empty;
        /// <summary>Raise everything due up to this date. Defaults to today.</summary>
        public DateTime? AsOf { get; set; }
        public string? CreatedBy { get; set; }
    }

    // ------------------------------------------------------------ staff payments

    public class GenericStaffPaymentRow
    {
        public int GenericStaffPaymentId { get; set; }
        public int GenericStaffId { get; set; }
        public string? StaffName { get; set; }
        public string? StaffRole { get; set; }
        public string? WorkerType { get; set; }
        public DateTime PaymentDate { get; set; }
        public DateTime? PeriodStart { get; set; }
        public DateTime? PeriodEnd { get; set; }
        public decimal Amount { get; set; }
        public string? PaymentMethod { get; set; }
        public int? GenericCashAccountId { get; set; }
        public string? CashAccountName { get; set; }
        /// <summary>The expense this payment booked, which is how it reaches the P&amp;L.</summary>
        public int? GenericExpenseId { get; set; }
        public string? CategoryName { get; set; }
        public string? Description { get; set; }
        public string? ReferenceNo { get; set; }
        /// <summary>Posted | Reversed.</summary>
        public string Status { get; set; } = string.Empty;
        public string? CreatedBy { get; set; }
        public string? ReversedBy { get; set; }
        public DateTime? ReversedAt { get; set; }
        public string? ReversalReason { get; set; }
    }

    public class RecordStaffPaymentRequest
    {
        public string FarmId { get; set; } = string.Empty;
        [Range(1, int.MaxValue, ErrorMessage = "A staff member is required.")]
        public int GenericStaffId { get; set; }
        [Range(0.01, double.MaxValue, ErrorMessage = "The amount must be greater than 0.")]
        public decimal Amount { get; set; }
        public DateTime? PaymentDate { get; set; }
        public string? PaymentMethod { get; set; }
        public int? CashAccountId { get; set; }
        /// <summary>Unset falls back to Employee Payments or Contractor Payments by worker type.</summary>
        public int? GenericExpenseCategoryId { get; set; }
        public DateTime? PeriodStart { get; set; }
        public DateTime? PeriodEnd { get; set; }
        public string? Description { get; set; }
        public string? Reference { get; set; }
        public string? CreatedBy { get; set; }
    }

    // -------------------------------------------------------------- owner money

    public class GenericOwnerEntryRow
    {
        public int GenericOwnerEntryId { get; set; }
        public DateTime EntryDate { get; set; }
        /// <summary>Contribution | Draw.</summary>
        public string EntryType { get; set; } = string.Empty;
        public decimal Amount { get; set; }
        public int? GenericCashAccountId { get; set; }
        public string? CashAccountName { get; set; }
        public string? PaymentMethod { get; set; }
        public string? OwnerName { get; set; }
        public string? ReferenceNo { get; set; }
        public string? Notes { get; set; }
        public string Status { get; set; } = string.Empty;
        public string? CreatedBy { get; set; }
        public string? ReversedBy { get; set; }
        public DateTime? ReversedAt { get; set; }
        public string? ReversalReason { get; set; }
    }

    public class RecordOwnerEntryRequest
    {
        public string FarmId { get; set; } = string.Empty;
        [Required] public string EntryType { get; set; } = OwnerEntryTypes.Contribution;
        [Range(0.01, double.MaxValue, ErrorMessage = "The amount must be greater than 0.")]
        public decimal Amount { get; set; }
        /// <summary>Required: owner money always moves cash. The SP rejects a null.</summary>
        public int? CashAccountId { get; set; }
        public DateTime? EntryDate { get; set; }
        public string? PaymentMethod { get; set; }
        public string? OwnerName { get; set; }
        public string? Reference { get; set; }
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
    }

    /// <summary>Shared by every reversal on this side.</summary>
    public class ReverseMoneyOutRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public string? Reason { get; set; }
        public string? ReversedBy { get; set; }
    }
}
