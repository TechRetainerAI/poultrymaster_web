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

        public decimal TotalProductionCost { get; set; }  // computed DB-side (excludes raw materials)

        // Migration 063: denormalized roll-up of raw material cost for this
        // batch. The all-in cost (used for cost/bag) is TotalProductionCost +
        // RawMaterialCost — kept separate so the existing PERSISTED computed
        // column doesn't have to be reshaped.
        public decimal RawMaterialCost { get; set; }

        // Migration 067 — server-computed derived values returned by the
        // GetAll / GetById SPs. The list page now binds Cost/Bag and the
        // all-in total cost directly from these fields rather than computing
        // them client-side (which was returning 0).
        public int GoodBags { get; set; }
        public decimal AllInCost { get; set; }
        public decimal CostPerBag { get; set; }
        public decimal ProductionEfficiencyPercent { get; set; }

        // Migration 067 — "All Machines / Combined" support.
        // Values: 'SingleMachine' (default) | 'AllMachines'.
        [StringLength(20)]
        public string MachineScope { get; set; } = "SingleMachine";

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

        // Migration 063: optional list of raw materials actually used for this
        // batch. When supplied to POST/PUT, the SP replaces existing usage
        // rows for the batch and recomputes RawMaterialCost. Read-side calls
        // ignore this — usage rows are fetched separately via the recipes
        // endpoint.
        public List<WaterProductionMaterialUsageInput>? MaterialsUsed { get; set; }
    }

    // Inbound DTO for the "Raw Materials Used" section of the Record Production
    // Batch modal. Property names match the JSON the SP's OPENJSON contract
    // expects (camelCase).
    public class WaterProductionMaterialUsageInput
    {
        public int WaterRawMaterialItemId { get; set; }
        public decimal QuantityUsed { get; set; }
        public decimal? ExpectedQuantityUsed { get; set; }
        public decimal? UnitCost { get; set; }
        public string? VarianceReason { get; set; }
        public string? Notes { get; set; }
    }

    // Outbound DTO returned by /production-batches/{id}/materials. Adds joined
    // material metadata so the UI can render the usage table without a
    // second round-trip.
    public class WaterProductionMaterialUsageRow
    {
        public int WaterRawMaterialUsageId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public int WaterRawMaterialItemId { get; set; }
        public string? ItemName { get; set; }
        public string? UnitOfMeasure { get; set; }
        public decimal? CurrentStock { get; set; }
        public int? WaterProductionBatchId { get; set; }
        public string? BatchNumber { get; set; }
        public string? FinishedProductName { get; set; }
        public DateTime UsedDate { get; set; }
        public decimal QuantityUsed { get; set; }
        public decimal? ExpectedQuantityUsed { get; set; }
        public decimal Variance { get; set; }
        public string? VarianceReason { get; set; }
        public decimal? UnitCost { get; set; }
        public decimal? TotalCost { get; set; }
        public int? UsedByStaffId { get; set; }
        public string? Notes { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    // =========================================================================
    // Production Recipe (Migration 063)
    // =========================================================================
    public class WaterProductionRecipeModel
    {
        [Key]
        public int WaterProductionRecipeId { get; set; }

        [Required]
        public string FarmId { get; set; } = string.Empty;

        [Required]
        public int WaterProductId { get; set; }

        [StringLength(150)]
        public string RecipeName { get; set; } = "Default";

        public bool IsDefault { get; set; } = true;
        public bool IsActive { get; set; } = true;

        [StringLength(500)]
        public string? Notes { get; set; }

        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public string? UpdatedBy { get; set; }
        public DateTime? UpdatedAt { get; set; }

        public List<WaterProductionRecipeItemModel> Items { get; set; } = new();
    }

    public class WaterProductionRecipeItemModel
    {
        [Key]
        public int WaterProductionRecipeItemId { get; set; }

        public int WaterProductionRecipeId { get; set; }

        [Required]
        public int WaterRawMaterialItemId { get; set; }

        // Joined columns (read-only):
        public string? RawMaterialName { get; set; }
        public string? RawMaterialUnit { get; set; }
        public decimal? RawMaterialStock { get; set; }
        public decimal? LatestUnitCost { get; set; }

        [Range(0, double.MaxValue)]
        public decimal QuantityPerOutputUnit { get; set; }

        [StringLength(30)]
        public string OutputUnit { get; set; } = "bag";

        [Range(0, double.MaxValue)]
        public decimal WasteAllowancePercent { get; set; }

        public bool IsOptional { get; set; }
        public int DisplayOrder { get; set; }

        [StringLength(300)]
        public string? Notes { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    // =========================================================================
    // Production Loss (Migration 067)
    // =========================================================================
    // One row per damaged-bags / rejected-sachets event, automatically created
    // when a production batch is approved. SourceType/SourceId resolve back to
    // the batch.
    public class WaterProductionLossModel
    {
        [Key]
        public int WaterProductionLossId { get; set; }

        public string FarmId { get; set; } = string.Empty;
        public DateTime LossDate { get; set; }

        [StringLength(40)]
        public string LossType { get; set; } = "ProductionDamage";

        [StringLength(40)]
        public string SourceType { get; set; } = "ProductionBatch";
        public int? SourceId { get; set; }

        public int? WaterProductId { get; set; }
        public string? ProductName { get; set; }   // join
        public string? BatchNumber { get; set; }   // join

        public int BagsLost { get; set; }
        public int SachetsLost { get; set; }
        public int SachetsPerBag { get; set; }

        public decimal CostPerBag { get; set; }
        public decimal BagsLossValue { get; set; }
        public decimal SachetsLossValue { get; set; }
        public decimal TotalValue { get; set; }

        [StringLength(500)]
        public string? Reason { get; set; }

        [StringLength(20)]
        public string Status { get; set; } = "Approved";

        [StringLength(1000)]
        public string? Notes { get; set; }

        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    // =========================================================================
    // Production Batch linked-records (Migration 067)
    // =========================================================================
    // Returned from /production-batches/{id}/linked-stock-txns.
    public class WaterProductionLinkedStockTxnRow
    {
        public int WaterStockTransactionId { get; set; }
        public int WaterProductId { get; set; }
        public string? ProductName { get; set; }
        public string? TxnType { get; set; }
        public int Quantity { get; set; }
        public decimal? UnitCost { get; set; }
        public string? Note { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    // Returned from /production-batches/{id}/linked-expenses. Mirrors enough of
    // WaterExpenseModel for the details view without pulling the full module.
    public class WaterProductionLinkedExpenseRow
    {
        public int WaterExpenseId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public DateTime ExpenseDate { get; set; }
        public int WaterExpenseCategoryId { get; set; }
        public string? CategoryName { get; set; }
        public string? Description { get; set; }
        public decimal Amount { get; set; }
        public string? PaidTo { get; set; }
        public string? PaymentMethod { get; set; }
        public int? WaterCashAccountId { get; set; }
        public string? CashAccountName { get; set; }
        public int? LinkedWaterProductionBatchId { get; set; }
        public string? Status { get; set; }
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
        public string? ApprovedBy { get; set; }
        public DateTime? ApprovedAt { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    // Body for POST/PUT to /Water/products/{id}/recipe.
    public class WaterProductionRecipeUpsertRequest
    {
        [StringLength(150)]
        public string RecipeName { get; set; } = "Default";

        [StringLength(500)]
        public string? Notes { get; set; }

        public List<WaterProductionRecipeItemModel> Items { get; set; } = new();
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
