namespace PoultryWeb.Models
{
    public class InventoryTransactionModel
    {
        public string FarmId { get; set; }
        public string UserId { get; set; }
        public int TransactionId { get; set; }
        public int ItemId { get; set; }
        public DateTime TransactionDate { get; set; }
        public decimal QuantityChange { get; set; }
        public string? TransactionType { get; set; }
        public string? Remarks { get; set; }
    }
}