using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    // Owner Money (migration 253): what the owner put in and what they took out.
    //
    // Not revenue and not expense. The amount is always POSITIVE here, exactly
    // as it is stored -- the direction lives in TransactionType, and the sign is
    // applied once, in SQL, when the cash row is written.

    public class PoultryOwnerMoneyModel
    {
        [Key] public int PoultryOwnerMoneyId { get; set; }
        public string FarmId { get; set; } = string.Empty;

        /// <summary>OWN-2026-0001 for a contribution, OWD- for a draw.</summary>
        public string? TransactionNumber { get; set; }
        public DateTime TransactionDate { get; set; }

        /// <summary>Contribution or Draw.</summary>
        public string TransactionType { get; set; } = string.Empty;
        public decimal Amount { get; set; }

        public int PoultryCashAccountId { get; set; }
        public string? AccountName { get; set; }
        public string? PaymentMethod { get; set; }

        public string? OwnerUserId { get; set; }
        public string? OwnerName { get; set; }

        public string? ReferenceNumber { get; set; }
        public string? Notes { get; set; }

        /// <summary>Posted or Reversed.</summary>
        public string Status { get; set; } = "Posted";

        /// <summary>The single cash row this wrote, and the one that undid it.</summary>
        public int? PoultryCashTransactionId { get; set; }
        public int? ReversalCashTransactionId { get; set; }

        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public string? ReversedBy { get; set; }
        public DateTime? ReversedAt { get; set; }
        public string? ReversalReason { get; set; }
    }

    /// <summary>
    /// The cards on the page. Reversed records count towards nothing: money put
    /// in and taken back out is not funding.
    /// </summary>
    public class PoultryOwnerMoneySummary
    {
        public decimal TotalContributions { get; set; }
        public decimal TotalDraws { get; set; }
        /// <summary>Contributions less draws, all time.</summary>
        public decimal NetFunding { get; set; }
        public decimal PeriodContributions { get; set; }
        public decimal PeriodDraws { get; set; }
        public int ContributionCount { get; set; }
        public int DrawCount { get; set; }
    }

    public class PoultryOwnerMoneyRecordRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;

        /// <summary>Contribution or Draw. The SP rejects anything else.</summary>
        [Required]
        [RegularExpression("^(Contribution|Draw)$",
            ErrorMessage = "Owner money must be a Contribution or a Draw.")]
        public string TransactionType { get; set; } = string.Empty;

        [Range(0.01, double.MaxValue, ErrorMessage = "Amount must be greater than zero.")]
        public decimal Amount { get; set; }

        [Required] public int PoultryCashAccountId { get; set; }

        public DateTime? TransactionDate { get; set; }
        [StringLength(50)] public string? PaymentMethod { get; set; }
        public string? OwnerUserId { get; set; }
        [StringLength(150)] public string? OwnerName { get; set; }
        [StringLength(100)] public string? ReferenceNumber { get; set; }
        [StringLength(500)] public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
    }

    /// <summary>Body for POST owner-money/{id}/reverse.</summary>
    public class PoultryOwnerMoneyReverseRequest
    {
        [Required(AllowEmptyStrings = false)]
        [StringLength(500, MinimumLength = 3)]
        public string Reason { get; set; } = string.Empty;
    }
}
