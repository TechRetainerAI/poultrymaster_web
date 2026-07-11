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

        /// <summary>Egg size for the daily collection (e.g. Small, Medium, Large, XLarge, Jumbo).</summary>
        [JsonPropertyName("eggGrade")]
        public string? EggGrade { get; set; }

        /// <summary>Eggs lost as "meaty" (yolk/blood spot). Nullable.</summary>
        public int? MeatyEggs { get; set; }

        /// <summary>Eggs lost as "soft" (thin/no shell). Nullable.</summary>
        public int? SoftEggs { get; set; }

        /// <summary>Eggs lost (missing, dropped, etc.). Nullable.</summary>
        public int? LostEggs { get; set; }

        // Doc 1 §4a-4c: feed + medication consumed from raw-material inventory and
        // the resulting production costing. All nullable — a record without feed/
        // medication selected just carries nulls (cost treated as 0).
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

        /// <summary>
        /// Migration 147: multiple medication lines, each drawn from raw-material
        /// inventory with its own FIFO/LIFO/HIFO batch cost. On write only the
        /// item id + quantity of each line are honoured (unit/total cost are
        /// recomputed server-side); on read every field is populated. The single
        /// SpecificMedicationUsed*/TotalMedication* columns above remain the
        /// aggregate roll-up (first line, sum of quantities, weighted-avg cost).
        /// </summary>
        public List<ProductionMedicationLineModel>? Medications { get; set; }

        /// <summary>
        /// Migration 148: multiple feed lines (inventory-based "Feed used" costing),
        /// same shape as Medications. The manual FeedKg / feed-type FeedUsage sync is
        /// separate and unaffected. The single SpecificFeedUsed*/TotalFeed* columns
        /// above remain the aggregate roll-up.
        /// </summary>
        public List<ProductionFeedLineModel>? Feeds { get; set; }
    }

    /// <summary>One medication line on a production record (migration 147).</summary>
    public class ProductionMedicationLineModel
    {
        public int? SpecificMedicationUsedId { get; set; }
        public string? SpecificMedicationUsedName { get; set; }
        public decimal? TotalMedicationConsumed { get; set; }
        public decimal? MedicationUnitCost { get; set; }
        public decimal? TotalMedicationCost { get; set; }
    }

    /// <summary>One feed line on a production record (migration 148).</summary>
    public class ProductionFeedLineModel
    {
        public int? SpecificFeedUsedId { get; set; }
        public string? SpecificFeedUsedName { get; set; }
        public decimal? TotalFeedConsumed { get; set; }
        public decimal? FeedUnitCost { get; set; }
        public decimal? TotalFeedCost { get; set; }
    }
}
