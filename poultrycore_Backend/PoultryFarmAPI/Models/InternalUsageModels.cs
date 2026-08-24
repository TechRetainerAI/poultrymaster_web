using System.Text.Json.Serialization;

namespace PoultryFarmAPIWeb.Models
{
    // =========================================================================
    // Internal Use (migration 212)
    //
    // Stock the company intentionally consumes rather than sells: staff welfare,
    // owner use, office refreshment, samples, donations, quality testing.
    //
    // Deliberately NOT a sale and NOT a loss. Posting reduces stock, writes an
    // append-only ledger row and books a non-cash expense; it creates no sale,
    // no customer balance, no payment and no cash transaction.
    //
    // Water ships first. Poultry and Generic clone this shape with the same
    // column and property names, so the services and pages stay clones rather
    // than cousins -- the way waterlossrecords/poultrylossrecords already relate.
    // =========================================================================

    // Constants rather than enums, matching GenericStockMovementTypes: these
    // values travel to Postgres and to the browser as plain strings, and an enum
    // would only add two conversions at every boundary.
    public static class InternalUseStatus
    {
        public const string Draft    = "Draft";
        public const string Posted   = "Posted";
        public const string Reversed = "Reversed";
    }

    public static class InternalUseCategories
    {
        public const string StaffWelfare        = "StaffWelfare";
        public const string OwnerUse            = "OwnerUse";
        public const string OfficeUse           = "OfficeUse";   // water / generic
        public const string FarmUse             = "FarmUse";     // poultry
        public const string Sample              = "Sample";
        public const string Donation            = "Donation";
        public const string QualityTest         = "QualityTest";
        public const string InternalConsumption = "InternalConsumption";
        public const string Other               = "Other";

        public static readonly string[] All =
        {
            StaffWelfare, OwnerUse, OfficeUse, FarmUse, Sample,
            Donation, QualityTest, InternalConsumption, Other,
        };

        public static bool IsValid(string? value) =>
            !string.IsNullOrWhiteSpace(value) &&
            Array.Exists(All, v => string.Equals(v, value, StringComparison.OrdinalIgnoreCase));
    }

    public class WaterInternalUsageItemModel
    {
        public int     WaterInternalUsageItemId { get; set; }
        public int     WaterProductId           { get; set; }
        public string? ProductName              { get; set; }   // read-side only

        // What the user typed, and in which unit. The conversion factor and the
        // resulting base-unit quantity are computed server-side and snapshotted,
        // so a later edit to the product's SachetsPerBag never restates history.
        public decimal  EntryQuantity     { get; set; }
        public string?  EntryUnit         { get; set; }          // 'Bag' | 'Sachet'
        public decimal  UnitsPerEntryUnit { get; set; } = 1;
        public decimal  StockQuantity     { get; set; }          // base units (sachets)

        public decimal? QuantityPerStaff  { get; set; }          // helper input, informational

        /// <summary>
        /// Cost in the unit the user chose — per bag when entering bags, per
        /// sachet when entering sachets. This is the figure they typed and the
        /// one TotalCost is computed from (migration 213). 0 = "use the average".
        /// </summary>
        public decimal  EntryUnitCost     { get; set; }

        /// <summary>Derived, per base unit (sachet). Read-side only — never sent up.</summary>
        public decimal  UnitCost          { get; set; }

        public decimal  TotalCost         { get; set; }
        public string?  ItemNotes         { get; set; }
    }

    public class WaterInternalUsageModel
    {
        public int      WaterInternalUsageId { get; set; }

        // Named exactly FarmId / UserId / CreatedBy / Id so AuditLogActionFilter
        // picks them up by reflection with no extra plumbing.
        public string   FarmId    { get; set; } = string.Empty;
        public string?  UserId    { get; set; }
        public string?  CreatedBy { get; set; }

        public DateTime UsageDate   { get; set; } = DateTime.UtcNow;
        public string?  ReferenceNo { get; set; }                // IU-2026-0001, server-assigned
        public string   Category    { get; set; } = string.Empty;
        public string?  Reason      { get; set; }
        public string?  RecipientName      { get; set; }
        public int?     ResponsibleStaffId { get; set; }

        // Staff helper input. Stored so the record can explain itself later
        // ("12 staff x 1 bag"), never used to recompute quantity at post time.
        public int?     StaffCount { get; set; }

        public string   Status         { get; set; } = InternalUseStatus.Draft;
        public decimal  TotalCostValue { get; set; }
        public string?  Notes          { get; set; }

        public string?   PostedBy       { get; set; }
        public DateTime? PostedAt       { get; set; }
        public string?   ReversedBy     { get; set; }
        public DateTime? ReversedAt     { get; set; }
        public string?   ReversalReason { get; set; }

        public DateTime  CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }

        public List<WaterInternalUsageItemModel> Items { get; set; } = new();
    }

    // ---------------------------------------------------------------- poultry
    // Same shape as the water pair, so the service and the page stay clones.
    // The conversion is crates -> eggs (fnpoultrycrateunits, migration 211) and
    // the ledger has a single signed quantity in stock units, so there is no
    // base-quantity equivalent here.
    public class PoultryInternalUsageItemModel
    {
        public int     PoultryInternalUsageItemId { get; set; }
        public int     PoultryProductId           { get; set; }
        public string? ProductName                { get; set; }   // read-side only

        public decimal  EntryQuantity     { get; set; }
        public string?  EntryUnit         { get; set; }          // 'Crate' | 'Egg' | product unit
        public decimal  UnitsPerEntryUnit { get; set; } = 1;
        public decimal  StockQuantity     { get; set; }          // eggs / birds / kg

        /// <summary>Eggs per crate for this line. Defaults to 30; ignored for non-egg products.</summary>
        public int?     EggsPerCrate      { get; set; }

        public decimal? QuantityPerStaff  { get; set; }

        /// <summary>Cost in the unit the user typed — per crate, per bird, per kg.</summary>
        public decimal  EntryUnitCost     { get; set; }
        /// <summary>Derived, per stock unit. Read-side only.</summary>
        public decimal  UnitCost          { get; set; }
        public decimal  TotalCost         { get; set; }
        public string?  ItemNotes         { get; set; }
    }

    public class PoultryInternalUsageModel
    {
        public int      PoultryInternalUsageId { get; set; }

        public string   FarmId    { get; set; } = string.Empty;
        public string?  UserId    { get; set; }
        public string?  CreatedBy { get; set; }

        public DateTime UsageDate   { get; set; } = DateTime.UtcNow;
        public string?  ReferenceNo { get; set; }
        public string   Category    { get; set; } = string.Empty;
        public string?  Reason      { get; set; }
        public string?  RecipientName      { get; set; }
        public int?     ResponsibleStaffId { get; set; }
        public int?     StaffCount { get; set; }

        public string   Status         { get; set; } = InternalUseStatus.Draft;
        public decimal  TotalCostValue { get; set; }
        public string?  Notes          { get; set; }

        public string?   PostedBy       { get; set; }
        public DateTime? PostedAt       { get; set; }
        public string?   ReversedBy     { get; set; }
        public DateTime? ReversedAt     { get; set; }
        public string?   ReversalReason { get; set; }

        public DateTime  CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }

        public List<PoultryInternalUsageItemModel> Items { get; set; } = new();
    }

    // ---------------------------------------------------------------- generic
    // Simplest of the three: genericproducts has one freetext unitofmeasure with
    // no conversion, so UnitsPerEntryUnit is always 1 and EntryUnitCost is just
    // the cost per unit. Costing is exact — genericproducts.costprice is real.
    public class GenericInternalUsageItemModel
    {
        public int     GenericInternalUsageItemId { get; set; }
        public int     GenericProductId           { get; set; }
        public string? ProductName                { get; set; }   // read-side only

        public decimal  EntryQuantity     { get; set; }
        public string?  EntryUnit         { get; set; }          // the product's unit of measure
        public decimal  UnitsPerEntryUnit { get; set; } = 1;
        public decimal  StockQuantity     { get; set; }

        public decimal? QuantityPerStaff  { get; set; }
        public decimal  EntryUnitCost     { get; set; }
        public decimal  UnitCost          { get; set; }
        public decimal  TotalCost         { get; set; }
        public string?  ItemNotes         { get; set; }
    }

    public class GenericInternalUsageModel
    {
        public int      GenericInternalUsageId { get; set; }

        public string   FarmId    { get; set; } = string.Empty;
        public string?  UserId    { get; set; }
        public string?  CreatedBy { get; set; }

        public DateTime UsageDate   { get; set; } = DateTime.UtcNow;
        public string?  ReferenceNo { get; set; }
        public string   Category    { get; set; } = string.Empty;
        public string?  Reason      { get; set; }
        public string?  RecipientName      { get; set; }
        public int?     ResponsibleStaffId { get; set; }
        public int?     StaffCount { get; set; }

        public string   Status         { get; set; } = InternalUseStatus.Draft;
        public decimal  TotalCostValue { get; set; }
        public string?  Notes          { get; set; }

        public string?   PostedBy       { get; set; }
        public DateTime? PostedAt       { get; set; }
        public string?   ReversedBy     { get; set; }
        public DateTime? ReversedAt     { get; set; }
        public string?   ReversalReason { get; set; }

        public DateTime  CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }

        public List<GenericInternalUsageItemModel> Items { get; set; } = new();
    }

    // Body for the post / reverse verbs.
    public class InternalUsageActionRequest
    {
        public string? UserId { get; set; }
        public string? Reason { get; set; }
    }

    public class SuggestedCostResponse
    {
        [JsonPropertyName("waterProductId")] public int     WaterProductId { get; set; }
        [JsonPropertyName("unitCost")]       public decimal UnitCost       { get; set; }
        [JsonPropertyName("baseUnit")]       public string? BaseUnit       { get; set; }
        [JsonPropertyName("sachetsPerBag")]  public int?    SachetsPerBag  { get; set; }
    }
}
