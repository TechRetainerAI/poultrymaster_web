using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    /// <summary>
    /// Which of water's raw-material categories a company-level setting reaches.
    /// Migration 274.
    ///
    /// Water has no Feed/Medication split, so the two configurable groups are
    /// Packaging and Treatment. Everything else is Unconfigured: it always
    /// expenses on purchase and can only be deferred item by item.
    ///
    /// These are the strings fnwatercostrecognition_categorygroup returns. They
    /// are not display text.
    /// </summary>
    public static class WaterCostRecognitionGroup
    {
        /// <summary>PackagingRoll, SachetFilm, OuterBag.</summary>
        public const string Packaging = "Packaging";

        /// <summary>Chemical. Filter and UVLamp are deliberately NOT here -- see 274.</summary>
        public const string Treatment = "Treatment";

        /// <summary>
        /// Filter, UVLamp, SparePart, Fuel, CleaningSupply, Other, and anything
        /// added later. Unreachable from the company settings by design.
        /// </summary>
        public const string Unconfigured = "Unconfigured";
    }

    /// <summary>
    /// When an inventory cost reaches Profit &amp; Loss, per water company.
    /// Migration 274.
    ///
    /// The method constants themselves are shared with the poultry side --
    /// <see cref="CostRecognitionMethod"/> -- because the two values mean exactly
    /// the same thing in both modules and the database checks the same strings.
    /// Only the two GROUPS differ, which is why this file declares those and
    /// nothing else.
    /// </summary>
    public class WaterFinancialSettingsModel
    {
        public string FarmId { get; set; } = string.Empty;

        public string PackagingCostRecognitionMethod { get; set; } = CostRecognitionMethod.ExpenseWhenPurchased;
        public string TreatmentCostRecognitionMethod { get; set; } = CostRecognitionMethod.ExpenseWhenPurchased;

        /// <summary>
        /// Forward-dated activation. Null means in force now. The server refuses
        /// a past date: backdating would claim to change how past purchases were
        /// treated while their snapshots say otherwise.
        /// </summary>
        public DateTime? EffectiveFromDate { get; set; }

        /// <summary>
        /// False when no row exists yet -- the company has never chosen. The page
        /// says so rather than presenting a default as though it were a decision.
        /// </summary>
        public bool IsConfigured { get; set; }

        /// <summary>
        /// Whether EXPENSE_WHEN_CONSUMED can be chosen at all.
        ///
        /// False until the phase-2 chain (migrations 275 and 277-281) is applied.
        /// While it is false the server REFUSES the deferred method, because
        /// stamping purchases as deferred while they are still expensed at
        /// purchase would charge the same cost to Profit &amp; Loss twice once
        /// consumption recognition lands. The settings page reads this to
        /// explain why the option is unavailable rather than offering it and
        /// letting the save fail.
        /// </summary>
        public bool DeferralAvailable { get; set; }

        public string? CreatedBy { get; set; }
        public DateTime? CreatedAt { get; set; }
        public string? UpdatedBy { get; set; }
        public DateTime? UpdatedAt { get; set; }

        /// <summary>
        /// What the settings said before this write. Populated only on the PUT
        /// response, so the audit trail can record the change without reading
        /// twice and racing itself.
        /// </summary>
        public string? PreviousPackagingMethod { get; set; }
        public string? PreviousTreatmentMethod { get; set; }
    }

    public class WaterFinancialSettingsUpdateRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;

        [Required]
        [RegularExpression("^(EXPENSE_WHEN_PURCHASED|EXPENSE_WHEN_CONSUMED)$",
            ErrorMessage = "Packaging cost recognition must be EXPENSE_WHEN_PURCHASED or EXPENSE_WHEN_CONSUMED.")]
        public string PackagingCostRecognitionMethod { get; set; } = CostRecognitionMethod.ExpenseWhenPurchased;

        [Required]
        [RegularExpression("^(EXPENSE_WHEN_PURCHASED|EXPENSE_WHEN_CONSUMED)$",
            ErrorMessage = "Treatment cost recognition must be EXPENSE_WHEN_PURCHASED or EXPENSE_WHEN_CONSUMED.")]
        public string TreatmentCostRecognitionMethod { get; set; } = CostRecognitionMethod.ExpenseWhenPurchased;

        public DateTime? EffectiveFromDate { get; set; }
        public string? UpdatedBy { get; set; }
    }

    /// <summary>
    /// One raw-material item and how its cost is treated, resolved server-side.
    ///
    /// A SEPARATE read from the item list, not extra columns on it. 274 does not
    /// rewrite spwaterrawmaterialitem_getall -- its live Postgres body is not in
    /// the repo to copy from -- so the resolved view is its own SP and its own
    /// model. The settings page joins the two by id.
    /// </summary>
    public class WaterItemCostRecognitionModel
    {
        public int WaterRawMaterialItemId { get; set; }
        public string? ItemName { get; set; }
        public string? Category { get; set; }
        public bool IsActive { get; set; }

        /// <summary>Null means "follow the company default for this category group".</summary>
        public string? CostRecognitionOverride { get; set; }

        /// <summary>What actually applies: the override if there is one, else the company default.</summary>
        public string EffectiveCostRecognitionMethod { get; set; } = CostRecognitionMethod.ExpenseWhenPurchased;

        /// <summary>ItemOverride | FarmDefault.</summary>
        public string CostRecognitionSource { get; set; } = Models.CostRecognitionSource.FarmDefault;

        /// <summary>Packaging | Treatment | Unconfigured.</summary>
        public string CostRecognitionCategoryGroup { get; set; } = WaterCostRecognitionGroup.Unconfigured;

        /// <summary>
        /// What the company default would have said, so the form can show "you
        /// are overriding X" without a second round trip.
        /// </summary>
        public string? FarmDefaultMethod { get; set; }
    }

    public class WaterItemCostRecognitionUpdateRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;

        /// <summary>
        /// Null or "USE_DEFAULT" clears the override. Anything else must be one
        /// of the two methods; the SP refuses the rest.
        /// </summary>
        [RegularExpression("^(EXPENSE_WHEN_PURCHASED|EXPENSE_WHEN_CONSUMED|USE_DEFAULT)$",
            ErrorMessage = "Override must be EXPENSE_WHEN_PURCHASED, EXPENSE_WHEN_CONSUMED or USE_DEFAULT.")]
        public string? CostRecognitionOverride { get; set; }

        public string? UpdatedBy { get; set; }
    }
}
