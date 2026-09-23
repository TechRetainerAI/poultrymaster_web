using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    public class HotelEmployeeLoanModel
    {
        [Key] public int HotelEmployeeLoanId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        public int HotelStaffId { get; set; }
        public string? StaffName { get; set; }
        public string LoanType { get; set; } = "SalaryAdvance";
        public string Status { get; set; } = "Draft";
        public decimal PrincipalAmount { get; set; }
        public decimal InterestAmount { get; set; }
        public decimal TotalRepayable { get; set; }
        public decimal TotalPrincipalRepaid { get; set; }
        public decimal TotalInterestRepaid { get; set; }
        public decimal OutstandingBalance { get; set; }
        public string RepaymentMethod { get; set; } = "Cash";
        public decimal DefaultPayrollDeduction { get; set; }
        public DateTime? DisbursementDate { get; set; }
        public DateTime? ExpectedEndDate { get; set; }
        public int? HotelCashAccountId { get; set; }
        public string? Reference { get; set; }
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public string? ReversedBy { get; set; }
        public string? ReversedReason { get; set; }
        public DateTime? ReversedAt { get; set; }
    }

    public class HotelEmployeeLoanRepaymentModel
    {
        [Key] public int HotelEmployeeLoanRepaymentId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public int HotelEmployeeLoanId { get; set; }
        public decimal Amount { get; set; }
        public decimal PrincipalAmount { get; set; }
        public decimal InterestAmount { get; set; }
        public string SourceType { get; set; } = "Cash";
        public string? PaymentMethod { get; set; }
        public int? HotelCashAccountId { get; set; }
        public decimal BalanceBefore { get; set; }
        public decimal BalanceAfter { get; set; }
        public DateTime RepaymentDate { get; set; }
        public string? Reference { get; set; }
        public string? Notes { get; set; }
        public string Status { get; set; } = "Posted";
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public string? ReversedBy { get; set; }
        public string? ReversedReason { get; set; }
        public DateTime? ReversedAt { get; set; }
    }

    public class HotelEmployeeLoanSummaryModel
    {
        public decimal TotalOutstanding { get; set; }
        public decimal TotalDisbursed { get; set; }
        public decimal TotalRepaid { get; set; }
        public int ActiveCount { get; set; }
    }

    public class HotelEmployeeLoanCreateRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        public int HotelStaffId { get; set; }
        public string? StaffName { get; set; }
        public string LoanType { get; set; } = "SalaryAdvance";
        public decimal PrincipalAmount { get; set; }
        public decimal InterestAmount { get; set; }
        public string RepaymentMethod { get; set; } = "Cash";
        public decimal DefaultPayrollDeduction { get; set; }
        public string? ExpectedEndDate { get; set; }
        public string? Reference { get; set; }
        public string? Notes { get; set; }
        public bool DisburseNow { get; set; }
        public int? HotelCashAccountId { get; set; }
        public string? DisbursementDate { get; set; }
    }

    public class HotelEmployeeLoanDisburseRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        public int? HotelCashAccountId { get; set; }
        public string? DisbursementDate { get; set; }
        public string? Reference { get; set; }
    }

    public class HotelEmployeeLoanRepaymentRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        public int HotelEmployeeLoanId { get; set; }
        public decimal Amount { get; set; }
        public string SourceType { get; set; } = "Cash";
        public int? HotelCashAccountId { get; set; }
        public string? RepaymentDate { get; set; }
        public string? Reference { get; set; }
        public string? Notes { get; set; }
    }

    public class HotelEmployeeLoanReasonRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        public string? Reason { get; set; }
    }
}
