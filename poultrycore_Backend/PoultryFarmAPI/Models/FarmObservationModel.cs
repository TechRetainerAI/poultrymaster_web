namespace PoultryFarmAPIWeb.Models
{
    /// <summary>
    /// Weekly free-text notes kept per farm. One row per (FarmId, WeekStartDate).
    /// Created by migration 018_WeeklyReportExtensions.sql.
    /// </summary>
    public class FarmObservationModel
    {
        public int Id { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public string? UserId { get; set; }
        /// <summary>Monday of the week these notes apply to (date only, no time).</summary>
        public DateTime WeekStartDate { get; set; }
        public string? Notes { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }
}
