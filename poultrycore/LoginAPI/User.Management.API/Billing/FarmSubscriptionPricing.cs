using User.Management.API.Models;

namespace User.Management.API.Billing
{
    public sealed record SubscriptionTierQuote(string TierKey, string ProductName, long UnitAmountMinor);

    public static class FarmSubscriptionPricing
    {
        public const int MaxBirdsAllowed = 1_000_000;

        /// <summary>
        /// Effective monthly amounts (major currency units). If tier2 is mis-set to match or exceed tier3
        /// (e.g. both 1500 while tier1 is 500), derive a middle tier between tier1 and tier3 so checkout and
        /// subscription-tiers stay aligned (500 / 1000 / 1500 for the usual GHS ladder).
        /// </summary>
        public static (decimal tier1, decimal tier2, decimal tier3) ResolveTierMonthlyAmounts(FarmSubscriptionOptions o)
        {
            var t1 = o.Tier1MonthlyAmount;
            var t2 = o.Tier2MonthlyAmount;
            var t3 = o.Tier3MonthlyAmount;

            if (t2 >= t3 && t1 > 0m && t3 > t1)
            {
                t2 = decimal.Round((t1 + t3) / 2m, 0, MidpointRounding.AwayFromZero);
                if (t2 <= t1) t2 = t1 + 1m;
                if (t2 >= t3) t2 = t3 - 1m;
            }

            return (t1, t2, t3);
        }

        public static SubscriptionTierQuote GetQuote(int totalBirdsActive, FarmSubscriptionOptions o)
        {
            if (o.Tier1MaxBirds < 0 || o.Tier2MaxBirds < o.Tier1MaxBirds)
                throw new InvalidOperationException("FarmSubscription tier limits are misconfigured.");

            var birds = Math.Max(0, totalBirdsActive);
            var currency = string.IsNullOrWhiteSpace(o.Currency) ? "ghs" : o.Currency.Trim().ToLowerInvariant();
            var (amt1, amt2, amt3) = ResolveTierMonthlyAmounts(o);

            string tierKey;
            string productName;
            decimal amountMajor;

            if (birds <= o.Tier1MaxBirds)
            {
                tierKey = "tier1";
                productName = $"PoultryMaster — up to {o.Tier1MaxBirds:N0} birds (monthly)";
                amountMajor = amt1;
            }
            else if (birds <= o.Tier2MaxBirds)
            {
                tierKey = "tier2";
                productName = $"PoultryMaster — {o.Tier1MaxBirds + 1:N0}–{o.Tier2MaxBirds:N0} birds (monthly)";
                amountMajor = amt2;
            }
            else
            {
                tierKey = "tier3";
                productName = $"PoultryMaster — over {o.Tier2MaxBirds:N0} birds (monthly)";
                amountMajor = amt3;
            }

            var minor = ToMinorUnits(amountMajor, currency);
            if (minor <= 0)
                throw new InvalidOperationException("Computed subscription amount must be greater than zero.");

            return new SubscriptionTierQuote(tierKey, productName, minor);
        }

        private static long ToMinorUnits(decimal major, string currency)
        {
            if (IsZeroDecimalCurrency(currency))
                return (long)Math.Round(major, MidpointRounding.AwayFromZero);
            return (long)Math.Round(major * 100m, MidpointRounding.AwayFromZero);
        }

        private static bool IsZeroDecimalCurrency(string c) =>
            c is "bif" or "clp" or "djf" or "gnf" or "jpy" or "kmf" or "krw" or "mga" or "pyg" or "rwf" or "ugx" or "vnd" or "vuv" or "xaf" or "xof" or "xpf";
    }
}
