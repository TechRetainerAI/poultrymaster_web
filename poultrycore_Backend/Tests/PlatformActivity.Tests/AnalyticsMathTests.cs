using System;
using System.Collections.Generic;
using System.Linq;
using PoultryFarmAPIWeb.Business;
using Xunit;

namespace PlatformActivity.Tests
{
    public class FeatureCatalogTests
    {
        [Theory]
        [InlineData("ProductionRecorded", "Poultry", "Production")]
        [InlineData("ProductionRecorded", "Water", "Production")]
        [InlineData("DailyClosingCompleted", "Generic", "Daily Closing")]
        [InlineData("DriverReturnCompleted", "Water", "Driver Returns")]
        [InlineData("CheckInCompleted", "Hotel", "Front Desk")]
        [InlineData("SubscriptionCreated", "Generic", "Subscriptions")]
        public void ActivityTypes_MapToFeatures(string type, string family, string feature)
        {
            Assert.Equal(feature, FeatureCatalog.Resolve(type, family));
        }

        [Fact]
        public void Feature_NotApplicableToFamily_ReturnsNull()
        {
            // Feed usage is a Poultry feature; a Hotel never gets compared on it.
            Assert.Null(FeatureCatalog.Resolve("FeedUsageRecorded", "Hotel"));
            Assert.False(FeatureCatalog.Applicable("Feed Usage", "Hotel"));
        }

        [Fact]
        public void UnknownActivityType_MapsToNoFeature()
        {
            Assert.Null(FeatureCatalog.Resolve("SomethingUnmapped", "Poultry"));
        }
    }

    public class RetentionMathTests
    {
        private static readonly DateOnly Signup = new(2026, 9, 1);

        [Fact]
        public void Day7Window_CatchesActivityBetweenDay7And29()
        {
            var days = new List<DateOnly> { Signup.AddDays(10) };
            Assert.False(RetentionMath.RetainedInWindow(Signup, days, 0)); // D1 = [1,7)
            Assert.True(RetentionMath.RetainedInWindow(Signup, days, 1));  // D7 = [7,30)
            Assert.False(RetentionMath.RetainedInWindow(Signup, days, 2)); // D30
        }

        [Fact]
        public void Day30Window_CatchesActivityBetweenDay30And59()
        {
            var days = new List<DateOnly> { Signup.AddDays(45) };
            Assert.False(RetentionMath.RetainedInWindow(Signup, days, 1));
            Assert.True(RetentionMath.RetainedInWindow(Signup, days, 2));
        }

        [Fact]
        public void SignupDayActivity_DoesNotCountAsRetention()
        {
            var days = new List<DateOnly> { Signup };
            for (var w = 0; w < 5; w++)
                Assert.False(RetentionMath.RetainedInWindow(Signup, days, w));
        }

        [Fact]
        public void WindowNotYetReached_IsDetected()
        {
            var today = Signup.AddDays(10);
            Assert.True(RetentionMath.WindowReached(Signup, today, 1));   // D7 reached
            Assert.False(RetentionMath.WindowReached(Signup, today, 2));  // D30 not yet
        }

        [Fact]
        public void CohortKeys_AreStable()
        {
            Assert.Equal("2026-09", RetentionMath.MonthKey(new DateOnly(2026, 9, 15)));
            Assert.StartsWith("2026-W", RetentionMath.WeekKey(new DateOnly(2026, 9, 15)));
        }
    }

    public class FunnelMathTests
    {
        private static OrgFunnelInput Org(bool company = true, bool setup = true, bool activity = true,
            int days = 5, bool paid = false) => new(company, setup, activity, days, paid);

        [Fact]
        public void Funnel_CountsAndConversionsAreSequential()
        {
            var stages = FunnelMath.Build(new List<OrgFunnelInput>
            {
                Org(paid: true),                             // full funnel
                Org(days: 1),                                // drops at 3-days stage
                Org(setup: false, activity: false, days: 0), // drops at setup
                Org(company: false, setup: false, activity: false, days: 0), // registered only
            });

            Assert.Equal(new[] { 4, 3, 2, 2, 1, 1 }, stages.Select(s => s.Count).ToArray());
            Assert.Null(stages[0].PercentOfPrevious);
            Assert.Equal(75.0, stages[1].PercentOfPrevious);
            Assert.Equal(100.0, stages[0].PercentOfTop);
            Assert.Equal(25.0, stages[5].PercentOfTop);
        }

        [Fact]
        public void EmptyFunnel_IsAllZeros_NoDivisionByZero()
        {
            var stages = FunnelMath.Build(new List<OrgFunnelInput>());
            Assert.All(stages, s => Assert.Equal(0, s.Count));
            Assert.Equal(0.0, stages[1].PercentOfPrevious);
        }

        [Fact]
        public void PaidWithoutUsage_DoesNotSkipStages()
        {
            // An org that paid but never used the product must not appear in the
            // "Converted to paid" stage of the USAGE funnel (stages are sequential).
            var stages = FunnelMath.Build(new List<OrgFunnelInput>
            {
                Org(setup: false, activity: false, days: 0, paid: true),
            });
            Assert.Equal(0, stages.Single(s => s.Key == "paid").Count);
        }
    }
}
