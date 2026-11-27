// Generic Employee Loans & Advances (migration 387).
//
// Money the company LENDS TO STAFF -- a receivable. The mirror image of
// GenericLoanModels, which is money the company borrowed. Nothing here is ever
// an expense at disbursement and nothing here is ever revenue when repaid; the
// rules live in the SQL functions and these types only carry the values.

namespace PoultryFarmAPIWeb.Models
{
    // ======================================================================
    // The advance
    // ======================================================================
    public class GenericEmployeeLoanModel
    {
        public int GenericEmployeeLoanId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public int GenericStaffId { get; set; }
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

        public int? GenericCashAccountId { get; set; }
        public string? CashAccountName { get; set; }
        public string? PaymentMethod { get; set; }
        public string? ReferenceNumber { get; set; }
        public int? GenericCashTransactionId { get; set; }
        public string? DisbursedBy { get; set; }
        public DateTime? DisbursedAt { get; set; }

        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public string? ReversedBy { get; set; }
        public DateTime? ReversedAt { get; set; }
        public string? ReversalReason { get; set; }
    }

    /// <summary>A page of advances plus how many there are in total.</summary>
    public class GenericEmployeeLoanPage
    {
        public List<GenericEmployeeLoanModel> Items { get; set; } = new();
        public long TotalCount { get; set; }
    }

    // ======================================================================
    // The repayment
    // ======================================================================
    public class GenericEmployeeLoanRepaymentModel
    {
        public int GenericEmployeeLoanRepaymentId { get; set; }
        public int GenericEmployeeLoanId { get; set; }
        public int GenericStaffId { get; set; }
        public string? StaffName { get; set; }

        public string? RepaymentNumber { get; set; }
        public DateTime RepaymentDate { get; set; }

        public decimal Amount { get; set; }
        public decimal PrincipalAmount { get; set; }
        public decimal InterestAmount { get; set; }

        /// <summary>Payroll | ManualCash | Bank | MoMo | Other.</summary>
        public string SourceType { get; set; } = "ManualCash";

        public int? GenericPayrollRunId { get; set; }
        public DateTime? PayrollPeriodStart { get; set; }
        public DateTime? PayrollPeriodEnd { get; set; }
        public int? GenericPayrollItemId { get; set; }

        /// <summary>Always null for a payroll repayment: no money moved.</summary>
        public int? GenericCashAccountId { get; set; }
        public string? CashAccountName { get; set; }
        public string? PaymentMethod { get; set; }
        public string? ReferenceNumber { get; set; }
        public string? Description { get; set; }
        public string? Notes { get; set; }

        public decimal BalanceBefore { get; set; }
        public decimal BalanceAfter { get; set; }
        public string Status { get; set; } = "Posted";

        public int? GenericCashTransactionId { get; set; }
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
    public class GenericEmployeeLoanSummary
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
    public class GenericEmployeeLoanEligible
    {
        public int GenericEmployeeLoanId { get; set; }
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
    public class GenericEmployeeLoanCreateRequest
    {
        public string FarmId { get; set; } = string.Empty;
        /// <summary>Projects & Contracts (501): an advance taken FOR a project -- { projectId } or { splits }. Absent / null projectId = personal (General).</summary>
        public System.Text.Json.JsonElement? Projects { get; set; }
        public int GenericStaffId { get; set; }
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
        public int? GenericCashAccountId { get; set; }
        public string? PaymentMethod { get; set; }
        public string? ReferenceNumber { get; set; }
        public string? CreatedBy { get; set; }
    }

    public class GenericEmployeeLoanUpdateRequest
    {
        public string FarmId { get; set; } = string.Empty;
        /// <summary>Projects & Contracts (501): an advance taken FOR a project -- { projectId } or { splits }. Absent / null projectId = personal (General).</summary>
        public System.Text.Json.JsonElement? Projects { get; set; }
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

    public class GenericEmployeeLoanDisburseRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public int GenericCashAccountId { get; set; }
        public string? PaymentMethod { get; set; }
        public string? ReferenceNumber { get; set; }
        public string? DisbursedBy { get; set; }
    }

    public class GenericEmployeeLoanReasonRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public string? Reason { get; set; }
        public string? ActionBy { get; set; }
    }

    public class GenericEmployeeLoanRepaymentRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public int GenericEmployeeLoanId { get; set; }
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
        public int? GenericCashAccountId { get; set; }
        public string? PaymentMethod { get; set; }
        public string? ReferenceNumber { get; set; }
        public string? Description { get; set; }
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
    }
}
