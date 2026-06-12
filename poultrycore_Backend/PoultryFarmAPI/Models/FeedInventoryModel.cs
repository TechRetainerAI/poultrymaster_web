namespace PoultryFarmAPIWeb.Models
{
    public class FeedInventoryModel
    {
        public string UserId { get; set; }
        public int FeedInventoryId { get; set; }
        public string FeedType { get; set; } = string.Empty;
        public decimal QuantityKg { get; set; }
        public DateTime LastUpdated { get; set; }
    }
}
