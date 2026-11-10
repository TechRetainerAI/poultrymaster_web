namespace PoultryFarmAPIWeb.Models
{
    // =========================================================================
    // Loans
    // =========================================================================
    public class GenericLoanModel
    {
        public int GenericLoanId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public string LenderName { get; set; } = string.Empty;
        public decimal OriginalPrincipal { get; set; }
        public decimal AmountReceived { get; set; }
        public decimal InterestRate { get; set; }
        public decimal TotalInterestPaid { get; set; }
        public decimal TotalFeesPaid { get; set; }
        public decimal TotalPrincipalPaid { get; set; }
        public decimal OutstandingBalance { get; set; }
        public DateTime LoanDate { get; set; }
        public DateTime? StartDate { get; set; }
        public DateTime? DueDate { get; set; }
        public string Status { get; set; } = "Active";
        public string? Notes { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    public class GenericLoanCreateRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public string LenderName { get; set; } = string.Empty;
        public decimal OriginalPrincipal { get; set; }
        public decimal AmountReceived { get; set; }
        public decimal InterestRate { get; set; }
        public DateTime? LoanDate { get; set; }
        public DateTime? StartDate { get; set; }
        public DateTime? DueDate { get; set; }
        public int? GenericCashAccountId { get; set; }
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
    }

    public class GenericLoanRepayRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public decimal PrincipalAmount { get; set; }
        public decimal InterestAmount { get; set; }
        public decimal FeeAmount { get; set; }
        public DateTime? PaymentDate { get; set; }
        public int? GenericCashAccountId { get; set; }
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
    }

    public class GenericLoanPaymentModel
    {
        public int GenericLoanPaymentId { get; set; }
        public int GenericLoanId { get; set; }
        public DateTime PaymentDate { get; set; }
        public decimal PrincipalAmount { get; set; }
        public decimal InterestAmount { get; set; }
        public decimal FeeAmount { get; set; }
        public decimal TotalPayment { get; set; }
        public string? Notes { get; set; }
        public bool IsReversed { get; set; }
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
