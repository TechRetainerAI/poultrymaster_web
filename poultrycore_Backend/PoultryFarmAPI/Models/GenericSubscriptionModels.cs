using System.ComponentModel.DataAnnotations;

namespace PoultryFarmAPIWeb.Models
{
    // Shapes for the Generic company's business templates, service plans,
    // subscriptions and billing runs (migrations 242-243).
    //
    // A "business template" is what the owner picked at company creation --
    // SaaS, Gym, School, Cleaning -- and it never changes the company's
    // Farms.Type, which stays "Generic". It drives labels, which menu items
    // appear, and what gets seeded.

    /// <summary>The MODULE BUNDLE -- which workflows exist at all.</summary>
    public static class GenericBusinessTemplates
    {
        public const string SubscriptionServiceBusiness = "SubscriptionServiceBusiness";
        public const string RetailBusiness = "RetailBusiness";
        public const string GeneralBusiness = "GeneralBusiness";
    }

    /// <summary>
    /// The VOCABULARY and the SEEDS -- what things are called and what
    /// categories, accounts and starter plans a brand new company gets. A gym
    /// and a SaaS company run the same bundle and differ only here.
    /// </summary>
    public static class GenericIndustryTemplates
    {
        public const string SaaS = "SaaS";
        public const string Gym = "Gym";
        public const string School = "School";
        public const string CleaningService = "CleaningService";
        public const string SecurityService = "SecurityService";
        public const string Agency = "Agency";
        public const string RetainerBusiness = "RetainerBusiness";
        public const string MembershipBusiness = "MembershipBusiness";
        public const string Retail = "Retail";
        public const string Other = "Other";
    }

    public static class BillingFrequencies
    {
        public const string Weekly = "Weekly";
        public const string Monthly = "Monthly";
        public const string Quarterly = "Quarterly";
        public const string Termly = "Termly";
        public const string SemiAnnual = "SemiAnnual";
        public const string Annual = "Annual";
        public const string OneTime = "OneTime";
    }

    public static class SubscriptionStatuses
    {
        public const string Draft = "Draft";
        public const string Active = "Active";
        public const string Paused = "Paused";
        public const string Overdue = "Overdue";
        public const string Suspended = "Suspended";
        public const string Cancelled = "Cancelled";
        public const string Expired = "Expired";
    }

    /// <summary>
    /// Which modules this company's menus and pages show. Never null: the getter
    /// synthesises a default row when a company has none, the same way
    /// spFarmProductionSettings_Get does, so no caller handles a missing row.
    /// </summary>
    public class GenericModuleSettings
    {
        public string FarmId { get; set; } = string.Empty;
        public bool EnableProducts { get; set; }
        public bool EnableInventory { get; set; }
        public bool EnableStockAdjustments { get; set; }
        public bool EnableInternalUse { get; set; }
        public bool EnablePurchases { get; set; }
        public bool EnableSubscriptions { get; set; }
        public bool EnableInvoices { get; set; }
        public bool EnableCustomerBalances { get; set; }
        public bool EnableStaffPayments { get; set; }
        public bool EnableCashAccounts { get; set; }
        // 251. Both default TRUE: Recurring Expenses shipped ungated in 249 and
        // Supplier Balances was shown to anyone with Purchases on, so a company
        // that has never opened the settings page loses no menu item.
        public bool EnableRecurringExpenses { get; set; } = true;
        public bool EnableSupplierBalances { get; set; } = true;
    }

    /// <summary>
    /// Company-level settings for a Generic business (migration 251).
    ///
    /// Not every field is read by something yet -- the migration's column
    /// comments say which, and the settings page shows only the ones that are.
    /// They exist here because the DTO has to round-trip whatever the table
    /// holds; a save that dropped the unread fields would blank them.
    /// </summary>
    public class GenericBusinessSettings
    {
        public string FarmId { get; set; } = string.Empty;

        // ---- subscription / billing ----------------------------------------
        public string DefaultBillingFrequency { get; set; } = "Monthly";
        public int DefaultPaymentDueDays { get; set; }
        public int DefaultGracePeriodDays { get; set; }
        public bool AutoGenerateInvoices { get; set; } = true;
        /// <summary>The billing run approves what it raises. FALSE since 243.</summary>
        public bool AutoPostInvoices { get; set; }
        public bool AutoMarkOverdueInvoices { get; set; } = true;
        public bool AllowOverpayments { get; set; }
        public bool AllowCustomerCredits { get; set; }
        public int? DefaultRevenueCategoryId { get; set; }
        public int? DefaultCashAccountForPayments { get; set; }

        // ---- expenses -------------------------------------------------------
        public int? DefaultExpenseCashAccountId { get; set; }
        public decimal? RequireReceiptAboveAmount { get; set; }
        public decimal? RequireApprovalAboveAmount { get; set; }
        public bool AllowUnpaidExpenses { get; set; } = true;
        public bool AllowPartialExpensePayments { get; set; } = true;

        // ---- cash -----------------------------------------------------------
        public bool RequireCashAccountForEveryPayment { get; set; } = true;
        public bool AllowNegativeCashAccounts { get; set; }
        public bool RequireReconciliationWarning { get; set; } = true;
        public string ReconciliationReminderFrequency { get; set; } = "Monthly";

        // ---- dashboard cards ------------------------------------------------
        public bool ShowMrr { get; set; } = true;
        public bool ShowBurnRate { get; set; } = true;
        public bool ShowBreakEvenCustomers { get; set; } = true;
        public bool ShowCustomerBalances { get; set; } = true;
        public bool ShowSupplierBalances { get; set; } = true;
        public bool ShowCalculatedCashAtHand { get; set; } = true;
        public bool ShowInventoryCards { get; set; }
    }

    /// <summary>
    /// Which template a company is on. Both fields are null for a Generic
    /// company that predates templates, which behaves exactly as it does today.
    /// </summary>
    public class GenericBusinessTemplateInfo
    {
        public string FarmId { get; set; } = string.Empty;
        public string? GenericBusinessTemplate { get; set; }
        public string? GenericIndustryTemplate { get; set; }
    }

    public class ApplyBusinessTemplateRequest
    {
        /// <summary>Included in the body on purpose: the audit filter's farmId
        /// cascade reads query string or body, not the {farmId} route segment.</summary>
        public string FarmId { get; set; } = string.Empty;
        [Required] public string BusinessTemplate { get; set; } = string.Empty;
        [Required] public string IndustryTemplate { get; set; } = string.Empty;
        public string? CreatedBy { get; set; }
    }

    /// <summary>
    /// A service plan. A plan IS a genericservices row -- the two plan columns
    /// were added to it rather than to a new table, so a plan sells through the
    /// existing sale-item path (ItemType = 'Service') with no special casing.
    /// </summary>
    public class GenericServicePlanRow
    {
        public int GenericServiceId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public string ServiceName { get; set; } = string.Empty;
        public int? GenericServiceCategoryId { get; set; }
        public string? CategoryName { get; set; }
        public decimal DefaultPrice { get; set; }
        /// <summary>Recurring | OneOff. Null on a plain service that is not a plan.</summary>
        public string? PlanType { get; set; }
        public string? BillingFrequency { get; set; }
        public string? Notes { get; set; }
        public bool IsActive { get; set; }
        public int ActiveSubscriptions { get; set; }
        /// <summary>What the active subscriptions on this plan bill per period.</summary>
        public decimal MonthlyValue { get; set; }
    }

    public class SetServicePlanRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public string? PlanType { get; set; }
        public string? BillingFrequency { get; set; }
    }

    public class GenericSubscriptionRow
    {
        public int GenericSubscriptionId { get; set; }
        public string FarmId { get; set; } = string.Empty;
        public int GenericCustomerId { get; set; }
        public string? CustomerName { get; set; }
        public int GenericServiceId { get; set; }
        public string? ServiceName { get; set; }
        public string? SubscriptionNumber { get; set; }
        public DateTime StartDate { get; set; }
        public DateTime? EndDate { get; set; }
        public string BillingFrequency { get; set; } = string.Empty;
        public decimal BillingAmount { get; set; }
        public decimal DiscountAmount { get; set; }
        public decimal TaxAmount { get; set; }
        public decimal TotalBillingAmount { get; set; }
        public DateTime? NextBillingDate { get; set; }
        public DateTime? LastBillingDate { get; set; }
        public int PaymentDueDays { get; set; }
        public bool AutoGenerateInvoice { get; set; }
        public string? DefaultPaymentMethod { get; set; }
        public int? DefaultCashAccountId { get; set; }
        public string Status { get; set; } = string.Empty;
        public string? Notes { get; set; }
        /// <summary>Approved invoices for this subscription that still carry a balance.</summary>
        public int OpenInvoiceCount { get; set; }
        public decimal OpenBalance { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime? CreatedAt { get; set; }
    }

    public class CreateSubscriptionRequest
    {
        public string FarmId { get; set; } = string.Empty;
        [Range(1, int.MaxValue, ErrorMessage = "A customer is required.")]
        public int GenericCustomerId { get; set; }
        [Range(1, int.MaxValue, ErrorMessage = "A plan is required.")]
        public int GenericServiceId { get; set; }
        [Required] public DateTime StartDate { get; set; }
        public DateTime? EndDate { get; set; }
        [Required] public string BillingFrequency { get; set; } = BillingFrequencies.Monthly;
        [Range(0.01, double.MaxValue, ErrorMessage = "The billing amount must be greater than 0.")]
        public decimal BillingAmount { get; set; }
        public decimal DiscountAmount { get; set; }
        public decimal TaxAmount { get; set; }
        public int PaymentDueDays { get; set; }
        public bool AutoGenerateInvoice { get; set; } = true;
        public string? DefaultPaymentMethod { get; set; }
        public int? DefaultCashAccountId { get; set; }
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
    }

    public class SetSubscriptionStatusRequest
    {
        public string FarmId { get; set; } = string.Empty;
        [Required] public string Status { get; set; } = string.Empty;
        /// <summary>Required by the SP when cancelling. Optional otherwise.</summary>
        public string? Reason { get; set; }
        public string? By { get; set; }
    }

    /// <summary>
    /// A genericsales row read as an invoice. Same table the Sales page shows;
    /// this shape adds the due date, the subscription it came from and whether
    /// it is overdue.
    /// </summary>
    public class GenericInvoiceRow
    {
        public int GenericSaleId { get; set; }
        public string? ReceiptNumber { get; set; }
        public DateTime SaleDate { get; set; }
        public DateTime? DueDate { get; set; }
        public int? GenericCustomerId { get; set; }
        public string? CustomerName { get; set; }
        public int? GenericSubscriptionId { get; set; }
        public string? SubscriptionNumber { get; set; }
        public DateTime? BillingPeriodStart { get; set; }
        public DateTime? BillingPeriodEnd { get; set; }
        public decimal TotalAmount { get; set; }
        public decimal AmountPaid { get; set; }
        public decimal Balance { get; set; }
        public string PaymentStatus { get; set; } = string.Empty;
        /// <summary>Draft | Approved | Cancelled | Refunded.</summary>
        public string Status { get; set; } = string.Empty;
        /// <summary>Only an approved invoice with a balance can be overdue.</summary>
        public bool IsOverdue { get; set; }
        public int AgeDays { get; set; }
        public string? Notes { get; set; }
        public DateTime? CreatedAt { get; set; }
    }

    /// <summary>One line of the billing preview: what generating now would raise.</summary>
    public class BillingPreviewRow
    {
        public int GenericSubscriptionId { get; set; }
        public string? SubscriptionNumber { get; set; }
        public int GenericCustomerId { get; set; }
        public string? CustomerName { get; set; }
        public string? ServiceName { get; set; }
        public string BillingFrequency { get; set; } = string.Empty;
        public DateTime BillingPeriodStart { get; set; }
        public DateTime BillingPeriodEnd { get; set; }
        public DateTime DueDate { get; set; }
        public decimal InvoiceAmount { get; set; }
        /// <summary>True when an invoice for this exact period already exists,
        /// so generating will skip it rather than bill the customer twice.</summary>
        public bool AlreadyBilled { get; set; }
    }

    public class BillingRunRow
    {
        public int GenericBillingRunId { get; set; }
        public DateTime BillingRunDate { get; set; }
        public DateTime AsOfDate { get; set; }
        public int TotalSubscriptionsChecked { get; set; }
        public int TotalInvoicesGenerated { get; set; }
        public int TotalSkipped { get; set; }
        public string Status { get; set; } = string.Empty;
        public string? Notes { get; set; }
        public string? CreatedBy { get; set; }
    }

    public class GenerateBillingRequest
    {
        public string FarmId { get; set; } = string.Empty;
        /// <summary>Bill everything due up to this date. Defaults to today.</summary>
        public DateTime? AsOf { get; set; }
        public string? CreatedBy { get; set; }
    }
}
