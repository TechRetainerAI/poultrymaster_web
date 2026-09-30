// The spec's required engine scenarios (Parts 40–44, 53, 63), run against the
// pure rules. Every number here mirrors either the live Ghana Poultry ladder
// or a scenario the spec names explicitly.

using PoultryFarmAPIWeb.Business;
using Xunit;

namespace PlatformBilling.Tests
{
    public class TierQualificationTests
    {
        // The live ladder, seeded by migration 329.
        private static readonly TierRule[] Poultry =
        {
            new("POULTRY_BIRDS", "starter", 0, 2000),
            new("POULTRY_BIRDS", "growth", 2001, 5000),
            new("POULTRY_BIRDS", "business", 5001, null),
        };

        [Theory]
        [InlineData(0, "starter")]
        [InlineData(1800, "starter")]     // Part 41's Company A
        [InlineData(2000, "starter")]     // inclusive upper bound
        [InlineData(2001, "growth")]
        [InlineData(5000, "growth")]
        [InlineData(5001, "business")]
        [InlineData(6365, "business")]    // Part 64's Prof Owusu figure, above 5,000
        [InlineData(8000, "business")]    // Part 41's Company B
        public void Qualifies_the_live_poultry_ladder(decimal birds, string expected) =>
            Assert.Equal(expected, PlatformBillingRules.QualifyTier(Poultry, "POULTRY_BIRDS", birds));

        [Fact]
        public void Unknown_profile_qualifies_nothing() =>
            Assert.Null(PlatformBillingRules.QualifyTier(Poultry, "HOTEL_ROOMS", 10));

        [Fact]
        public void Overlapping_rules_resolve_to_the_higher_band_deterministically()
        {
            var overlapping = new[]
            {
                new TierRule("P", "starter", 0, 3000),
                new TierRule("P", "growth", 2000, null),
            };
            Assert.Equal("growth", PlatformBillingRules.QualifyTier(overlapping, "P", 2500));
        }
    }

    public class PriceResolutionTests
    {
        [Fact]
        public void Profile_specific_entry_beats_any_profile_entry()
        {
            var entries = new[]
            {
                new PriceEntry(1, "growth", null, "GHS", 900, null, true),
                new PriceEntry(2, "growth", "POULTRY_BIRDS", "GHS", 1000, null, true),
            };
            Assert.Equal(2, PlatformBillingRules.ResolvePrice(entries, "growth", "POULTRY_BIRDS")!.Id);
        }

        [Fact]
        public void Any_profile_entry_serves_profiles_without_their_own_price()
        {
            var entries = new[] { new PriceEntry(1, "starter", null, "GHS", 500, null, true) };
            Assert.Equal(1, PlatformBillingRules.ResolvePrice(entries, "starter", "GENERIC_STANDARD")!.Id);
        }

        [Fact]
        public void No_entry_is_null_never_zero() // PricingNotConfigured, spec Part 39
        {
            var entries = new[] { new PriceEntry(1, "starter", "POULTRY_BIRDS", "GHS", 500, null, true) };
            Assert.Null(PlatformBillingRules.ResolvePrice(entries, "starter", "HOTEL_ROOMS"));
        }
    }

    public class DiscountTests
    {
        private static readonly DiscountRule[] Ladder =
        {
            new(2, 5), new(3, 10), new(5, 15),
        };

        [Theory]
        [InlineData(1, null)]
        [InlineData(2, 5.0)]
        [InlineData(3, 10.0)]
        [InlineData(4, 10.0)]
        [InlineData(5, 15.0)]
        [InlineData(9, 15.0)]
        public void Highest_reached_rule_wins(int companies, double? expected)
        {
            var picked = PlatformBillingRules.PickDiscount(Ladder, companies);
            Assert.Equal((decimal?)expected, picked?.Percent);
        }

        [Fact]
        public void No_active_rules_means_no_discount() =>
            Assert.Null(PlatformBillingRules.PickDiscount(Array.Empty<DiscountRule>(), 10));
    }

    public class TotalsTests
    {
        [Fact]
        public void Part40_worked_example_three_companies_ten_percent()
        {
            // Poultry 1,500 + Water 1,000 + School 500; 3 companies -> 10%.
            var (subtotal, discount, tax, total) =
                PlatformBillingRules.Totals(new[] { 1500m, 1000m, 500m }, 10m, 0m);
            Assert.Equal(3000m, subtotal);
            Assert.Equal(300m, discount);
            Assert.Equal(0m, tax);
            Assert.Equal(2700m, total);
        }

        [Fact]
        public void Tax_applies_after_discount()
        {
            var (_, _, tax, total) = PlatformBillingRules.Totals(new[] { 1000m }, 10m, 15m);
            Assert.Equal(135m, tax);       // 15% of 900, not of 1,000
            Assert.Equal(1035m, total);
        }

        [Fact]
        public void Money_rounds_half_away_from_zero_at_2dp()
        {
            Assert.Equal(0.13m, PlatformBillingRules.Money(0.125m));
            var (subtotal, discount, _, _) = PlatformBillingRules.Totals(new[] { 33.335m }, 50m, 0m);
            Assert.Equal(33.34m, subtotal);
            Assert.Equal(16.67m, discount);
        }
    }

    public class IdentityAndUnitsTests
    {
        [Fact]
        public void Invoice_number_is_deterministic_per_account_period() // spec Part 33
        {
            var a = PlatformBillingRules.InvoiceNumber(7, new DateTime(2026, 9, 1));
            var b = PlatformBillingRules.InvoiceNumber(7, new DateTime(2026, 9, 1));
            Assert.Equal(a, b);
            Assert.Equal("VC-7-202609", a);
            Assert.NotEqual(a, PlatformBillingRules.InvoiceNumber(7, new DateTime(2026, 10, 1)));
            Assert.NotEqual(a, PlatformBillingRules.InvoiceNumber(8, new DateTime(2026, 9, 1)));
        }

        [Theory]
        [InlineData(1500, "GHS", 150000)]  // two-decimal: live Ghana business tier
        [InlineData(1500, "NGN", 150000)]
        [InlineData(1500, "JPY", 1500)]    // zero-decimal guard: never 100x
        public void Minor_units_respect_the_currency(double major, string currency, long expected) =>
            Assert.Equal(expected, PlatformBillingRules.ToMinorUnits((decimal)major, currency));
    }

    public class ProfileResolutionTests
    {
        [Theory]
        [InlineData("Poultry", "POULTRY_BIRDS")]
        [InlineData("Water", "WATER_STANDARD")]
        [InlineData("Hotel", "HOTEL_ROOMS")]
        [InlineData("Restaurant", "RESTAURANT_LOCATIONS")]
        [InlineData("Generic", "GENERIC_STANDARD")]
        public void Family_maps_to_its_profile(string family, string expected) =>
            Assert.Equal(expected, PlatformBillingRules.ResolveProfileCode(family, null));

        [Fact]
        public void A_new_generic_template_needs_no_billing_code() // spec Part 43
        {
            // "Pharmacy" has never been seen by any billing code; the family
            // alone routes it to GENERIC_STANDARD.
            Assert.Equal("GENERIC_STANDARD", PlatformBillingRules.ResolveProfileCode("Generic", null));
        }

        [Fact]
        public void A_state_override_wins() =>
            Assert.Equal("SCHOOL_STUDENTS", PlatformBillingRules.ResolveProfileCode("Generic", "SCHOOL_STUDENTS"));
    }
}
