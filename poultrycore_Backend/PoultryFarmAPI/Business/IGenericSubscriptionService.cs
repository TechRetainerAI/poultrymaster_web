using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    /// <summary>
    /// Business templates and module visibility (migration 242).
    /// </summary>
    public interface IGenericBusinessTemplateService
    {
        Task<GenericBusinessTemplateInfo> GetTemplate(string farmId);
        Task<GenericModuleSettings> GetModuleSettings(string farmId);
        Task<GenericModuleSettings> SaveModuleSettings(GenericModuleSettings s);

        /// <summary>Company policy and defaults (migration 251). Never null.</summary>
        Task<GenericBusinessSettings> GetBusinessSettings(string farmId);

        /// <summary>Saves the whole settings object and returns what was stored.</summary>
        Task<GenericBusinessSettings> SaveBusinessSettings(GenericBusinessSettings s);

        Task ApplyTemplate(ApplyBusinessTemplateRequest r);
    }

    /// <summary>
    /// Recurring plans and the subscriptions customers are on (migration 243).
    /// </summary>
    public interface IGenericSubscriptionService
    {
        Task<List<GenericServicePlanRow>> GetPlans(string farmId, bool activeOnly);
        Task<int> SetPlan(int serviceId, SetServicePlanRequest r);
        Task<List<GenericSubscriptionRow>> GetAll(string farmId, string? status);
        Task<int> Create(CreateSubscriptionRequest r);
        Task<int> SetStatus(int subscriptionId, SetSubscriptionStatusRequest r);

        // 499: upgrade/downgrade
        Task<int> ChangePlan(int subscriptionId, ChangePlanRequest r);
        Task<List<PlanChangeRow>> GetPlanChanges(string farmId, int subscriptionId);

        // 499: coupons
        Task<List<CouponRow>> GetCoupons(string farmId, bool activeOnly);
        Task<int> CreateCoupon(CreateCouponRequest r);
        Task DeactivateCoupon(string farmId, int couponId);
        Task<CouponValidationResult> ValidateCoupon(ValidateCouponRequest r);

        // 499: late fees
        Task<List<AppliedLateFeeRow>> ApplyLateFees(string farmId);
        Task WaiveLateFee(string farmId, int feeId, string reason, string? waivedBy);
        Task<List<LateFeeRow>> GetLateFeesBySale(string farmId, int saleId);
    }

    /// <summary>
    /// The billing run: preview what is due, then raise the invoices.
    ///
    /// There is no scheduler anywhere in this codebase -- no AddHostedService,
    /// no Hangfire, no Quartz -- so billing is an explicit, user-triggered state
    /// machine modelled on the payroll run, not a cron job.
    /// </summary>
    public interface IGenericBillingService
    {
        Task<List<BillingPreviewRow>> Preview(string farmId, DateTime? asOf);
        Task<int> Generate(GenerateBillingRequest r);
        Task<List<BillingRunRow>> GetRuns(string farmId);
        Task<List<GenericInvoiceRow>> GetInvoices(
            string farmId, string? status, bool subscriptionOnly, DateTime? from, DateTime? to);
    }
}
