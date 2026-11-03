namespace PoultryFarmAPIWeb.Models
{
    /// <summary>One weigh-in of a flock (migration 400). Weights in grams.</summary>
    public class FlockWeighIn
    {
        public int WeighInId { get; set; }
        public int FlockId { get; set; }
        public string FlockName { get; set; } = string.Empty;
        public string FlockType { get; set; } = "Layer";
        public string? Breed { get; set; }
        public bool FlockClosed { get; set; }
        public DateTime WeighDate { get; set; }
        public int AgeInDays { get; set; }
        public int SampleSize { get; set; }
        public decimal AvgWeightG { get; set; }
        public decimal? MinWeightG { get; set; }
        public decimal? MaxWeightG { get; set; }
        public decimal? UniformityPct { get; set; }
        public decimal? CvPct { get; set; }
        /// <summary>The birds as weighed; null when only the summary was recorded.</summary>
        public decimal[]? WeightsG { get; set; }
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        /// <summary>Previous weigh-in of the same flock, and the gain per day since it.</summary>
        public decimal? PrevAvgWeightG { get; set; }
        public int? DaysSincePrev { get; set; }
        public decimal? DailyGainG { get; set; }
    }

    /// <summary>
    /// Create or edit a weigh-in. Send WeightsG (one per bird) OR SampleSize +
    /// AvgWeightG. When weights are sent the server derives every figure from
    /// them and ignores the summary fields.
    /// </summary>
    public class FlockWeighInSaveRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public int FlockId { get; set; }
        public DateTime WeighDate { get; set; }
        public int? SampleSize { get; set; }
        public decimal? AvgWeightG { get; set; }
        public decimal[]? WeightsG { get; set; }
        public decimal? UniformityPct { get; set; }
        public decimal? CvPct { get; set; }
        public decimal? MinWeightG { get; set; }
        public decimal? MaxWeightG { get; set; }
        public string? Notes { get; set; }
    }
}
