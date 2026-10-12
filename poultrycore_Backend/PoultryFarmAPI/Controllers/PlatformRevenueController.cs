// PROMPT 6: revenue intelligence for VisibilityCore leadership. Financial
// metrics are gated like the rest of the cross-tenant admin surface —
// SystemAdmin / PlatformOwner only, enforced server-side. Everything is
// read-time aggregation of the authoritative billing tables (plus the monthly
// MRR snapshot for movement); nothing here writes invoices or payments.

using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/PlatformRevenue")]
    [Authorize(Roles = "SystemAdmin,PlatformOwner,BillingAdmin")]
    public class PlatformRevenueController : ControllerBase
    {
        private readonly IPlatformRevenueService _svc;

        public PlatformRevenueController(IPlatformRevenueService svc) => _svc = svc;

        /// <summary>The full revenue intelligence payload: per-currency MRR/ARR/ARPO
        /// blocks, movement, vertical and market splits, per-organization rows
        /// (incl. Revenue At Risk), trials, renewals, discounts, credits and
        /// billing exceptions. Also refreshes this month's MRR snapshots and the
        /// attention queue's RevenueAtRisk values.</summary>
        [HttpGet("dashboard")]
        public async Task<IActionResult> Dashboard() => Ok(await _svc.GetDashboardAsync());
    }
}
