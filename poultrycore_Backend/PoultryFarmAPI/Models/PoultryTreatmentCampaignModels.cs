// Treatment Campaigns (migration 339): one medication given to many flocks over
// one or more days. Each posted day is medication lines on the flocks'
// production records, through the same spproductionrecord_update an individual
// edit uses. Doses and withdrawal periods are the farm's own figures -- nothing
// is built in.

namespace PoultryFarmAPIWeb.Models
{
    public class MedicationProduct
    {
        public int PoultryRawMaterialItemId { get; set; }
        public string ItemName { get; set; } = string.Empty;
        public string? Category { get; set; }
        public string? UnitOfMeasure { get; set; }
        /// <summary>FIFO | LIFO | HIFO -- the item's own costing method.</summary>
        public string UsageMethod { get; set; } = "FIFO";
        public bool IsActive { get; set; }
        /// <summary>What the purchase lots can supply: exactly what posting can draw.</summary>
        public decimal AvailableQuantity { get; set; }
        public int LotCount { get; set; }
        /// <summary>EXPENSE_WHEN_PURCHASED | EXPENSE_WHEN_CONSUMED for this item today.</summary>
        public string? CostRecognitionMethod { get; set; }
        /// <summary>The farm's saved dose; null = none saved, so no suggestion.</summary>
        public decimal? DoseQuantity { get; set; }
        /// <summary>PerBird | Per1000Birds | PerFlock.</summary>
        public string? DoseBasis { get; set; }
        public int? EggWithdrawalDays { get; set; }
        public int? MeatWithdrawalDays { get; set; }
        public string? WithdrawalNotes { get; set; }
    }

    public class MedicationProductSettingsRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public decimal? DoseQuantity { get; set; }
        public string? DoseBasis { get; set; }
        public int? EggWithdrawalDays { get; set; }
        public int? MeatWithdrawalDays { get; set; }
        public string? WithdrawalNotes { get; set; }
    }

    public class TreatmentFlockOption
    {
        public int FlockId { get; set; }
        public string FlockName { get; set; } = string.Empty;
        public string? BatchName { get; set; }
        public string? HouseName { get; set; }
        public int? Birds { get; set; }
    }

    public class TreatmentCampaign
    {
        public int PoultryTreatmentCampaignId { get; set; }
        public string Name { get; set; } = string.Empty;
        public int PoultryRawMaterialItemId { get; set; }
        public string? ItemName { get; set; }
        public string? UnitOfMeasure { get; set; }
        public string? Reason { get; set; }
        public DateTime StartDate { get; set; }
        public DateTime EndDate { get; set; }
        public int PlannedDays { get; set; }
        public string? DoseInstructions { get; set; }
        public decimal? DoseQuantity { get; set; }
        public string? DoseBasis { get; set; }
        /// <summary>User | Product | None -- where the dose figure came from.</summary>
        public string DoseSource { get; set; } = "None";
        public int? EggWithdrawalDays { get; set; }
        public int? MeatWithdrawalDays { get; set; }
        public string? WithdrawalNotes { get; set; }
        public string? Notes { get; set; }
        /// <summary>Stored: Open | Completed | Cancelled.</summary>
        public string Lifecycle { get; set; } = "Open";
        /// <summary>Shown: Scheduled | InProgress | Completed | Cancelled.</summary>
        public string Status { get; set; } = "Scheduled";
        public DateTime CompanyToday { get; set; }
        public int FlockCount { get; set; }
        public int PostedDays { get; set; }
        public decimal TotalQuantity { get; set; }
        public decimal? TotalCost { get; set; }
        public DateTime? LastPostedDate { get; set; }
        public DateTime? EggWithdrawalUntil { get; set; }
        public DateTime? MeatWithdrawalUntil { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime CreatedAtUtc { get; set; }
        public string? CompletedBy { get; set; }
        public DateTime? CompletedAtUtc { get; set; }
        public string? CancelledBy { get; set; }
        public DateTime? CancelledAtUtc { get; set; }
        public string? CancelReason { get; set; }
    }

    public class TreatmentCampaignFlock
    {
        public int FlockId { get; set; }
        public string FlockName { get; set; } = string.Empty;
        public string? HouseName { get; set; }
        public int? BirdsAtCreation { get; set; }
        /// <summary>This flock's own dose, when it differs from the campaign's.</summary>
        public decimal? DoseQuantity { get; set; }
        public string? Notes { get; set; }
        public bool IsClosed { get; set; }
        public int PostedDays { get; set; }
        public decimal TotalQuantity { get; set; }
        public DateTime? LastPostedDate { get; set; }
    }

    public class TreatmentDayRow
    {
        public int FlockId { get; set; }
        public string FlockName { get; set; } = string.Empty;
        public string? HouseName { get; set; }
        public bool IsClosed { get; set; }
        /// <summary>Production records for the date. Only exactly 1 can be dosed.</summary>
        public int RecordCount { get; set; }
        public int? ProductionRecordId { get; set; }
        public int? Birds { get; set; }
        public decimal? DoseQuantity { get; set; }
        public string? DoseBasis { get; set; }
        /// <summary>Plain arithmetic on the farm's own dose; null when there is no dose.</summary>
        public decimal? SuggestedQuantity { get; set; }
        /// <summary>This product already on the day's record (from any source).</summary>
        public decimal ThisItemQuantity { get; set; }
        /// <summary>What this campaign already posted for the flock on the date; null = not yet.</summary>
        public decimal? PostedQuantity { get; set; }
        public string? Notes { get; set; }
    }

    public class TreatmentDayPosting
    {
        public int PoultryTreatmentCampaignPostId { get; set; }
        public int PoultryTreatmentCampaignId { get; set; }
        public DateTime BusinessDate { get; set; }
        public int FlockCount { get; set; }
        public decimal TotalQuantity { get; set; }
        public decimal? TotalCost { get; set; }
        public string Status { get; set; } = "Posted";
        public string? Notes { get; set; }
        public string? PostedBy { get; set; }
        public DateTime PostedAtUtc { get; set; }
        public string? ReversedBy { get; set; }
        public DateTime? ReversedAtUtc { get; set; }
        public string? ReversalReason { get; set; }
    }

    public class TreatmentDayLine
    {
        public int PoultryTreatmentCampaignPostLineId { get; set; }
        public int FlockId { get; set; }
        public string? FlockName { get; set; }
        public int ProductionRecordId { get; set; }
        public int? Birds { get; set; }
        public decimal? DoseQuantity { get; set; }
        public string? DoseBasis { get; set; }
        public decimal? SuggestedQuantity { get; set; }
        public decimal ActualQuantity { get; set; }
        public decimal? UnitCost { get; set; }
        public decimal? TotalCost { get; set; }
        public string? Notes { get; set; }
        public string? ReversalNote { get; set; }
    }

    public class FlockTreatmentHistoryRow
    {
        public int PoultryTreatmentCampaignPostLineId { get; set; }
        public int PoultryTreatmentCampaignPostId { get; set; }
        public int PoultryTreatmentCampaignId { get; set; }
        public string CampaignName { get; set; } = string.Empty;
        public string? Reason { get; set; }
        public string? ItemName { get; set; }
        public string? UnitOfMeasure { get; set; }
        public DateTime BusinessDate { get; set; }
        public int ProductionRecordId { get; set; }
        public int? Birds { get; set; }
        public decimal ActualQuantity { get; set; }
        public decimal? TotalCost { get; set; }
        public string PostStatus { get; set; } = "Posted";
        public DateTime? EggWithdrawalUntil { get; set; }
        public DateTime? MeatWithdrawalUntil { get; set; }
        public string? Notes { get; set; }
    }

    public class TreatmentCampaignFlockInput
    {
        public int FlockId { get; set; }
        public decimal? DoseQuantity { get; set; }
        public string? Notes { get; set; }
    }

    public class TreatmentCampaignCreateRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public int ItemId { get; set; }
        public string? Reason { get; set; }
        public DateTime StartDate { get; set; }
        public DateTime EndDate { get; set; }
        public string? DoseInstructions { get; set; }
        public decimal? DoseQuantity { get; set; }
        public string? DoseBasis { get; set; }
        /// <summary>User | Product.</summary>
        public string? DoseSource { get; set; }
        public int? EggWithdrawalDays { get; set; }
        public int? MeatWithdrawalDays { get; set; }
        public string? WithdrawalNotes { get; set; }
        public string? Notes { get; set; }
        /// <summary>Also save the dose and withdrawal as the product's own settings.</summary>
        public bool SaveAsProductDefault { get; set; }
        public List<TreatmentCampaignFlockInput> Flocks { get; set; } = new();
    }

    public class TreatmentDayLineInput
    {
        public int FlockId { get; set; }
        public decimal ActualQuantity { get; set; }
        public decimal? SuggestedQuantity { get; set; }
        public string? Notes { get; set; }
    }

    public class TreatmentDayPostRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public DateTime BusinessDate { get; set; }
        public string? Notes { get; set; }
        public List<TreatmentDayLineInput> Lines { get; set; } = new();
    }

    public class TreatmentReasonRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public string Reason { get; set; } = string.Empty;
    }

    public class TreatmentFarmRequest
    {
        public string FarmId { get; set; } = string.Empty;
    }
}
