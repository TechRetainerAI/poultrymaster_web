// PROMPT 6: revenue intelligence DTOs. Amounts are ALWAYS grouped by currency
// (per billing market) — the API never sums GHS + NGN + USD into one number
// and no FX conversion is invented.

namespace PoultryFarmAPIWeb.Models
{
    public class MoneyByCurrencyDto
    {
        public string CurrencyCode { get; set; } = "";
        public decimal Amount { get; set; }
    }

    public class RevenueCurrencyBlockDto
    {
        public string CurrencyCode { get; set; } = "";
        public string MarketCode { get; set; } = "";
        public decimal Mrr { get; set; }                 // net recurring, pre-tax
        public decimal GrossMrr { get; set; }
        public decimal Arr { get; set; }                 // 12 × MRR
        public int PayingOrganizations { get; set; }
        public int PayingCompanies { get; set; }
        public decimal? Arpo { get; set; }               // MRR / paying orgs
        public decimal? Arpc { get; set; }               // MRR / paying companies
        public decimal NewMrr { get; set; }              // vs previous month snapshot
        public decimal ExpansionMrr { get; set; }
        public decimal ContractionMrr { get; set; }
        public decimal ChurnedMrr { get; set; }
        public decimal PastDueAmount { get; set; }       // open invoice balances past due
        public decimal FailedPaymentsAmount30d { get; set; }
        public int FailedPaymentsCount30d { get; set; }
        public decimal DiscountsGrantedThisMonth { get; set; }   // invoice discountamount
        public decimal CreditsIssuedOutstanding { get; set; }
        public decimal TrialPotentialMrr { get; set; }   // what current trials would pay (clearly not revenue)
    }

    public class OrgRevenueRowDto
    {
        public string OrganizationId { get; set; } = "";
        public string? OrganizationName { get; set; }
        public string CurrencyCode { get; set; } = "";
        public string MarketCode { get; set; } = "";
        public string AccountStatus { get; set; } = "Trial";
        public string BillingCycle { get; set; } = "monthly";
        public decimal GrossMrr { get; set; }
        public decimal NetMrr { get; set; }
        public int PayingCompanies { get; set; }
        public string? Health { get; set; }
        public DateTime? LastMeaningfulActivityAtUtc { get; set; }
        public double? ActivityTrendPercent { get; set; }
        /// <summary>Net MRR counted as at risk (health At Risk / Inactive, or past due).</summary>
        public decimal RevenueAtRisk { get; set; }
        public List<string> RiskReasons { get; set; } = new();
        public DateTime? NextRenewalUtc { get; set; }
    }

    public class VerticalRevenueRowDto
    {
        public string CompanyFamily { get; set; } = "";
        public string? BusinessTemplate { get; set; }
        public string CurrencyCode { get; set; } = "";
        public decimal Mrr { get; set; }
        public int Companies { get; set; }
        public decimal? AveragePrice { get; set; }
        public double ShareOfCurrencyMrr { get; set; }   // % within the same currency only
    }

    public class TrialIntelligenceDto
    {
        public int OrganizationsInTrial { get; set; }
        public int TrialEnding7d { get; set; }
        public int TrialEnding30d { get; set; }
        public int ConvertedThisMonth { get; set; }
        /// <summary>Converted = at least one successful payment; rate over all accounts that started a trial.</summary>
        public double? TrialToPaidConversionRate { get; set; }
        public double? AverageDaysToConversion { get; set; }
        public List<OrgRevenueRowDto> HighEngagementTrialsNotPaid { get; set; } = new();
        public List<OrgRevenueRowDto> LowEngagementTrialsEndingSoon { get; set; } = new();
    }

    public class RenewalRowDto
    {
        public string OrganizationId { get; set; } = "";
        public string? OrganizationName { get; set; }
        public DateTime RenewalAtUtc { get; set; }
        public string BillingCycle { get; set; } = "monthly";
        public decimal Amount { get; set; }              // expected recurring charge for the cycle
        public string CurrencyCode { get; set; } = "";
        public string? Health { get; set; }
        public string PaymentState { get; set; } = "";   // account status
    }

    public class DiscountIntelligenceDto
    {
        public List<MoneyByCurrencyDto> GrantedThisMonth { get; set; } = new();     // invoice discountamount
        public List<MoneyByCurrencyDto> GrantedLast90d { get; set; } = new();
        public int ActiveAutomaticMultiCompany { get; set; }   // accounts currently earning the auto discount
        public int ActivePromotionalDiscounts { get; set; }
        public int ActiveCustomerSpecificDiscounts { get; set; }
        public List<AccountDiscountRowDto> LargestDiscountAccounts { get; set; } = new();
        public List<AccountDiscountRowDto> ExpiringDiscounts { get; set; } = new();
    }

    public class AccountDiscountRowDto
    {
        public string OrganizationId { get; set; } = "";
        public string? OrganizationName { get; set; }
        public string Name { get; set; } = "";
        public string DiscountType { get; set; } = "";
        public decimal Value { get; set; }
        public decimal? LastInvoicePercent { get; set; }
        public DateTime? EndDate { get; set; }
    }

    public class CreditIntelligenceDto
    {
        public List<MoneyByCurrencyDto> Issued { get; set; } = new();
        public List<MoneyByCurrencyDto> Consumed { get; set; } = new();
        public List<MoneyByCurrencyDto> Outstanding { get; set; } = new();
        public List<CreditReasonRowDto> ByReason { get; set; } = new();
    }

    public class CreditReasonRowDto
    {
        public string Reason { get; set; } = "";
        public string CurrencyCode { get; set; } = "";
        public decimal Amount { get; set; }
        public int Count { get; set; }
    }

    public class BillingExceptionRowDto
    {
        public string Kind { get; set; } = "";          // PricingNotConfigured|ScaleSetupRequired|PastDueInvoice|MissingProviderLink|MarketChangePending
        public string OrganizationId { get; set; } = "";
        public string? OrganizationName { get; set; }
        public string? CompanyId { get; set; }
        public string? CompanyName { get; set; }
        public string Detail { get; set; } = "";
    }

    public class RevenueDashboardDto
    {
        /// <summary>MRR rule: billable companies' evaluated monthly price; annual
        /// accounts normalized as AnnualPrice/12; net = after discounts, pre-tax;
        /// account credits are payment instruments, never discounts or MRR; no
        /// cross-currency totals, no invented FX.</summary>
        public string MrrDefinition { get; set; } =
            "Net MRR = evaluated recurring monthly price of billable companies minus discounts, pre-tax; annual cycles counted as annual/12; credits excluded; reported per currency.";
        public List<RevenueCurrencyBlockDto> ByCurrency { get; set; } = new();
        public List<VerticalRevenueRowDto> ByVertical { get; set; } = new();
        public List<OrgRevenueRowDto> Organizations { get; set; } = new();
        public List<OrgRevenueRowDto> RevenueAtRisk { get; set; } = new();
        public TrialIntelligenceDto Trials { get; set; } = new();
        public List<RenewalRowDto> Renewals30d { get; set; } = new();
        public DiscountIntelligenceDto Discounts { get; set; } = new();
        public CreditIntelligenceDto Credits { get; set; } = new();
        public List<BillingExceptionRowDto> Exceptions { get; set; } = new();
        public List<MoneyByCurrencyDto> RecoveredPayments30d { get; set; } = new();  // paid after due date
        public DateTime GeneratedAtUtc { get; set; } = DateTime.UtcNow;
    }
}
