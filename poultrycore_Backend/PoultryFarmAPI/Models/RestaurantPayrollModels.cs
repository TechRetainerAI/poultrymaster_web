// Restaurant payroll and staff loans & advances (migration 326).
// Row DTOs mirror the sprestaurant_* result columns (read by name, ignoring
// case). Every class starts with "Restaurant" and is unique API-wide: Swagger
// keys schemas by class name, and a duplicate 500s the whole document.

namespace PoultryFarmAPIWeb.Models
{
    // ── Staff loans ─────────────────────────────────────────────────────────

    public class RestaurantStaffLoan
    {
        public int StaffLoanId { get; set; }
        public int RestaurantStaffId { get; set; }
        public string? StaffName { get; set; }
        public bool StaffIsActive { get; set; }
        public string LoanNumber { get; set; } = "";
        public string LoanType { get; set; } = "";
        public string Status { get; set; } = "";
        public decimal PrincipalAmount { get; set; }
        public decimal InterestAmount { get; set; }
        public decimal TotalRepayable { get; set; }
        public decimal TotalPrincipalRepaid { get; set; }
        public decimal TotalInterestRepaid { get; set; }
        public decimal OutstandingBalance { get; set; }
        public string RepaymentMethod { get; set; } = "";
        public decimal DefaultPayrollDeduction { get; set; }
        public DateTime? DisbursementDate { get; set; }
        public DateTime? ExpectedEndDate { get; set; }
        public int? CashAccountId { get; set; }
        public string? CashAccountName { get; set; }
        public string? Reference { get; set; }
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public string? ClosedBy { get; set; }
        public string? ClosedReason { get; set; }
        public DateTime? ClosedAt { get; set; }
        public int RepaymentCount { get; set; }
        public DateTime? LastRepaymentDate { get; set; }
        /// <summary>Amount draft payroll runs are already set to deduct from this loan.</summary>
        public decimal DraftPayrollClaims { get; set; }
    }

    public class RestaurantStaffLoanRepayment
    {
        public int RepaymentId { get; set; }
        public int StaffLoanId { get; set; }
        public string? LoanNumber { get; set; }
        public int RestaurantStaffId { get; set; }
        public string? StaffName { get; set; }
        public decimal Amount { get; set; }
        public decimal PrincipalAmount { get; set; }
        public decimal InterestAmount { get; set; }
        public string SourceType { get; set; } = "";
        public int? CashAccountId { get; set; }
        public string? CashAccountName { get; set; }
        public int? PayrollRunId { get; set; }
        public string? PayrollRunNumber { get; set; }
        public decimal BalanceBefore { get; set; }
        public decimal BalanceAfter { get; set; }
        public DateTime RepaymentDate { get; set; }
        public string? Reference { get; set; }
        public string? Notes { get; set; }
        public string Status { get; set; } = "";
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public string? ReversedBy { get; set; }
        public string? ReversedReason { get; set; }
        public DateTime? ReversedAt { get; set; }
    }

    public class RestaurantStaffLoanSummary
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

    public class RestaurantStaffLoanEligible
    {
        public int StaffLoanId { get; set; }
        public string LoanNumber { get; set; } = "";
        public string LoanType { get; set; } = "";
        public string RepaymentMethod { get; set; } = "";
        public decimal OutstandingBalance { get; set; }
        public decimal DefaultPayrollDeduction { get; set; }
        public decimal ClaimedElsewhere { get; set; }
        public decimal Available { get; set; }
        public decimal SuggestedDeduction { get; set; }
        public decimal CurrentDeduction { get; set; }
    }

    public class RestaurantStaffLoanStaffRow
    {
        public int RestaurantStaffId { get; set; }
        public string? StaffName { get; set; }
        public string? Role { get; set; }
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

    public class RestaurantStaffLoanCreateRequest
    {
        public int RestaurantStaffId { get; set; }
        public string LoanType { get; set; } = "SalaryAdvance";
        public decimal PrincipalAmount { get; set; }
        public decimal InterestAmount { get; set; }
        public string RepaymentMethod { get; set; } = "PayrollDeduction";
        public decimal DefaultPayrollDeduction { get; set; }
        public DateTime? ExpectedEndDate { get; set; }
        public string? Reference { get; set; }
        public string? Notes { get; set; }
        public bool DisburseNow { get; set; }
        public int? CashAccountId { get; set; }
        public DateTime? DisbursementDate { get; set; }
    }

    public class RestaurantStaffLoanUpdateRequest
    {
        public string LoanType { get; set; } = "SalaryAdvance";
        public decimal PrincipalAmount { get; set; }
        public decimal InterestAmount { get; set; }
        public string RepaymentMethod { get; set; } = "PayrollDeduction";
        public decimal DefaultPayrollDeduction { get; set; }
        public DateTime? ExpectedEndDate { get; set; }
        public string? Reference { get; set; }
        public string? Notes { get; set; }
    }

    public class RestaurantStaffLoanDisburseRequest
    {
        public int? CashAccountId { get; set; }
        public DateTime? DisbursementDate { get; set; }
        public string? Reference { get; set; }
    }

    public class RestaurantStaffLoanRepayRequest
    {
        public decimal Amount { get; set; }
        /// <summary>Cash, MoMo, Bank or Other. Payroll repayments come only from approving a payroll run.</summary>
        public string SourceType { get; set; } = "Cash";
        public int? CashAccountId { get; set; }
        public DateTime? RepaymentDate { get; set; }
        public string? Reference { get; set; }
        public string? Notes { get; set; }
    }

    // ── Payroll ─────────────────────────────────────────────────────────────

    public class RestaurantPayrollRun
    {
        public int PayrollRunId { get; set; }
        public string RunNumber { get; set; } = "";
        public DateTime PeriodStart { get; set; }
        public DateTime PeriodEnd { get; set; }
        public DateTime PayDate { get; set; }
        public string Status { get; set; } = "";
        public int? CashAccountId { get; set; }
        public string? CashAccountName { get; set; }
        public decimal TotalGross { get; set; }
        public decimal TotalDeductions { get; set; }
        public decimal TotalLoanDeductions { get; set; }
        public decimal TotalNet { get; set; }
        public int LineCount { get; set; }
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public string? ApprovedBy { get; set; }
        public DateTime? ApprovedAt { get; set; }
        public string? PaidBy { get; set; }
        public DateTime? PaidAt { get; set; }
        public string? CancelledBy { get; set; }
        public string? CancelReason { get; set; }
        public string? ReopenedBy { get; set; }
        public string? ReopenReason { get; set; }
    }

    public class RestaurantPayrollLine
    {
        public int PayrollLineId { get; set; }
        public int PayrollRunId { get; set; }
        public int RestaurantStaffId { get; set; }
        public string? StaffName { get; set; }
        public string? StaffRole { get; set; }
        public string? SalaryType { get; set; }
        public decimal BasicPay { get; set; }
        public decimal Allowances { get; set; }
        public decimal Overtime { get; set; }
        public decimal Bonus { get; set; }
        public decimal OtherDeductions { get; set; }
        public decimal LoanDeductions { get; set; }
        public decimal GrossPay { get; set; }
        public decimal NetPay { get; set; }
        public string PaymentMethod { get; set; } = "Cash";
        public string? Notes { get; set; }
    }

    public class RestaurantPayrollDeduction
    {
        public int PayrollDeductionId { get; set; }
        public int PayrollLineId { get; set; }
        public int RestaurantStaffId { get; set; }
        public int StaffLoanId { get; set; }
        public string? LoanNumber { get; set; }
        public string LoanType { get; set; } = "";
        public string DeductionType { get; set; } = "";
        public decimal Amount { get; set; }
        public string Status { get; set; } = "";
        public int? RepaymentId { get; set; }
        public decimal OutstandingBalance { get; set; }
    }

    public class RestaurantPayrollRunDetail
    {
        public RestaurantPayrollRun? Run { get; set; }
        public List<RestaurantPayrollLine> Lines { get; set; } = new();
        public List<RestaurantPayrollDeduction> Deductions { get; set; } = new();
    }

    public class RestaurantPayrollReportRow
    {
        public int RestaurantStaffId { get; set; }
        public string? StaffName { get; set; }
        public string? StaffRole { get; set; }
        public int Runs { get; set; }
        public decimal BasicPay { get; set; }
        public decimal Extras { get; set; }
        public decimal GrossPay { get; set; }
        public decimal OtherDeductions { get; set; }
        public decimal LoanDeductions { get; set; }
        public decimal NetPay { get; set; }
    }

    public class RestaurantPayrollRunRequest
    {
        public DateTime PeriodStart { get; set; }
        public DateTime PeriodEnd { get; set; }
        public DateTime? PayDate { get; set; }
        public int? CashAccountId { get; set; }
        public string? Notes { get; set; }
    }

    public class RestaurantPayrollLoanDeductionInput
    {
        public int LoanId { get; set; }
        public decimal Amount { get; set; }
    }

    public class RestaurantPayrollLineRequest
    {
        public int RestaurantStaffId { get; set; }
        public decimal BasicPay { get; set; }
        public decimal Allowances { get; set; }
        public decimal Overtime { get; set; }
        public decimal Bonus { get; set; }
        /// <summary>Tax, penalties and the like. Staff loan repayments go in LoanDeductions.</summary>
        public decimal OtherDeductions { get; set; }
        public string? PaymentMethod { get; set; }
        public string? Notes { get; set; }
        /// <summary>null keeps the line's loan deductions; a list replaces them (empty removes all).</summary>
        public List<RestaurantPayrollLoanDeductionInput>? LoanDeductions { get; set; }
    }

    public class RestaurantPayrollPayRequest
    {
        public DateTime? PayDate { get; set; }
        public int? CashAccountId { get; set; }
    }
}
