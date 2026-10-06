// Admin-app DTOs (ADMIN APP spec 2026-10-05): the shapes the platform admin
// console reads and writes. Customer-facing models stay in
// PlatformBillingModels.cs.

using System;
using System.Collections.Generic;

namespace PoultryFarmAPIWeb.Models
{
    public class AdminOrgListItemModel
    {
        public long AccountId { get; set; }
        public string OwnerUserId { get; set; } = string.Empty;
        public string? OwnerEmail { get; set; }
        public string? OwnerName { get; set; }
        public string? OrgCode { get; set; }
        public string MarketCode { get; set; } = string.Empty;
        public string CurrencyCode { get; set; } = string.Empty;
        public string Status { get; set; } = string.Empty;
        public string BillingCycle { get; set; } = string.Empty;
        public int CompanyCount { get; set; }
    }

    /// <summary>Spec 31/32 — the support inspector for one organization.</summary>
    public class AdminOrgInspectorModel
    {
        public BillingAccountModel Account { get; set; } = new();
        public string? OwnerEmail { get; set; }
        public string? OwnerName { get; set; }
        public List<AdminCompanyModel> Companies { get; set; } = new();
        public List<AdminDiscountModel> Discounts { get; set; } = new();
        public List<AdminCreditModel> Credits { get; set; } = new();
        public BillPreviewModel Preview { get; set; } = new();
        public List<PlatformInvoiceModel> Invoices { get; set; } = new();
        public List<PlatformPaymentModel> Payments { get; set; } = new();
    }

    public class AdminCompanyModel
    {
        public string FarmId { get; set; } = string.Empty;
        public string CompanyName { get; set; } = string.Empty;
        public string CompanyFamily { get; set; } = string.Empty;
        public string BusinessType { get; set; } = string.Empty;
        public string BillingProfileCode { get; set; } = string.Empty;
        public string BillingProfileName { get; set; } = string.Empty;
        public string MetricType { get; set; } = string.Empty;
        public decimal MetricValue { get; set; }
        /// <summary>"Operational data (read-only)" or "Configured scale" — spec 7/32.</summary>
        public string MetricSource { get; set; } = string.Empty;
        public string? TierCode { get; set; }
        public string? TierName { get; set; }
        public decimal? MonthlyAmount { get; set; }
        public decimal? AnnualPrice { get; set; }
        public decimal? CustomPrice { get; set; }
        public decimal? GrandfatheredPrice { get; set; }
        public string ParticipationStatus { get; set; } = string.Empty;
        public string PricingStatus { get; set; } = string.Empty;
    }

    public class AdminDiscountModel
    {
        public long Id { get; set; }
        public string Name { get; set; } = string.Empty;
        public string DiscountType { get; set; } = string.Empty;
        public decimal Value { get; set; }
        public string Scope { get; set; } = string.Empty;
        public string? FarmId { get; set; }
        public string? ProfileCode { get; set; }
        public DateTime StartDate { get; set; }
        public DateTime? EndDate { get; set; }
        public int? DurationPeriods { get; set; }
        public int AppliedCount { get; set; }
        public int? RemainingPeriods { get; set; }
        public bool Stackable { get; set; }
        public int Priority { get; set; }
        public string Reason { get; set; } = string.Empty;
        public string? InternalNotes { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime CreatedAtUtc { get; set; }
        public string? ApprovedBy { get; set; }
        public string? RevokedBy { get; set; }
        public DateTime? RevokedAtUtc { get; set; }
        public bool Active { get; set; }
    }

    public class AdminCreditModel
    {
        public long Id { get; set; }
        public decimal Amount { get; set; }
        public string CurrencyCode { get; set; } = string.Empty;
        public decimal Used { get; set; }
        public decimal Remaining { get; set; }
        public string Reason { get; set; } = string.Empty;
        public string? Reference { get; set; }
        public DateTime? ExpiresAtUtc { get; set; }
        public string? IssuedBy { get; set; }
        public DateTime IssuedAtUtc { get; set; }
        public string? RevokedBy { get; set; }
        public List<string> AppliedInvoices { get; set; } = new();
    }

    public class AdminPromotionModel
    {
        public long Id { get; set; }
        public string Code { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public string DiscountType { get; set; } = string.Empty;
        public decimal Value { get; set; }
        public int DurationPeriods { get; set; }
        public string? MarketCode { get; set; }
        public bool NewCustomersOnly { get; set; }
        public DateTime StartDate { get; set; }
        public DateTime? EndDate { get; set; }
        public int? MaxRedemptions { get; set; }
        public int Redemptions { get; set; }
        public bool Stackable { get; set; }
        public bool Active { get; set; }
    }

    public class AdminTierRuleModel
    {
        public long Id { get; set; }
        public string ProfileCode { get; set; } = string.Empty;
        public string TierCode { get; set; } = string.Empty;
        public decimal MinValue { get; set; }
        public decimal? MaxValue { get; set; }
        public DateTime EffectiveFrom { get; set; }
        public DateTime? EffectiveTo { get; set; }
        public bool Active { get; set; }
    }

    public class AdminPresentationModel
    {
        public long Id { get; set; }
        public string BillingProfileCode { get; set; } = string.Empty;
        public string? BusinessTemplateCode { get; set; }
        public string DisplayName { get; set; } = string.Empty;
        public string? ShortDescription { get; set; }
        public string? MetricDisplayName { get; set; }
        public string? MetricSingular { get; set; }
        public string? MetricPlural { get; set; }
        public int SortOrder { get; set; }
        public bool Active { get; set; }
        public List<AdminTierPresentationModel> Tiers { get; set; } = new();
    }

    public class AdminTierPresentationModel
    {
        public string TierCode { get; set; } = string.Empty;
        public string? Headline { get; set; }
        public string? Description { get; set; }
        /// <summary>One bullet per line.</summary>
        public string? FeatureBullets { get; set; }
        public string? BadgeText { get; set; }
        public bool IsMostPopular { get; set; }
        public string? CtaText { get; set; }
        public int DisplayOrder { get; set; }
    }

    /// <summary>Spec 34/35/36 — the three readiness dashboards in one payload.</summary>
    public class AdminCoverageModel
    {
        public List<string> PricingWarnings { get; set; } = new();
        public List<AdminPriceCoverageRow> PriceCoverage { get; set; } = new();
        public List<string> PresentationStatus { get; set; } = new();
    }

    public class AdminPriceCoverageRow
    {
        public string MarketCode { get; set; } = string.Empty;
        public string ProfileCode { get; set; } = string.Empty;
        public string TierCode { get; set; } = string.Empty;
        public bool HasMonthly { get; set; }
        public bool HasAnnual { get; set; }
    }

    public class AdminEventModel
    {
        public long Id { get; set; }
        public DateTime AtUtc { get; set; }
        public string EventType { get; set; } = string.Empty;
        public long? AccountId { get; set; }
        public string? FarmId { get; set; }
        public string? OldValue { get; set; }
        public string? NewValue { get; set; }
        public string? Actor { get; set; }
        public string? Notes { get; set; }
    }

    // ---------------- request bodies ----------------

    public class AdminDiscountBody
    {
        public string UserId { get; set; } = string.Empty;          // acting admin
        public string OwnerUserId { get; set; } = string.Empty;     // target organization
        public string Name { get; set; } = string.Empty;
        public string DiscountType { get; set; } = "Percentage";
        public decimal Value { get; set; }
        public string Scope { get; set; } = "Organization";
        public string? FarmId { get; set; }
        public string? ProfileCode { get; set; }
        public DateTime? StartDate { get; set; }
        public DateTime? EndDate { get; set; }
        public int? DurationPeriods { get; set; }
        public bool Stackable { get; set; } = true;
        public int Priority { get; set; } = 100;
        public string Reason { get; set; } = string.Empty;
        public string? InternalNotes { get; set; }
    }

    public class AdminPromotionBody
    {
        public string UserId { get; set; } = string.Empty;
        public string Code { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public string DiscountType { get; set; } = "Percentage";
        public decimal Value { get; set; }
        public int DurationPeriods { get; set; } = 1;
        public string? MarketCode { get; set; }
        public bool NewCustomersOnly { get; set; }
        public DateTime? StartDate { get; set; }
        public DateTime? EndDate { get; set; }
        public int? MaxRedemptions { get; set; }
        public bool Stackable { get; set; }
    }

    public class AdminCreditBody
    {
        public string UserId { get; set; } = string.Empty;
        public string OwnerUserId { get; set; } = string.Empty;
        public decimal Amount { get; set; }
        public string Reason { get; set; } = string.Empty;
        public string? InternalNotes { get; set; }
        public string? Reference { get; set; }
        public DateTime? ExpiresAtUtc { get; set; }
    }

    public class AdminTierRulesBody
    {
        public string UserId { get; set; } = string.Empty;
        public string ProfileCode { get; set; } = string.Empty;
        public DateTime? EffectiveFrom { get; set; }
        public List<AdminTierRuleRow> Rules { get; set; } = new();
    }
    public class AdminTierRuleRow
    {
        public string TierCode { get; set; } = string.Empty;
        public decimal MinValue { get; set; }
        public decimal? MaxValue { get; set; }
    }

    public class AdminPresentationBody
    {
        public string UserId { get; set; } = string.Empty;
        public string BillingProfileCode { get; set; } = string.Empty;
        public string? BusinessTemplateCode { get; set; }
        public string DisplayName { get; set; } = string.Empty;
        public string? ShortDescription { get; set; }
        public string? MetricDisplayName { get; set; }
        public string? MetricSingular { get; set; }
        public string? MetricPlural { get; set; }
        public int SortOrder { get; set; } = 100;
        public bool Active { get; set; } = true;
        public List<AdminTierPresentationModel> Tiers { get; set; } = new();
    }

    public class AdminContractBody
    {
        public string UserId { get; set; } = string.Empty;
        public string OwnerUserId { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public string? ContractReference { get; set; }
        public string BillingFrequency { get; set; } = "monthly";
        public DateTime? EffectiveFrom { get; set; }
        public DateTime? EffectiveTo { get; set; }
        public string? Notes { get; set; }
        /// <summary>Per-company custom prices the contract fixes (spec 33/37).</summary>
        public List<AdminContractCompanyRow> Companies { get; set; } = new();
    }
    public class AdminContractCompanyRow
    {
        public string FarmId { get; set; } = string.Empty;
        public decimal? CustomMonthlyPrice { get; set; }
    }

    /// <summary>Spec 23 — backend-generated before/after preview for a proposed discount.</summary>
    public class AdminDiscountPreviewModel
    {
        public BillPreviewModel Current { get; set; } = new();
        public BillPreviewModel WithProposed { get; set; } = new();
    }

    // -------- customer-facing presentation payload (spec 11-16) --------

    public class PublicPricingModel
    {
        public string MarketCode { get; set; } = string.Empty;
        public string CurrencyCode { get; set; } = string.Empty;
        public string BillingProfileCode { get; set; } = string.Empty;
        public string? BusinessTemplateCode { get; set; }
        /// <summary>True when the template had no override and the profile default was used (spec 16).</summary>
        public bool UsedFallback { get; set; }
        public string DisplayName { get; set; } = string.Empty;
        public string? ShortDescription { get; set; }
        public string? MetricDisplayName { get; set; }
        public string? MetricSingular { get; set; }
        public string? MetricPlural { get; set; }
        public List<PublicPlanCardModel> Plans { get; set; } = new();
    }

    public class PublicPlanCardModel
    {
        public string TierCode { get; set; } = string.Empty;
        public string TierName { get; set; } = string.Empty;
        public string? Headline { get; set; }
        public List<string> FeatureBullets { get; set; } = new();
        public string? BadgeText { get; set; }
        public bool IsMostPopular { get; set; }
        public string? CtaText { get; set; }
        public decimal? MonthlyPrice { get; set; }
        public decimal? AnnualPrice { get; set; }
        public decimal? MinValue { get; set; }
        public decimal? MaxValue { get; set; }
    }
}
