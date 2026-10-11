using PoultryFarmAPIWeb.Business;
using Xunit;

namespace PlatformActivity.Tests
{
    public class RevenueMathTests
    {
        // ---- MRR normalization (spec section 3) ----

        [Fact]
        public void MonthlyCycle_MrrIsTheMonthlyAmount()
        {
            var (gross, net) = RevenueMath.NormalizeToMonthly(1500m, 0m, "monthly");
            Assert.Equal(1500m, gross);
            Assert.Equal(1500m, net);
        }

        [Fact]
        public void AnnualCycle_MrrIsAnnualDividedBy12()
        {
            var (gross, net) = RevenueMath.NormalizeToMonthly(12000m, 0m, "annual");
            Assert.Equal(1000m, gross);
            Assert.Equal(1000m, net);
        }

        [Fact]
        public void DiscountedPrice_NetIsAfterDiscount_PreTax()
        {
            var (gross, net) = RevenueMath.NormalizeToMonthly(2000m, 300m, "monthly");
            Assert.Equal(2000m, gross);
            Assert.Equal(1700m, net);
        }

        [Fact]
        public void AnnualDiscount_NormalizedMonthly()
        {
            var (_, net) = RevenueMath.NormalizeToMonthly(12000m, 1200m, "annual");
            Assert.Equal(900m, net);
        }

        [Fact]
        public void DiscountLargerThanSubtotal_NeverNegative()
        {
            var (_, net) = RevenueMath.NormalizeToMonthly(100m, 500m, "monthly");
            Assert.Equal(0m, net);
        }

        // ---- paying definition: credits/trials never make MRR ----

        [Theory]
        [InlineData("Active", true)]
        [InlineData("PastDue", true)]      // still subscribed, payment troubled
        [InlineData("GracePeriod", true)]
        [InlineData("Trial", false)]
        [InlineData("Suspended", false)]
        [InlineData("Cancelled", false)]
        [InlineData(null, false)]
        public void PayingStatuses(string? status, bool expected)
        {
            Assert.Equal(expected, RevenueMath.IsPaying(status));
        }

        // ---- MRR movement (New / Expansion / Contraction / Churned) ----

        [Fact]
        public void FirstPayingMonth_IsNewMrr()
        {
            var m = RevenueMath.ClassifyMovement(0m, 1500m);
            Assert.Equal((1500m, 0m, 0m, 0m), m);
        }

        [Fact]
        public void Growth_IsExpansion()
        {
            var m = RevenueMath.ClassifyMovement(1000m, 1400m);
            Assert.Equal((0m, 400m, 0m, 0m), m);
        }

        [Fact]
        public void Shrink_IsContraction_NotChurn()
        {
            var m = RevenueMath.ClassifyMovement(1400m, 1000m);
            Assert.Equal((0m, 0m, 400m, 0m), m);
        }

        [Fact]
        public void ToZero_IsChurnedMrr()
        {
            var m = RevenueMath.ClassifyMovement(1500m, 0m);
            Assert.Equal((0m, 0m, 0m, 1500m), m);
        }

        [Fact]
        public void Flat_IsNoMovement()
        {
            var m = RevenueMath.ClassifyMovement(1500m, 1500m);
            Assert.Equal((0m, 0m, 0m, 0m), m);
        }

        [Fact]
        public void NeverPaying_IsNoMovement()
        {
            var m = RevenueMath.ClassifyMovement(0m, 0m);
            Assert.Equal((0m, 0m, 0m, 0m), m);
        }
    }
}
