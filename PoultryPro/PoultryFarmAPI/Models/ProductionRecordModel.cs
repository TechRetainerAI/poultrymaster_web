using System.Text.Json.Serialization;

namespace PoultryFarmAPIWeb.Models
{
    public class ProductionRecordModel
    {
        public int Id { get; set; }
        public string FarmId { get; set; }
        public string UserId { get; set; }
        public string CreatedBy { get; set; }
        public string UpdatedBy { get; set; }
        public int AgeInWeeks { get; set; }
        public int AgeInDays { get; set; }
        public DateTime Date { get; set; }
        public int NoOfBirds { get; set; }
        public int Mortality { get; set; }
        public int NoOfBirdsLeft { get; set; }
        public decimal FeedKg { get; set; }
        public string Medication { get; set; }
        
        [JsonPropertyName("production9AM")]
        public int Production9AM { get; set; }
        
        [JsonPropertyName("production12PM")]
        public int Production12PM { get; set; }
        
        [JsonPropertyName("production4PM")]
        public int Production4PM { get; set; }
        
        public int TotalProduction { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public int? FlockId { get; set; }
        
        // New fields for unified table (shared with EggProduction)
        public int? BrokenEggs { get; set; }
        public string? Notes { get; set; }
        public int EggCount { get; set; }
    }
}
