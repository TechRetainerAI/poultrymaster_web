namespace PoultryWeb.Models
{
    public class ExpenseModel
    {
        public string FarmId { get; set; }
        public string UserId { get; set; }
        public int ExpenseId { get; set; }
        public DateTime ExpenseDate { get; set; }
        public string Category { get; set; } = string.Empty;
        public string? Description { get; set; }
        public decimal Amount { get; set; }
        public string? PaymentMethod { get; set; }
        public int? FlockId { get; set; }
        public DateTime CreatedDate { get; set; }
    }
}
