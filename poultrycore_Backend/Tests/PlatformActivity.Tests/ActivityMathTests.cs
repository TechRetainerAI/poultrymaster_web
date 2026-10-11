using System;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;
using Xunit;

namespace PlatformActivity.Tests
{
    public class ActivityMathTests
    {
        private const double Band = 10.0;

        // ---- trend (spec section 13): current vs preceding equal-length period ----

        [Fact]
        public void Trend_300vs200_IsPlus50Percent_Increasing()
        {
            var t = ActivityMath.ComputeTrend(300, 200, Band);
            Assert.Equal(nameof(PlatformTrendStatus.Increasing), t.Status);
            Assert.Equal(50.0, t.PercentChange);
        }

        [Fact]
        public void Trend_PreviousZero_NoInfinity_NewActivity()
        {
            var t = ActivityMath.ComputeTrend(10, 0, Band);
            Assert.Equal(nameof(PlatformTrendStatus.NewActivity), t.Status);
            Assert.Null(t.PercentChange); // undefined, never Infinity
        }

        [Fact]
        public void Trend_CurrentZero_IsInactive()
        {
            var t = ActivityMath.ComputeTrend(0, 50, Band);
            Assert.Equal(nameof(PlatformTrendStatus.Inactive), t.Status);
            Assert.Equal(-100.0, t.PercentChange);
        }

        [Fact]
        public void Trend_BothZero_IsInactive_NoPercent()
        {
            var t = ActivityMath.ComputeTrend(0, 0, Band);
            Assert.Equal(nameof(PlatformTrendStatus.Inactive), t.Status);
            Assert.Null(t.PercentChange);
        }

        [Fact]
        public void Trend_WithinBand_IsStable()
        {
            var t = ActivityMath.ComputeTrend(105, 100, Band);
            Assert.Equal(nameof(PlatformTrendStatus.Stable), t.Status);
            Assert.Equal(5.0, t.PercentChange);
        }

        [Fact]
        public void Trend_BelowBand_IsDeclining()
        {
            var t = ActivityMath.ComputeTrend(60, 100, Band);
            Assert.Equal(nameof(PlatformTrendStatus.Declining), t.Status);
            Assert.Equal(-40.0, t.PercentChange);
        }

        // ---- deterministic status classification (spec section 12) ----

        private static readonly DateTime Now = new(2026, 10, 11, 12, 0, 0, DateTimeKind.Utc);

        [Fact]
        public void Status_ActiveToday_WinsRegardlessOfTimestamps()
        {
            var s = ActivityMath.ClassifyStatus(true, Now.AddDays(-90), Now, 7, 30);
            Assert.Equal(PlatformActivityStatus.ActiveToday, s);
        }

        [Theory]
        [InlineData(3, PlatformActivityStatus.Active7Days)]
        [InlineData(7, PlatformActivityStatus.Active7Days)]
        [InlineData(8, PlatformActivityStatus.Active30Days)]
        [InlineData(30, PlatformActivityStatus.Active30Days)]
        [InlineData(31, PlatformActivityStatus.Inactive30Plus)]
        [InlineData(365, PlatformActivityStatus.Inactive30Plus)]
        public void Status_ByAgeOfLastMeaningfulActivity(int daysAgo, PlatformActivityStatus expected)
        {
            var s = ActivityMath.ClassifyStatus(false, Now.AddDays(-daysAgo), Now, 7, 30);
            Assert.Equal(expected, s);
        }

        [Fact]
        public void Status_NeverActive_IsNoActivity()
        {
            var s = ActivityMath.ClassifyStatus(false, null, Now, 7, 30);
            Assert.Equal(PlatformActivityStatus.NoActivity, s);
        }

        // ---- Going Quiet rule (Prompt 2, section 11) ----

        [Theory]
        [InlineData(50, 0, true)]    // very active before, silent now
        [InlineData(10, 2, true)]    // exactly at both thresholds
        [InlineData(9, 0, false)]    // never active enough — not "going quiet", just small
        [InlineData(50, 3, false)]   // still active now
        [InlineData(0, 0, false)]    // never active at all
        public void GoingQuiet_Rule(long baseline, long recent, bool expected)
        {
            Assert.Equal(expected, ActivityMath.IsGoingQuiet(baseline, recent, baselineMin: 10, recentMax: 2));
        }
    }
}
