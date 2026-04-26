using System.Text.Json.Serialization;

namespace PoultryFarmAPIWeb.Models
{
    public class EggProductionModel
    {
        public string? FarmId { get; set; }
        public string UserId { get; set; }
        public int ProductionId { get; set; }
        public int FlockId { get; set; }
        public string? FlockName { get; set; }
        public DateTime ProductionDate { get; set; }
        public int EggCount { get; set; }
        [JsonPropertyName("production9AM")]
        public int Production9AM { get; set; }
        [JsonPropertyName("production12PM")]
        public int Production12PM { get; set; }
        [JsonPropertyName("production4PM")]
        public int Production4PM { get; set; }
        public int TotalProduction { get; set; }
        public int? BrokenEggs { get; set; }
        public string? Notes { get; set; }
    }
}
