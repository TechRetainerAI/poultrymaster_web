using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    // Water Daily Production (migration 193) — the water mirror of poultry Batch
    // Production. A day's combined output is captured here, split across machines
    // by the allocation rows, and posted into real WaterProductionBatches.

    public static class WaterDailyProductionStatus
    {
        public const string Draft = "Draft";
        public const string PendingAllocation = "PendingAllocation";
        public const string Allocated = "Allocated";
        public const string Posted = "Posted";
        public const string Reversed = "Reversed";
        public const string Cancelled = "Cancelled";
    }

    public class WaterDailyProductionMachineModel
    {
        public int WaterDailyProductionMachineId { get; set; }
        public int WaterMachineId { get; set; }
        public string? MachineName { get; set; }
        public string? MachineNumber { get; set; }
        public int? CapacityPerHour { get; set; }
        public int? OperatorStaffId { get; set; }
    }

    public class WaterDailyProductionMaterialModel
    {
        public int WaterDailyProductionMaterialId { get; set; }
        public int WaterRawMaterialItemId { get; set; }
        public string? ItemName { get; set; }
        public string? UnitOfMeasure { get; set; }
        public decimal QuantityUsed { get; set; }
        public decimal? ExpectedQuantityUsed { get; set; }
        public decimal? UnitCost { get; set; }
        public decimal TotalCost { get; set; }
        public string? VarianceReason { get; set; }
        public string? Notes { get; set; }
    }

    public class WaterDailyProductionAllocationMaterialModel
    {
        public int WaterDailyProductionAllocationMaterialId { get; set; }
        public int? WaterDailyProductionMaterialId { get; set; }
        public int WaterRawMaterialItemId { get; set; }
        public string? ItemName { get; set; }
        public decimal QuantityAllocated { get; set; }
        public decimal? ExpectedQuantityAllocated { get; set; }
        public decimal? UnitCost { get; set; }
        public decimal TotalCost { get; set; }
    }

    public class WaterDailyProductionAllocationModel
    {
        public int WaterDailyProductionAllocationId { get; set; }
        public int WaterMachineId { get; set; }
        public string? MachineName { get; set; }
        public string? AllocationMethod { get; set; }
        public string? Shift { get; set; }
        public int? OperatorStaffId { get; set; }
        public DateTime? StartTime { get; set; }
        public DateTime? EndTime { get; set; }
        public int BagsProduced { get; set; }
        public int LooseSachetsProduced { get; set; }
        public int RejectedSachets { get; set; }
        public int DamagedBags { get; set; }
        public int PackagingRollsUsed { get; set; }
        public int? EstimatedWaterUsedLitres { get; set; }
        public decimal ElectricityCost { get; set; }
        public decimal FuelCost { get; set; }
        public decimal LaborCost { get; set; }
        public decimal OtherProductionCost { get; set; }
        public decimal TotalProductionCost { get; set; }
        public decimal? RawMaterialCost { get; set; }
        public string? Notes { get; set; }
        public int? GeneratedWaterProductionBatchId { get; set; }
        public string? GeneratedBatchNumber { get; set; }
        public List<WaterDailyProductionAllocationMaterialModel> Materials { get; set; } = new();
    }

    public class WaterDailyProductionPostingModel
    {
        public int WaterDailyProductionPostingId { get; set; }
        public int? WaterDailyProductionAllocationId { get; set; }
        public int PostingVersion { get; set; }
        public int WaterProductionBatchId { get; set; }
        public string BatchNumber { get; set; } = string.Empty;
        public int? WaterMachineId { get; set; }
        public string? PostedBy { get; set; }
        public DateTime? PostedAt { get; set; }
        public string? ReversedBy { get; set; }
        public DateTime? ReversedAt { get; set; }
    }

    public class WaterDailyProductionModel
    {
        public int WaterDailyProductionId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        public string? UserId { get; set; }
        [StringLength(60)] public string? ProductionNumber { get; set; }
        public DateTime ProductionDate { get; set; }
        [StringLength(20)] public string Shift { get; set; } = "FullDay";
        // AllMachines | CustomMachines | SingleMachine
        [StringLength(20)] public string MachineSelectionType { get; set; } = "AllMachines";
        [Range(1, int.MaxValue)] public int WaterProductId { get; set; }
        public int? WaterBoreholeId { get; set; }
        public int? OperatorStaffId { get; set; }
        public DateTime? StartTime { get; set; }
        public DateTime? EndTime { get; set; }

        [Range(0, int.MaxValue)] public int BagsProduced { get; set; }
        [Range(1, int.MaxValue)] public int SachetsPerBag { get; set; } = 30;
        [Range(0, int.MaxValue)] public int LooseSachetsProduced { get; set; }
        [Range(0, int.MaxValue)] public int RejectedSachets { get; set; }
        [Range(0, int.MaxValue)] public int DamagedBags { get; set; }
        [Range(0, int.MaxValue)] public int PackagingRollsUsed { get; set; }
        public int? EstimatedWaterUsedLitres { get; set; }

        public decimal ElectricityCost { get; set; }
        public decimal FuelCost { get; set; }
        public decimal LaborCost { get; set; }
        public decimal OtherProductionCost { get; set; }
        public decimal TotalProductionCost { get; set; }
        public decimal RawMaterialCost { get; set; }

        [StringLength(20)] public string QualityStatus { get; set; } = "Pending";
        public decimal? QualityPHLevel { get; set; }
        public decimal? QualityChlorinePpm { get; set; }
        public decimal? QualityTurbidity { get; set; }
        public int? QualityTDS { get; set; }
        [StringLength(500)] public string? QualityNotes { get; set; }

        [StringLength(30)] public string Status { get; set; } = WaterDailyProductionStatus.PendingAllocation;
        public int PostingVersion { get; set; }
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime? CreatedAt { get; set; }
        public string? UpdatedBy { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public string? PostedBy { get; set; }
        public DateTime? PostedAt { get; set; }
        public string? ReversedBy { get; set; }
        public DateTime? ReversedAt { get; set; }

        // Read-only enrichments from the SP
        public string? ProductName { get; set; }
        public string? BoreholeName { get; set; }
        public int GoodBags { get; set; }
        public decimal AllInCost { get; set; }
        public decimal CostPerBag { get; set; }
        public decimal ProductionEfficiencyPercent { get; set; }
        public int MachineCount { get; set; }
        public int AllocationCount { get; set; }

        public List<WaterDailyProductionMachineModel> Machines { get; set; } = new();
        public List<WaterDailyProductionMaterialModel> Materials { get; set; } = new();
        public List<WaterDailyProductionAllocationModel> Allocations { get; set; } = new();
        public List<WaterDailyProductionPostingModel> Postings { get; set; } = new();
    }

    public class SaveWaterDailyProductionAllocationRequest
    {
        public string? UpdatedBy { get; set; }
        [StringLength(30)] public string? Status { get; set; }
        public List<WaterDailyProductionAllocationModel> Allocations { get; set; } = new();
    }

    public class WaterDailyProductionActionRequest
    {
        public string? UserId { get; set; }
        [StringLength(30)] public string? Status { get; set; }
    }
}
