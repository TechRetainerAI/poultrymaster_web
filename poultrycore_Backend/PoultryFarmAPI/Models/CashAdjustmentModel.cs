namespace PoultryFarmAPIWeb.Models
{
    public class CashAdjustmentModel
    {
        public int AdjustmentId { get; set; }
        public string UserId { get; set; } = string.Empty;
        public string FarmId { get; set; } = string.Empty;
        public DateTime AdjustmentDate { get; set; }
        public string AdjustmentType { get; set; } = string.Empty;  // OpeningBalance, OwnerInjection, LoanReceived, Withdrawal, Correction
        public decimal Amount { get; set; }
        public string? Description { get; set; }
        public DateTime CreatedDate { get; set; }
    }
}
