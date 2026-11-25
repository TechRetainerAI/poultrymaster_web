namespace PoultryFarmAPIWeb.Models
{
    // =========================================================================
    // Loans
    // =========================================================================
    public class GenericLoanModel
    {
        public int GenericLoanId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public string? LoanNumber { get; set; }
        public string LenderName { get; set; } = string.Empty;
        public string? LenderType { get; set; }
        public string? AccountNumber { get; set; }
        public decimal OriginalPrincipal { get; set; }
        public decimal AmountReceived { get; set; }
        public decimal InterestRate { get; set; }
        public string? InterestType { get; set; }
        public int? TermMonths { get; set; }
        public string? PaymentFrequency { get; set; }
        public decimal TotalInterestPaid { get; set; }
        public decimal TotalFeesPaid { get; set; }
        public decimal TotalPrincipalPaid { get; set; }
        public decimal OutstandingBalance { get; set; }
        public DateTime LoanDate { get; set; }
        public DateTime? StartDate { get; set; }
        public DateTime? DueDate { get; set; }
        public DateTime? NextPaymentDate { get; set; }
        public int? GenericCashAccountId { get; set; }
        public string? AccountName { get; set; }
        public int PaymentCount { get; set; }
        public bool IsOverdue { get; set; }
        public DateTime? PaidOffDate { get; set; }
        public string? CancelReason { get; set; }
        public string Status { get; set; } = "Active";
        public string? Notes { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    public class GenericLoanCreateRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public string LenderName { get; set; } = string.Empty;
        public string? LenderType { get; set; }
        public string? AccountNumber { get; set; }
        public decimal OriginalPrincipal { get; set; }
        public decimal AmountReceived { get; set; }
        public decimal? InterestRate { get; set; }
        public string? InterestType { get; set; }
        public int? TermMonths { get; set; }
        public string? PaymentFrequency { get; set; }
        public DateTime? NextPaymentDate { get; set; }
        public DateTime? LoanDate { get; set; }
        public DateTime? StartDate { get; set; }
        public DateTime? DueDate { get; set; }
        public int? GenericCashAccountId { get; set; }
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
        /// <summary>Projects & Contracts: { projectId, costClass } or { splits: [...] }. Saved with the loan in one statement.</summary>
        public System.Text.Json.JsonElement? Projects { get; set; }
    }

    /// <summary>Terms only; the money on a loan is never edited (as on Poultry).</summary>
    public class GenericLoanUpdateRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public string? LenderName { get; set; }
        public string? LenderType { get; set; }
        public string? AccountNumber { get; set; }
        public decimal? InterestRate { get; set; }
        public string? InterestType { get; set; }
        public int? TermMonths { get; set; }
        public string? PaymentFrequency { get; set; }
        public DateTime? DueDate { get; set; }
        public DateTime? NextPaymentDate { get; set; }
        public string? Notes { get; set; }
        public string? UpdatedBy { get; set; }
        /// <summary>Projects & Contracts: sent only when the project was changed; null leaves it as it is.</summary>
        public System.Text.Json.JsonElement? Projects { get; set; }
    }

    public class GenericLoanReasonRequest
    {
        public string Reason { get; set; } = string.Empty;
        public string? By { get; set; }
    }

    public class GenericLoanRepayRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public decimal PrincipalAmount { get; set; }
        public decimal InterestAmount { get; set; }
        public decimal FeeAmount { get; set; }
        public decimal OtherAmount { get; set; }
        public DateTime? PaymentDate { get; set; }
        public int? GenericCashAccountId { get; set; }
        public string? PaymentMethod { get; set; }
        public string? ReferenceNumber { get; set; }
        public DateTime? NextPaymentDate { get; set; }
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
    }

    public class GenericLoanPaymentModel
    {
        public int GenericLoanPaymentId { get; set; }
        public int GenericLoanId { get; set; }
        public string? LoanNumber { get; set; }
        public string? PaymentNumber { get; set; }
        public DateTime PaymentDate { get; set; }
        public decimal PrincipalAmount { get; set; }
        public decimal InterestAmount { get; set; }
        public decimal FeeAmount { get; set; }
        public decimal OtherAmount { get; set; }
        public decimal TotalPayment { get; set; }
        public int? GenericCashAccountId { get; set; }
        public string? AccountName { get; set; }
        public string? PaymentMethod { get; set; }
        public string? ReferenceNumber { get; set; }
        public string? Notes { get; set; }
        public bool IsReversed { get; set; }
        public string Status { get; set; } = "Posted";
        public DateTime? ReversedAt { get; set; }
        public string? ReversalReason { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    // =========================================================================
    // Assets
    // =========================================================================
    public class GenericAssetModel
    {
        public int GenericAssetId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public string AssetName { get; set; } = string.Empty;
        public string? Category { get; set; }
        public DateTime PurchaseDate { get; set; }
        public decimal PurchaseCost { get; set; }
        public decimal CurrentValue { get; set; }
        public decimal TotalDepreciation { get; set; }
        public int? UsefulLifeMonths { get; set; }
        public string? DepreciationMethod { get; set; }
        public string Status { get; set; } = "Active";
        public DateTime? DisposalDate { get; set; }
        public decimal? DisposalAmount { get; set; }
        public string? Location { get; set; }
        public string? SerialNumber { get; set; }
        public string? Notes { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    public class GenericAssetCreateRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public string AssetName { get; set; } = string.Empty;
        public string? Category { get; set; }
        public DateTime? PurchaseDate { get; set; }
        public decimal PurchaseCost { get; set; }
        public int? UsefulLifeMonths { get; set; }
        public string? DepreciationMethod { get; set; }
        public string? Location { get; set; }
        public string? SerialNumber { get; set; }
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
    }

    public class GenericAssetDisposeRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public DateTime? DisposalDate { get; set; }
        public decimal DisposalAmount { get; set; }
    }
}
