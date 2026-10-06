// ADMIN APP spec tests at the pure-rules level: discount stacking (spec 44),
// tier-rule validation (spec 6/42), water tier bands (spec 5), and the
// max-companies bound on automatic rules (spec 18).

using System;
using System.Collections.Generic;
using System.Linq;
using PoultryFarmAPIWeb.Business;
using Xunit;

namespace PlatformBilling.Tests
{
    public class PlatformBillingAdminRulesTests
    {
        // ---------------- discount stacking (spec 24/44) ----------------

        [Fact]
        public void Stackables_apply_in_priority_order_on_running_amount()
        {
            // 3000 -> multi-company 10% (-300) -> early adopter 10% of 2700 (-270) = spec 23's example.
            var applied = PlatformBillingRules.ApplyDiscountStack(3000m, new[]
            {
                new SpecialDiscount(0, "Multi-company", "Percentage", 10m, true, 0),
                new SpecialDiscount(7, "Early adopter", "Percentage", 10m, true, 100),
            });
            Assert.Equal(2, applied.Count);
            Assert.Equal(300m, applied[0].Amount);
            Assert.Equal(270m, applied[1].Amount);
        }

        [Fact]
        public void NonStackable_wins_only_when_it_saves_more()
        {
            // Stacked chain saves 300; the exclusive 20% promo saves 600 -> promo alone wins.
            var applied = PlatformBillingRules.ApplyDiscountStack(3000m, new[]
            {
                new SpecialDiscount(0, "Multi-company", "Percentage", 10m, true, 0),
                new SpecialDiscount(9, "Launch promo", "Percentage", 20m, false, 100),
            });
            var only = Assert.Single(applied);
            Assert.Equal(9, only.Id);
            Assert.Equal(600m, only.Amount);

            // A weaker exclusive (5% = 150) loses to the stacked 10% = 300.
            applied = PlatformBillingRules.ApplyDiscountStack(3000m, new[]
            {
                new SpecialDiscount(0, "Multi-company", "Percentage", 10m, true, 0),
                new SpecialDiscount(9, "Weak promo", "Percentage", 5m, false, 100),
            });
            var kept = Assert.Single(applied);
            Assert.Equal(0, kept.Id);
            Assert.Equal(300m, kept.Amount);
        }

        [Fact]
        public void Fixed_amount_discount_never_exceeds_the_amount()
        {
            var applied = PlatformBillingRules.ApplyDiscountStack(200m, new[]
            {
                new SpecialDiscount(3, "Goodwill", "Fixed", 500m, true, 0),
            });
            Assert.Equal(200m, Assert.Single(applied).Amount);
        }

        [Fact]
        public void Empty_discounts_mean_no_change()
        {
            Assert.Empty(PlatformBillingRules.ApplyDiscountStack(1000m, Array.Empty<SpecialDiscount>()));
        }

        // ---------------- automatic rule bounds (spec 18) ----------------

        [Fact]
        public void MaxCompanies_bound_is_respected()
        {
            var rules = new[]
            {
                new DiscountRule(2, 5m, MaxCompanies: 2),
                new DiscountRule(3, 10m),
            };
            Assert.Equal(5m, PlatformBillingRules.PickDiscount(rules, 2)!.Percent);
            Assert.Equal(10m, PlatformBillingRules.PickDiscount(rules, 3)!.Percent);
            Assert.Null(PlatformBillingRules.PickDiscount(new[] { new DiscountRule(2, 5m, MaxCompanies: 2) }, 3));
        }

        // ---------------- tier-rule validation (spec 6/42) ----------------

        [Fact]
        public void Valid_water_ladder_passes()
        {
            // Spec 5: Starter 0-1 line, Growth 2-3, Business 4+.
            var problems = PlatformBillingRules.ValidateTierRules(new (string, decimal, decimal?)[]
            {
                ("starter", 0m, 1m), ("growth", 2m, 3m), ("business", 4m, null),
            });
            Assert.Empty(problems);
        }

        [Theory]
        [InlineData(0, 5, 2, 8, "overlap")]     // 2-8 overlaps 0-5
        [InlineData(0, 1, 5, 9, "Gap")]         // nothing covers 2-4
        public void Overlaps_and_gaps_are_rejected(int aMin, int aMax, int bMin, int bMax, string expected)
        {
            var problems = PlatformBillingRules.ValidateTierRules(new (string, decimal, decimal?)[]
            {
                ("starter", aMin, aMax), ("growth", bMin, bMax),
            });
            Assert.Contains(problems, p => p.Contains(expected, StringComparison.OrdinalIgnoreCase));
        }

        [Fact]
        public void Max_below_min_and_duplicates_are_rejected()
        {
            var problems = PlatformBillingRules.ValidateTierRules(new (string, decimal, decimal?)[]
            {
                ("starter", 5m, 2m),
            });
            Assert.Contains(problems, p => p.Contains("below min"));

            problems = PlatformBillingRules.ValidateTierRules(new (string, decimal, decimal?)[]
            {
                ("starter", 0m, 1m), ("starter", 2m, null),
            });
            Assert.Contains(problems, p => p.Contains("more than one active rule"));
        }

        [Fact]
        public void Unbounded_band_below_a_later_band_is_rejected()
        {
            var problems = PlatformBillingRules.ValidateTierRules(new (string, decimal, decimal?)[]
            {
                ("growth", 2m, null), ("business", 4m, null),
            });
            Assert.Contains(problems, p => p.Contains("unreachable"));
        }

        // ---------------- water qualification (spec 5/42) ----------------

        [Theory]
        [InlineData(0.0, "starter")]   // zero-line setup state still resolves
        [InlineData(1.0, "starter")]
        [InlineData(2.0, "growth")]
        [InlineData(3.0, "growth")]
        [InlineData(4.0, "business")]
        [InlineData(12.0, "business")]
        public void Water_production_lines_qualify_by_band(double lines, string expected)
        {
            var rules = new[]
            {
                new TierRule("WATER_PRODUCTION_LINES", "starter", 0m, 1m),
                new TierRule("WATER_PRODUCTION_LINES", "growth", 2m, 3m),
                new TierRule("WATER_PRODUCTION_LINES", "business", 4m, null),
            };
            Assert.Equal(expected,
                PlatformBillingRules.QualifyTier(rules, "WATER_PRODUCTION_LINES", (decimal)lines));
        }

        [Fact]
        public void Water_family_resolves_to_production_lines_profile()
        {
            Assert.Equal("WATER_PRODUCTION_LINES", PlatformBillingRules.ResolveProfileCode("Water", null));
        }
    }
}
