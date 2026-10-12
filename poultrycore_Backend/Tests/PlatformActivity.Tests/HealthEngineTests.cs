using System;
using System.Collections.Generic;
using System.Linq;
using PoultryFarmAPIWeb.Business;
using Xunit;

namespace PlatformActivity.Tests
{
    public class HealthEngineTests
    {
        private static readonly DateTime Now = new(2026, 10, 11, 12, 0, 0, DateTimeKind.Utc);
        private static readonly PlatformHealthOptions O = new();

        private static CompanyHealthInput Company(
            int? ageDays = 100, int? firstDaysAgo = 90, int? lastDaysAgo = 1,
            int activeDays30 = 10, long m30 = 30, long mPrev30 = 30, int users30 = 2,
            string trend = "Stable", double? pct = 0, int failed7 = 0)
            => new("c1", "Test Co",
                ageDays is int a ? Now.AddDays(-a) : null,
                firstDaysAgo is int f ? Now.AddDays(-f) : null,
                lastDaysAgo is int l ? Now.AddDays(-l) : null,
                activeDays30, m30, mPrev30, users30, trend, pct, failed7);

        private static OrganizationHealthSignals Billing(
            string status = "None", DateTime? trialEnd = null, bool pastDue = false,
            bool paymentFailed = false, long m30 = 30, int? firstCompanyDaysAgo = 100)
            => new(firstCompanyDaysAgo is int d ? Now.AddDays(-d) : null,
                status, trialEnd, pastDue, paymentFailed, m30);

        // ---- company rules ----

        [Fact]
        public void NewAccount_NoActivity_IsNew_NotInactive()
        {
            var r = HealthEngine.EvaluateCompany(Company(ageDays: 3, firstDaysAgo: null, lastDaysAgo: null, mPrev30: 0), O, Now);
            Assert.Equal(HealthLevel.New, r.Level);
            Assert.Contains(r.Reasons, x => x.Contains("too early"));
        }

        [Fact]
        public void OldAccount_NeverActive_IsInactive()
        {
            var r = HealthEngine.EvaluateCompany(Company(ageDays: 60, firstDaysAgo: null, lastDaysAgo: null, mPrev30: 0), O, Now);
            Assert.Equal(HealthLevel.Inactive, r.Level);
            Assert.Contains(r.Reasons, x => x.Contains("Never meaningfully active"));
        }

        [Fact]
        public void ActiveAccount_IsHealthy_WithReasons()
        {
            var r = HealthEngine.EvaluateCompany(Company(lastDaysAgo: 1, activeDays30: 20), O, Now);
            Assert.Equal(HealthLevel.Healthy, r.Level);
            Assert.Contains(r.Reasons, x => x.Contains("Last meaningful activity 1 day ago"));
            Assert.Contains(r.Reasons, x => x.Contains("20 active days"));
        }

        [Fact]
        public void PreviouslyActive_Silent17Days_IsAtRisk_Explained()
        {
            var r = HealthEngine.EvaluateCompany(Company(lastDaysAgo: 17, mPrev30: 42), O, Now);
            Assert.Equal(HealthLevel.AtRisk, r.Level);
            Assert.Contains(r.Reasons, x => x.Contains("No meaningful activity for 17 days"));
            Assert.Contains(r.Reasons, x => x.Contains("42 meaningful actions"));
        }

        [Fact]
        public void Silent35Days_IsInactive()
        {
            var r = HealthEngine.EvaluateCompany(Company(lastDaysAgo: 35), O, Now);
            Assert.Equal(HealthLevel.Inactive, r.Level);
            Assert.Contains(r.Reasons, x => x.Contains("No meaningful activity for 35 days"));
        }

        [Fact]
        public void SharpUsageDrop_NeedsAttention()
        {
            var r = HealthEngine.EvaluateCompany(Company(lastDaysAgo: 2, trend: "Declining", pct: -70), O, Now);
            Assert.Equal(HealthLevel.NeedsAttention, r.Level);
            Assert.Contains(r.Reasons, x => x.Contains("Usage down 70%"));
        }

        [Fact]
        public void RepeatedErrors_NeedsAttention()
        {
            var r = HealthEngine.EvaluateCompany(Company(failed7: 25), O, Now);
            Assert.Equal(HealthLevel.NeedsAttention, r.Level);
            Assert.Contains(r.Reasons, x => x.Contains("25 failed requests"));
        }

        [Fact]
        public void MultipleSignals_AllReasonsAccumulate()
        {
            var r = HealthEngine.EvaluateCompany(
                Company(lastDaysAgo: 2, trend: "Declining", pct: -80, failed7: 30), O, Now);
            Assert.Equal(HealthLevel.NeedsAttention, r.Level);
            Assert.Contains(r.Reasons, x => x.Contains("Usage down"));
            Assert.Contains(r.Reasons, x => x.Contains("failed requests"));
        }

        // ---- organization aggregation ----

        private static (CompanyHealthInput, HealthResult) Judged(HealthLevel level, string name = "Co")
        {
            var input = Company() with { CompanyName = name };
            return (input, new HealthResult(level, new List<string>()));
        }

        [Fact]
        public void Org_MixedHealthyAndAtRisk_IsNeedsAttention_NotAverage()
        {
            var companies = new List<(CompanyHealthInput, HealthResult)>
            {
                Judged(HealthLevel.Healthy, "Poultry"),
                Judged(HealthLevel.Healthy, "Water"),
                Judged(HealthLevel.AtRisk, "Restaurant"),
            };
            var r = HealthEngine.EvaluateOrganization(companies, Billing(), O, Now);
            Assert.Equal(HealthLevel.NeedsAttention, r.Level);
            Assert.Contains(r.Reasons, x => x.Contains("Restaurant"));
        }

        [Fact]
        public void Org_AllHealthy_IsHealthy()
        {
            var r = HealthEngine.EvaluateOrganization(
                new List<(CompanyHealthInput, HealthResult)> { Judged(HealthLevel.Healthy), Judged(HealthLevel.Healthy) },
                Billing(), O, Now);
            Assert.Equal(HealthLevel.Healthy, r.Level);
        }

        [Fact]
        public void Org_AllInactive_IsInactive()
        {
            var r = HealthEngine.EvaluateOrganization(
                new List<(CompanyHealthInput, HealthResult)> { Judged(HealthLevel.Inactive), Judged(HealthLevel.Inactive) },
                Billing(), O, Now);
            Assert.Equal(HealthLevel.Inactive, r.Level);
        }

        [Fact]
        public void Org_AllNewCompanies_IsNew()
        {
            var r = HealthEngine.EvaluateOrganization(
                new List<(CompanyHealthInput, HealthResult)> { Judged(HealthLevel.New) },
                Billing(firstCompanyDaysAgo: 3), O, Now);
            Assert.Equal(HealthLevel.New, r.Level);
        }

        // ---- billing overlays ----

        [Fact]
        public void PastDue_EscalatesHealthyOrg_ToAtRisk()
        {
            var r = HealthEngine.EvaluateOrganization(
                new List<(CompanyHealthInput, HealthResult)> { Judged(HealthLevel.Healthy) },
                Billing(status: "PastDue", pastDue: true), O, Now);
            Assert.Equal(HealthLevel.AtRisk, r.Level);
            Assert.Contains(r.Reasons, x => x.Contains("past-due"));
        }

        [Fact]
        public void PaymentFailed_EscalatesToNeedsAttention()
        {
            var r = HealthEngine.EvaluateOrganization(
                new List<(CompanyHealthInput, HealthResult)> { Judged(HealthLevel.Healthy) },
                Billing(paymentFailed: true), O, Now);
            Assert.Equal(HealthLevel.NeedsAttention, r.Level);
            Assert.Contains(r.Reasons, x => x.Contains("payment failed"));
        }

        [Fact]
        public void TrialEndingSoon_HighEngagement_FlagsSalesOpportunity()
        {
            var r = HealthEngine.EvaluateOrganization(
                new List<(CompanyHealthInput, HealthResult)> { Judged(HealthLevel.Healthy) },
                Billing(status: "Trial", trialEnd: Now.AddDays(3), m30: 50), O, Now);
            Assert.Equal(HealthLevel.NeedsAttention, r.Level);
            Assert.Contains(r.Reasons, x => x.Contains("Highly engaged trial ends in 3 days"));
        }

        [Fact]
        public void TrialEndingSoon_LowEngagement_IsExplainedDifferently()
        {
            var r = HealthEngine.EvaluateOrganization(
                new List<(CompanyHealthInput, HealthResult)> { Judged(HealthLevel.Healthy) },
                Billing(status: "Trial", trialEnd: Now.AddDays(4), m30: 2), O, Now);
            Assert.Equal(HealthLevel.NeedsAttention, r.Level);
            Assert.Contains(r.Reasons, x => x.Contains("low engagement"));
        }

        [Fact]
        public void TrialFarAway_DoesNotFlag()
        {
            var r = HealthEngine.EvaluateOrganization(
                new List<(CompanyHealthInput, HealthResult)> { Judged(HealthLevel.Healthy) },
                Billing(status: "Trial", trialEnd: Now.AddDays(20), m30: 50), O, Now);
            Assert.Equal(HealthLevel.Healthy, r.Level);
        }

        [Fact]
        public void BillingOverlay_NeverImprovesWorseLevel()
        {
            var r = HealthEngine.EvaluateOrganization(
                new List<(CompanyHealthInput, HealthResult)> { Judged(HealthLevel.Inactive) },
                Billing(paymentFailed: true), O, Now);
            Assert.Equal(HealthLevel.Inactive, r.Level);  // escalate-only overlay
        }

        // ---- configuration changes change the verdict ----

        [Fact]
        public void CustomThresholds_ChangeTheOutcome()
        {
            var strict = new PlatformHealthOptions { AtRiskDaysSince = 5, InactiveDaysSince = 10 };
            var tenDaysSilent = Company(lastDaysAgo: 10);
            Assert.Equal(HealthLevel.Healthy, HealthEngine.EvaluateCompany(tenDaysSilent, O, Now).Level)
                ;
            Assert.Equal(HealthLevel.Inactive, HealthEngine.EvaluateCompany(tenDaysSilent, strict, Now).Level);
        }

        [Fact]
        public void EveryVerdict_CarriesAtLeastOneReason()
        {
            var cases = new[]
            {
                Company(ageDays: 2, firstDaysAgo: null, lastDaysAgo: null),
                Company(ageDays: 90, firstDaysAgo: null, lastDaysAgo: null),
                Company(lastDaysAgo: 1),
                Company(lastDaysAgo: 20),
                Company(lastDaysAgo: 40),
            };
            foreach (var c in cases)
                Assert.NotEmpty(HealthEngine.EvaluateCompany(c, O, Now).Reasons);
        }
    }
}
