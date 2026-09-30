// The pure calculation core of platform billing: tier qualification, price
// resolution, discounts, rounding. No database, no provider, no clock — every
// rule here is a function of its arguments, which is what makes the engine's
// behaviour testable and the invoices explainable months later.

namespace PoultryFarmAPIWeb.Business
{
    public sealed record TierRule(string ProfileCode, string TierCode, decimal MinValue, decimal? MaxValue);
    public sealed record PriceEntry(long Id, string TierCode, string? ProfileCode, string CurrencyCode,
        decimal MonthlyPrice, decimal? AnnualPrice, bool TaxInclusive);
    public sealed record DiscountRule(int MinCompanies, decimal Percent);

    public static class PlatformBillingRules
    {
        /// <summary>
        /// Which tier a metric value qualifies for under a profile's rules.
        /// Rules are [min, max] inclusive; max NULL means unbounded. When
        /// bands overlap the highest-ranked match wins deterministically by
        /// taking the rule with the greatest min — a misconfigured overlap
        /// must never make the answer depend on row order.
        /// </summary>
        public static string? QualifyTier(IEnumerable<TierRule> rules, string profileCode, decimal metricValue)
        {
            TierRule? best = null;
            foreach (var r in rules)
            {
                if (!string.Equals(r.ProfileCode, profileCode, StringComparison.OrdinalIgnoreCase)) continue;
                if (metricValue < r.MinValue) continue;
                if (r.MaxValue.HasValue && metricValue > r.MaxValue.Value) continue;
                if (best is null || r.MinValue > best.MinValue) best = r;
            }
            return best?.TierCode;
        }

        /// <summary>
        /// The price for a tier in a price book. A profile-specific entry
        /// beats a profile-NULL (any-profile) entry; no entry at all means
        /// PricingNotConfigured — never zero, never a guess (spec Part 39).
        /// </summary>
        public static PriceEntry? ResolvePrice(IEnumerable<PriceEntry> entries, string tierCode, string profileCode)
        {
            PriceEntry? generic = null;
            foreach (var e in entries)
            {
                if (!string.Equals(e.TierCode, tierCode, StringComparison.OrdinalIgnoreCase)) continue;
                if (string.Equals(e.ProfileCode, profileCode, StringComparison.OrdinalIgnoreCase)) return e;
                if (e.ProfileCode is null) generic ??= e;
            }
            return generic;
        }

        /// <summary>
        /// The discount for a number of eligible companies: the active rule
        /// with the highest MinCompanies that the count reaches. No rule →
        /// 0%. Percentages live in data, never in this file (spec Part 8).
        /// </summary>
        public static DiscountRule? PickDiscount(IEnumerable<DiscountRule> rules, int eligibleCompanies)
        {
            DiscountRule? best = null;
            foreach (var r in rules)
            {
                if (eligibleCompanies < r.MinCompanies) continue;
                if (best is null || r.MinCompanies > best.MinCompanies) best = r;
            }
            return best;
        }

        /// <summary>
        /// CompanyFamily/Template → Billing Profile (spec 2.4/2.5). A per-
        /// company override wins; otherwise the family maps to its profile,
        /// and EVERY Generic template — School, Gym, Pharmacy, ones that do
        /// not exist yet — resolves to GENERIC_STANDARD with no code change
        /// (spec Parts 18/43).
        /// </summary>
        public static string ResolveProfileCode(string family, string? stateOverride) =>
            stateOverride ?? family.Trim().ToLowerInvariant() switch
            {
                "poultry" => "POULTRY_BIRDS",
                "water" => "WATER_STANDARD",
                "hotel" => "HOTEL_ROOMS",
                "restaurant" => "RESTAURANT_LOCATIONS",
                _ => "GENERIC_STANDARD",
            };

        /// <summary>Central money rounding: 2dp, away from zero (spec Part 53).</summary>
        public static decimal Money(decimal value) =>
            Math.Round(value, 2, MidpointRounding.AwayFromZero);

        /// <summary>
        /// Invoice arithmetic in one place so subtotal → discount → tax →
        /// total is the same everywhere it is shown. Tax applies after the
        /// discount; all figures are in the one account currency.
        /// </summary>
        public static (decimal Subtotal, decimal DiscountAmount, decimal TaxAmount, decimal Total)
            Totals(IEnumerable<decimal> lineAmounts, decimal discountPercent, decimal taxRatePercent)
        {
            var subtotal = Money(lineAmounts.Sum());
            var discount = Money(subtotal * discountPercent / 100m);
            var taxable = subtotal - discount;
            var tax = Money(taxable * taxRatePercent / 100m);
            return (subtotal, discount, tax, Money(taxable + tax));
        }

        /// <summary>Deterministic invoice identity for an account's period (spec Part 33).</summary>
        public static string InvoiceNumber(long accountId, DateTime periodStart) =>
            $"VC-{accountId}-{periodStart:yyyyMM}";

        /// <summary>
        /// Paystack minor units. GHS/NGN/USD are all 2-decimal; the check
        /// exists so a future zero-decimal market cannot be charged 100x.
        /// </summary>
        public static long ToMinorUnits(decimal major, string currency)
        {
            var zeroDecimal = currency.ToUpperInvariant() is "BIF" or "CLP" or "DJF" or "GNF" or "JPY"
                or "KMF" or "KRW" or "MGA" or "PYG" or "RWF" or "UGX" or "VND" or "VUV" or "XAF" or "XOF" or "XPF";
            return zeroDecimal
                ? (long)Math.Round(major, MidpointRounding.AwayFromZero)
                : (long)Math.Round(major * 100m, MidpointRounding.AwayFromZero);
        }
    }
}
