using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    public class HotelEmployeeLoanModel
    {
        [Key] public int HotelEmployeeLoanId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        public int HotelStaffId { get; set; }
        public string? StaffName { get; set; }
        public bool StaffIsActive { get; set; }
        public string? LoanNumber { get; set; }
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
        public string? CashAccountName { get; set; }
        public string? Reference { get; set; }
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public string? ReversedBy { get; set; }
        public string? ReversedReason { get; set; }
        public DateTime? ReversedAt { get; set; }
        public int RepaymentCount { get; set; }
        public DateTime? LastRepaymentDate { get; set; }
        /// <summary>Amount draft payroll runs are already set to deduct from this loan.</summary>
        public decimal DraftPayrollClaims { get; set; }
    }

    public class HotelEmployeeLoanRepaymentModel
    {
        [Key] public int HotelEmployeeLoanRepaymentId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public int HotelEmployeeLoanId { get; set; }
        public string? LoanNumber { get; set; }
        public int HotelStaffId { get; set; }
        public string? StaffName { get; set; }
        public decimal Amount { get; set; }
        public decimal PrincipalAmount { get; set; }
        public decimal InterestAmount { get; set; }
        public string SourceType { get; set; } = "Cash";
        public string? PaymentMethod { get; set; }
        public int? HotelCashAccountId { get; set; }
        public string? CashAccountName { get; set; }
        public int? CashTransactionId { get; set; }
        public int? HotelPayrollRunId { get; set; }
        public string? PayrollPeriod { get; set; }
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
        public int StaffWithLoans { get; set; }
        public int DraftCount { get; set; }
        public int PaidCount { get; set; }
        public decimal InterestEarned { get; set; }
        public decimal RepaidViaPayroll { get; set; }
        public decimal DraftPayrollClaims { get; set; }
    }

    /// <summary>One open loan of a staff member, as the payroll screen needs it.</summary>
    public class HotelEmployeeLoanEligibleModel
    {
        public int HotelEmployeeLoanId { get; set; }
        public string? LoanNumber { get; set; }
        public string LoanType { get; set; } = "";
        public string RepaymentMethod { get; set; } = "";
        public decimal OutstandingBalance { get; set; }
        public decimal DefaultPayrollDeduction { get; set; }
        /// <summary>Already set aside on other draft payroll lines.</summary>
        public decimal ClaimedElsewhere { get; set; }
        /// <summary>The most this payroll line may deduct.</summary>
        public decimal Available { get; set; }
        public decimal SuggestedDeduction { get; set; }
        /// <summary>What this payroll line deducts today (0 if none).</summary>
        public decimal CurrentDeduction { get; set; }
    }

    /// <summary>Per staff member: what they owe and what moved in a period.</summary>
    public class HotelEmployeeLoanStaffReportRow
    {
        public int HotelStaffId { get; set; }
        public string StaffName { get; set; } = "";
        public string? Department { get; set; }
        public bool StaffIsActive { get; set; }
        public int ActiveLoans { get; set; }
        public decimal Outstanding { get; set; }
        public decimal DisbursedInPeriod { get; set; }
        public decimal RepaidCashInPeriod { get; set; }
        public decimal RepaidPayrollInPeriod { get; set; }
        public decimal InterestInPeriod { get; set; }
        public DateTime? LastRepaymentDate { get; set; }
        public decimal TotalEver { get; set; }
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

    public class HotelEmployeeLoanUpdateRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        public string LoanType { get; set; } = "SalaryAdvance";
        public decimal PrincipalAmount { get; set; }
        public decimal InterestAmount { get; set; }
        public string RepaymentMethod { get; set; } = "Cash";
        public decimal DefaultPayrollDeduction { get; set; }
        public string? ExpectedEndDate { get; set; }
        public string? Reference { get; set; }
        public string? Notes { get; set; }
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

    // ── Payroll deductions ────────────────────────────────────────────────

    /// <summary>One loan deduction on a payroll line, as sent by the payroll screen.</summary>
    public class HotelPayrollLoanDeductionInput
    {
        public int LoanId { get; set; }
        public decimal Amount { get; set; }
    }

    /// <summary>A loan deduction on a payroll run, as stored.</summary>
    public class HotelPayrollDeductionModel
    {
        public int HotelPayrollDeductionId { get; set; }
        public int HotelPayrollItemId { get; set; }
        public int HotelStaffId { get; set; }
        public int HotelEmployeeLoanId { get; set; }
        public string? LoanNumber { get; set; }
        public string LoanType { get; set; } = "";
        public string DeductionType { get; set; } = "";
        public decimal Amount { get; set; }
        public string Status { get; set; } = "Draft";
        public int? HotelEmployeeLoanRepaymentId { get; set; }
        public decimal OutstandingBalance { get; set; }
    }
}
