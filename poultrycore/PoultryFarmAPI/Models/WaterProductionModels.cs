using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    // =========================================================================
    // Water Company — Phase W1 production models.
    // =========================================================================

    public static class WaterProductionBatchStatus
    {
        public const string Draft     = "Draft";
        public const string Approved  = "Approved";
        public const string Cancelled = "Cancelled";
    }

    public static class WaterProductionShifts
    {
        public const string Morning   = "Morning";
        public const string Afternoon = "Afternoon";
        public const string Night     = "Night";
        public const string FullDay   = "FullDay";
    }

    public static class WaterQualityResult
    {
        public const string Pending = "Pending";
        public const string Passed  = "Passed";
        public const string Failed  = "Failed";
    }

    // =========================================================================
    // Borehole
    // =========================================================================
    public class WaterBoreholeModel
    {
        [Key]
        public int WaterBoreholeId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        [Required]
        [StringLength(150)]
        public string BoreholeName { get; set; } = string.Empty;

        [StringLength(255)]
        public string? Location { get; set; }
        [StringLength(60)]
        public string? PumpType { get; set; }
        [StringLength(60)]
        public string? PumpCapacity { get; set; }
        [StringLength(60)]
        public string? TankCapacity { get; set; }
        [StringLength(120)]
        public string? WaterTreatmentMethod { get; set; }
        [StringLength(120)]
        public string? FiltrationSystem { get; set; }

        public bool UVSterilizationAvailable { get; set; }
        public int? MaintenanceFrequencyDays { get; set; }
        public DateTime? LastMaintenanceDate { get; set; }
        public DateTime? NextMaintenanceDate { get; set; }
        public DateTime? WaterQualityTestDueDate { get; set; }

        [StringLength(30)]
        public string Status { get; set; } = "Active";

        [StringLength(1000)]
        public string? Notes { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    // =========================================================================
    // Machine
    // =========================================================================
    public class WaterMachineModel
    {
        [Key]
        public int WaterMachineId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        [Required]
        [StringLength(150)]
        public string MachineName { get; set; } = string.Empty;

        [StringLength(60)]
        public string? MachineNumber { get; set; }
        [StringLength(40)]
        public string? MachineType { get; set; }
        [StringLength(120)]
        public string? Manufacturer { get; set; }
        public DateTime? PurchaseDate { get; set; }
        public int? CapacityPerHour { get; set; }
        public int? AssignedOperatorStaffId { get; set; }
        public int? MaintenanceFrequencyDays { get; set; }
        public DateTime? LastMaintenanceDate { get; set; }
        public DateTime? NextMaintenanceDate { get; set; }

        [StringLength(30)]
        public string Status { get; set; } = "Active";

        [StringLength(1000)]
        public string? Notes { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    // =========================================================================
    // Production Batch
    // =========================================================================
    public class WaterProductionBatchModel
    {
        [Key]
        public int WaterProductionBatchId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        [Required]
        [StringLength(60)]
        public string BatchNumber { get; set; } = string.Empty;

        public DateTime ProductionDate { get; set; }

        [StringLength(20)]
        public string Shift { get; set; } = WaterProductionShifts.FullDay;

        public int? WaterMachineId { get; set; }
        public string? MachineName { get; set; }  // join
        public int? WaterBoreholeId { get; set; }
        public string? BoreholeName { get; set; }  // join
        public int? OperatorStaffId { get; set; }
        public DateTime? StartTime { get; set; }
        public DateTime? EndTime { get; set; }

        [Required]
        public int WaterProductId { get; set; }
        public string? ProductName { get; set; }  // join

        [Range(0, int.MaxValue)]
        public int BagsProduced { get; set; }

        [Range(1, int.MaxValue)]
        public int SachetsPerBag { get; set; } = 30;

        [Range(0, int.MaxValue)]
        public int LooseSachetsProduced { get; set; }

        [Range(0, int.MaxValue)]
        public int RejectedSachets { get; set; }

        [Range(0, int.MaxValue)]
        public int DamagedBags { get; set; }

        [Range(0, int.MaxValue)]
        public int PackagingRollsUsed { get; set; }

        public int? EstimatedWaterUsedLitres { get; set; }

        [Range(0, double.MaxValue)]
        public decimal ElectricityCost { get; set; }

        [Range(0, double.MaxValue)]
        public decimal FuelCost { get; set; }

        [Range(0, double.MaxValue)]
        public decimal LaborCost { get; set; }

        [Range(0, double.MaxValue)]
        public decimal OtherProductionCost { get; set; }

        public decimal TotalProductionCost { get; set; }  // computed DB-side

        [StringLength(20)]
        public string QualityStatus { get; set; } = WaterQualityResult.Pending;

        public decimal? QualityPHLevel { get; set; }
        public decimal? QualityChlorinePpm { get; set; }
        public decimal? QualityTurbidity { get; set; }
        public int? QualityTDS { get; set; }

        [StringLength(500)]
        public string? QualityNotes { get; set; }

        [StringLength(1000)]
        public string? Notes { get; set; }

        [StringLength(20)]
        public string Status { get; set; } = WaterProductionBatchStatus.Draft;

        public string? CreatedBy { get; set; }
        public string? ApprovedBy { get; set; }
        public DateTime? ApprovedAt { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public bool IsDeleted { get; set; }
    }

    // =========================================================================
    // Quality Test (separate, detailed)
    // =========================================================================
    public class WaterQualityTestModel
    {
        [Key]
        public int WaterQualityTestId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        public int? WaterBoreholeId { get; set; }
        public string? BoreholeName { get; set; }
        public int? WaterProductionBatchId { get; set; }
        public string? BatchNumber { get; set; }

        public DateTime TestDate { get; set; }

        [StringLength(40)]
        public string? TestType { get; set; }

        public decimal? PHLevel { get; set; }
        public int? TDS { get; set; }
        public decimal? Turbidity { get; set; }
        public decimal? ChlorineLevel { get; set; }

        [StringLength(20)]
        public string Result { get; set; } = WaterQualityResult.Pending;

        [StringLength(120)]
        public string? TestedBy { get; set; }
        [StringLength(150)]
        public string? LabName { get; set; }
        [StringLength(500)]
        public string? AttachmentUrl { get; set; }
        public DateTime? NextTestDate { get; set; }

        [StringLength(1000)]
        public string? Notes { get; set; }

        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    // =========================================================================
    // Daily Pumping Log
    // =========================================================================
    public class WaterDailyPumpingLogModel
    {
        [Key]
        public int WaterDailyPumpingLogId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        [Required]
        public int WaterBoreholeId { get; set; }
        public string? BoreholeName { get; set; }

        public DateTime LogDate { get; set; }
        public int? OpeningTankLevel { get; set; }
        public int? ClosingTankLevel { get; set; }
        public int? EstimatedLitresPumped { get; set; }
        public DateTime? PumpStartTime { get; set; }
        public DateTime? PumpEndTime { get; set; }
        public decimal? ElectricityUsed { get; set; }
        public decimal? FuelUsed { get; set; }
        public int? OperatorStaffId { get; set; }

        [StringLength(500)]
        public string? Notes { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }
}
