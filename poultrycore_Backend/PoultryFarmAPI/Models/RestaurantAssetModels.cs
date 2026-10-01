// Restaurant Capital Investments/Assets (migration 328).
// Row DTOs mirror the sprestaurant_capitalasset_* / _assetdepreciation_* result
// columns (read by name, ignoring case). Every class starts with "Restaurant"
// and is unique API-wide: Swagger keys schemas by class name, and a duplicate
// 500s the whole document.

namespace PoultryFarmAPIWeb.Models
{
    public class RestaurantAssetCategory
    {
        public int AssetCategoryId { get; set; }
        public string CategoryName { get; set; } = "";
        public int? DefaultUsefulLifeMonths { get; set; }
        public int SortOrder { get; set; }
        public bool IsActive { get; set; }
        public int AssetCount { get; set; }
    }

    public class RestaurantCapitalAsset
    {
        public int CapitalAssetId { get; set; }
        public string AssetNumber { get; set; } = "";
        public string AssetName { get; set; } = "";
        public int? AssetCategoryId { get; set; }
        public string? CategoryName { get; set; }
        public string? Description { get; set; }
        public DateTime AcquisitionDate { get; set; }
        public DateTime? InServiceDate { get; set; }
        public string? Location { get; set; }
        public string? SerialNumber { get; set; }
        public int? SupplierId { get; set; }
        public string? SupplierName { get; set; }
        public string Status { get; set; } = "";
        public string? Notes { get; set; }
        /// <summary>The TOTAL capitalised cost, under the reference's old name. Read TotalCapitalizedCost.</summary>
        public decimal OriginalCost { get; set; }
        public decimal ResidualValue { get; set; }
        public decimal DepreciableAmount { get; set; }
        public int? UsefulLifeMonths { get; set; }
        public decimal? MonthlyDepreciation { get; set; }
        public decimal AccumulatedDepreciation { get; set; }
        public decimal CurrentBookValue { get; set; }
        public decimal RemainingDepreciable { get; set; }
        public bool IsFullyDepreciated { get; set; }
        public int CostEntries { get; set; }
        public int DepreciationEntries { get; set; }
        public DateTime? DisposalDate { get; set; }
        public decimal? DisposalProceeds { get; set; }
        public int? DisposalAccountId { get; set; }
        public string? DisposalNotes { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime? CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public string? ReversedBy { get; set; }
        public DateTime? ReversedAt { get; set; }
        public string? ReversalReason { get; set; }
        public decimal AcquisitionCost { get; set; }
        public decimal AdditionalCost { get; set; }
        public decimal TotalCapitalizedCost { get; set; }
        /// <summary>Still owed to suppliers on this asset's purchases.</summary>
        public decimal AmountOwed { get; set; }

        public List<RestaurantCapitalAssetCost>? Costs { get; set; }
        public List<RestaurantAssetDepreciation>? Depreciation { get; set; }
    }

    public class RestaurantCapitalAssetCost
    {
        public int AssetCostId { get; set; }
        public int CapitalAssetId { get; set; }
        public DateTime CostDate { get; set; }
        public string? Description { get; set; }
        public string? CostCategory { get; set; }
        public decimal Amount { get; set; }
        public string? SourceType { get; set; }
        public int? CorrectionOfId { get; set; }
        public int? SupplierId { get; set; }
        public string? SupplierName { get; set; }
        public string? PaymentMethod { get; set; }
        public decimal AmountPaid { get; set; }
        public decimal Balance { get; set; }
        public string? PaymentStatus { get; set; }
        public DateTime? DueDate { get; set; }
        public int? CashAccountId { get; set; }
        public string? CashAccountName { get; set; }
        public decimal? DocumentAmount { get; set; }
        public string Status { get; set; } = "";
        public string? CreatedBy { get; set; }
        public DateTime? CreatedAt { get; set; }
        public string? ReversedBy { get; set; }
        public DateTime? ReversedAt { get; set; }
        public string? ReversalReason { get; set; }
    }

    public class RestaurantAssetDepreciation
    {
        public int AssetDepreciationId { get; set; }
        public int CapitalAssetId { get; set; }
        public string? AssetNumber { get; set; }
        public string? AssetName { get; set; }
        public string? CategoryName { get; set; }
        public DateTime PeriodStart { get; set; }
        public DateTime PeriodEnd { get; set; }
        public DateTime DepreciationDate { get; set; }
        public decimal Amount { get; set; }
        public string? DepreciationMethod { get; set; }
        public string? SourceType { get; set; }
        public string? Status { get; set; }
        public int? ReversalOfId { get; set; }
        public decimal? OriginalCost { get; set; }
        public decimal? MonthlyDepreciation { get; set; }
        public decimal? AccumulatedAfter { get; set; }
        public decimal? BookValueAfter { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime? CreatedAt { get; set; }
        public string? ReversedBy { get; set; }
        public DateTime? ReversedAt { get; set; }
        public string? ReversalReason { get; set; }
    }

    public class RestaurantCapitalAssetSummary
    {
        public int TotalAssets { get; set; }
        public int ActiveAssets { get; set; }
        public int DraftAssets { get; set; }
        public int DisposedAssets { get; set; }
        public int FullyDepreciated { get; set; }
        public decimal TotalAssetCost { get; set; }
        public decimal AccumulatedDepreciation { get; set; }
        public decimal CurrentBookValue { get; set; }
        public decimal AddedInPeriod { get; set; }
        public int AddedCount { get; set; }
        public decimal AmountOwed { get; set; }
    }

    public class RestaurantAssetDepreciationDue
    {
        public int CapitalAssetId { get; set; }
        public string? AssetNumber { get; set; }
        public string? AssetName { get; set; }
        public int MonthsDue { get; set; }
        public decimal AmountDue { get; set; }
        public decimal? MonthlyDepreciation { get; set; }
        public DateTime? NextPeriod { get; set; }
    }

    public class RestaurantAssetDepreciationRun
    {
        public int AssetsProcessed { get; set; }
        public int EntriesCreated { get; set; }
        public decimal TotalAmount { get; set; }
    }

    /// <summary>One open capital purchase document: the seam for Supplier Balances.</summary>
    public class RestaurantCapitalAssetPayable
    {
        public int AssetCostId { get; set; }
        public int CapitalAssetId { get; set; }
        public string? AssetNumber { get; set; }
        public string? AssetName { get; set; }
        public string? SourceType { get; set; }
        public int? SupplierId { get; set; }
        public string? SupplierName { get; set; }
        public DateTime DocumentDate { get; set; }
        public DateTime? DueDate { get; set; }
        public decimal Amount { get; set; }
        public decimal AmountPaid { get; set; }
        public decimal Balance { get; set; }
    }

    // ── Requests ────────────────────────────────────────────────────────────

    public class RestaurantAssetCategoryRequest
    {
        public int? AssetCategoryId { get; set; }
        public string CategoryName { get; set; } = "";
        public int? DefaultUsefulLifeMonths { get; set; }
        public bool? IsActive { get; set; }
    }

    public class RestaurantCapitalAssetCreateRequest
    {
        public string AssetName { get; set; } = "";
        public int? AssetCategoryId { get; set; }
        public string? Description { get; set; }
        public DateTime? AcquisitionDate { get; set; }
        public DateTime? InServiceDate { get; set; }
        public decimal? Amount { get; set; }
        public decimal? ResidualValue { get; set; }
        public int? UsefulLifeMonths { get; set; }
        public string? Supplier { get; set; }
        public int? SupplierId { get; set; }
        public string? PaymentMethod { get; set; }
        public decimal? AmountPaid { get; set; }
        public DateTime? DueDate { get; set; }
        public int? CashAccountId { get; set; }
        public string? Location { get; set; }
        public string? SerialNumber { get; set; }
        public string? Notes { get; set; }
    }

    public class RestaurantCapitalAssetUpdateRequest
    {
        public string? AssetName { get; set; }
        public int? AssetCategoryId { get; set; }
        public string? Description { get; set; }
        public string? Location { get; set; }
        public string? SerialNumber { get; set; }
        public string? Notes { get; set; }
        public DateTime? InServiceDate { get; set; }
        public int? UsefulLifeMonths { get; set; }
        public decimal? ResidualValue { get; set; }
        public bool SetFinancials { get; set; }
    }

    public class RestaurantCapitalAssetCostRequest
    {
        public DateTime? CostDate { get; set; }
        public string? Description { get; set; }
        public string? CostCategory { get; set; }
        public decimal Amount { get; set; }
        public string? Supplier { get; set; }
        public int? SupplierId { get; set; }
        public string? PaymentMethod { get; set; }
        public decimal? AmountPaid { get; set; }
        public DateTime? DueDate { get; set; }
        public int? CashAccountId { get; set; }
    }

    public class RestaurantCapitalAssetCorrectCostRequest
    {
        public decimal NewAmount { get; set; }
        public DateTime? EffectiveDate { get; set; }
        public string Reason { get; set; } = "";
    }

    public class RestaurantCapitalAssetDisposeRequest
    {
        public DateTime? DisposalDate { get; set; }
        public decimal? Proceeds { get; set; }
        public int? CashAccountId { get; set; }
        public string? Notes { get; set; }
    }

    public class RestaurantDepreciationGenerateRequest
    {
        public DateTime? ThroughDate { get; set; }
        public int? AssetId { get; set; }
    }

    public class RestaurantDepreciationAdjustRequest
    {
        public int AssetId { get; set; }
        public DateTime PeriodStart { get; set; }
        public decimal Amount { get; set; }
        public string Reason { get; set; } = "";
    }
}
