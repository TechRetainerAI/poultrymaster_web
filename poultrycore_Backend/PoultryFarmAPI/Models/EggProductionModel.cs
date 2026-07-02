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

        /// <summary>Egg size / sort (e.g. Small, Medium, Large). Same column as ProductionRecords.EggGrade.</summary>
        [JsonPropertyName("eggGrade")]
        public string? EggGrade { get; set; }

        // Doc 4: feed/medication usage costing captured from raw-material inventory.
        public int? SpecificFeedUsedId { get; set; }
        public string? SpecificFeedUsedName { get; set; }
        public decimal? FeedUnitCost { get; set; }
        public decimal? TotalFeedConsumed { get; set; }
        public decimal? TotalFeedCost { get; set; }
        public int? SpecificMedicationUsedId { get; set; }
        public string? SpecificMedicationUsedName { get; set; }
        public decimal? MedicationUnitCost { get; set; }
        public decimal? TotalMedicationConsumed { get; set; }
        public decimal? TotalMedicationCost { get; set; }
        public decimal? TotalCostOfProduction { get; set; }
    }
}
