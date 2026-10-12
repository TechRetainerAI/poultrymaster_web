using System.Collections.Generic;
using PoultryFarmAPIWeb.Business;
using Xunit;

namespace PlatformActivity.Tests
{
    public class FlagMathTests
    {
        private static readonly FlagContext Ctx = new(
            UserId: "user-1", CompanyId: "farm-1", OrganizationId: "org-1",
            BusinessTemplate: "School", CompanyFamily: "Generic", Market: "GH");

        [Fact]
        public void MasterOff_AlwaysWins()
        {
            var rules = new List<FlagRule> { new("User", "user-1", true) };
            var (enabled, scope) = FlagMath.Resolve(false, true, rules, Ctx);
            Assert.False(enabled);
            Assert.Equal("MasterOff", scope);
        }

        [Fact]
        public void NoRules_UsesDefault()
        {
            Assert.False(FlagMath.Resolve(true, false, new List<FlagRule>(), Ctx).Enabled);
            Assert.True(FlagMath.Resolve(true, true, new List<FlagRule>(), Ctx).Enabled);
        }

        [Fact]
        public void GlobalRule_AppliesToEveryone()
        {
            var rules = new List<FlagRule> { new("Global", "", true) };
            var (enabled, scope) = FlagMath.Resolve(true, false, rules, Ctx);
            Assert.True(enabled);
            Assert.Equal("Global", scope);
        }

        [Fact]
        public void MarketRollout_PoultryGhanaStyle()
        {
            // "Poultry Ghana" stage: family + market rules, family is more specific.
            var rules = new List<FlagRule>
            {
                new("Market", "GH", false),
                new("CompanyFamily", "Generic", true),
            };
            var (enabled, scope) = FlagMath.Resolve(true, false, rules, Ctx);
            Assert.True(enabled);
            Assert.Equal("CompanyFamily", scope);
        }

        [Fact]
        public void OrganizationOverride_BeatsFamilyAndMarket()
        {
            var rules = new List<FlagRule>
            {
                new("CompanyFamily", "Generic", true),
                new("Organization", "org-1", false),   // pilot org opted out
            };
            var (enabled, scope) = FlagMath.Resolve(true, true, rules, Ctx);
            Assert.False(enabled);
            Assert.Equal("Organization", scope);
        }

        [Fact]
        public void CompanyRule_BeatsOrganization()
        {
            var rules = new List<FlagRule>
            {
                new("Organization", "org-1", false),
                new("Company", "farm-1", true),
            };
            Assert.True(FlagMath.Resolve(true, false, rules, Ctx).Enabled);
        }

        [Fact]
        public void UserRule_IsMostSpecific()
        {
            var rules = new List<FlagRule>
            {
                new("Company", "farm-1", false),
                new("User", "user-1", true),
            };
            var (enabled, scope) = FlagMath.Resolve(true, false, rules, Ctx);
            Assert.True(enabled);
            Assert.Equal("User", scope);
        }

        [Fact]
        public void RulesForOtherScopeValues_DoNotMatch()
        {
            var rules = new List<FlagRule>
            {
                new("Company", "some-other-farm", true),
                new("Organization", "another-org", true),
            };
            Assert.False(FlagMath.Resolve(true, false, rules, Ctx).Enabled);
        }

        [Fact]
        public void MissingContext_SkipsThatScope()
        {
            var anonymous = new FlagContext(null, null, null, null, null, null);
            var rules = new List<FlagRule> { new("User", "user-1", true), new("Global", "", true) };
            var (enabled, scope) = FlagMath.Resolve(true, false, rules, anonymous);
            Assert.True(enabled);
            Assert.Equal("Global", scope);
        }
    }

    public class ErrorIntelClassifierTests
    {
        [Theory]
        [InlineData("Sale", true)]                 // failed sale postings are customer impact
        [InlineData("EggProduction", true)]
        [InlineData("WaterDailyProduction", true)]
        [InlineData("FlockBatch", true)]           // audit alias for MainFlockBatch
        [InlineData("PoultryAdvancedReports", false)]  // report surface: harmless
        [InlineData("UserQuickLink", false)]
        [InlineData("", false)]
        public void CriticalResourceDetection(string resource, bool expected)
        {
            Assert.Equal(expected, ActivityClassifier.IsCriticalResource(resource));
        }

        [Theory]
        [InlineData("WaterExpense", "Water")]
        [InlineData("HotelBooking", "Hotel")]
        [InlineData("Sale", "Poultry")]
        [InlineData("SomethingUnknown", null)]
        public void ModuleMapping(string resource, string? module)
        {
            Assert.Equal(module, ActivityClassifier.ModuleForResource(resource));
        }
    }
}
