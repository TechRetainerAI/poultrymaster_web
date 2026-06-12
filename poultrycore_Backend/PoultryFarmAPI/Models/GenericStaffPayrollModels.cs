using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    public static class GenericStaffRoles
    {
        public const string Owner             = "Owner";
        public const string Manager           = "Manager";
        public const string Accountant        = "Accountant";
        public const string Cashier           = "Cashier";
        public const string Salesperson       = "Salesperson";
        public const string InventoryOfficer  = "InventoryOfficer";
        public const string Cleaner           = "Cleaner";
        public const string Security          = "Security";
        public const string Driver            = "Driver";
        public const string ServiceProvider   = "ServiceProvider";
        public const string Other             = "Other";
    }

    public static class GenericStaffSalaryTypes
    {
        public const string Daily       = "Daily";
        public const string Weekly      = "Weekly";
        public const string Monthly     = "Monthly";
        public const string Commission  = "Commission";
        public const string Mixed       = "Mixed";
    }

    public static class GenericStaffAttendanceStatus
    {
        public const string Present  = "Present";
        public const string Absent   = "Absent";
        public const string Late     = "Late";
        public const string HalfDay  = "HalfDay";
        public const string OffDay   = "OffDay";
    }

    public static class GenericPayrollStatus
    {
        public const string Draft     = "Draft";
        public const string Approved  = "Approved";
        public const string Paid      = "Paid";
        public const string Cancelled = "Cancelled";
    }

    // ====================================================================
    // Staff
    // ====================================================================
    public class GenericStaffModel
    {
        [Key] public int GenericStaffId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;

        [Required, StringLength(100)] public string FirstName { get; set; } = string.Empty;
        [Required, StringLength(100)] public string LastName  { get; set; } = string.Empty;

        [StringLength(50)]  public string? PhoneNumber { get; set; }
        [StringLength(200)] public string? Email { get; set; }

        [Required, StringLength(40)] public string Role { get; set; } = GenericStaffRoles.Other;
        [Required, StringLength(20)] public string SalaryType { get; set; } = GenericStaffSalaryTypes.Monthly;

        [Range(0, double.MaxValue)] public decimal BasePay { get; set; }
        public decimal? CommissionRate { get; set; }

        public int? BranchId { get; set; }

        public bool IsActive { get; set; } = true;
        public bool IsDeleted { get; set; }

        [StringLength(1000)] public string? Notes { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    // ====================================================================
    // Attendance
    // ====================================================================
    public class GenericStaffAttendanceModel
    {
        [Key] public int GenericStaffAttendanceId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required] public int GenericStaffId { get; set; }
        public string? StaffName { get; set; }
        public string? StaffRole { get; set; }

        [Required] public DateTime AttendanceDate { get; set; }
        public DateTime? ClockIn { get; set; }
        public DateTime? ClockOut { get; set; }

        [StringLength(30)] public string? Shift { get; set; }
        [Required, StringLength(20)] public string Status { get; set; } = GenericStaffAttendanceStatus.Present;

        [StringLength(500)] public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    public class GenericStaffAttendanceUpsertRequest
    {
        [Required] public int GenericStaffId { get; set; }
        [Required] public DateTime AttendanceDate { get; set; }
        public DateTime? ClockIn { get; set; }
        public DateTime? ClockOut { get; set; }
        [StringLength(30)] public string? Shift { get; set; }
        [Required, StringLength(20)] public string Status { get; set; } = GenericStaffAttendanceStatus.Present;
        [StringLength(500)] public string? Notes { get; set; }
    }

    // ====================================================================
    // Payroll Run + Items
    // ====================================================================
    public class GenericPayrollRunModel
    {
        [Key] public int GenericPayrollRunId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;

        [Required] public DateTime PeriodStart { get; set; }
        [Required] public DateTime PeriodEnd { get; set; }
        public DateTime? PayDate { get; set; }

        public decimal TotalGrossPay { get; set; }
        public decimal TotalDeductions { get; set; }
        public decimal TotalNetPay { get; set; }

        [StringLength(20)] public string Status { get; set; } = GenericPayrollStatus.Draft;

        public int? GenericCashAccountId { get; set; }
        public string? CashAccountName { get; set; }

        [StringLength(1000)] public string? Notes { get; set; }

        public string? CreatedBy { get; set; }
        public string? ApprovedBy { get; set; }
        public DateTime? ApprovedAt { get; set; }
        public string? PaidBy { get; set; }
        public DateTime? PaidAt { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }

        // Populated by GetById.
        public List<GenericPayrollItemModel> Items { get; set; } = new();
    }

    public class GenericPayrollItemModel
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
        public decimal NetPay { get; set; }

        [StringLength(20)] public string? PaymentMethod { get; set; }
        [StringLength(500)] public string? Notes { get; set; }

        public DateTime CreatedAt { get; set; }
    }

    public class GenericPayrollRunCreateRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        [Required] public DateTime PeriodStart { get; set; }
        [Required] public DateTime PeriodEnd { get; set; }
        public DateTime? PayDate { get; set; }
        public int? GenericCashAccountId { get; set; }
        [StringLength(1000)] public string? Notes { get; set; }
    }

    public class GenericPayrollRunUpdateRequest
    {
        [Required] public DateTime PeriodStart { get; set; }
        [Required] public DateTime PeriodEnd { get; set; }
        public DateTime? PayDate { get; set; }
        public int? GenericCashAccountId { get; set; }
        [StringLength(1000)] public string? Notes { get; set; }
    }

    public class GenericPayrollItemUpsertRequest
    {
        [Required] public int GenericStaffId { get; set; }
        public decimal BasicPay { get; set; }
        public decimal DailyWage { get; set; }
        public decimal Commission { get; set; }
        public decimal Bonus { get; set; }
        public decimal Deductions { get; set; }
        [StringLength(20)] public string? PaymentMethod { get; set; }
        [StringLength(500)] public string? Notes { get; set; }
    }

    public class GenericPayrollRunMarkPaidRequest
    {
        public DateTime? PayDate { get; set; }
    }

    public class GenericPayrollRunCancelRequest
    {
        [StringLength(500)] public string? Reason { get; set; }
    }
}
