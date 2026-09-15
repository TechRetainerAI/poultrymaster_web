using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    /// <summary>
    /// When an inventory cost reaches Profit &amp; Loss. Migration 261.
    ///
    /// The values are the strings the database stores and checks; they are not
    /// display text and must not be localised or prettified on the way through.
    /// A C# enum was deliberately not used: every layer between here and the SP
    /// speaks strings, and an enum would only add two conversions and a way for
    /// them to disagree.
    /// </summary>
    public static class CostRecognitionMethod
    {
        /// <summary>
        /// Today's behaviour. The cost reaches the P&amp;L as the supplier is paid
        /// -- poultry raw-material recognition is cash-basis -- and later
        /// consumption never expenses it again.
        /// </summary>
        public const string ExpenseWhenPurchased = "EXPENSE_WHEN_PURCHASED";

        /// <summary>
        /// The cost is held as inventory value. Cash, supplier balance and stock
        /// behave exactly as before; the P&amp;L waits for consumption (Phase 2).
        /// </summary>
        public const string ExpenseWhenConsumed = "EXPENSE_WHEN_CONSUMED";

        /// <summary>What the item form sends for "use farm default". Never stored.</summary>
        public const string UseDefault = "USE_DEFAULT";

        public static bool IsValid(string? v)
            => v == ExpenseWhenPurchased || v == ExpenseWhenConsumed;

        /// <summary>
        /// Normalises what the item form sends into what the column stores:
        /// null and "USE_DEFAULT" both mean "no override".
        /// </summary>
        public static string? NormaliseOverride(string? v)
        {
            var s = (v ?? string.Empty).Trim();
            if (s.Length == 0 || s == UseDefault) return null;
            return s;
        }
    }

    /// <summary>Where an item's effective method came from.</summary>
    public static class CostRecognitionSource
    {
        public const string FarmDefault = "FarmDefault";
        public const string ItemOverride = "ItemOverride";
    }

    public class PoultryFinancialSettingsModel
    {
        public string FarmId { get; set; } = string.Empty;

        public string FeedCostRecognitionMethod { get; set; } = CostRecognitionMethod.ExpenseWhenPurchased;
        public string MedicationCostRecognitionMethod { get; set; } = CostRecognitionMethod.ExpenseWhenPurchased;

        /// <summary>
        /// Forward-dated activation. Null means in force now. The server refuses
        /// a past date: backdating would claim to change how past purchases were
        /// treated while their snapshots say otherwise.
        /// </summary>
        public DateTime? EffectiveFromDate { get; set; }

        /// <summary>
        /// False when no row exists yet -- the farm has never chosen. The page
        /// says so rather than presenting a default as though it were a decision.
        /// </summary>
        public bool IsConfigured { get; set; }

        public string? CreatedBy { get; set; }
        public DateTime? CreatedAt { get; set; }
        public string? UpdatedBy { get; set; }
        public DateTime? UpdatedAt { get; set; }

        /// <summary>
        /// What the settings said before this write. Populated only on the PUT
        /// response, so the audit trail can record the change without reading
        /// twice and racing itself.
        /// </summary>
        public string? PreviousFeedMethod { get; set; }
        public string? PreviousMedicationMethod { get; set; }
    }

    public class PoultryFinancialSettingsUpdateRequest
    {
        [Required] public string FarmId { get; set; } = string.Empty;

        [Required]
        [RegularExpression("^(EXPENSE_WHEN_PURCHASED|EXPENSE_WHEN_CONSUMED)$",
            ErrorMessage = "Feed cost recognition must be EXPENSE_WHEN_PURCHASED or EXPENSE_WHEN_CONSUMED.")]
        public string FeedCostRecognitionMethod { get; set; } = CostRecognitionMethod.ExpenseWhenPurchased;

        [Required]
        [RegularExpression("^(EXPENSE_WHEN_PURCHASED|EXPENSE_WHEN_CONSUMED)$",
            ErrorMessage = "Medication cost recognition must be EXPENSE_WHEN_PURCHASED or EXPENSE_WHEN_CONSUMED.")]
        public string MedicationCostRecognitionMethod { get; set; } = CostRecognitionMethod.ExpenseWhenPurchased;

        public DateTime? EffectiveFromDate { get; set; }
        public string? UpdatedBy { get; set; }
    }
}
