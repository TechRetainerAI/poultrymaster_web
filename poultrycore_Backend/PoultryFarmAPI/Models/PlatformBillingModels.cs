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
        /// <summary>Resolved | PricingNotConfigured | CustomPrice | Grandfathered | Exempt.</summary>
        public string PricingStatus { get; set; } = string.Empty;
        public string ParticipationStatus { get; set; } = "Active";
        public long? EvaluationId { get; set; }
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
    }

    public class BillingSummaryModel
    {
        public BillingAccountModel Account { get; set; } = new();
        public List<CompanyBillingRowModel> Companies { get; set; } = new();
        public BillPreviewModel Preview { get; set; } = new();
        /// <summary>False while the master enforcement switch is off — nothing is ever restricted.</summary>
        public bool EnforcementEnabled { get; set; }
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
        public decimal Balance { get; set; }
        public string Status { get; set; } = string.Empty;
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
