// PROMPT 3 (Customer Health Engine): deterministic, explainable health
// classification. No black-box score — every verdict carries reasons built
// from actual VisibilityCore data ("No meaningful activity for 17 days",
// "Trial ends in 4 days"), and every threshold is centrally configurable via
// the PlatformHealth appsettings section.
//
// Pure functions only: the engine never touches the database, which is what
// makes every rule unit-testable (new account, decline, trial ending,
// payment failure, mixed organizations, custom thresholds, ...).

namespace PoultryFarmAPIWeb.Business
{
    public enum HealthLevel
    {
        New = 0,            // insufficient history to judge
        Healthy = 1,
        NeedsAttention = 2,
        AtRisk = 3,
        Inactive = 4,
    }

    public class PlatformHealthOptions
    {
        public const string Section = "PlatformHealth";
        /// <summary>Younger than this with no activity yet = New, not Inactive.</summary>
        public int NewAccountDays { get; set; } = 14;
        /// <summary>Previously active + this many days silent = At Risk.</summary>
        public int AtRiskDaysSince { get; set; } = 14;
        /// <summary>This many days silent = Inactive.</summary>
        public int InactiveDaysSince { get; set; } = 30;
        /// <summary>Trial ending within this many days raises attention.</summary>
        public int TrialEndingSoonDays { get; set; } = 5;
        /// <summary>Meaningful events in 30d at/above this = "highly engaged" trial.</summary>
        public int HighEngagementMin30d { get; set; } = 20;
        /// <summary>Usage drop (percent vs previous period) that flags a decline.</summary>
        public double UsageDropPercent { get; set; } = 50;
        /// <summary>Failed requests in 7 days at/above this = RepeatedErrors.</summary>
        public int RepeatedErrorsMin7d { get; set; } = 20;
        /// <summary>Org never meaningfully active after this many days = NoActivityAfterSignup.</summary>
        public int NoActivityAfterSignupDays { get; set; } = 7;
        /// <summary>Failed attempts at ONE critical business operation (7d) that raise attention.</summary>
        public int FailedCriticalOpsMin7d { get; set; } = 5;
    }

    public sealed record CompanyHealthInput(
        string CompanyId,
        string CompanyName,
        DateTime? CreatedAtUtc,
        DateTime? FirstMeaningfulAtUtc,
        DateTime? LastMeaningfulAtUtc,
        int ActiveDays30d,
        long Meaningful30d,
        long MeaningfulPrev30d,
        int ActiveUsers30d,
        string TrendStatus,
        double? TrendPercent,
        int FailedRequests7d);

    public sealed record OrganizationHealthSignals(
        DateTime? FirstCompanyCreatedAtUtc,
        string SubscriptionStatus,        // None | Trial | Active | PastDue
        DateTime? TrialEndUtc,
        bool HasPastDueInvoice,
        bool PaymentFailedRecently,
        long Meaningful30d);

    public sealed record HealthResult(HealthLevel Level, IReadOnlyList<string> Reasons)
    {
        public string LevelName => Level switch
        {
            HealthLevel.New => "New",
            HealthLevel.Healthy => "Healthy",
            HealthLevel.NeedsAttention => "Needs Attention",
            HealthLevel.AtRisk => "At Risk",
            _ => "Inactive",
        };
    }

    public static class HealthEngine
    {
        public static HealthResult EvaluateCompany(CompanyHealthInput c, PlatformHealthOptions o, DateTime nowUtc)
        {
            var reasons = new List<string>();
            var ageDays = c.CreatedAtUtc is DateTime created ? (int)(nowUtc - created).TotalDays : (int?)null;

            if (c.FirstMeaningfulAtUtc is null)
            {
                if (ageDays is null || ageDays < o.NewAccountDays)
                {
                    reasons.Add(ageDays is int a
                        ? $"Created {a} day{(a == 1 ? "" : "s")} ago; no meaningful activity yet — too early to judge"
                        : "No meaningful activity yet — too early to judge");
                    return new HealthResult(HealthLevel.New, reasons);
                }
                reasons.Add($"Never meaningfully active since creation {ageDays} days ago");
                return new HealthResult(HealthLevel.Inactive, reasons);
            }

            var daysSince = (int)(nowUtc - c.LastMeaningfulAtUtc!.Value).TotalDays;

            if (daysSince >= o.InactiveDaysSince)
            {
                reasons.Add($"No meaningful activity for {daysSince} days");
                if (c.MeaningfulPrev30d > 0)
                    reasons.Add($"Was previously active ({c.MeaningfulPrev30d} meaningful actions in the prior 30-day window)");
                return new HealthResult(HealthLevel.Inactive, reasons);
            }

            if (daysSince >= o.AtRiskDaysSince)
            {
                reasons.Add($"No meaningful activity for {daysSince} days after previously being active");
                if (c.MeaningfulPrev30d > 0)
                    reasons.Add($"Previous 30-day activity: {c.MeaningfulPrev30d} meaningful actions");
                return new HealthResult(HealthLevel.AtRisk, reasons);
            }

            var level = HealthLevel.Healthy;
            reasons.Add(daysSince <= 0
                ? "Meaningful activity today"
                : $"Last meaningful activity {daysSince} day{(daysSince == 1 ? "" : "s")} ago");
            reasons.Add($"{c.ActiveDays30d} active day{(c.ActiveDays30d == 1 ? "" : "s")} in the last 30");

            if (c.TrendStatus == "Declining" && c.TrendPercent is double pct && pct <= -o.UsageDropPercent)
            {
                level = HealthLevel.NeedsAttention;
                reasons.Add($"Usage down {Math.Abs(pct):0}% vs the previous 30 days");
            }

            if (c.FailedRequests7d >= o.RepeatedErrorsMin7d)
            {
                level = Max(level, HealthLevel.NeedsAttention);
                reasons.Add($"{c.FailedRequests7d} failed requests in the last 7 days");
            }

            return new HealthResult(level, reasons);
        }

        /// <summary>Organization health: rolls up company results (never a blind
        /// average) and then overlays billing-level signals, which can only
        /// escalate — a past-due invoice never makes an org look healthier.</summary>
        public static HealthResult EvaluateOrganization(
            IReadOnlyList<(CompanyHealthInput Input, HealthResult Result)> companies,
            OrganizationHealthSignals s, PlatformHealthOptions o, DateTime nowUtc)
        {
            var reasons = new List<string>();
            HealthLevel level;

            var judged = companies.Where(c => c.Result.Level != HealthLevel.New).ToList();
            if (companies.Count == 0 || judged.Count == 0)
            {
                var age = s.FirstCompanyCreatedAtUtc is DateTime f ? (int)(nowUtc - f).TotalDays : (int?)null;
                if (companies.Count == 0)
                {
                    level = HealthLevel.New;
                    reasons.Add("No companies created yet");
                }
                else
                {
                    level = HealthLevel.New;
                    reasons.Add(age is int a
                        ? $"All {companies.Count} companies are new ({a} days since first company); insufficient history"
                        : "All companies are new; insufficient history");
                }
            }
            else
            {
                var healthy = judged.Count(c => c.Result.Level == HealthLevel.Healthy);
                var needsAttention = judged.Count(c => c.Result.Level == HealthLevel.NeedsAttention);
                var atRisk = judged.Where(c => c.Result.Level == HealthLevel.AtRisk).ToList();
                var inactive = judged.Where(c => c.Result.Level == HealthLevel.Inactive).ToList();

                if (atRisk.Count == 0 && inactive.Count == 0)
                {
                    if (needsAttention > 0)
                    {
                        level = HealthLevel.NeedsAttention;
                        reasons.Add($"{needsAttention} of {judged.Count} companies need attention");
                    }
                    else
                    {
                        level = HealthLevel.Healthy;
                        reasons.Add($"All {judged.Count} active compan{(judged.Count == 1 ? "y is" : "ies are")} healthy");
                    }
                }
                else if (healthy > 0 || needsAttention > 0)
                {
                    // Mixed: some companies fine, some struggling — the org needs a look,
                    // but is not itself At Risk/Inactive (spec section 5).
                    level = HealthLevel.NeedsAttention;
                    var troubled = atRisk.Concat(inactive).Select(c => c.Input.CompanyName).ToList();
                    reasons.Add($"{healthy + needsAttention} of {judged.Count} companies active, but {troubled.Count} struggling: {string.Join(", ", troubled)}");
                }
                else if (atRisk.Count > 0)
                {
                    level = HealthLevel.AtRisk;
                    reasons.Add(inactive.Count > 0
                        ? $"All companies at risk or inactive ({atRisk.Count} at risk, {inactive.Count} inactive)"
                        : $"All {atRisk.Count} compan{(atRisk.Count == 1 ? "y" : "ies")} at risk");
                }
                else
                {
                    level = HealthLevel.Inactive;
                    reasons.Add($"All {inactive.Count} compan{(inactive.Count == 1 ? "y" : "ies")} inactive");
                }
            }

            // ---- billing overlays (escalate only) ----
            if (s.HasPastDueInvoice)
            {
                level = Max(level, HealthLevel.AtRisk);
                reasons.Add("Has a past-due invoice");
            }
            if (s.PaymentFailedRecently)
            {
                level = Max(level, HealthLevel.NeedsAttention);
                reasons.Add("A payment failed in the last 7 days");
            }
            if (s.SubscriptionStatus == "Trial" && s.TrialEndUtc is DateTime te && te > nowUtc)
            {
                var daysLeft = (int)Math.Ceiling((te - nowUtc).TotalDays);
                if (daysLeft <= o.TrialEndingSoonDays)
                {
                    level = Max(level, HealthLevel.NeedsAttention);
                    reasons.Add(s.Meaningful30d >= o.HighEngagementMin30d
                        ? $"Highly engaged trial ends in {daysLeft} day{(daysLeft == 1 ? "" : "s")} — sales opportunity"
                        : $"Trial ends in {daysLeft} day{(daysLeft == 1 ? "" : "s")} with low engagement and no payment set up");
                }
            }

            return new HealthResult(level, reasons);
        }

        private static HealthLevel Max(HealthLevel a, HealthLevel b) => a >= b ? a : b;
    }
}
