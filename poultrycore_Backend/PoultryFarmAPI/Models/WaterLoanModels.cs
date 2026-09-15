using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    // Loans and repayments (migration 259) -- the water twin of
    // WaterLoanModels, shape for shape.
    //
    // The three rules the SP enforces, restated here because they are what these
    // shapes exist to express:
    //   principal repayment is not an expense;
    //   cash moves once, for the total;
    //   a lender is not a supplier.

    public class WaterLoanModel
    {
        [Key] public int WaterLoanId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        /// <summary>LN-2026-0001.</summary>
        public string? LoanNumber { get; set; }

        public string LenderName { get; set; } = string.Empty;
        public string LenderType { get; set; } = "Other";
        public string? AccountNumber { get; set; }

        public DateTime LoanDate { get; set; }
        /// <summary>What is OWED. May exceed AmountReceived when a fee was withheld.</summary>
        public decimal OriginalPrincipal { get; set; }
        /// <summary>What actually ARRIVED. This, not the principal, is the cash in.</summary>
        public decimal AmountReceived { get; set; }

        public decimal? InterestRate { get; set; }
        public string? InterestType { get; set; }
        public int? TermMonths { get; set; }
        public string? PaymentFrequency { get; set; }

        public DateTime StartDate { get; set; }
        public DateTime? EndDate { get; set; }
        public DateTime? NextPaymentDate { get; set; }

        public int? WaterCashAccountId { get; set; }
        public string? AccountName { get; set; }

        public decimal OutstandingPrincipal { get; set; }
        public decimal TotalPrincipalRepaid { get; set; }
        public decimal TotalInterestPaid { get; set; }
        public decimal TotalFeesPaid { get; set; }

        public string Status { get; set; } = "Active";
        /// <summary>Derived on read, never stored: no scheduler exists to stamp it.</summary>
        public bool IsOverdue { get; set; }
        public int PaymentCount { get; set; }
        public DateTime? PaidOffDate { get; set; }

        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public string? ReversalReason { get; set; }
    }

    public class WaterLoanPaymentModel
    {
        [Key] public int WaterLoanPaymentId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public int WaterLoanId { get; set; }
        public string? LoanNumber { get; set; }
        public string? LenderName { get; set; }

        public string? PaymentNumber { get; set; }
        public DateTime PaymentDate { get; set; }

        public decimal TotalAmount { get; set; }
        public decimal PrincipalAmount { get; set; }
        public decimal InterestAmount { get; set; }
        public decimal FeeAmount { get; set; }
        public decimal OtherAmount { get; set; }

        public int WaterCashAccountId { get; set; }
        public string? AccountName { get; set; }
        public string? PaymentMethod { get; set; }
        public string? ReferenceNumber { get; set; }
        public string? Notes { get; set; }
        public string Status { get; set; } = "Posted";

        /// <summary>The expense rows for the cost of borrowing. Null when zero.</summary>
        public int? InterestExpenseId { get; set; }
        public int? FeeExpenseId { get; set; }

        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public string? ReversedBy { get; set; }
        public DateTime? ReversedAt { get; set; }
        public string? ReversalReason { get; set; }
    }

    public class WaterLoanSummary
    {
        public int ActiveLoans { get; set; }
        public decimal TotalBorrowed { get; set; }
        public decimal TotalReceived { get; set; }
        public decimal OutstandingPrincipal { get; set; }
        public decimal TotalPrincipalRepaid { get; set; }
        public decimal TotalInterestPaid { get; set; }
        public decimal TotalFeesPaid { get; set; }
        public int OverdueLoans { get; set; }
        public DateTime? NextPaymentDate { get; set; }
    }

    public class WaterLoanCreateRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required(AllowEmptyStrings = false)] public string LenderName { get; set; } = string.Empty;
        [Range(0.01, double.MaxValue)] public decimal OriginalPrincipal { get; set; }
        [Required] public DateTime StartDate { get; set; }

        [Range(0, double.MaxValue)] public decimal AmountReceived { get; set; }
        public int? WaterCashAccountId { get; set; }

        public string LenderType { get; set; } = "Other";
        public string? AccountNumber { get; set; }
        public DateTime? LoanDate { get; set; }
        public decimal? InterestRate { get; set; }
        public string? InterestType { get; set; }
        public int? TermMonths { get; set; }
        public string? PaymentFrequency { get; set; }
        public DateTime? EndDate { get; set; }
        public DateTime? NextPaymentDate { get; set; }
        public string Status { get; set; } = "Active";
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
    }

    /// <summary>
    /// Only the descriptive fields. Principal, amount received and every running
    /// total are consequences of postings and are not editable here.
    /// </summary>
    public class WaterLoanUpdateRequest
    {
        public string? LenderName { get; set; }
        public string? LenderType { get; set; }
        public string? AccountNumber { get; set; }
        public decimal? InterestRate { get; set; }
        public string? InterestType { get; set; }
        public int? TermMonths { get; set; }
        public string? PaymentFrequency { get; set; }
        public DateTime? EndDate { get; set; }
        public DateTime? NextPaymentDate { get; set; }
        public string? Notes { get; set; }
    }

    public class WaterLoanPaymentRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required] public int WaterLoanId { get; set; }
        [Required] public int WaterCashAccountId { get; set; }

        [Range(0, double.MaxValue)] public decimal PrincipalAmount { get; set; }
        [Range(0, double.MaxValue)] public decimal InterestAmount { get; set; }
        [Range(0, double.MaxValue)] public decimal FeeAmount { get; set; }
        [Range(0, double.MaxValue)] public decimal OtherAmount { get; set; }

        public DateTime? PaymentDate { get; set; }
        public string? PaymentMethod { get; set; }
        public string? ReferenceNumber { get; set; }
        public string? Notes { get; set; }
        /// <summary>Moves the loan's schedule on. Left alone when omitted.</summary>
        public DateTime? NextPaymentDate { get; set; }
        public string? CreatedBy { get; set; }
    }

    /// <summary>A reason is required, and it lands in the audit trail.</summary>
    public class WaterLoanReasonRequest
    {
        [Required(AllowEmptyStrings = false)]
        [StringLength(500, MinimumLength = 3)]
        public string Reason { get; set; } = string.Empty;
    }
}
