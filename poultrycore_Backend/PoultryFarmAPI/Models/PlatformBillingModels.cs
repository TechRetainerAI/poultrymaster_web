// Platform billing & subscriptions (migration 329) — the Business Office is
// the billing customer; each Company contributes one line to its consolidated
// bill. These models are deliberately provider-neutral: Paystack appears only
// as a provider string and external references, never as the domain itself.

namespace PoultryFarmAPIWeb.Models
{
    /// <summary>The Organization's billing account, one per Business Office owner.</summary>
    public class BillingAccountModel
    {
        public long Id { get; set; }
        public string OwnerUserId { get; set; } = string.Empty;
        public string? OrgCode { get; set; }
        public string MarketCode { get; set; } = "GH";
        public string CurrencyCode { get; set; } = "GHS";
        public string? BillingEmail { get; set; }
        public string? BillingContactName { get; set; }
        public string Status { get; set; } = "Trial";
        public string BillingCycle { get; set; } = "monthly";
        public DateTime? TrialStartUtc { get; set; }
        public DateTime? TrialEndUtc { get; set; }
        public int? TrialDaysLeft { get; set; }
        public string VerificationStatus { get; set; } = "Unverified";
        public DateTime? CurrentPeriodStart { get; set; }
        public DateTime? CurrentPeriodEnd { get; set; }
        public bool CancelAtPeriodEnd { get; set; }
        public string? Provider { get; set; }
        /// <summary>A requested market change waiting for its effective date (spec 3.7).</summary>
        public string? PendingMarketCode { get; set; }
        public DateTime? PendingMarketEffective { get; set; }
    }

    /// <summary>
    /// One company's row on the Business Office billing table: what it is,
    /// how its scale was measured, which tier that qualifies for and what
    /// that costs in the account's market. `PricingStatus` is honest — a
    /// profile with no configured price says PricingNotConfigured rather
    /// than guessing (spec Part 39).
    /// </summary>
    public class CompanyBillingRowModel
    {
        public string FarmId { get; set; } = string.Empty;
        public string CompanyName { get; set; } = string.Empty;
        /// <summary>Poultry | Water | Hotel | Restaurant | Generic.</summary>
        public string CompanyFamily { get; set; } = string.Empty;
        /// <summary>Friendly template for Generic (School, Gym…); family otherwise.</summary>
        public string BusinessType { get; set; } = string.Empty;
        public string BillingProfileCode { get; set; } = string.Empty;
        public string BillingProfileName { get; set; } = string.Empty;
        public string MetricType { get; set; } = string.Empty;
        public decimal MetricValue { get; set; }
        public string? TierCode { get; set; }
        public string? TierName { get; set; }
        public decimal? MonthlyAmount { get; set; }
        public string CurrencyCode { get; set; } = string.Empty;
        /// <summary>Resolved | PricingNotConfigured | ScaleSetupRequired | CustomPrice | Grandfathered | Exempt.</summary>
        public string PricingStatus { get; set; } = string.Empty;
        public string ParticipationStatus { get; set; } = "Active";
        public long? EvaluationId { get; set; }
        /// <summary>Set while the company is inside its own evaluation window (spec 10.3).</summary>
        public DateTime? EvaluationUntilUtc { get; set; }
    }

    /// <summary>"Your operation now qualifies for Growth…" — announced, never a surprise charge (spec 30).</summary>
    public class PendingTierChangeModel
    {
        public string FarmId { get; set; } = string.Empty;
        public string CompanyName { get; set; } = string.Empty;
        public string FromTierName { get; set; } = string.Empty;
        public string ToTierName { get; set; } = string.Empty;
        public DateTime EffectiveDate { get; set; }
    }

    public class MarketChangePreviewModel
    {
        public string MarketCode { get; set; } = string.Empty;
        public string MarketName { get; set; } = string.Empty;
        public string CurrencyCode { get; set; } = string.Empty;
        public bool MarketActive { get; set; }
        public List<CompanyBillingRowModel> Companies { get; set; } = new();
        public BillPreviewModel Preview { get; set; } = new();
    }

    /// <summary>The company-level "Plan &amp; Usage" view (spec 23) — read-only, managed by the Business Office.</summary>
    public class PlanUsageModel
    {
        public string FarmId { get; set; } = string.Empty;
        public string CompanyName { get; set; } = string.Empty;
        public string BillingProfileCode { get; set; } = string.Empty;
        public string MetricType { get; set; } = string.Empty;
        public decimal MetricValue { get; set; }
        public string? TierCode { get; set; }
        public decimal? MonthlyAmount { get; set; }
        public string CurrencyCode { get; set; } = string.Empty;
        public string PricingStatus { get; set; } = string.Empty;
        public DateTime EvaluatedAtUtc { get; set; }
        public string ManagedBy { get; set; } = string.Empty;
    }

    public class EntitlementModel
    {
        public string TierCode { get; set; } = string.Empty;
        public string Capability { get; set; } = string.Empty;
        public bool Enabled { get; set; }
        public decimal? Limit { get; set; }
        /// <summary>Current usage where the platform can measure it (MAX_USERS today); null = not measured.</summary>
        public decimal? Usage { get; set; }
        /// <summary>True when a configured limit is reached — the UI shows an upgrade notice, never a lockout (spec 24).</summary>
        public bool LimitReached { get; set; }
    }

    /// <summary>The consolidated bill preview (spec Part 29) — same engine, no charge.</summary>
    public class BillPreviewModel
    {
        public decimal Subtotal { get; set; }
        public int EligibleCompanyCount { get; set; }
        public decimal DiscountPercent { get; set; }
        public decimal DiscountAmount { get; set; }
        public decimal TaxRate { get; set; }
        public decimal TaxAmount { get; set; }
        public decimal Total { get; set; }
        public string CurrencyCode { get; set; } = string.Empty;
        /// <summary>True when any company is PricingNotConfigured — checkout is blocked.</summary>
        public bool HasUnpricedCompanies { get; set; }
        public DateTime PeriodStart { get; set; }
        public DateTime PeriodEnd { get; set; }
        /// <summary>Every discount that shaped this preview, auto + special (admin-app spec 23).</summary>
        public List<DiscountLineModel> DiscountBreakdown { get; set; } = new();
        /// <summary>Unused account credit that will offset the next invoice (admin-app spec 26/27).</summary>
        public decimal CreditsAvailable { get; set; }
        public decimal EstimatedCreditApplied { get; set; }
        public decimal EstimatedAmountDue { get; set; }
    }

    public class DiscountLineModel
    {
        public long Id { get; set; }               // 0 = the automatic multi-company rule
        public string Name { get; set; } = string.Empty;
        public decimal Amount { get; set; }
    }

    public class BillingSummaryModel
    {
        public BillingAccountModel Account { get; set; } = new();
        public List<CompanyBillingRowModel> Companies { get; set; } = new();
        public BillPreviewModel Preview { get; set; } = new();
        /// <summary>False while the master enforcement switch is off — nothing is ever restricted.</summary>
        public bool EnforcementEnabled { get; set; }
        public List<PendingTierChangeModel> PendingTierChanges { get; set; } = new();
        /// <summary>Customer-safe "why is my bill lower" details (customer-app spec 23-26). Never internal notes.</summary>
        public List<SavingsDetailModel> Savings { get; set; } = new();
    }

    public class SavingsDetailModel
    {
        /// <summary>MultiCompany | Discount | Promotion | Credit.</summary>
        public string Kind { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public string? DiscountType { get; set; }
        public decimal? Value { get; set; }
        public decimal AmountThisPeriod { get; set; }
        public DateTime? EndDate { get; set; }
        public int? RemainingPeriods { get; set; }
        public string? Explanation { get; set; }
    }

    /// <summary>Backend-computed monthly↔annual comparison (customer-app spec 8/9). Display + confirmation only.</summary>
    public class CyclePreviewModel
    {
        public string CurrentCycle { get; set; } = string.Empty;
        public string TargetCycle { get; set; } = string.Empty;
        public BillPreviewModel Current { get; set; } = new();
        public BillPreviewModel Target { get; set; } = new();
        /// <summary>Companies that would be unpriced under the target cycle (e.g. no annual price configured).</summary>
        public List<string> MissingPrices { get; set; } = new();
        public DateTime EffectiveDate { get; set; }
    }

    public class PricingContextModel
    {
        public string BillingProfileCode { get; set; } = string.Empty;
        public string? BusinessTemplateCode { get; set; }
        public string DisplayName { get; set; } = string.Empty;
        public int SortOrder { get; set; }
    }

    public class PlatformInvoiceModel
    {
        public long Id { get; set; }
        public string InvoiceNumber { get; set; } = string.Empty;
        public string CurrencyCode { get; set; } = string.Empty;
        public DateTime PeriodStart { get; set; }
        public DateTime PeriodEnd { get; set; }
        public DateTime IssueDate { get; set; }
        public DateTime DueDate { get; set; }
        public decimal Subtotal { get; set; }
        public decimal DiscountAmount { get; set; }
        public decimal TaxAmount { get; set; }
        public decimal TotalAmount { get; set; }
        public decimal AmountPaid { get; set; }
        public decimal CreditApplied { get; set; }
        public decimal Balance { get; set; }
        public string Status { get; set; } = string.Empty;
        public string? DiscountBreakdown { get; set; }
        public List<PlatformInvoiceLineModel> Lines { get; set; } = new();
    }

    public class PlatformInvoiceLineModel
    {
        public string? FarmId { get; set; }
        public string Description { get; set; } = string.Empty;
        public string? TierCode { get; set; }
        public decimal? MetricValue { get; set; }
        public string? MetricType { get; set; }
        public decimal UnitPrice { get; set; }
        public decimal LineAmount { get; set; }
    }

    public class PlatformPaymentModel
    {
        public long Id { get; set; }
        public string Provider { get; set; } = string.Empty;
        public string? ExternalReference { get; set; }
        public decimal Amount { get; set; }
        public string CurrencyCode { get; set; } = string.Empty;
        public string Status { get; set; } = string.Empty;
        public DateTime? PaymentDateUtc { get; set; }
        public string? InvoiceNumber { get; set; }
        public string? MethodSummary { get; set; }
    }

    public class StartCheckoutRequest
    {
        public string UserId { get; set; } = string.Empty;
        public string SuccessUrl { get; set; } = string.Empty;
        public string FailureUrl { get; set; } = string.Empty;
    }

    public class StartCheckoutResponse
    {
        public bool Success { get; set; }
        public string? CheckoutUrl { get; set; }
        public string? Reference { get; set; }
        public string? InvoiceNumber { get; set; }
        public decimal? Amount { get; set; }
        public string? CurrencyCode { get; set; }
        public string? Message { get; set; }
    }

    /// <summary>"Why this price?" (spec 22.5) — read from the stored evaluation, not recomputed.</summary>
    public class PricingExplainModel
    {
        public string FarmId { get; set; } = string.Empty;
        public string CompanyName { get; set; } = string.Empty;
        public string BillingProfileName { get; set; } = string.Empty;
        public string MetricType { get; set; } = string.Empty;
        public decimal MetricValue { get; set; }
        public string? TierName { get; set; }
        public string MarketName { get; set; } = string.Empty;
        public decimal? MonthlyAmount { get; set; }
        public string CurrencyCode { get; set; } = string.Empty;
        public string PricingStatus { get; set; } = string.Empty;
        public DateTime EvaluatedAtUtc { get; set; }
        /// <summary>The tier above, and what value reaches it — "Next tier" display.</summary>
        public string? NextTierName { get; set; }
        public decimal? NextTierAtValue { get; set; }
    }
}
