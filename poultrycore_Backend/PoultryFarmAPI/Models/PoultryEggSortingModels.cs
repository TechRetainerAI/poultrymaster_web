// Egg Sorting Workspace (migrations 341-343): egg classes (Unsorted + sizes)
// in the one stock ledger, sorting sessions that turn Unsorted into sizes, and
// the readers the workspace, Egg Tracker, sales and reports use.

namespace PoultryFarmAPIWeb.Models
{
    public class EggSortingSettings
    {
        public string FarmId { get; set; } = string.Empty;
        public bool EnableEggSorting { get; set; }
        /// <summary>Off | Warning | Blocking -- what Daily Closing does with unsorted eggs.</summary>
        public string ClosingPolicy { get; set; } = "Warning";
        public bool IsCustomised { get; set; }
        public string? UpdatedBy { get; set; }
        public DateTime? UpdatedAtUtc { get; set; }
        /// <summary>Eggs in one crate for this farm (344; default 30).</summary>
        public int EggsPerCrate { get; set; } = 30;
        /// <summary>Default selling price per crate of Unsorted / General eggs (344).</summary>
        public decimal? UnsortedPricePerCrate { get; set; }
    }

    public class EggSortingSettingsRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public bool EnableEggSorting { get; set; }
        public string ClosingPolicy { get; set; } = "Warning";
        public int EggsPerCrate { get; set; } = 30;
        public decimal? UnsortedPricePerCrate { get; set; }
    }

    /// <summary>
    /// 393: egg packaging -- Boxes of N crates. A box is a quantity unit only;
    /// stock stays in individual eggs. Not a poultry Batch.
    /// </summary>
    public class EggPackagingSettings
    {
        public string FarmId { get; set; } = string.Empty;
        public int EggsPerCrate { get; set; } = 30;
        public bool EnableBoxes { get; set; }
        /// <summary>In force: null when boxes are off.</summary>
        public int? CratesPerBox { get; set; }
        /// <summary>CratesPerBox x EggsPerCrate; null when boxes are off.</summary>
        public int? EggsPerBox { get; set; }
        /// <summary>BoxesCratesPieces | CratesPieces | Pieces (in force).</summary>
        public string EggDisplay { get; set; } = "CratesPieces";
        /// <summary>Boxes | Crates -- which field Add Sale puts first (in force).</summary>
        public string SaleEntryUnit { get; set; } = "Crates";
        /// <summary>Bumps whenever the conversion changes.</summary>
        public int PackagingVersion { get; set; } = 1;
        /// <summary>What the settings screen edits (kept while boxes are off).</summary>
        public int? StoredCratesPerBox { get; set; }
        public string StoredDisplay { get; set; } = "CratesPieces";
        public string StoredEntryUnit { get; set; } = "Crates";
    }

    public class EggPackagingRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public bool EnableBoxes { get; set; }
        public int? CratesPerBox { get; set; }
        public string EggDisplay { get; set; } = "CratesPieces";
        public string SaleEntryUnit { get; set; } = "Crates";
    }

    /// <summary>One egg class: Unsorted (EggSizeId null) or a size.</summary>
    public class EggClass
    {
        public int PoultryProductId { get; set; }
        public int? EggSizeId { get; set; }
        public string Name { get; set; } = string.Empty;
        /// <summary>Unsorted | Size</summary>
        public string ClassKind { get; set; } = "Unsorted";
        public int SortOrder { get; set; }
        public bool IsActive { get; set; }
        /// <summary>Eggs on hand (the ledger sum).</summary>
        public decimal OnHand { get; set; }
        /// <summary>Default selling price per crate (344); null = none set.</summary>
        public decimal? PricePerCrate { get; set; }
        /// <summary>394: price per box; null = crates per box x the crate price.</summary>
        public decimal? PricePerBox { get; set; }
        /// <summary>394: price per egg; null = the crate price shared over the crate.</summary>
        public decimal? PricePerPiece { get; set; }
    }

    public class EggSizePriceRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public decimal? PricePerCrate { get; set; }
    }

    /// <summary>394: one egg class's crate, box and piece prices (null = not set).</summary>
    public class EggClassPricesRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public decimal? PricePerCrate { get; set; }
        public decimal? PricePerBox { get; set; }
        public decimal? PricePerPiece { get; set; }
    }

    /// <summary>Breakage / loss (eggs out) or a stock-take / correction (signed) against one egg class.</summary>
    public class EggClassAdjustRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public int PoultryProductId { get; set; }
        /// <summary>Breakage | Loss | Stocktake | Correction</summary>
        public string Kind { get; set; } = "Breakage";
        public int Quantity { get; set; }
        public string Reason { get; set; } = string.Empty;
    }

    public class EggSortingAuditRow
    {
        public long AuditId { get; set; }
        /// <summary>Sorting | EggSize | Settings | Sale | Adjustment</summary>
        public string Entity { get; set; } = string.Empty;
        public int? EntityId { get; set; }
        public string Action { get; set; } = string.Empty;
        public string? Actor { get; set; }
        /// <summary>JSON object; shape depends on the action.</summary>
        public string? Details { get; set; }
        public DateTime AtUtc { get; set; }
    }

    public class EggSizeSaveRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public int? EggSizeId { get; set; }
        public string Name { get; set; } = string.Empty;
        public int? SortOrder { get; set; }
        public bool IsActive { get; set; } = true;
    }

    /// <summary>One pick of one production record, with what is left to sort.</summary>
    public class EggSortingPick
    {
        public int ProductionRecordId { get; set; }
        public int FlockId { get; set; }
        public string? FlockName { get; set; }
        public string? BatchName { get; set; }
        public string? HouseName { get; set; }
        public DateTime ProductionDate { get; set; }
        public int PickNumber { get; set; }
        public int PickGross { get; set; }
        public int PickSorted { get; set; }
        public int PickLeft { get; set; }
        /// <summary>LEAST(pick left, record left): what a by-pick sorting may take now.</summary>
        public int Available { get; set; }
        public int RecordGross { get; set; }
        /// <summary>Broken + meaty + soft + lost recorded on the day (not attributed to a pick).</summary>
        public int RecordCollectionLoss { get; set; }
        public int RecordSaleable { get; set; }
        public int RecordSorted { get; set; }
        public int RecordLeft { get; set; }
        /// <summary>Sorted from this pick by by-pick sessions only (pick composition is valid for these).</summary>
        public int ByPickSorted { get; set; }
    }

    public class EggSortingSummary
    {
        public DateTime BusinessDate { get; set; }
        public decimal UnsortedOnHand { get; set; }
        public decimal SizedOnHand { get; set; }
        public int SortedToday { get; set; }
        public int SizedCreatedToday { get; set; }
        public int LossToday { get; set; }
        public int SessionsToday { get; set; }
        /// <summary>Saleable production not yet sorted (all dates up to the business date).</summary>
        public int ProductionLeft { get; set; }
        public int RecordsWithLeft { get; set; }
        public DateTime? OldestLeftDate { get; set; }
    }

    public class EggSortingLine
    {
        public int? LineId { get; set; }
        /// <summary>SizedOutput | Reject | Breakage | OtherLoss</summary>
        public string LineType { get; set; } = "SizedOutput";
        public int? EggSizeId { get; set; }
        public string? SizeName { get; set; }
        public int Quantity { get; set; }
        public string? Notes { get; set; }
    }

    public class EggSortingSource
    {
        public int ProductionRecordId { get; set; }
        public int PickNumber { get; set; }
        public DateTime ProductionDate { get; set; }
        public int Quantity { get; set; }
    }

    public class EggSortingSession
    {
        public int SessionId { get; set; }
        public string SessionNo { get; set; } = string.Empty;
        /// <summary>ByPick | Combined</summary>
        public string SortingMode { get; set; } = "ByPick";
        public int FlockId { get; set; }
        public string? FlockName { get; set; }
        public int? ProductionRecordId { get; set; }
        public int? PickNumber { get; set; }
        public int[] ScopeRecordIds { get; set; } = Array.Empty<int>();
        public DateTime SortingDate { get; set; }
        /// <summary>Draft | Posted | Reversed</summary>
        public string Status { get; set; } = "Draft";
        public int InputQuantity { get; set; }
        public int OutputQuantity { get; set; }
        public int LossQuantity { get; set; }
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime CreatedAtUtc { get; set; }
        public string? PostedBy { get; set; }
        public DateTime? PostedAtUtc { get; set; }
        public string? ReversedBy { get; set; }
        public DateTime? ReversedAtUtc { get; set; }
        public string? ReversalReason { get; set; }
        public DateTime? FirstProductionDate { get; set; }
        public DateTime? LastProductionDate { get; set; }
        public List<EggSortingLine> Lines { get; set; } = new();
        public List<EggSortingSource> Sources { get; set; } = new();
    }

    public class EggSortingSaveRequest
    {
        public string FarmId { get; set; } = string.Empty;
        /// <summary>ByPick | Combined</summary>
        public string SortingMode { get; set; } = "ByPick";
        public DateTime SortingDate { get; set; }
        /// <summary>ByPick: the one record. Combined: the flock's records to draw from (FIFO).</summary>
        public int[] ProductionRecordIds { get; set; } = Array.Empty<int>();
        public int? PickNumber { get; set; }
        public List<EggSortingLine> Lines { get; set; } = new();
        public string? Notes { get; set; }
        /// <summary>Set by the page once per dialog: a retried create returns the first session.</summary>
        public Guid? ClientRequestId { get; set; }
        /// <summary>true = post in the same transaction (the "Post sorting" button).</summary>
        public bool Post { get; set; }
    }

    public class EggSortingReverseRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public string Reason { get; set; } = string.Empty;
    }

    public class EggCompositionRow
    {
        public string GroupKey { get; set; } = string.Empty;
        public string GroupLabel { get; set; } = string.Empty;
        public string GroupSort { get; set; } = string.Empty;
        /// <summary>The flock the row belongs to (migration 350); null before it.</summary>
        public int? FlockId { get; set; }
        public string? FlockName { get; set; }
        public string LineType { get; set; } = string.Empty;
        public int? EggSizeId { get; set; }
        public string? SizeName { get; set; }
        public int SizeSort { get; set; }
        public decimal Quantity { get; set; }
        public int Sessions { get; set; }
        public int CombinedSessions { get; set; }
    }

    public class EggCarryoverRow
    {
        public DateTime ProductionDate { get; set; }
        /// <summary>The flock the row belongs to (migration 350); null before it.</summary>
        public int? FlockId { get; set; }
        public string? FlockName { get; set; }
        public int Records { get; set; }
        public long Gross { get; set; }
        public long CollectionLoss { get; set; }
        public long Saleable { get; set; }
        public long Sorted { get; set; }
        public long LeftUnsorted { get; set; }
    }

    public class EggLedgerRow
    {
        public int TransactionId { get; set; }
        public DateTime CreatedAtUtc { get; set; }
        public DateTime BusinessDate { get; set; }
        public string TxnType { get; set; } = string.Empty;
        public int PoultryProductId { get; set; }
        public string ClassName { get; set; } = string.Empty;
        public string ClassKind { get; set; } = string.Empty;
        public decimal QuantityIn { get; set; }
        public decimal QuantityOut { get; set; }
        public decimal RunningBalance { get; set; }
        public int? RelatedId { get; set; }
        public string? Note { get; set; }
        public string? CreatedBy { get; set; }
        public int? FlockId { get; set; }
        public string? FlockName { get; set; }
        public int? ProductionRecordId { get; set; }
        public string? PickNumbers { get; set; }
        public string? SortingSessionNo { get; set; }
        public int? SaleId { get; set; }
        public string? CustomerName { get; set; }
        public string? SaleGroupNo { get; set; }
        public string? Reference { get; set; }
    }

    public class ProductionDuplicateGroup
    {
        public int FlockId { get; set; }
        public string? FlockName { get; set; }
        public DateTime ProductionDate { get; set; }
        public int RecordCount { get; set; }
        public int[] RecordIds { get; set; } = Array.Empty<int>();
        public long TotalEggs { get; set; }
        public string? Grades { get; set; }
    }

    /// <summary>One sale entry with several egg classes (or products), posted as rows sharing a sale number.</summary>
    public class SaleGroupRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public string UserId { get; set; } = string.Empty;
        public DateTime SaleDate { get; set; }
        public string? CustomerName { get; set; }
        public int? CustomerId { get; set; }
        public string? PaymentMethod { get; set; }
        public int? PoultryCashAccountId { get; set; }
        public bool Paid { get; set; }
        public string? SaleDescription { get; set; }
        public int? FlockId { get; set; }
        /// <summary>366: optional batch attribution; the database checks the flock belongs to it.</summary>
        public int? BatchId { get; set; }
        /// <summary>351: the reversed sale this one corrects, if it is a Correct Sale re-entry.</summary>
        public int? CorrectsSaleId { get; set; }
        /// <summary>
        /// 358: one id per Add Sale form. A retry or double-click with the same
        /// key returns the sale already posted instead of posting a second.
        /// </summary>
        public string? RequestKey { get; set; }
        /// <summary>
        /// Part payment: with Paid = false, the amount the customer paid at the
        /// counter. Recorded as ONE customer payment in the same transaction as
        /// the sale; the rest stays owed. Needs a customer (a walk-in cannot owe).
        /// </summary>
        public decimal? AmountPaidNow { get; set; }
        /// <summary>
        /// Pay with customer credit (351): with Paid = false, how much of the
        /// customer's held credit settles this sale. Allocation only -- no new
        /// payment, no cash. Applied after any part payment, in the same
        /// transaction, so the sale never lands with half its credit.
        /// </summary>
        public decimal? CustomerCreditAmount { get; set; }
        public List<SaleGroupLine> Lines { get; set; } = new();
    }

    public class SaleGroupLine
    {
        public string Product { get; set; } = "Fresh Eggs";
        /// <summary>Egg class product; null = Unsorted / General.</summary>
        public int? EggProductId { get; set; }
        /// <summary>In eggs (pieces) for egg lines.</summary>
        public decimal Quantity { get; set; }
        /// <summary>Per crate for egg lines.</summary>
        public decimal UnitPrice { get; set; }
        public decimal TotalAmount { get; set; }

        // 394: an egg line entered as Boxes / Crates / Pieces. Any of the three
        // set = the database converts them with the company's packaging and
        // keeps the conversion on the line. All null = the old crates + loose path.
        public int? Boxes { get; set; }
        public int? Crates { get; set; }
        public int? Pieces { get; set; }
        /// <summary>Null = crates per box x the crate price.</summary>
        public decimal? PricePerBox { get; set; }
        /// <summary>Null = the crate price shared over the crate.</summary>
        public decimal? PricePerPiece { get; set; }
        /// <summary>True when Add Sale's total override set this line's amount.</summary>
        public bool? AmountOverridden { get; set; }

        // 401: a bird line. "PerBird" or "PerKg"; Quantity stays the bird
        // count. Per kg, the database checks the amount and sets the per-bird
        // price from LiveWeightKg x PricePerKg.
        public string? PricingBasis { get; set; }
        public decimal? LiveWeightKg { get; set; }
        public decimal? PricePerKg { get; set; }
    }

    public class SaleGroupResult
    {
        public string SaleGroupNo { get; set; } = string.Empty;
        /// <summary>358: the ONE sale created, whatever the number of lines.</summary>
        public int SaleId { get; set; }
        /// <summary>Kept for older callers; since 358 always exactly [SaleId].</summary>
        public int[] SaleIds { get; set; } = Array.Empty<int>();
        public decimal TotalAmount { get; set; }
        public int LineCount { get; set; }
        /// <summary>360: sales created; above 1 when different products were split.</summary>
        public int SaleCount { get; set; } = 1;
        /// <summary>True when the request key matched a sale already posted.</summary>
        public bool Duplicate { get; set; }
    }
}
