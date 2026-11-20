// Employee Credit (migration 460 (Water port of 441)): money the business is holding for a member of
// staff. A liability -- the mirror of Employee Loans.
namespace PoultryFarmAPIWeb.Models
{
    public class WaterEmployeeCreditBalance
    {
        public int WaterStaffId { get; set; }
        public string? StaffName { get; set; }
        public string? StaffRole { get; set; }
        public bool IsActive { get; set; }
        public decimal Balance { get; set; }
        public decimal TotalIn { get; set; }
        public decimal TotalPaidOut { get; set; }
        public DateTime? LastEntryDate { get; set; }
        public int EntryCount { get; set; }
    }

    public class WaterEmployeeCreditEntry
    {
        public int WaterEmployeeCreditId { get; set; }
        public int WaterStaffId { get; set; }
        public string? StaffName { get; set; }
        /// <summary>PayrollSaving | WagesOwed | OpeningBalance | Deposit | Payout</summary>
        public string EntryType { get; set; } = string.Empty;
        public decimal Amount { get; set; }
        public decimal SignedAmount { get; set; }
        public decimal RunningBalance { get; set; }
        public DateTime EntryDate { get; set; }
        public int? WaterCashAccountId { get; set; }
        public string? AccountName { get; set; }
        public string? PaymentMethod { get; set; }
        public string? Reference { get; set; }
        public string? Description { get; set; }
        public int? WaterPayrollRunId { get; set; }
        public string? PayrollPeriod { get; set; }
        public int? ExpenseId { get; set; }
        public string Status { get; set; } = "Posted";
        public string? CreatedBy { get; set; }
        public DateTime? CreatedAt { get; set; }
        public string? ReversedBy { get; set; }
        public DateTime? ReversedAt { get; set; }
        public string? ReversalReason { get; set; }
    }

    public class WaterEmployeeCreditTotal
    {
        public decimal TotalHeld { get; set; }
        public int StaffCount { get; set; }
    }

    public class WaterEmployeeCreditAddRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public int WaterStaffId { get; set; }
        /// <summary>OpeningBalance | Deposit | WagesOwed</summary>
        public string EntryType { get; set; } = string.Empty;
        public decimal Amount { get; set; }
        public DateTime? EntryDate { get; set; }
        public int? WaterCashAccountId { get; set; }
        public string? PaymentMethod { get; set; }
        public string? Reference { get; set; }
        public string? Description { get; set; }
        public string? CreatedBy { get; set; }
    }

    public class WaterEmployeeCreditPayoutRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public int WaterStaffId { get; set; }
        public decimal Amount { get; set; }
        public int WaterCashAccountId { get; set; }
        public DateTime? EntryDate { get; set; }
        public string? PaymentMethod { get; set; }
        public string? Reference { get; set; }
        public string? Description { get; set; }
        public string? CreatedBy { get; set; }
    }

    public class WaterEmployeeCreditReverseRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public string? Reason { get; set; }
        public string? ActionBy { get; set; }
    }
}
