namespace PoultryFarmAPIWeb.Models
{
    /// <summary>
    /// Batch-level production record header + its child collections. A batch record
    /// captures TOTAL production for a group of flocks and is inert (PendingAllocation)
    /// until an allocation is posted into flock-level ProductionRecords (migration 156).
    /// </summary>
    public class ProductionBatchRecordModel
    {
        public int Id { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public string? UserId { get; set; }
        public string? CreatedBy { get; set; }
        public string? UpdatedBy { get; set; }
        public string? PostedBy { get; set; }

        /// <summary>SpecificBatch | AllBatches | CustomBatch.</summary>
        public string BatchSelectionType { get; set; } = "AllBatches";
        public int? SelectedBirdBatchId { get; set; }
        public string? BatchName { get; set; }

        public DateTime ProductionDate { get; set; }
        public int? AgeInWeeks { get; set; }
        public int? AgeInDays { get; set; }
        public string? AgeDisplay { get; set; }

        public int? FirstPickCrates { get; set; }
        public int? FirstPickLooseEggs { get; set; }
        public int FirstPickTotal { get; set; }
        public int? SecondPickCrates { get; set; }
        public int? SecondPickLooseEggs { get; set; }
        public int SecondPickTotal { get; set; }
        public int? ThirdPickCrates { get; set; }
        public int? ThirdPickLooseEggs { get; set; }
        public int ThirdPickTotal { get; set; }
        public int? FourthPickCrates { get; set; }
        public int? FourthPickLooseEggs { get; set; }
        public int FourthPickTotal { get; set; }

        public int? BrokenEggs { get; set; }
        public int? MeatyEggs { get; set; }
        public int? SoftEggs { get; set; }
        public int? LostEggs { get; set; }
        public int TotalEggs { get; set; }

        public decimal? FeedKg { get; set; }
        public int Deaths { get; set; }
        public int? BirdsLeft { get; set; }
        public string? EggGrade { get; set; }

        /// <summary>Free-text feed type/description (e.g. "Layer Feed").</summary>
        public string? FeedType { get; set; }
        /// <summary>Free-text medication description; propagated to each flock record on post.</summary>
        public string? Medication { get; set; }

        public decimal? TotalFeedCost { get; set; }
        public decimal? TotalMedicationCost { get; set; }
        public decimal? TotalCostOfProduction { get; set; }

        /// <summary>Draft | PendingAllocation | Allocated | Posted | Reversed | Cancelled.</summary>
        public string Status { get; set; } = "PendingAllocation";
        public string? Notes { get; set; }

        public DateTime CreatedDate { get; set; }
        public DateTime? UpdatedDate { get; set; }
        public DateTime? PostedDate { get; set; }

        public List<ProductionBatchIncludedFlockModel> IncludedFlocks { get; set; } = new();
        public List<ProductionBatchUsageLineModel> Feeds { get; set; } = new();
        public List<ProductionBatchUsageLineModel> Medications { get; set; } = new();
        public List<ProductionBatchAllocationModel> Allocations { get; set; } = new();
    }

    /// <summary>A flock frozen into the batch's allocation scope.</summary>
    public class ProductionBatchIncludedFlockModel
    {
        public int FlockId { get; set; }
        public string? FlockName { get; set; }
        public int? BirdBatchId { get; set; }
    }

    /// <summary>A batch-level feed or medication usage line.</summary>
    public class ProductionBatchUsageLineModel
    {
        public int? Id { get; set; }
        public int ItemId { get; set; }
        public string? ItemName { get; set; }
        public decimal Qty { get; set; }
        public decimal? UnitCost { get; set; }
        public decimal? TotalCost { get; set; }
        public string? Method { get; set; }
    }

    /// <summary>One flattened feed/medication line inside an allocation row.</summary>
    public class ProductionBatchAllocationUsageLineModel
    {
        /// <summary>Id of the parent batch-level feed or medication usage line this maps to.</summary>
        public int? BatchUsageId { get; set; }
        public int ItemId { get; set; }
        public string? ItemName { get; set; }
        public decimal Qty { get; set; }
        public decimal? UnitCost { get; set; }
        public decimal? TotalCost { get; set; }
    }

    /// <summary>Per-flock allocation of the batch totals.</summary>
    public class ProductionBatchAllocationModel
    {
        public int? Id { get; set; }
        public int FlockId { get; set; }
        public string? FlockName { get; set; }
        public string? AllocationMethod { get; set; }
        public int? AgeInWeeks { get; set; }
        public int? AgeInDays { get; set; }
        public int? BirdsBefore { get; set; }
        public int Deaths { get; set; }
        public int? BirdsAfter { get; set; }
        public int FirstPickEggs { get; set; }
        public int SecondPickEggs { get; set; }
        public int ThirdPickEggs { get; set; }
        public int FourthPickEggs { get; set; }
        public int? BrokenEggs { get; set; }
        public int? MeatyEggs { get; set; }
        public int? SoftEggs { get; set; }
        public int? LostEggs { get; set; }
        public int TotalEggs { get; set; }
        public decimal? EggPercentage { get; set; }
        public decimal? FeedKg { get; set; }
        public decimal? TotalFeedCost { get; set; }
        public decimal? TotalMedicationCost { get; set; }
        public decimal? TotalCostOfProduction { get; set; }
        public string? Notes { get; set; }
        public int? GeneratedProductionRecordId { get; set; }

        public List<ProductionBatchAllocationUsageLineModel> Feeds { get; set; } = new();
        public List<ProductionBatchAllocationUsageLineModel> Medications { get; set; } = new();
    }

    /// <summary>Body for POST /api/ProductionBatchRecord/{id}/allocation.</summary>
    public class SaveAllocationRequest
    {
        public string? UpdatedBy { get; set; }
        public string? Status { get; set; }
        public List<ProductionBatchAllocationModel> Allocations { get; set; } = new();
    }

    /// <summary>Body for the post / reverse / status-change actions.</summary>
    public class BatchActionRequest
    {
        public string? UserId { get; set; }
        public string? Status { get; set; }
    }
}
