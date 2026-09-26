using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    public class HotelAssetCategoryModel
    {
        [Key] public int HotelAssetCategoryId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public string CategoryName { get; set; } = string.Empty;
        public int DefaultUsefulLifeMonths { get; set; } = 60;
        public int SortOrder { get; set; }
        public bool IsActive { get; set; } = true;
    }

    public class HotelCapitalAssetModel
    {
        [Key] public int HotelCapitalAssetId { get; set; }
        [Required] public string FarmId { get; set; } = string.Empty;
        public string AssetName { get; set; } = string.Empty;
        public string? AssetNumber { get; set; }
        public int? HotelAssetCategoryId { get; set; }
        public string? CategoryName { get; set; }
        public string Status { get; set; } = "Draft";
        public DateTime? AcquisitionDate { get; set; }
        public DateTime? InServiceDate { get; set; }
        public DateTime? DisposalDate { get; set; }
        public decimal AcquisitionCost { get; set; }
        public decimal AdditionalCost { get; set; }
        public decimal TotalCapitalizedCost { get; set; }
        public decimal ResidualValue { get; set; }
        public int UsefulLifeMonths { get; set; } = 60;
        public string DepreciationMethod { get; set; } = "StraightLine";
        public decimal AccumulatedDepreciation { get; set; }
        public decimal CurrentBookValue { get; set; }
        public string? Supplier { get; set; }
        public string? Location { get; set; }
        public string? SerialNumber { get; set; }
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public string? ReversedBy { get; set; }
        public string? ReversedReason { get; set; }
        public DateTime? ReversedAt { get; set; }
    }

    public class HotelCapitalAssetCostModel
    {
        [Key] public int HotelCapitalAssetCostId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public int HotelCapitalAssetId { get; set; }
        public decimal Amount { get; set; }
        public string SourceType { get; set; } = "Acquisition";
        public string? Description { get; set; }
        public DateTime? CostDate { get; set; }
        public string Status { get; set; } = "Posted";
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    public class HotelAssetDepreciationModel
    {
        [Key] public int HotelAssetDepreciationId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public int HotelCapitalAssetId { get; set; }
        public string? AssetName { get; set; }
        public DateTime PeriodStart { get; set; }
        public decimal Amount { get; set; }
        public decimal AccumulatedAfter { get; set; }
        public decimal BookValueAfter { get; set; }
        public string DepreciationMethod { get; set; } = "StraightLine";
        public string SourceType { get; set; } = "Scheduled";
        public string? Reason { get; set; }
        public string Status { get; set; } = "Posted";
        public string? CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    public class HotelCapitalAssetSummaryModel
    {
        public int TotalAssets { get; set; }
        public int ActiveAssets { get; set; }
        public int DraftAssets { get; set; }
        public decimal TotalAssetCost { get; set; }
        public decimal AccumulatedDepreciation { get; set; }
        public decimal CurrentBookValue { get; set; }
    }

    public class HotelDepreciationRunResult
    {
        public int AssetsProcessed { get; set; }
        public int EntriesCreated { get; set; }
        public decimal TotalAmount { get; set; }
    }

    public class HotelCapitalAssetCreateRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        public string AssetName { get; set; } = string.Empty;
        public int? HotelAssetCategoryId { get; set; }
        public string? AcquisitionDate { get; set; }
        public string? InServiceDate { get; set; }
        public decimal ResidualValue { get; set; }
        public int UsefulLifeMonths { get; set; } = 60;
        public decimal Amount { get; set; }
        public string? Supplier { get; set; }
        public string? Location { get; set; }
        public string? SerialNumber { get; set; }
        public string? Notes { get; set; }
    }

    public class HotelCapitalAssetUpdateRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        public string AssetName { get; set; } = string.Empty;
        public int? HotelAssetCategoryId { get; set; }
        public string? AcquisitionDate { get; set; }
        public string? InServiceDate { get; set; }
        public decimal ResidualValue { get; set; }
        public int UsefulLifeMonths { get; set; } = 60;
        public string? Supplier { get; set; }
        public string? Location { get; set; }
        public string? SerialNumber { get; set; }
        public string? Notes { get; set; }
    }

    public class HotelAssetCostRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        public decimal Amount { get; set; }
        public string? Description { get; set; }
        public string? CostDate { get; set; }
    }

    public class HotelAssetReasonRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        public string? Reason { get; set; }
        public string? DisposalDate { get; set; }
    }

    public class HotelDepreciationGenerateRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;
        public string? ThroughDate { get; set; }
        public int? AssetId { get; set; }
    }
}
