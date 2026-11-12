// 428. Payroll templates: the standard payroll, set up once and used every period.
namespace PoultryFarmAPIWeb.Models
{
    public class PoultryPayrollTemplateModel
    {
        public int PoultryPayrollTemplateId { get; set; }
        public string Name { get; set; } = string.Empty;
        public string Frequency { get; set; } = "Monthly";
        public int? PoultryCashAccountId { get; set; }
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
        public List<PoultryPayrollTemplateLineModel> Lines { get; set; } = new();
    }

    public class PoultryPayrollTemplateLineModel
    {
        public int PoultryPayrollTemplateLineId { get; set; }
        public int PoultryStaffId { get; set; }
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

    public class PoultryPayrollTemplateLineInput
    {
        public int PoultryStaffId { get; set; }
        public decimal BasicPay { get; set; }
        public decimal DailyWage { get; set; }
        public decimal Commission { get; set; }
        public decimal Bonus { get; set; }
        public decimal Deductions { get; set; }
        public string? PaymentMethod { get; set; }
        public string? Notes { get; set; }
    }

    public class PoultryPayrollTemplateSaveRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public string Frequency { get; set; } = "Monthly";
        public int? PoultryCashAccountId { get; set; }
        public string? Notes { get; set; }
        public string? SavedBy { get; set; }
        public List<PoultryPayrollTemplateLineInput> Lines { get; set; } = new();
    }

    public class PoultryPayrollTemplateSetActiveRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public bool IsActive { get; set; }
        public string? By { get; set; }
    }

    public class PoultryPayrollTemplateCreateRunRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public DateTime PeriodStart { get; set; }
        public DateTime PeriodEnd { get; set; }
        public DateTime? PayDate { get; set; }
        public int? PoultryCashAccountId { get; set; }
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
    }
}
