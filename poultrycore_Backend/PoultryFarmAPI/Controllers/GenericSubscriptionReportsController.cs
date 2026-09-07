using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    /// <summary>
    /// The subscription dashboard and the subscription-business reports
    /// (migration 250).
    ///
    /// Deliberately mounted under the EXISTING reports route -- everything here
    /// is a read of the same company's numbers, and "generic-company/reports"
    /// already maps to the generic.reports permission in IamPermissionMap. A new
    /// route prefix would have landed in the unmapped bucket.
    ///
    /// Six of the spec's twelve reports are not here because they already exist:
    /// customer payments, unpaid customers and customer balances come from
    /// GenericBalancesController, supplier balances likewise, cash flow from
    /// reports/cash-summary and the P&amp;L from reports/period-pnl. This
    /// controller adds the income SPLIT the P&amp;L page needs, not a second P&amp;L.
    /// </summary>
    [ApiController]
    [Route("api/generic-company/{farmId}/reports")]
    public class GenericSubscriptionReportsController : ControllerBase
    {
        private readonly IGenericSubscriptionReportService _reports;
        private readonly IGenericCompanyService _companies;

        public GenericSubscriptionReportsController(
            IGenericSubscriptionReportService reports, IGenericCompanyService companies)
        {
            _reports = reports;
            _companies = companies;
        }

        /// <summary>
        /// Every panel of the subscription dashboard for one month, in one call.
        /// </summary>
        [HttpGet("subscription-dashboard")]
        public async Task<ActionResult<GenericSubDashboard>> SubscriptionDashboard(
            string farmId, [FromQuery] DateTime? asOf)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _reports.GetDashboardAsync(farmId, asOf));
        }

        /// <summary>Active / new / lost MRR per month. Defaults to the last twelve.</summary>
        [HttpGet("mrr")]
        public async Task<ActionResult<IEnumerable<GenericMrrRow>>> Mrr(
            string farmId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            var (from, to) = DefaultRange(fromDate, toDate);
            return Ok(await _reports.GetMrrAsync(farmId, from, to));
        }

        /// <summary>Subscription revenue by month, by plan and by customer.</summary>
        [HttpGet("subscription-revenue")]
        public async Task<ActionResult<GenericSubRevenueReport>> SubscriptionRevenue(
            string farmId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            var (from, to) = DefaultRange(fromDate, toDate);
            return Ok(await _reports.GetSubscriptionRevenueAsync(farmId, from, to));
        }

        /// <summary>
        /// Recurring income vs everything else. Pairs with reports/period-pnl,
        /// which still owns the totals.
        /// </summary>
        [HttpGet("income-split")]
        public async Task<ActionResult<GenericIncomeSplit>> IncomeSplit(
            string farmId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            var (from, to) = DefaultRange(fromDate, toDate);
            return Ok(await _reports.GetIncomeSplitAsync(farmId, from, to));
        }

        /// <summary>Expenses by category, by supplier, and the monthly trend.</summary>
        [HttpGet("expense-report")]
        public async Task<ActionResult<GenericExpenseReport>> ExpenseReport(
            string farmId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            var (from, to) = DefaultRange(fromDate, toDate);
            return Ok(await _reports.GetExpenseReportAsync(farmId, from, to));
        }

        /// <summary>
        /// Hosting / cloud cost against revenue, plus the category list the page
        /// offers as checkboxes.
        ///
        /// Sending categoryIds picks those categories. Sending none of them
        /// falls back to the SUGGESTED categories -- unless useSuggested=false,
        /// which means the owner unticked everything and is a different
        /// question with a different (zero) answer. A query string cannot carry
        /// an empty list, so that third case needs its own flag.
        /// </summary>
        [HttpGet("hosting-cost")]
        public async Task<ActionResult<GenericHostingCostReport>> HostingCost(
            string farmId,
            [FromQuery] DateTime? fromDate,
            [FromQuery] DateTime? toDate,
            [FromQuery] int[]? categoryIds,
            [FromQuery] bool useSuggested = true)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            var (from, to) = DefaultRange(fromDate, toDate);
            var chosen = categoryIds is { Length: > 0 }
                ? categoryIds
                : useSuggested ? null : Array.Empty<int>();
            return Ok(await _reports.GetHostingCostAsync(farmId, from, to, chosen));
        }

        /// <summary>Labour cost by person, by month and by role.</summary>
        [HttpGet("staff-cost")]
        public async Task<ActionResult<GenericStaffCostReport>> StaffCost(
            string farmId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            var (from, to) = DefaultRange(fromDate, toDate);
            return Ok(await _reports.GetStaffCostAsync(farmId, from, to));
        }

        /// <summary>
        /// How many customers cover the monthly cost base. months is how many
        /// COMPLETE months of expenses to average; the current partial month is
        /// never one of them.
        /// </summary>
        [HttpGet("break-even")]
        public async Task<ActionResult<GenericBreakEven>> BreakEven(
            string farmId, [FromQuery] DateTime? asOf, [FromQuery] int months = 3)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _reports.GetBreakEvenAsync(farmId, asOf, Math.Clamp(months, 1, 24)));
        }

        /// <summary>
        /// The last twelve months when the caller gives no range. Reports here
        /// are month-grained, so the default starts at a month boundary rather
        /// than "a year ago today", which would cut the first month in half.
        /// </summary>
        private static (DateTime From, DateTime To) DefaultRange(DateTime? from, DateTime? to)
        {
            var end = (to ?? DateTime.UtcNow).Date;
            var start = from?.Date ?? new DateTime(end.Year, end.Month, 1).AddMonths(-11);
            return (start, end);
        }
    }
}
