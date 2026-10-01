// Distribute Feed (migration 335): one feed product to many flocks for one
// business date, posted as feed lines on each flock's production record through
// the same spproductionrecord_update an individual edit uses.

namespace PoultryFarmAPIWeb.Models
{
    public class FeedDistributionAvailability
    {
        public int PoultryRawMaterialItemId { get; set; }
        public string ItemName { get; set; } = string.Empty;
        public string? Category { get; set; }
        public string? UnitOfMeasure { get; set; }
        /// <summary>FIFO | LIFO | HIFO -- the item's own costing method.</summary>
        public string UsageMethod { get; set; } = "FIFO";
        /// <summary>What the purchase lots can supply: exactly what posting can draw.</summary>
        public decimal AvailableKg { get; set; }
        public decimal? CurrentQuantity { get; set; }
        public int LotCount { get; set; }
        /// <summary>EXPENSE_WHEN_PURCHASED | EXPENSE_WHEN_CONSUMED for this item today.</summary>
        public string? CostRecognitionMethod { get; set; }
        /// <summary>The farm's saved rate for this feed, always in grams per bird per day; null = none saved.</summary>
        public decimal? GramsPerBirdPerDay { get; set; }
        /// <summary>The unit the saved rate was entered in (336): g_bird, kg_bird, kg_100, kg_1000, lb_bird, lb_100.</summary>
        public string? RateUnit { get; set; }
    }

    public class FeedDistributionCandidate
    {
        public int FlockId { get; set; }
        public string FlockName { get; set; } = string.Empty;
        public string? BatchName { get; set; }
        public string? HouseName { get; set; }
        /// <summary>Production records for the date. Only exactly 1 can receive feed.</summary>
        public int RecordCount { get; set; }
        public int? ProductionRecordId { get; set; }
        public int? Birds { get; set; }
        /// <summary>Feed kg entered by hand on the record (only when it has no stock lines).</summary>
        public decimal? ManualFeedKg { get; set; }
        public decimal StockFeedKg { get; set; }
        /// <summary>This feed already on the record today.</summary>
        public decimal ThisItemKg { get; set; }
        /// <summary>Average kg of this feed per day it was given, over the recent window; null = no history.</summary>
        public decimal? RecentAvgKg { get; set; }
        public int? RecentAvgDays { get; set; }
    }

    public class FeedDistributionLineInput
    {
        public int FlockId { get; set; }
        public decimal ActualKg { get; set; }
        public decimal? SuggestedKg { get; set; }
        public int? Birds { get; set; }
        public string? Notes { get; set; }
    }

    public class FeedDistributionPostRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public DateTime BusinessDate { get; set; }
        public int ItemId { get; set; }
        /// <summary>Manual | Rate | RecentAverage -- how the suggestions were made.</summary>
        public string? Basis { get; set; }
        public decimal? GramsPerBirdPerDay { get; set; }
        /// <summary>The unit the rate was typed in; the grams figure is already converted.</summary>
        public string? RateUnit { get; set; }
        /// <summary>Also save GramsPerBirdPerDay as this feed's default rate.</summary>
        public bool SaveRate { get; set; }
        public string? Notes { get; set; }
        public List<FeedDistributionLineInput> Lines { get; set; } = new();
    }

    public class FeedDistributionReverseRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public string? Reason { get; set; }
    }

    public class FeedRateRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public int ItemId { get; set; }
        /// <summary>Null clears the saved rate.</summary>
        public decimal? GramsPerBirdPerDay { get; set; }
        public string? RateUnit { get; set; }
    }

    public class FeedDistribution
    {
        public int PoultryFeedDistributionId { get; set; }
        public DateTime BusinessDate { get; set; }
        public int PoultryRawMaterialItemId { get; set; }
        public string? ItemName { get; set; }
        public string Basis { get; set; } = "Manual";
        public decimal? GramsPerBirdPerDay { get; set; }
        public string? RateUnit { get; set; }
        public decimal? TotalSuggestedKg { get; set; }
        public decimal TotalActualKg { get; set; }
        public decimal? TotalCost { get; set; }
        public int FlockCount { get; set; }
        /// <summary>Posted | Reversed</summary>
        public string Status { get; set; } = "Posted";
        public string? Notes { get; set; }
        public string? PostedBy { get; set; }
        public DateTime PostedAtUtc { get; set; }
        public string? ReversedBy { get; set; }
        public DateTime? ReversedAtUtc { get; set; }
        public string? ReversalReason { get; set; }
    }

    public class FeedDistributionLine
    {
        public int PoultryFeedDistributionLineId { get; set; }
        public int FlockId { get; set; }
        public string? FlockName { get; set; }
        public int ProductionRecordId { get; set; }
        public int? Birds { get; set; }
        public decimal? SuggestedKg { get; set; }
        public decimal ActualKg { get; set; }
        public decimal? UnitCost { get; set; }
        public decimal? TotalCost { get; set; }
        public string? Notes { get; set; }
        public string? ReversalNote { get; set; }
    }
}
