// 451. Generic payroll, the Poultry way: runs with reopen / delete / YTD details,
// structured deductions and templates. Ported from the Poultry payroll models.
// Run / item classes are GenericPay* because GenericPayroll* (the older
// api/generic-company payroll) already exist.
using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    public class GenericPayRunModel
    {
        [Key] public int GenericPayrollRunId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;

        [Required] public DateTime PeriodStart { get; set; }
        [Required] public DateTime PeriodEnd { get; set; }
        public DateTime? PayDate { get; set; }

        public decimal TotalGrossPay { get; set; }
        public decimal TotalDeductions { get; set; }
        public decimal TotalNetPay { get; set; }

        [StringLength(20)] public string Status { get; set; } = "Draft";

        public int? GenericCashAccountId { get; set; }
        public string? CashAccountName { get; set; }

        [StringLength(1000)] public string? Notes { get; set; }

        public string? CreatedBy { get; set; }
        public string? ApprovedBy { get; set; }
        public DateTime? ApprovedAt { get; set; }
        public string? PaidBy { get; set; }
        public DateTime? PaidAt { get; set; }

        // Audit trail for Unapprove/Reapprove cycle.
        public string?   ReopenedBy { get; set; }
        public DateTime? ReopenedAt { get; set; }
        [StringLength(500)] public string? ReopenReason { get; set; }
        public string?   ReapprovedBy { get; set; }
        public DateTime? ReapprovedAt { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }

        public List<GenericPayItemModel> Items { get; set; } = new();
    }

    public class GenericPayItemModel
    {
        [Key] public int GenericPayrollItemId { get; set; }
        public int GenericPayrollRunId { get; set; }
        [Required] public int GenericStaffId { get; set; }
        public string? StaffName { get; set; }
        public string? StaffRole { get; set; }

        [Range(0, double.MaxValue)] public decimal BasicPay { get; set; }
        [Range(0, double.MaxValue)] public decimal DailyWage { get; set; }
        [Range(0, double.MaxValue)] public decimal Commission { get; set; }
        [Range(0, double.MaxValue)] public decimal Bonus { get; set; }
        [Range(0, double.MaxValue)] public decimal Deductions { get; set; }
        public decimal NetPay { get; set; } // computed column on the table

        [StringLength(20)] public string? PaymentMethod { get; set; }
        [StringLength(500)] public string? Notes { get; set; }

        public DateTime CreatedAt { get; set; }
    }

    public class GenericPayRunCreateRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required] public DateTime PeriodStart { get; set; }
        [Required] public DateTime PeriodEnd { get; set; }
        public DateTime? PayDate { get; set; }
        public int? GenericCashAccountId { get; set; }
        [StringLength(1000)] public string? Notes { get; set; }
    }

    public class GenericPayItemUpsertRequest
    {
        [Required] public int GenericStaffId { get; set; }
        public decimal BasicPay { get; set; }
        public decimal DailyWage { get; set; }
        public decimal Commission { get; set; }
        public decimal Bonus { get; set; }
        /// <summary>Old meaning: the line's TOTAL deductions. Ignored when OtherDeductions is sent.</summary>
        public decimal Deductions { get; set; }
        [StringLength(20)] public string? PaymentMethod { get; set; }
        [StringLength(500)] public string? Notes { get; set; }
        /// <summary>442. The typed "Other deductions" only (advances and kept credit are separate rows).</summary>
        public decimal? OtherDeductions { get; set; }
        /// <summary>442. Wages kept as employee credit on this line. Null = leave as is, 0 = remove.</summary>
        public decimal? EmployeeCredit { get; set; }
    }

    public class GenericPayRunMarkPaidRequest
    {
        public DateTime? PayDate { get; set; }
    }

    public class GenericPayRunCancelRequest
    {
        [StringLength(500)] public string? Reason { get; set; }
    }

    // Payload returned by spGenericPayrollRun_GetDetailsWithYtd (4 result sets).
    public class GenericPayRunDetailsModel
    {
        public GenericPayRunModel? Run { get; set; }
        public GenericPayYtdTotals? YtdTotals { get; set; }
        public List<GenericPayYtdStaffRow> YtdByStaff { get; set; } = new();
        public GenericPayLinkedExpense? LinkedExpense { get; set; }
    }

    public class GenericPayYtdTotals
    {
        public int     Year             { get; set; }
        public decimal YtdGrossPaid     { get; set; }
        public decimal YtdDeductions    { get; set; }
        public decimal YtdNetPaid       { get; set; }
        public int     TotalPayrollRuns { get; set; }
        public int     TotalStaffPaid   { get; set; }
    }

    public class GenericPayYtdStaffRow
    {
        public int     GenericStaffId { get; set; }
        public string? StaffName      { get; set; }
        public string? StaffRole      { get; set; }
        public decimal YtdBasic       { get; set; }
        public decimal YtdDaily       { get; set; }
        public decimal YtdCommission  { get; set; }
        public decimal YtdBonus       { get; set; }
        public decimal YtdDeductions  { get; set; }
        public decimal YtdGross       { get; set; }
        public decimal YtdNet         { get; set; }
    }

    // Generic linked expense (dbo.Expense: free-text Category, no approval flow).
    public class GenericPayLinkedExpense
    {
        public int      ExpenseId     { get; set; }
        public string   FarmId        { get; set; } = string.Empty;
        public DateTime ExpenseDate   { get; set; }
        public string?  Category      { get; set; }
        public string?  Description   { get; set; }
        public decimal  Amount        { get; set; }
        public string?  PaymentMethod { get; set; }
        public string?  SourceType    { get; set; }
        public int?     SourceId      { get; set; }
        public DateTime CreatedDate   { get; set; }
    }

    public class GenericPayrollDeductionModel
    {
        /// <summary>Null on the synthetic legacy row -- it is a leftover, not a record.</summary>
        public int? GenericPayrollItemDeductionId { get; set; }
        public int GenericPayrollItemId { get; set; }
        public int GenericStaffId { get; set; }
        public string DeductionType { get; set; } = "OtherDeduction";
        public decimal Amount { get; set; }

        public int? GenericEmployeeLoanId { get; set; }
        public string? LoanNumber { get; set; }
        public string? LoanType { get; set; }
        public decimal? LoanOutstanding { get; set; }
        public int? GenericEmployeeLoanRepaymentId { get; set; }

        public string? Description { get; set; }
        public string? Reference { get; set; }
        public string Status { get; set; } = "Draft";
        /// <summary>True for the unexplained remainder of a pre-306 deduction.</summary>
        public bool IsLegacy { get; set; }

        public string? CreatedBy { get; set; }
        public DateTime? CreatedAt { get; set; }
    }

    /// <summary>One row per payroll line: its totals, and what its advances suggest.</summary>
    public class GenericPayrollDeductionRunRow
    {
        public int GenericPayrollItemId { get; set; }
        public int GenericStaffId { get; set; }
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

    public class GenericPayrollDeductionSaveRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public int GenericPayrollItemId { get; set; }
        public string DeductionType { get; set; } = "OtherDeduction";
        public decimal Amount { get; set; }
        public int? GenericEmployeeLoanId { get; set; }
        public string? Description { get; set; }
        public string? Reference { get; set; }
        /// <summary>Given to edit an existing deduction, omitted to add one.</summary>
        public int? GenericPayrollItemDeductionId { get; set; }
        public string? SavedBy { get; set; }
    }

    public class GenericPayrollTemplateModel
    {
        public int GenericPayrollTemplateId { get; set; }
        public string Name { get; set; } = string.Empty;
        public string Frequency { get; set; } = "Monthly";
        public int? GenericCashAccountId { get; set; }
        public string? CashAccountName { get; set; }
        public string? Notes { get; set; }
        public bool IsActive { get; set; }
        public int LineCount { get; set; }
        public int StaffInactiveCount { get; set; }
        public decimal TotalGross { get; set; }
        public decimal TotalDeductions { get; set; }
        public decimal TotalNet { get; set; }
        public int RunCount { get; set; }
        public DateTime? LastPeriodStart { get; set; }
        public DateTime? LastPeriodEnd { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public string? UpdatedBy { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public List<GenericPayrollTemplateLineModel> Lines { get; set; } = new();
    }

    public class GenericPayrollTemplateLineModel
    {
        public int GenericPayrollTemplateLineId { get; set; }
        public int GenericStaffId { get; set; }
        public string? StaffName { get; set; }
        public string? StaffRole { get; set; }
        public bool StaffIsActive { get; set; }
        public decimal BasicPay { get; set; }
        public decimal DailyWage { get; set; }
        public decimal Commission { get; set; }
        public decimal Bonus { get; set; }
        public decimal Deductions { get; set; }
        public decimal NetPay { get; set; }
        public string? PaymentMethod { get; set; }
        public string? Notes { get; set; }
    }

    public class GenericPayrollTemplateLineInput
    {
        public int GenericStaffId { get; set; }
        public decimal BasicPay { get; set; }
        public decimal DailyWage { get; set; }
        public decimal Commission { get; set; }
        public decimal Bonus { get; set; }
        public decimal Deductions { get; set; }
        public string? PaymentMethod { get; set; }
        public string? Notes { get; set; }
    }

    public class GenericPayrollTemplateSaveRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public string Frequency { get; set; } = "Monthly";
        public int? GenericCashAccountId { get; set; }
        public string? Notes { get; set; }
        public string? SavedBy { get; set; }
        public List<GenericPayrollTemplateLineInput> Lines { get; set; } = new();
    }

    public class GenericPayrollTemplateSetActiveRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public bool IsActive { get; set; }
        public string? By { get; set; }
    }

    public class GenericPayrollTemplateCreateRunRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public DateTime PeriodStart { get; set; }
        public DateTime PeriodEnd { get; set; }
        public DateTime? PayDate { get; set; }
        public int? GenericCashAccountId { get; set; }
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
    }
}
