using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    // Loans and repayments (migration 254).
    //
    // The three rules the SP enforces, restated here because they are what these
    // shapes exist to express:
    //   principal repayment is not an expense;
    //   cash moves once, for the total;
    //   a lender is not a supplier.

    public class PoultryLoanModel
    {
        [Key] public int PoultryLoanId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        /// <summary>LN-2026-0001.</summary>
        public string? LoanNumber { get; set; }

        /// <summary>
        /// NULL on a row that came from a Cash Flow "Loan received" adjustment
        /// (290/291): there is no lender behind one, and inventing a placeholder
        /// here would put a made-up name in front of the owner.
        /// </summary>
        public string? LenderName { get; set; }
        public string? LenderType { get; set; }
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

        public int? PoultryCashAccountId { get; set; }
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

        /// <summary>
        /// 'Loan' for a real loan record, 'CashAdjustment' for a borrowing
        /// recorded on the Cash Flow page (290/291). The page keys rows on
        /// (Source, SourceId) and hides Repay on a CashAdjustment row -- the
        /// loan id is 0 on those, so it cannot be used as a key or a target.
        /// </summary>
        public string Source { get; set; } = "Loan";
        public int SourceId { get; set; }
    }

    public class PoultryLoanPaymentModel
    {
        [Key] public int PoultryLoanPaymentId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public int PoultryLoanId { get; set; }
        public string? LoanNumber { get; set; }
        public string? LenderName { get; set; }

        public string? PaymentNumber { get; set; }
        public DateTime PaymentDate { get; set; }

        public decimal TotalAmount { get; set; }
        public decimal PrincipalAmount { get; set; }
        public decimal InterestAmount { get; set; }
        public decimal FeeAmount { get; set; }
        public decimal OtherAmount { get; set; }

        public int PoultryCashAccountId { get; set; }
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

    public class PoultryLoanSummary
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

    /// <summary>
    /// Turn a Cash Flow "Loan received" adjustment into a real, repayable loan
    /// (292/293). There is no amount here on purpose: it comes from the
    /// adjustment, and letting the caller restate it would let the debt and the
    /// cash event disagree on day one.
    ///
    /// The conversion writes NO cash row -- the adjustment remains the cash
    /// event -- so there is no cash account to choose either.
    /// </summary>
    public class PoultryLoanFromAdjustmentRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        [Range(1, int.MaxValue)] public int AdjustmentId { get; set; }
        [Required(AllowEmptyStrings = false)] public string LenderName { get; set; } = string.Empty;

        public string LenderType { get; set; } = "Other";
        public string? AccountNumber { get; set; }
        public decimal? InterestRate { get; set; }
        public string? InterestType { get; set; }
        public int? TermMonths { get; set; }
        public string? PaymentFrequency { get; set; }
        public DateTime? EndDate { get; set; }
        public DateTime? NextPaymentDate { get; set; }
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
    }

    public class PoultryLoanCreateRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required(AllowEmptyStrings = false)] public string LenderName { get; set; } = string.Empty;
        [Range(0.01, double.MaxValue)] public decimal OriginalPrincipal { get; set; }
        [Required] public DateTime StartDate { get; set; }

        [Range(0, double.MaxValue)] public decimal AmountReceived { get; set; }
        public int? PoultryCashAccountId { get; set; }

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
    public class PoultryLoanUpdateRequest
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

    public class PoultryLoanPaymentRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required] public int PoultryLoanId { get; set; }
        [Required] public int PoultryCashAccountId { get; set; }

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
    public class PoultryLoanReasonRequest
    {
        [Required(AllowEmptyStrings = false)]
        [StringLength(500, MinimumLength = 3)]
        public string Reason { get; set; } = string.Empty;
    }
}
