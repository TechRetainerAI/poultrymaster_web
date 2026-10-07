// The pure calculation core of platform billing: tier qualification, price
// resolution, discounts, rounding. No database, no provider, no clock — every
// rule here is a function of its arguments, which is what makes the engine's
// behaviour testable and the invoices explainable months later.

namespace PoultryFarmAPIWeb.Business
{
    public sealed record TierRule(string ProfileCode, string TierCode, decimal MinValue, decimal? MaxValue);
    public sealed record PriceEntry(long Id, string TierCode, string? ProfileCode, string CurrencyCode,
        decimal MonthlyPrice, decimal? AnnualPrice, bool TaxInclusive);
    public sealed record DiscountRule(int MinCompanies, decimal Percent, int? MaxCompanies = null, string? Name = null, bool Stackable = true, int Priority = 0);
    /// <summary>One applicable discount, auto or special (admin-app spec 21/24).</summary>
    public sealed record SpecialDiscount(long Id, string Name, string DiscountType, decimal Value, bool Stackable, int Priority);
    public sealed record AppliedDiscount(long Id, string Name, decimal Amount);

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
                if (r.MaxCompanies.HasValue && eligibleCompanies > r.MaxCompanies.Value) continue;
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
                "water" => "WATER_PRODUCTION_LINES",
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
        /// Every checkout reference is "&lt;invoicenumber&gt;-&lt;guid&gt;"; this
        /// recovers the invoice number so a payment settles even when a later
        /// checkout attempt replaced the invoice's stored reference.
        /// </summary>
        public static string InvoiceNumberFromReference(string reference) =>
            reference.Contains('-') ? reference[..reference.LastIndexOf('-')] : reference;

        /// <summary>
        /// The monthly-equivalent charge for a billing cycle. Annual uses the
        /// explicitly configured annual price — never "12 x monthly" computed
        /// in code (spec 11.3); an annual cycle with no annual price is
        /// unpriced, not guessed.
        /// </summary>
        public static decimal? CyclePrice(PriceEntry entry, string billingCycle) =>
            string.Equals(billingCycle, "annual", StringComparison.OrdinalIgnoreCase)
                ? entry.AnnualPrice
                : entry.MonthlyPrice;

        /// <summary>
        /// Where an account stands against its oldest unpaid invoice
        /// (spec Part 20): Active until due, then PastDue, then GracePeriod
        /// after the grace days, then Suspended after the suspend window.
        /// Pure bookkeeping — whether anything is actually restricted is the
        /// enforcement switch's business, not this function's.
        /// </summary>
        public static string AccountStatusFor(DateTime oldestUnpaidDueDate, DateTime today, int graceDays, int suspendDaysAfterGrace)
        {
            if (today <= oldestUnpaidDueDate) return "Active";
            var overdue = (today - oldestUnpaidDueDate).Days;
            if (overdue <= graceDays) return "PastDue";
            if (overdue <= graceDays + suspendDaysAfterGrace) return "GracePeriod";
            return "Suspended";
        }

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
    
        /// <summary>
        /// Deterministic discount stacking (admin-app spec 24). Stackable
        /// discounts apply in priority order (lower first), each on the
        /// RUNNING amount. A non-stackable discount competes alone against
        /// the whole stacked chain; the customer gets whichever saves more.
        /// Fixed amounts never take a line below zero. Pure math — which
        /// discounts are applicable (dates, scope, periods) is decided by
        /// the caller from data.
        /// </summary>
        public static List<AppliedDiscount> ApplyDiscountStack(decimal subtotal, IEnumerable<SpecialDiscount> discounts)
        {
            var all = discounts.ToList();
            var stacked = new List<AppliedDiscount>();
            var running = subtotal;
            foreach (var d in all.Where(x => x.Stackable).OrderBy(x => x.Priority).ThenBy(x => x.Id))
            {
                var amt = d.DiscountType.Equals("Fixed", StringComparison.OrdinalIgnoreCase)
                    ? Math.Min(Money(d.Value), running)
                    : Money(running * d.Value / 100m);
                if (amt <= 0) continue;
                stacked.Add(new AppliedDiscount(d.Id, d.Name, amt));
                running -= amt;
            }
            var stackedTotal = stacked.Sum(x => x.Amount);

            AppliedDiscount? bestSolo = null;
            foreach (var d in all.Where(x => !x.Stackable))
            {
                var amt = d.DiscountType.Equals("Fixed", StringComparison.OrdinalIgnoreCase)
                    ? Math.Min(Money(d.Value), subtotal)
                    : Money(subtotal * d.Value / 100m);
                if (amt <= 0) continue;
                if (bestSolo is null || amt > bestSolo.Amount) bestSolo = new AppliedDiscount(d.Id, d.Name, amt);
            }

            if (bestSolo is not null && bestSolo.Amount > stackedTotal)
                return new List<AppliedDiscount> { bestSolo };
            return stacked;
        }

        /// <summary>
        /// Tier-rule validation before save (admin-app spec 6): max &lt; min,
        /// duplicate tiers, overlapping ranges and gaps between consecutive
        /// bands. Returns problem descriptions; empty = valid.
        /// </summary>
        public static List<string> ValidateTierRules(IEnumerable<(string Tier, decimal Min, decimal? Max)> rules)
        {
            var problems = new List<string>();
            var list = rules.OrderBy(r => r.Min).ToList();
            var dup = list.GroupBy(r => r.Tier, StringComparer.OrdinalIgnoreCase).FirstOrDefault(g => g.Count() > 1);
            if (dup != null) problems.Add($"Tier '{dup.Key}' has more than one active rule.");
            foreach (var r in list)
                if (r.Max.HasValue && r.Max.Value < r.Min)
                    problems.Add($"Tier '{r.Tier}': max ({r.Max}) is below min ({r.Min}).");
            for (var i = 0; i < list.Count - 1; i++)
            {
                var a = list[i]; var b = list[i + 1];
                if (!a.Max.HasValue)
                    problems.Add($"Tier '{a.Tier}' has no upper bound but '{b.Tier}' starts above it — unreachable band.");
                else if (b.Min <= a.Max.Value)
                    problems.Add($"Tiers '{a.Tier}' and '{b.Tier}' overlap between {b.Min} and {a.Max}.");
                else if (b.Min > a.Max.Value + 1)
                    problems.Add($"Gap between '{a.Tier}' (ends {a.Max}) and '{b.Tier}' (starts {b.Min}).");
            }
            return problems;
        }
    }
}
