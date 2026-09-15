// Poultry capital assets and depreciation (migrations 270, 271).
//
// A capital asset is a purchase the farm will still own next year: a poultry
// house, a vehicle, a feed mixer, a generator. It is NOT this month's expense,
// and the whole point of these types is to keep the two apart.
//
// THREE NUMBERS ARE DERIVED, NOT STORED
// -------------------------------------
//   OriginalCost             the sum of the asset's capitalised costs
//   AccumulatedDepreciation  the sum of its depreciation ledger
//   CurrentBookValue         cost less accumulated, floored at residual value
//
// The server computes all three; writing them has no effect. A stored total
// would have to be kept in step with the rows behind it, and the day the two
// disagree there is no way to tell which is right.

using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    /// <summary>The status values an asset moves through. Strings, matching the DB.</summary>
    public static class CapitalAssetStatus
    {
        /// <summary>Acquired or under construction; not yet earning, so not depreciating.</summary>
        public const string Draft = "Draft";
        /// <summary>In service with a useful life set. Depreciation runs.</summary>
        public const string Active = "Active";
        /// <summary>Nothing left to depreciate. Book value has reached residual value.</summary>
        public const string FullyDepreciated = "FullyDepreciated";
        public const string Disposed = "Disposed";
        /// <summary>Acquisition unwound. The row is KEPT with its reason.</summary>
        public const string Reversed = "Reversed";
    }

    public static class FinancialCostType
    {
        public const string OperatingExpense = "OperatingExpense";
        public const string InventoryPurchase = "InventoryPurchase";
        public const string CapitalAsset = "CapitalAsset";
        public const string NonCashExpense = "NonCashExpense";
        public const string FinancingExpense = "FinancingExpense";
    }

    public class PoultryAssetCategoryModel
    {
        public int PoultryAssetCategoryId { get; set; }
        public string? FarmId { get; set; }
        [Required] [StringLength(80)] public string CategoryName { get; set; } = string.Empty;
        /// <summary>A suggestion the form fills in, never a rule.</summary>
        public int? DefaultUsefulLifeMonths { get; set; }
        public int SortOrder { get; set; }
        public bool IsActive { get; set; } = true;
        /// <summary>Read-only.</summary>
        public int AssetCount { get; set; }
    }

    public class PoultryCapitalAssetModel
    {
        public int PoultryCapitalAssetId { get; set; }
        public string? FarmId { get; set; }
        /// <summary>Read-only: the per-farm running number, AST-0001.</summary>
        public string? AssetNumber { get; set; }
        [Required] [StringLength(150)] public string AssetName { get; set; } = string.Empty;
        public int? PoultryAssetCategoryId { get; set; }
        public string? CategoryName { get; set; }
        [StringLength(500)] public string? Description { get; set; }

        public DateTime AcquisitionDate { get; set; }
        /// <summary>
        /// When the asset started earning. Depreciation runs from the month
        /// containing this date, not from acquisition: a house finished in March
        /// and stocked in June has not been earning since March.
        /// </summary>
        public DateTime? InServiceDate { get; set; }

        [StringLength(150)] public string? Location { get; set; }
        [StringLength(80)] public string? SerialNumber { get; set; }
        public int? SupplierId { get; set; }
        public string? SupplierName { get; set; }
        public string Status { get; set; } = CapitalAssetStatus.Draft;
        [StringLength(500)] public string? Notes { get; set; }

        // ---- financial ------------------------------------------------------

        /// <summary>Read-only: the sum of the asset's capitalised costs.</summary>
        public decimal OriginalCost { get; set; }
        /// <summary>What the farm expects the asset to still be worth at the end.</summary>
        public decimal ResidualValue { get; set; }
        /// <summary>Read-only: OriginalCost - ResidualValue, never below zero.</summary>
        public decimal DepreciableAmount { get; set; }
        public int? UsefulLifeMonths { get; set; }
        /// <summary>Read-only: DepreciableAmount / UsefulLifeMonths, straight line.</summary>
        public decimal? MonthlyDepreciation { get; set; }
        /// <summary>Read-only: the signed sum of the depreciation ledger.</summary>
        public decimal AccumulatedDepreciation { get; set; }
        /// <summary>Read-only: never falls below ResidualValue.</summary>
        public decimal CurrentBookValue { get; set; }
        /// <summary>Read-only: what is still to be charged to Profit &amp; Loss.</summary>
        public decimal RemainingDepreciable { get; set; }
        public bool IsFullyDepreciated { get; set; }

        /// <summary>Read-only: how many capitalised cost entries the asset has.</summary>
        public int CostEntries { get; set; }
        /// <summary>Read-only: how many depreciation charges have been posted.</summary>
        public int DepreciationEntries { get; set; }

        public DateTime? DisposalDate { get; set; }
        public decimal? DisposalProceeds { get; set; }

        public string? CreatedBy { get; set; }
        public DateTime? CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public string? ReversedBy { get; set; }
        public DateTime? ReversedAt { get; set; }
        public string? ReversalReason { get; set; }

        public List<PoultryCapitalAssetCostModel> Costs { get; set; } = new();
        public List<PoultryAssetDepreciationModel> Depreciation { get; set; } = new();
    }

    /// <summary>
    /// One capitalised amount. An asset that is BUILT rather than bought has
    /// several: cement, wood, labour, roofing. ExpenseId links to the expense row
    /// that actually moved the money or opened the payable.
    /// </summary>
    public class PoultryCapitalAssetCostModel
    {
        public int PoultryCapitalAssetCostId { get; set; }
        public int PoultryCapitalAssetId { get; set; }
        public DateTime CostDate { get; set; }
        [StringLength(300)] public string? Description { get; set; }
        [StringLength(80)] public string? CostCategory { get; set; }
        public decimal Amount { get; set; }
        /// <summary>Acquisition | AdditionalCost.</summary>
        public string? SourceType { get; set; }
        public int? ExpenseId { get; set; }
        public int? SupplierId { get; set; }
        public string? SupplierName { get; set; }
        /// <summary>Read-only, from the linked expense.</summary>
        public string? PaymentStatus { get; set; }
        public decimal? AmountPaid { get; set; }
        public decimal? Balance { get; set; }
        public string Status { get; set; } = "Posted";
        public string? CreatedBy { get; set; }
        public DateTime? CreatedAt { get; set; }
        public string? ReversedBy { get; set; }
        public DateTime? ReversedAt { get; set; }
        public string? ReversalReason { get; set; }
    }

    /// <summary>
    /// One month's charge. Amount is SIGNED -- a reversal is a negative row
    /// beside the original, never an edit to it -- so accumulated depreciation is
    /// a plain sum.
    /// </summary>
    public class PoultryAssetDepreciationModel
    {
        public int PoultryAssetDepreciationId { get; set; }
        public int PoultryCapitalAssetId { get; set; }
        public string? AssetNumber { get; set; }
        public string? AssetName { get; set; }
        public string? CategoryName { get; set; }
        public DateTime PeriodStart { get; set; }
        public DateTime PeriodEnd { get; set; }
        public DateTime? DepreciationDate { get; set; }
        public decimal Amount { get; set; }
        public string? DepreciationMethod { get; set; }
        /// <summary>Scheduled | CatchUp | ManualAdjustment | Reversal.</summary>
        public string? SourceType { get; set; }
        public string? Status { get; set; }
        /// <summary>The non-cash expense row this charge wrote.</summary>
        public int? ExpenseId { get; set; }
        public int? ReversalOfId { get; set; }

        public decimal? OriginalCost { get; set; }
        public decimal? MonthlyDepreciation { get; set; }
        /// <summary>Read-only: accumulated depreciation as at this row.</summary>
        public decimal? AccumulatedAfter { get; set; }
        /// <summary>Read-only: book value as at this row.</summary>
        public decimal? BookValueAfter { get; set; }

        public string? CreatedBy { get; set; }
        public DateTime? CreatedAt { get; set; }
        public string? ReversedBy { get; set; }
        public DateTime? ReversedAt { get; set; }
        public string? ReversalReason { get; set; }
    }

    /// <summary>The cards at the top of the register.</summary>
    public class PoultryCapitalAssetSummaryModel
    {
        public int TotalAssets { get; set; }
        public int ActiveAssets { get; set; }
        public int DraftAssets { get; set; }
        public int DisposedAssets { get; set; }
        public int FullyDepreciated { get; set; }
        public decimal TotalAssetCost { get; set; }
        public decimal AccumulatedDepreciation { get; set; }
        /// <summary>
        /// A BALANCE, never a period total: what the farm owns today. Only
        /// AddedInPeriod is scoped to the selected dates.
        /// </summary>
        public decimal CurrentBookValue { get; set; }
        public decimal AddedInPeriod { get; set; }
        public int AddedCount { get; set; }
    }

    /// <summary>What "Generate due depreciation" would do, before it does it.</summary>
    public class PoultryAssetDepreciationDueModel
    {
        public int PoultryCapitalAssetId { get; set; }
        public string? AssetNumber { get; set; }
        public string? AssetName { get; set; }
        public int MonthsDue { get; set; }
        public decimal AmountDue { get; set; }
        public decimal? MonthlyDepreciation { get; set; }
        public DateTime? NextPeriod { get; set; }
    }

    public class PoultryAssetDepreciationRunResult
    {
        public int AssetsProcessed { get; set; }
        public int EntriesCreated { get; set; }
        public decimal TotalAmount { get; set; }
    }

    // ---- requests -----------------------------------------------------------

    public class PoultryCapitalAssetCreateRequest
    {
        public string? FarmId { get; set; }
        [Required] [StringLength(150)] public string AssetName { get; set; } = string.Empty;
        public int? AssetCategoryId { get; set; }
        [StringLength(500)] public string? Description { get; set; }
        public DateTime? AcquisitionDate { get; set; }
        public DateTime? InServiceDate { get; set; }
        /// <summary>
        /// Optional. An asset that will be BUILT starts at nothing and grows
        /// through AddCost; only one bought outright names its price here.
        /// </summary>
        public decimal? Amount { get; set; }
        public decimal? ResidualValue { get; set; }
        public int? UsefulLifeMonths { get; set; }
        [StringLength(200)] public string? Supplier { get; set; }
        public int? SupplierId { get; set; }
        [StringLength(30)] public string? PaymentMethod { get; set; }
        /// <summary>Null means paid in full, matching the expense rail.</summary>
        public decimal? AmountPaid { get; set; }
        public DateTime? DueDate { get; set; }
        public int? CashAccountId { get; set; }
        /// <summary>The expense category the acquisition is filed under.</summary>
        [StringLength(80)] public string? ExpenseCategory { get; set; }
        [StringLength(150)] public string? Location { get; set; }
        [StringLength(80)] public string? SerialNumber { get; set; }
        [StringLength(500)] public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
    }

    public class PoultryCapitalAssetUpdateRequest
    {
        public string? FarmId { get; set; }
        [StringLength(150)] public string? AssetName { get; set; }
        public int? AssetCategoryId { get; set; }
        [StringLength(500)] public string? Description { get; set; }
        [StringLength(150)] public string? Location { get; set; }
        [StringLength(80)] public string? SerialNumber { get; set; }
        [StringLength(500)] public string? Notes { get; set; }
        public DateTime? InServiceDate { get; set; }
        public int? UsefulLifeMonths { get; set; }
        public decimal? ResidualValue { get; set; }
        /// <summary>
        /// Whether this write means the three financial fields at all. They are
        /// LOCKED once depreciation has been posted -- changing a useful life
        /// retroactively invalidates every month already charged.
        /// </summary>
        public bool SetFinancials { get; set; }
        public string? UpdatedBy { get; set; }
    }

    public class PoultryCapitalAssetCostRequest
    {
        public string? FarmId { get; set; }
        public DateTime? CostDate { get; set; }
        [StringLength(300)] public string? Description { get; set; }
        [StringLength(80)] public string? CostCategory { get; set; }
        public decimal Amount { get; set; }
        [StringLength(200)] public string? Supplier { get; set; }
        public int? SupplierId { get; set; }
        [StringLength(30)] public string? PaymentMethod { get; set; }
        public decimal? AmountPaid { get; set; }
        public DateTime? DueDate { get; set; }
        public int? CashAccountId { get; set; }
        [StringLength(80)] public string? ExpenseCategory { get; set; }
        public string? CreatedBy { get; set; }
    }

    public class PoultryCapitalAssetDisposeRequest
    {
        public string? FarmId { get; set; }
        public DateTime? DisposalDate { get; set; }
        /// <summary>Cash in when received. Deliberately NOT revenue.</summary>
        public decimal? Proceeds { get; set; }
        public int? CashAccountId { get; set; }
        [StringLength(500)] public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
    }

    public class PoultryReversalRequest
    {
        public string? FarmId { get; set; }
        [Required] [StringLength(500)] public string Reason { get; set; } = string.Empty;
        public string? CreatedBy { get; set; }
    }

    public class PoultryDepreciationGenerateRequest
    {
        public string? FarmId { get; set; }
        /// <summary>Charge every due month up to and including this one. Defaults to today.</summary>
        public DateTime? ThroughDate { get; set; }
        /// <summary>Null runs every eligible asset.</summary>
        public int? AssetId { get; set; }
        public string? CreatedBy { get; set; }
    }

    public class PoultryDepreciationAdjustRequest
    {
        public string? FarmId { get; set; }
        public int AssetId { get; set; }
        public DateTime PeriodStart { get; set; }
        public decimal Amount { get; set; }
        [Required] [StringLength(500)] public string Reason { get; set; } = string.Empty;
        public string? CreatedBy { get; set; }
    }
}
