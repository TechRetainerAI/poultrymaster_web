namespace PoultryFarmAPIWeb.Models
{
    public class FeedUsageModel
    {
        public string FarmId { get; set; }  // FIXED: Changed from 'internal set' to 'set' so JSON deserialization works!
        public string UserId { get; set; }
        public int FeedUsageId { get; set; }
        public int FlockId { get; set; }
        public DateTime UsageDate { get; set; }
        public string FeedType { get; set; } = string.Empty;
        public decimal QuantityKg { get; set; }
        
        // New fields for synced data
        public string? Source { get; set; }  // "Production Record" or "Manual Entry"
        public int? SourceProductionRecordId { get; set; }
    
        /// <summary>When the row was created -- the clock time tables show
        /// beside the business date (migration 301). Null on a database that
        /// predates it.</summary>
        public DateTime? CreatedAt { get; set; }
}
}
