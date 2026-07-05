using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    public static class PoultryStaffRoles
    {
        public const string FarmManager      = "FarmManager";
        public const string Supervisor       = "Supervisor";
        public const string FarmHand         = "FarmHand";
        public const string VaccinatorHealth = "VaccinatorHealth";
        public const string FeedMillOperator = "FeedMillOperator";
        public const string EggCollector     = "EggCollector";
        public const string Salesperson      = "Salesperson";
        public const string Accountant       = "Accountant";
        public const string Cleaner          = "Cleaner";
        public const string Security         = "Security";
        public const string Driver           = "Driver";
        public const string Other            = "Other";
    }

    public static class PoultryStaffSalaryTypes
    {
        public const string Daily      = "Daily";
        public const string Weekly     = "Weekly";
        public const string Monthly    = "Monthly";
        public const string Commission = "Commission";
        public const string Mixed      = "Mixed";
    }

    public static class PoultryStaffAttendanceStatus
    {
        public const string Present = "Present";
        public const string Absent  = "Absent";
        public const string Late    = "Late";
        public const string HalfDay = "HalfDay";
        public const string OffDay  = "OffDay";
    }

    public static class PoultryPayrollStatus
    {
        public const string Draft     = "Draft";
        public const string Approved  = "Approved";
        public const string Paid      = "Paid";
        public const string Reopened  = "Reopened";
        public const string Cancelled = "Cancelled";
    }

    // ====================================================================
    // Staff
    // ====================================================================
    public class PoultryStaffModel
    {
        [Key] public int PoultryStaffId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;

        [Required, StringLength(100)] public string FirstName { get; set; } = string.Empty;
        [Required, StringLength(100)] public string LastName  { get; set; } = string.Empty;

        [StringLength(50)]  public string? PhoneNumber { get; set; }
        [StringLength(200)] public string? Email { get; set; }

        [Required, StringLength(40)] public string Role { get; set; } = PoultryStaffRoles.Other;
        [Required, StringLength(20)] public string SalaryType { get; set; } = PoultryStaffSalaryTypes.Monthly;

        [Range(0, double.MaxValue)] public decimal BasePay { get; set; }
        public decimal? CommissionRate { get; set; }

        public bool IsActive { get; set; } = true;
        public bool IsDeleted { get; set; }

        [StringLength(1000)] public string? Notes { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    // ====================================================================
    // Attendance
    // ====================================================================
    public class PoultryStaffAttendanceModel
    {
        [Key] public int PoultryStaffAttendanceId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required] public int PoultryStaffId { get; set; }
        public string? StaffName { get; set; } // SP join

        [Required] public DateTime AttendanceDate { get; set; }
        public DateTime? ClockIn { get; set; }
        public DateTime? ClockOut { get; set; }

        [StringLength(30)] public string? Shift { get; set; }
        [Required, StringLength(20)] public string Status { get; set; } = PoultryStaffAttendanceStatus.Present;

        [StringLength(500)] public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    public class PoultryStaffAttendanceUpsertRequest
    {
        [Required] public int PoultryStaffId { get; set; }
        [Required] public DateTime AttendanceDate { get; set; }
        public DateTime? ClockIn { get; set; }
        public DateTime? ClockOut { get; set; }
        [StringLength(30)] public string? Shift { get; set; }
        [Required, StringLength(20)] public string Status { get; set; } = PoultryStaffAttendanceStatus.Present;
        [StringLength(500)] public string? Notes { get; set; }
    }

    // ====================================================================
    // Payroll Run + Items
    // ====================================================================
    public class PoultryPayrollRunModel
    {
        [Key] public int PoultryPayrollRunId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;

        [Required] public DateTime PeriodStart { get; set; }
        [Required] public DateTime PeriodEnd { get; set; }
        public DateTime? PayDate { get; set; }

        public decimal TotalGrossPay { get; set; }
        public decimal TotalDeductions { get; set; }
        public decimal TotalNetPay { get; set; }

        [StringLength(20)] public string Status { get; set; } = PoultryPayrollStatus.Draft;

        public int? PoultryCashAccountId { get; set; }
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

        public List<PoultryPayrollItemModel> Items { get; set; } = new();
    }

    public class PoultryPayrollItemModel
    {
        [Key] public int PoultryPayrollItemId { get; set; }
        public int PoultryPayrollRunId { get; set; }
        [Required] public int PoultryStaffId { get; set; }
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

    public class PoultryPayrollRunCreateRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required] public DateTime PeriodStart { get; set; }
        [Required] public DateTime PeriodEnd { get; set; }
        public DateTime? PayDate { get; set; }
        public int? PoultryCashAccountId { get; set; }
        [StringLength(1000)] public string? Notes { get; set; }
    }

    public class PoultryPayrollItemUpsertRequest
    {
        [Required] public int PoultryStaffId { get; set; }
        public decimal BasicPay { get; set; }
        public decimal DailyWage { get; set; }
        public decimal Commission { get; set; }
        public decimal Bonus { get; set; }
        public decimal Deductions { get; set; }
        [StringLength(20)] public string? PaymentMethod { get; set; }
        [StringLength(500)] public string? Notes { get; set; }
    }

    public class PoultryPayrollRunMarkPaidRequest
    {
        public DateTime? PayDate { get; set; }
    }

    public class PoultryPayrollRunCancelRequest
    {
        [StringLength(500)] public string? Reason { get; set; }
    }

    // Payload returned by spPoultryPayrollRun_GetDetailsWithYtd (4 result sets).
    public class PoultryPayrollRunDetailsModel
    {
        public PoultryPayrollRunModel? Run { get; set; }
        public PoultryPayrollYtdTotals? YtdTotals { get; set; }
        public List<PoultryPayrollYtdStaffRow> YtdByStaff { get; set; } = new();
        public PoultryPayrollLinkedExpense? LinkedExpense { get; set; }
    }

    public class PoultryPayrollYtdTotals
    {
        public int     Year             { get; set; }
        public decimal YtdGrossPaid     { get; set; }
        public decimal YtdDeductions    { get; set; }
        public decimal YtdNetPaid       { get; set; }
        public int     TotalPayrollRuns { get; set; }
        public int     TotalStaffPaid   { get; set; }
    }

    public class PoultryPayrollYtdStaffRow
    {
        public int     PoultryStaffId { get; set; }
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

    // Poultry linked expense (dbo.Expense: free-text Category, no approval flow).
    public class PoultryPayrollLinkedExpense
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
}
