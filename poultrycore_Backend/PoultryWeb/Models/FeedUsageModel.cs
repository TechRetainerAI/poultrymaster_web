namespace PoultryWeb.Models
{
    public class FeedUsageModel
    {
        public string FarmId { get; set; }
        public string UserId { get; set; }
        public int FeedUsageId { get; set; }
        public int FlockId { get; set; }
        public DateTime UsageDate { get; set; }
        public string FeedType { get; set; } = string.Empty;
        public decimal QuantityKg { get; set; }
        
    }
}
