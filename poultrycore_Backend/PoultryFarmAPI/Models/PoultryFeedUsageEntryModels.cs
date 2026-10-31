// Feed Usage from stock (migration 389). See Business/PoultryFeedUsageEntryService.cs.

namespace PoultryFarmAPIWeb.Models
{
    public class FeedUsageCandidate
    {
        public int FlockId { get; set; }
        public string FlockName { get; set; } = string.Empty;
        public int? BatchId { get; set; }
        public string? BatchName { get; set; }
        public string? HouseName { get; set; }
        /// <summary>None | FeedOnly | Recorded | Duplicate -- the flock's production record for the date.</summary>
        public string RecordStatus { get; set; } = "None";
        public int? ProductionRecordId { get; set; }
        public int? Birds { get; set; }
        public decimal StockFeedKg { get; set; }
        /// <summary>The feed already on the record, e.g. "wheat brown 40 kg".</summary>
        public string? FeedLines { get; set; }
    }

    public class FeedUsageEntry
    {
        public int PoultryFeedUsageEntryId { get; set; }
        public DateTime BusinessDate { get; set; }
        public string Scope { get; set; } = "Flock";
        public int? BatchId { get; set; }
        public string? BatchName { get; set; }
        public string? SplitBasis { get; set; }
        public decimal TotalKg { get; set; }
        public decimal? TotalCost { get; set; }
        public int FlockCount { get; set; }
        public int FeedOnlyRecords { get; set; }
        public string Status { get; set; } = "Posted";
        public string? Notes { get; set; }
        public string? PostedBy { get; set; }
        public DateTime? PostedAtUtc { get; set; }
        public string? ReversedBy { get; set; }
        public DateTime? ReversedAtUtc { get; set; }
        public string? ReversalReason { get; set; }
    }

    public class FeedUsageEntryLine
    {
        public int PoultryFeedUsageLineId { get; set; }
        public int FlockId { get; set; }
        public string? FlockName { get; set; }
        public int ProductionRecordId { get; set; }
        public bool CreatedRecord { get; set; }
        public int ItemId { get; set; }
        public string? ItemName { get; set; }
        public decimal QuantityKg { get; set; }
        public decimal? UnitCost { get; set; }
        public decimal? TotalCost { get; set; }
        public int? Birds { get; set; }
        public string? ReversalNote { get; set; }
    }

    /// <summary>One feed line on a production record (or an old typed-in row with no stock).</summary>
    public class FeedUsageLogRow
    {
        public DateTime UsageDate { get; set; }
        public int FlockId { get; set; }
        public string? FlockName { get; set; }
        public int? ProductionRecordId { get; set; }
        /// <summary>The record's sourcetype (ManualSingleFlock, BatchAllocation, FeedUsage) or Legacy.</summary>
        public string? RecordSource { get; set; }
        public bool FeedOnly { get; set; }
        public int? ItemId { get; set; }
        public string? ItemName { get; set; }
        public decimal QuantityKg { get; set; }
        public decimal? UnitCost { get; set; }
        public decimal? TotalCost { get; set; }
        public int? EntryId { get; set; }
        public int? DistributionId { get; set; }
        public int? LegacyFeedUsageId { get; set; }
    }

    public class FeedUsageLineInput
    {
        public int FlockId { get; set; }
        public int ItemId { get; set; }
        public decimal Qty { get; set; }
        public int? Birds { get; set; }
    }

    public class FeedUsagePostRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public DateTime BusinessDate { get; set; }
        /// <summary>Flock | Batch.</summary>
        public string Scope { get; set; } = "Flock";
        public int? BatchId { get; set; }
        /// <summary>Birds | Equal | Manual -- how a batch total was split.</summary>
        public string? SplitBasis { get; set; }
        public string? Notes { get; set; }
        public List<FeedUsageLineInput> Lines { get; set; } = new();
    }

    public class FeedUsageReverseRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public string? Reason { get; set; }
    }
}
