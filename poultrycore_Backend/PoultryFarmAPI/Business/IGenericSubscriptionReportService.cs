using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    /// <summary>
    /// The read side of the Generic subscription business (migration 250): the
    /// dashboard, and the reports that are not already served by an existing
    /// function.
    ///
    /// Six of the twelve reports the spec lists are answered by functions that
    /// already exist -- customer payments, unpaid customers, customer balances,
    /// supplier balances, cash flow and the P&amp;L -- and are served by
    /// GenericBalancesController and GenericReportController. They are
    /// deliberately not duplicated here; only the subscription-income split the
    /// P&amp;L page needs on top is new.
    /// </summary>
    public interface IGenericSubscriptionReportService
    {
        /// <summary>Every panel of the subscription dashboard, for one month.</summary>
        Task<GenericSubDashboard> GetDashboardAsync(string farmId, DateTime? asOf);

        /// <summary>Active / new / lost MRR per month.</summary>
        Task<List<GenericMrrRow>> GetMrrAsync(string farmId, DateTime fromDate, DateTime toDate);

        /// <summary>Subscription revenue by month, by plan and by customer.</summary>
        Task<GenericSubRevenueReport> GetSubscriptionRevenueAsync(string farmId, DateTime fromDate, DateTime toDate);

        /// <summary>Recurring income vs everything else, for the P&amp;L page.</summary>
        Task<GenericIncomeSplit> GetIncomeSplitAsync(string farmId, DateTime fromDate, DateTime toDate);

        /// <summary>Expenses by category, by supplier, and the monthly trend.</summary>
        Task<GenericExpenseReport> GetExpenseReportAsync(string farmId, DateTime fromDate, DateTime toDate);

        /// <summary>
        /// Hosting / cloud cost against revenue. Null categoryIds uses the
        /// suggested categories; an EMPTY array means none were chosen.
        /// </summary>
        Task<GenericHostingCostReport> GetHostingCostAsync(
            string farmId, DateTime fromDate, DateTime toDate, int[]? categoryIds);

        /// <summary>Labour cost by person, by month and by role.</summary>
        Task<GenericStaffCostReport> GetStaffCostAsync(string farmId, DateTime fromDate, DateTime toDate);

        /// <summary>How many customers cover the monthly cost base.</summary>
        Task<GenericBreakEven> GetBreakEvenAsync(string farmId, DateTime? asOf, int months);
    }
}
