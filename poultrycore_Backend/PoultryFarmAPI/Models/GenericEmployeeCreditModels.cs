// Employee Credit (migration 441): money the farm is holding for a member of
// staff. A liability -- the mirror of Employee Loans.
namespace PoultryFarmAPIWeb.Models
{
    public class GenericEmployeeCreditBalance
    {
        public int GenericStaffId { get; set; }
        public string? StaffName { get; set; }
        public string? StaffRole { get; set; }
        public bool IsActive { get; set; }
        public decimal Balance { get; set; }
        public decimal TotalIn { get; set; }
        public decimal TotalPaidOut { get; set; }
        public DateTime? LastEntryDate { get; set; }
        public int EntryCount { get; set; }
    }

    public class GenericEmployeeCreditEntry
    {
        public int GenericEmployeeCreditId { get; set; }
        public int GenericStaffId { get; set; }
        public string? StaffName { get; set; }
        /// <summary>PayrollSaving | WagesOwed | OpeningBalance | Deposit | Payout</summary>
        public string EntryType { get; set; } = string.Empty;
        public decimal Amount { get; set; }
        public decimal SignedAmount { get; set; }
        public decimal RunningBalance { get; set; }
        public DateTime EntryDate { get; set; }
        public int? GenericCashAccountId { get; set; }
        public string? AccountName { get; set; }
        public string? PaymentMethod { get; set; }
        public string? Reference { get; set; }
        public string? Description { get; set; }
        public int? GenericPayrollRunId { get; set; }
        public string? PayrollPeriod { get; set; }
        public int? ExpenseId { get; set; }
        public string Status { get; set; } = "Posted";
        public string? CreatedBy { get; set; }
        public DateTime? CreatedAt { get; set; }
        public string? ReversedBy { get; set; }
        public DateTime? ReversedAt { get; set; }
        public string? ReversalReason { get; set; }
    }

    public class GenericEmployeeCreditTotal
    {
        public decimal TotalHeld { get; set; }
        public int StaffCount { get; set; }
    }

    public class GenericEmployeeCreditAddRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public int GenericStaffId { get; set; }
        /// <summary>OpeningBalance | Deposit | WagesOwed</summary>
        public string EntryType { get; set; } = string.Empty;
        public decimal Amount { get; set; }
        public DateTime? EntryDate { get; set; }
        public int? GenericCashAccountId { get; set; }
        public string? PaymentMethod { get; set; }
        public string? Reference { get; set; }
        public string? Description { get; set; }
        public string? CreatedBy { get; set; }
    }

    public class GenericEmployeeCreditPayoutRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public int GenericStaffId { get; set; }
        public decimal Amount { get; set; }
        public int GenericCashAccountId { get; set; }
        public DateTime? EntryDate { get; set; }
        public string? PaymentMethod { get; set; }
        public string? Reference { get; set; }
        public string? Description { get; set; }
        public string? CreatedBy { get; set; }
    }

    public class GenericEmployeeCreditReverseRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public string? Reason { get; set; }
        public string? ActionBy { get; set; }
    }
}
