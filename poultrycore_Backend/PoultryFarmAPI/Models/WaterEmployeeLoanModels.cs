// Employee Loans & Advances, water side (migrations 313/314).
//
// Money the company LENDS TO STAFF -- a receivable. The mirror image of
// WaterLoanModels, which is money the company borrowed. Nothing here is ever
// an expense at disbursement and nothing here is ever revenue when repaid; the
// rules live in the SQL functions and these types only carry the values.

namespace PoultryFarmAPIWeb.Models
{
    // ======================================================================
    // The advance
    // ======================================================================
    public class WaterEmployeeLoanModel
    {
        public int WaterEmployeeLoanId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public int WaterStaffId { get; set; }
        public string? StaffName { get; set; }
        public string? StaffRole { get; set; }

        public string? LoanNumber { get; set; }
        public string LoanType { get; set; } = "EmployeeLoan";

        public decimal PrincipalAmount { get; set; }
        public bool InterestEnabled { get; set; }
        public decimal InterestAmount { get; set; }
        public decimal? InterestRate { get; set; }
        public string? InterestType { get; set; }
        /// <summary>Principal + interest. What the worker owes in total.</summary>
        public decimal TotalRepayable { get; set; }

        public DateTime DisbursementDate { get; set; }
        public string RepaymentMethod { get; set; } = "PayrollDeduction";
        /// <summary>A suggestion for payroll. Nothing posts because it is set.</summary>
        public decimal? DefaultPayrollDeduction { get; set; }
        public DateTime? ExpectedStartDate { get; set; }
        public DateTime? ExpectedEndDate { get; set; }

        public string? Purpose { get; set; }
        public string? Description { get; set; }
        public string? Notes { get; set; }

        public string Status { get; set; } = "Draft";
        public DateTime? PaidAt { get; set; }

        public decimal TotalRepaid { get; set; }
        public decimal TotalPrincipalRepaid { get; set; }
        public decimal TotalInterestRepaid { get; set; }
        public decimal OutstandingBalance { get; set; }
        public int RepaymentCount { get; set; }

        public int? WaterCashAccountId { get; set; }
        public string? CashAccountName { get; set; }
        public string? PaymentMethod { get; set; }
        public string? ReferenceNumber { get; set; }
        public int? WaterCashTransactionId { get; set; }
        public string? DisbursedBy { get; set; }
        public DateTime? DisbursedAt { get; set; }

        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public string? ReversedBy { get; set; }
        public DateTime? ReversedAt { get; set; }
        public string? ReversalReason { get; set; }
    }

    /// <summary>A page of advances plus how many there are in total.</summary>
    public class WaterEmployeeLoanPage
    {
        public List<WaterEmployeeLoanModel> Items { get; set; } = new();
        public long TotalCount { get; set; }
    }

    // ======================================================================
    // The repayment
    // ======================================================================
    public class WaterEmployeeLoanRepaymentModel
    {
        public int WaterEmployeeLoanRepaymentId { get; set; }
        public int WaterEmployeeLoanId { get; set; }
        public int WaterStaffId { get; set; }
        public string? StaffName { get; set; }

        public string? RepaymentNumber { get; set; }
        public DateTime RepaymentDate { get; set; }

        public decimal Amount { get; set; }
        public decimal PrincipalAmount { get; set; }
        public decimal InterestAmount { get; set; }

        /// <summary>Payroll | ManualCash | Bank | MoMo | Other.</summary>
        public string SourceType { get; set; } = "ManualCash";

        public int? WaterPayrollRunId { get; set; }
        public DateTime? PayrollPeriodStart { get; set; }
        public DateTime? PayrollPeriodEnd { get; set; }
        public int? WaterPayrollItemId { get; set; }
        public int? WaterPayrollDeductionId { get; set; }

        /// <summary>Always null for a payroll repayment: no money moved.</summary>
        public int? WaterCashAccountId { get; set; }
        public string? CashAccountName { get; set; }
        public string? PaymentMethod { get; set; }
        public string? ReferenceNumber { get; set; }
        public string? Description { get; set; }
        public string? Notes { get; set; }

        public decimal BalanceBefore { get; set; }
        public decimal BalanceAfter { get; set; }
        public string Status { get; set; } = "Posted";

        public int? WaterCashTransactionId { get; set; }
        public int? ReversalCashTransactionId { get; set; }

        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public string? ReversedBy { get; set; }
        public DateTime? ReversedAt { get; set; }
        public string? ReversalReason { get; set; }
    }

    // ======================================================================
    // Summary + eligibility
    // ======================================================================
    public class WaterEmployeeLoanSummary
    {
        public decimal OutstandingTotal { get; set; }
        public decimal DisbursedInPeriod { get; set; }
        public decimal RepaidInPeriod { get; set; }
        public int ActiveLoans { get; set; }
        public int StaffWithActiveLoans { get; set; }
        public int PaidLoans { get; set; }
        public int DraftLoans { get; set; }
    }

    /// <summary>An advance a payroll deduction may legally be applied to.</summary>
    public class WaterEmployeeLoanEligible
    {
        public int WaterEmployeeLoanId { get; set; }
        public string? LoanNumber { get; set; }
        public string LoanType { get; set; } = "EmployeeLoan";
        public decimal OutstandingBalance { get; set; }
        public decimal? DefaultPayrollDeduction { get; set; }
        public string? RepaymentMethod { get; set; }
        public DateTime DisbursementDate { get; set; }
    }

    // ======================================================================
    // Requests
    // ======================================================================
    public class WaterEmployeeLoanCreateRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public int WaterStaffId { get; set; }
        public decimal PrincipalAmount { get; set; }
        public DateTime DisbursementDate { get; set; }
        public string? LoanType { get; set; }

        public bool InterestEnabled { get; set; }
        public decimal? InterestAmount { get; set; }
        public decimal? InterestRate { get; set; }
        public string? InterestType { get; set; }

        public string? RepaymentMethod { get; set; }
        public decimal? DefaultPayrollDeduction { get; set; }
        public DateTime? ExpectedStartDate { get; set; }
        public DateTime? ExpectedEndDate { get; set; }

        public string? Purpose { get; set; }
        public string? Description { get; set; }
        public string? Notes { get; set; }

        /// <summary>
        /// True hands the money over now and makes the advance Active. False
        /// records the agreement only: a Draft owes nothing and has no cash row.
        /// </summary>
        public bool DisburseNow { get; set; }
        public int? WaterCashAccountId { get; set; }
        public string? PaymentMethod { get; set; }
        public string? ReferenceNumber { get; set; }
        public string? CreatedBy { get; set; }
    }

    public class WaterEmployeeLoanUpdateRequest
    {
        public string FarmId { get; set; } = string.Empty;
        /// <summary>Refused once the advance is disbursed -- that is history.</summary>
        public decimal? PrincipalAmount { get; set; }
        public DateTime? DisbursementDate { get; set; }
        public string? LoanType { get; set; }
        public bool? InterestEnabled { get; set; }
        public decimal? InterestAmount { get; set; }
        public decimal? InterestRate { get; set; }
        public string? InterestType { get; set; }
        public string? RepaymentMethod { get; set; }
        public decimal? DefaultPayrollDeduction { get; set; }
        public DateTime? ExpectedStartDate { get; set; }
        public DateTime? ExpectedEndDate { get; set; }
        public string? Purpose { get; set; }
        public string? Description { get; set; }
        public string? Notes { get; set; }
        public string? UpdatedBy { get; set; }
    }

    public class WaterEmployeeLoanDisburseRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public int WaterCashAccountId { get; set; }
        public string? PaymentMethod { get; set; }
        public string? ReferenceNumber { get; set; }
        public string? DisbursedBy { get; set; }
    }

    public class WaterEmployeeLoanReasonRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public string? Reason { get; set; }
        public string? ActionBy { get; set; }
    }

    public class WaterEmployeeLoanRepaymentRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public int WaterEmployeeLoanId { get; set; }
        public decimal Amount { get; set; }
        /// <summary>
        /// ManualCash | Bank | MoMo | Other. 'Payroll' is rejected by the
        /// controller: a payroll repayment is posted by approving the payroll,
        /// never by calling this.
        /// </summary>
        public string? SourceType { get; set; }
        public decimal? PrincipalAmount { get; set; }
        public decimal? InterestAmount { get; set; }
        public DateTime? RepaymentDate { get; set; }
        public int? WaterCashAccountId { get; set; }
        public string? PaymentMethod { get; set; }
        public string? ReferenceNumber { get; set; }
        public string? Description { get; set; }
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
    }

    // ======================================================================
    // Structured payroll deductions (314)
    // ======================================================================
    public class WaterPayrollDeductionModel
    {
        /// <summary>Null on the synthetic legacy row -- it is a leftover, not a record.</summary>
        public int? WaterPayrollItemDeductionId { get; set; }
        public int WaterPayrollItemId { get; set; }
        public int WaterStaffId { get; set; }
        public string DeductionType { get; set; } = "OtherDeduction";
        public decimal Amount { get; set; }

        public int? WaterEmployeeLoanId { get; set; }
        public string? LoanNumber { get; set; }
        public string? LoanType { get; set; }
        public decimal? LoanOutstanding { get; set; }
        public int? WaterEmployeeLoanRepaymentId { get; set; }

        public string? Description { get; set; }
        public string? Reference { get; set; }
        public string Status { get; set; } = "Draft";
        /// <summary>True for the unexplained remainder of a pre-314 deduction.</summary>
        public bool IsLegacy { get; set; }

        public string? CreatedBy { get; set; }
        public DateTime? CreatedAt { get; set; }
    }

    /// <summary>One row per payroll line: its totals, and what its advances suggest.</summary>
    public class WaterPayrollDeductionRunRow
    {
        public int WaterPayrollItemId { get; set; }
        public int WaterStaffId { get; set; }
        public string? StaffName { get; set; }
        public decimal Deductions { get; set; }
        public decimal LegacyDeductions { get; set; }
        public decimal StructuredTotal { get; set; }
        public int StructuredCount { get; set; }
        public decimal LoanRepaymentTotal { get; set; }
        public int ActiveLoanCount { get; set; }
        public decimal ActiveLoanOutstanding { get; set; }
        public decimal SuggestedDeduction { get; set; }
    }

    public class WaterPayrollDeductionSaveRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public int WaterPayrollItemId { get; set; }
        public string DeductionType { get; set; } = "OtherDeduction";
        public decimal Amount { get; set; }
        public int? WaterEmployeeLoanId { get; set; }
        public string? Description { get; set; }
        public string? Reference { get; set; }
        /// <summary>Given to edit an existing deduction, omitted to add one.</summary>
        public int? WaterPayrollItemDeductionId { get; set; }
        public string? SavedBy { get; set; }
    }
}
