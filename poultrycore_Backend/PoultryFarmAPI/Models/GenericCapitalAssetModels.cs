// Generic capital assets and depreciation (migration 453), ported from Water's
// asset register so the Generic page reads like Poultry's and Water's.
//
// Every derived number (acquisition cost, additional cost, total capitalised
// cost, accumulated depreciation, book value) is computed by the database;
// writing them has no effect. OriginalCost is an alias of the TOTAL.
// GenericExpenseId on a cost row is always null: on Generic the cost line is
// itself the document (cash out + supplier payable), not an expense row.

using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    public class GenericAssetCategoryModel
    {
        public int GenericAssetCategoryId { get; set; }
        public string? FarmId { get; set; }
        [Required] [StringLength(80)] public string CategoryName { get; set; } = string.Empty;
        /// <summary>A suggestion the form fills in, never a rule.</summary>
        public int? DefaultUsefulLifeMonths { get; set; }
        public int SortOrder { get; set; }
        public bool IsActive { get; set; } = true;
        /// <summary>Read-only.</summary>
        public int AssetCount { get; set; }
    }

    public class GenericCapitalAssetModel
    {
        public int GenericCapitalAssetId { get; set; }
        public string? FarmId { get; set; }
        /// <summary>Read-only: the per-company running number, AST-0001.</summary>
        public string? AssetNumber { get; set; }
        [Required] [StringLength(150)] public string AssetName { get; set; } = string.Empty;
        public int? GenericAssetCategoryId { get; set; }
        public string? CategoryName { get; set; }
        [StringLength(500)] public string? Description { get; set; }

        public DateTime AcquisitionDate { get; set; }
        /// <summary>
        /// When the asset started earning. Depreciation runs from the month
        /// containing this date, not from acquisition: a borehole finished in
        /// March and commissioned in June has not been earning since March.
        /// </summary>
        public DateTime? InServiceDate { get; set; }

        [StringLength(150)] public string? Location { get; set; }
        [StringLength(80)] public string? SerialNumber { get; set; }
        public int? SupplierId { get; set; }
        public string? SupplierName { get; set; }
        public string Status { get; set; } = CapitalAssetStatus.Draft;
        [StringLength(500)] public string? Notes { get; set; }

        // ---- financial ------------------------------------------------------

        /// <summary>
        /// Read-only: the TOTAL capitalised cost. Kept under 283's name for
        /// callers written against it -- new code should read
        /// <see cref="TotalCapitalizedCost"/>, which says what it is.
        /// </summary>
        public decimal OriginalCost { get; set; }

        /// <summary>
        /// Read-only: what the asset was originally acquired for, including
        /// any correction to that figure. Zero for one that was BUILT cost by
        /// cost and never had a single acquisition.
        /// </summary>
        public decimal AcquisitionCost { get; set; }
        /// <summary>Read-only: everything capitalised into it since.</summary>
        public decimal AdditionalCost { get; set; }
        /// <summary>
        /// Read-only: AcquisitionCost + AdditionalCost. The same number as
        /// <see cref="OriginalCost"/> and the one screens are meant to print.
        /// </summary>
        public decimal TotalCapitalizedCost { get; set; }

        /// <summary>What the company expects the asset to still be worth at the end.</summary>
        public decimal ResidualValue { get; set; }
        /// <summary>Read-only: TotalCapitalizedCost - ResidualValue, never below zero.</summary>
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

        public List<GenericCapitalAssetCostModel> Costs { get; set; } = new();
        public List<GenericAssetDepreciationModel> Depreciation { get; set; } = new();
    }

    /// <summary>
    /// One capitalised amount. An asset that is BUILT rather than bought has
    /// several: drilling, pump, casing, wiring. GenericExpenseId links to the
    /// genericexpenses row that actually moved the money or opened the payable.
    /// </summary>
    public class GenericCapitalAssetCostModel
    {
        public int GenericCapitalAssetCostId { get; set; }
        public int GenericCapitalAssetId { get; set; }
        public DateTime CostDate { get; set; }
        [StringLength(300)] public string? Description { get; set; }
        [StringLength(80)] public string? CostCategory { get; set; }
        /// <summary>
        /// SIGNED. Positive for every cost; negative only on an
        /// OriginalCostCorrection that reduced what was recorded.
        /// </summary>
        public decimal Amount { get; set; }
        /// <summary>
        /// Acquisition | AdditionalCost | OriginalCostCorrection (314).
        /// Acquisition and OriginalCostCorrection together are the original
        /// acquisition cost; everything else is an additional capitalised cost.
        /// </summary>
        public string? SourceType { get; set; }
        public int? GenericExpenseId { get; set; }
        public int? SupplierId { get; set; }
        public string? SupplierName { get; set; }
        /// <summary>Read-only, from the linked expense.</summary>
        public string? PaymentStatus { get; set; }
        public decimal? AmountPaid { get; set; }
        public decimal? Balance { get; set; }
        /// <summary>Read-only, from the linked expense.</summary>
        public string? PaymentMethod { get; set; }
        /// <summary>When the unpaid part falls due, from the linked expense.</summary>
        public DateTime? DueDate { get; set; }
        /// <summary>Which cash account the money left, from the linked expense.</summary>
        public string? CashAccountName { get; set; }
        /// <summary>
        /// What the linked expense says the document is now for. A
        /// correction shares the acquisition's expense, so this is the CORRECTED
        /// figure, not this row's own signed amount.
        /// </summary>
        public decimal? ExpenseAmount { get; set; }
        /// <summary>The expense category the document was filed under.</summary>
        public string? ExpenseCategory { get; set; }
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
    public class GenericAssetDepreciationModel
    {
        public int GenericAssetDepreciationId { get; set; }
        public int GenericCapitalAssetId { get; set; }
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
        /// <summary>The non-cash genericexpenses row this charge wrote.</summary>
        public int? GenericExpenseId { get; set; }
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
    public class GenericCapitalAssetSummaryModel
    {
        public int TotalAssets { get; set; }
        public int ActiveAssets { get; set; }
        public int DraftAssets { get; set; }
        public int DisposedAssets { get; set; }
        public int FullyDepreciated { get; set; }
        public decimal TotalAssetCost { get; set; }
        public decimal AccumulatedDepreciation { get; set; }
        /// <summary>
        /// A BALANCE, never a period total: what the company owns today. Only
        /// AddedInPeriod is scoped to the selected dates.
        /// </summary>
        public decimal CurrentBookValue { get; set; }
        public decimal AddedInPeriod { get; set; }
        public int AddedCount { get; set; }
    }

    /// <summary>What "Generate due depreciation" would do, before it does it.</summary>
    public class GenericAssetDepreciationDueModel
    {
        public int GenericCapitalAssetId { get; set; }
        public string? AssetNumber { get; set; }
        public string? AssetName { get; set; }
        public int MonthsDue { get; set; }
        public decimal AmountDue { get; set; }
        public decimal? MonthlyDepreciation { get; set; }
        public DateTime? NextPeriod { get; set; }
    }

    public class GenericAssetDepreciationRunResult
    {
        public int AssetsProcessed { get; set; }
        public int EntriesCreated { get; set; }
        public decimal TotalAmount { get; set; }
    }

    // ---- requests -----------------------------------------------------------

    public class GenericCapitalAssetCreateRequest
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
        /// <summary>
        /// A genericsuppliers id. Unlike the poultry request there is no free-text
        /// supplier alongside it: 283 reads the name off the supplier row, so a
        /// second hand-typed name could only contradict it.
        /// </summary>
        public int? SupplierId { get; set; }
        [StringLength(30)] public string? PaymentMethod { get; set; }
        /// <summary>
        /// Null means paid in full, EXCEPT on a Credit purchase where it means
        /// nothing has been paid -- the rule 047 gave every other generic bill.
        /// </summary>
        public decimal? AmountPaid { get; set; }
        public DateTime? DueDate { get; set; }
        public int? CashAccountId { get; set; }
        /// <summary>The generic expense category the acquisition is filed under.</summary>
        [StringLength(80)] public string? ExpenseCategory { get; set; }
        [StringLength(150)] public string? Location { get; set; }
        [StringLength(80)] public string? SerialNumber { get; set; }
        [StringLength(500)] public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
    }

    public class GenericCapitalAssetUpdateRequest
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

    public class GenericCapitalAssetCostRequest
    {
        public string? FarmId { get; set; }
        public DateTime? CostDate { get; set; }
        [StringLength(300)] public string? Description { get; set; }
        [StringLength(80)] public string? CostCategory { get; set; }
        public decimal Amount { get; set; }
        public int? SupplierId { get; set; }
        [StringLength(30)] public string? PaymentMethod { get; set; }
        public decimal? AmountPaid { get; set; }
        public DateTime? DueDate { get; set; }
        public int? CashAccountId { get; set; }
        [StringLength(80)] public string? ExpenseCategory { get; set; }
        public string? CreatedBy { get; set; }
    }

    /// <summary>
    /// Correcting a data-entry mistake in the original acquisition cost.
    ///
    /// Deliberately NOT an editable field on the update request: this is a
    /// financial event with a date, an author and a reason, and it moves cash
    /// and the supplier balance. A Reason is required whether or not anything
    /// downstream exists yet -- an unexplained 117,000 swing is not an audit
    /// trail.
    /// </summary>
    public class GenericCapitalAssetCorrectCostRequest
    {
        public string? FarmId { get; set; }
        /// <summary>What the original acquisition SHOULD have been recorded as.</summary>
        public decimal NewAmount { get; set; }
        /// <summary>The date the correction takes effect. Defaults to today.</summary>
        public DateTime? EffectiveDate { get; set; }
        [Required] [StringLength(500)] public string Reason { get; set; } = string.Empty;
        public string? CreatedBy { get; set; }
    }

    public class GenericCapitalAssetDisposeRequest
    {
        public string? FarmId { get; set; }
        public DateTime? DisposalDate { get; set; }
        /// <summary>Cash in when received. Deliberately NOT revenue.</summary>
        public decimal? Proceeds { get; set; }
        public int? CashAccountId { get; set; }
        [StringLength(500)] public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
    }

    public class GenericReversalRequest
    {
        public string? FarmId { get; set; }
        [Required] [StringLength(500)] public string Reason { get; set; } = string.Empty;
        public string? CreatedBy { get; set; }
    }

    public class GenericDepreciationGenerateRequest
    {
        public string? FarmId { get; set; }
        /// <summary>Charge every due month up to and including this one. Defaults to today.</summary>
        public DateTime? ThroughDate { get; set; }
        /// <summary>Null runs every eligible asset.</summary>
        public int? AssetId { get; set; }
        public string? CreatedBy { get; set; }
    }

    public class GenericDepreciationAdjustRequest
    {
        public string? FarmId { get; set; }
        public int AssetId { get; set; }
        public DateTime PeriodStart { get; set; }
        public decimal Amount { get; set; }
        [Required] [StringLength(500)] public string Reason { get; set; } = string.Empty;
        public string? CreatedBy { get; set; }
    }
}
