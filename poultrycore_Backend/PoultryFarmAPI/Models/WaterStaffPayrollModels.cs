using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    public static class WaterStaffRoles
    {
        public const string MachineOperator  = "MachineOperator";
        public const string PackagingWorker  = "PackagingWorker";
        public const string Loader           = "Loader";
        public const string Driver           = "Driver";
        public const string MotorKingRider   = "MotorKingRider";
        public const string Salesperson      = "Salesperson";
        public const string FactoryManager   = "FactoryManager";
        public const string Accountant       = "Accountant";
        public const string Cleaner          = "Cleaner";
        public const string Security         = "Security";
        public const string Other            = "Other";
    }

    public static class WaterStaffSalaryTypes
    {
        public const string Daily       = "Daily";
        public const string Weekly      = "Weekly";
        public const string Monthly     = "Monthly";
        public const string Commission  = "Commission";
        public const string Mixed       = "Mixed";
    }

    public static class WaterStaffAttendanceStatus
    {
        public const string Present  = "Present";
        public const string Absent   = "Absent";
        public const string Late     = "Late";
        public const string HalfDay  = "HalfDay";
        public const string OffDay   = "OffDay";
    }

    public static class WaterPayrollStatus
    {
        public const string Draft     = "Draft";
        public const string Approved  = "Approved";
        public const string Paid      = "Paid";
        public const string Cancelled = "Cancelled";
    }

    // ====================================================================
    // Staff
    // ====================================================================
    public class WaterStaffModel
    {
        [Key] public int WaterStaffId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;

        [Required, StringLength(100)] public string FirstName { get; set; } = string.Empty;
        [Required, StringLength(100)] public string LastName  { get; set; } = string.Empty;

        [StringLength(50)]  public string? PhoneNumber { get; set; }
        [StringLength(200)] public string? Email { get; set; }

        [Required, StringLength(40)] public string Role { get; set; } = WaterStaffRoles.Other;
        [Required, StringLength(20)] public string SalaryType { get; set; } = WaterStaffSalaryTypes.Monthly;

        [Range(0, double.MaxValue)] public decimal BasePay { get; set; }

        public decimal? CommissionRate { get; set; }

        public int? AssignedWaterVehicleId { get; set; }
        public int? AssignedWaterRouteId { get; set; }

        public bool IsActive { get; set; } = true;
        public bool IsDeleted { get; set; }

        [StringLength(1000)] public string? Notes { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    // ====================================================================
    // Attendance
    // ====================================================================
    public class WaterStaffAttendanceModel
    {
        [Key] public int WaterStaffAttendanceId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required] public int WaterStaffId { get; set; }
        public string? StaffName { get; set; } // SP join

        [Required] public DateTime AttendanceDate { get; set; }
        public DateTime? ClockIn { get; set; }
        public DateTime? ClockOut { get; set; }

        [StringLength(30)] public string? Shift { get; set; }
        [Required, StringLength(20)] public string Status { get; set; } = WaterStaffAttendanceStatus.Present;

        [StringLength(500)] public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    /// <summary>POST/PUT body for attendance upsert (one row per staff/date/shift).</summary>
    public class WaterStaffAttendanceUpsertRequest
    {
        [Required] public int WaterStaffId { get; set; }
        [Required] public DateTime AttendanceDate { get; set; }
        public DateTime? ClockIn { get; set; }
        public DateTime? ClockOut { get; set; }
        [StringLength(30)] public string? Shift { get; set; }
        [Required, StringLength(20)] public string Status { get; set; } = WaterStaffAttendanceStatus.Present;
        [StringLength(500)] public string? Notes { get; set; }
    }

    // ====================================================================
    // Payroll Run + Items
    // ====================================================================
    public class WaterPayrollRunModel
    {
        [Key] public int WaterPayrollRunId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;

        [Required] public DateTime PeriodStart { get; set; }
        [Required] public DateTime PeriodEnd { get; set; }
        public DateTime? PayDate { get; set; }

        public decimal TotalGrossPay { get; set; }
        public decimal TotalDeductions { get; set; }
        public decimal TotalNetPay { get; set; }

        [StringLength(20)] public string Status { get; set; } = WaterPayrollStatus.Draft;

        public int? WaterCashAccountId { get; set; }
        public string? CashAccountName { get; set; }

        [StringLength(1000)] public string? Notes { get; set; }

        public string? CreatedBy { get; set; }
        public string? ApprovedBy { get; set; }
        public DateTime? ApprovedAt { get; set; }
        public string? PaidBy { get; set; }
        public DateTime? PaidAt { get; set; }

        // Migration 080 — audit trail for Unapprove/Reapprove cycle.
        public string?   ReopenedBy { get; set; }
        public DateTime? ReopenedAt { get; set; }
        [StringLength(500)] public string? ReopenReason { get; set; }
        public string?   ReapprovedBy { get; set; }
        public DateTime? ReapprovedAt { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }

        // Populated when fetched via GetById.
        public List<WaterPayrollItemModel> Items { get; set; } = new();
    }

    public class WaterPayrollItemModel
    {
        [Key] public int WaterPayrollItemId { get; set; }
        public int WaterPayrollRunId { get; set; }
        [Required] public int WaterStaffId { get; set; }
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

    public class WaterPayrollRunCreateRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required] public DateTime PeriodStart { get; set; }
        [Required] public DateTime PeriodEnd { get; set; }
        public DateTime? PayDate { get; set; }
        public int? WaterCashAccountId { get; set; }
        [StringLength(1000)] public string? Notes { get; set; }
    }

    public class WaterPayrollItemUpsertRequest
    {
        [Required] public int WaterStaffId { get; set; }
        public decimal BasicPay { get; set; }
        public decimal DailyWage { get; set; }
        public decimal Commission { get; set; }
        public decimal Bonus { get; set; }
        public decimal Deductions { get; set; }
        [StringLength(20)] public string? PaymentMethod { get; set; }
        [StringLength(500)] public string? Notes { get; set; }
    }

    public class WaterPayrollRunMarkPaidRequest
    {
        public DateTime? PayDate { get; set; }
    }

    public class WaterPayrollRunCancelRequest
    {
        [StringLength(500)] public string? Reason { get; set; }
    }

    // Migration 082: payload returned by spWaterPayrollRun_GetDetailsWithYtd.
    // Powers the /water-payroll/[id]/details page in one round-trip.
    public class WaterPayrollRunDetailsModel
    {
        public WaterPayrollRunModel? Run { get; set; }
        public WaterPayrollYtdTotals? YtdTotals { get; set; }
        public List<WaterPayrollYtdStaffRow> YtdByStaff { get; set; } = new();
        public WaterPayrollLinkedExpense? LinkedExpense { get; set; }
    }

    public class WaterPayrollYtdTotals
    {
        public int     Year             { get; set; }
        public decimal YtdGrossPaid     { get; set; }
        public decimal YtdDeductions    { get; set; }
        public decimal YtdNetPaid       { get; set; }
        public int     TotalPayrollRuns { get; set; }
        public int     TotalStaffPaid   { get; set; }
    }

    public class WaterPayrollYtdStaffRow
    {
        public int     WaterStaffId    { get; set; }
        public string? StaffName       { get; set; }
        public string? StaffRole       { get; set; }
        public decimal YtdBasic        { get; set; }
        public decimal YtdDaily        { get; set; }
        public decimal YtdCommission   { get; set; }
        public decimal YtdBonus        { get; set; }
        public decimal YtdDeductions   { get; set; }
        public decimal YtdGross        { get; set; }
        public decimal YtdNet          { get; set; }
    }

    public class WaterPayrollLinkedExpense
    {
        public int      WaterExpenseId         { get; set; }
        public string   FarmId                 { get; set; } = string.Empty;
        public DateTime ExpenseDate            { get; set; }
        public int      WaterExpenseCategoryId { get; set; }
        public string?  CategoryName           { get; set; }
        public string?  Description            { get; set; }
        public decimal  Amount                 { get; set; }
        public string?  PaymentMethod          { get; set; }
        public int?     WaterCashAccountId     { get; set; }
        public string?  CashAccountName        { get; set; }
        public string?  Status                 { get; set; }
        public string?  Notes                  { get; set; }
        public string?  CreatedBy              { get; set; }
        public string?  ApprovedBy             { get; set; }
        public DateTime? ApprovedAt            { get; set; }
        public string?  SourceType             { get; set; }
        public int?     SourceId               { get; set; }
        public DateTime CreatedAt              { get; set; }
        public DateTime? UpdatedAt             { get; set; }
    }
}
