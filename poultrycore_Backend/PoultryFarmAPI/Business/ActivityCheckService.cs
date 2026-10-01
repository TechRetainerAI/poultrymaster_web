// Missing Activity Detector (migration 332): "which expected farm activities
// have not been completed yet?"
//
// SHAPE
// =====
// An IActivityCheck answers one deterministic question for one company and
// business date. ActivityCheckService runs every check that applies to the
// company's type and that the caller is allowed to see, and folds the results
// into one report. Adding a check -- driver returns, cash reconciliation,
// unposted batches, pending approvals, daily closing -- is one new class and one
// DI line; neither this service, the controller nor the report shape changes.
//
// NOTHING IS PERSISTED
// ====================
// Every result is recomputed from the records that already exist. A future
// Business Office "My Tasks" or notification feed can call RunAsync for each
// company the owner has access to; only what needs acknowledgement or history
// should ever be written, and it should reference a result (check key +
// business date + subject), not copy it.
//
// PERMISSIONS
// ===========
// Each check names the permission that guards the data it reveals. The route is
// exempt from the IAM route map (see IamPermissionMap) because no single key can
// describe a report that spans several modules' data; instead each check is
// gated here, with the same posture as IamEnforcementFilter: in shadow mode
// (Iam:Enforced = false) a check the caller lacks is logged and still returned;
// once enforcement is on, it is dropped from the report.

using Microsoft.Extensions.Logging;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IActivityCheck
    {
        /// <summary>Stable id, e.g. "poultry.production.daily".</summary>
        string Key { get; }
        /// <summary>The company type this check applies to (poultry | water | generic).</summary>
        string Module { get; }
        /// <summary>The permission that guards the data this check reveals.</summary>
        string RequiredPermission { get; }

        Task<ActivityCheckResult> RunAsync(ActivityCheckContext context);
    }

    public interface IActivityCheckService
    {
        /// <summary>
        /// Throws ArgumentException when the business date is after the
        /// company's today.
        /// </summary>
        Task<ActivityCompletenessReport> RunAsync(
            string farmId, string? userId, DateTime? businessDate, bool enforcePermissions);
    }

    public class ActivityCheckService : IActivityCheckService
    {
        private readonly IEnumerable<IActivityCheck> _checks;
        private readonly ICompanyTimeService _time;
        private readonly IIamService _iam;
        private readonly ILogger<ActivityCheckService> _logger;

        public ActivityCheckService(
            IEnumerable<IActivityCheck> checks,
            ICompanyTimeService time,
            IIamService iam,
            ILogger<ActivityCheckService> logger)
        {
            _checks = checks;
            _time = time;
            _iam = iam;
            _logger = logger;
        }

        public async Task<ActivityCompletenessReport> RunAsync(
            string farmId, string? userId, DateTime? businessDate, bool enforcePermissions)
        {
            // The company's clock decides "today" -- never the server's or the
            // browser's. See CompanyTimeService.
            var clock = await _time.GetContextAsync(farmId);
            var date = (businessDate ?? clock.BusinessDate).Date;
            if (date > clock.BusinessDate.Date)
                throw new ArgumentException(
                    $"Business date {date:yyyy-MM-dd} is in the future for this company (today is {clock.BusinessDate:yyyy-MM-dd}).");

            var module = await _iam.GetModuleForFarmAsync(farmId);
            var report = new ActivityCompletenessReport
            {
                FarmId = farmId,
                Module = module,
                BusinessDate = date,
                CompanyToday = clock.BusinessDate.Date,
                CompanyLocalDateTime = clock.CompanyLocalDateTime,
                TimeZoneId = clock.TimeZoneId,
                GeneratedAtUtc = clock.UtcNow,
            };

            // An unresolvable company type runs nothing rather than guessing:
            // a poultry check against a water company would report every flock
            // it does not have as "complete", which is noise, not safety.
            if (module is null) return report;

            var ctx = new ActivityCheckContext { FarmId = farmId, BusinessDate = date };
            foreach (var check in _checks.Where(c =>
                         string.Equals(c.Module, module, StringComparison.OrdinalIgnoreCase)))
            {
                if (!await MayViewAsync(check, userId, farmId, enforcePermissions))
                {
                    report.HiddenCheckCount++;
                    continue;
                }

                var result = await check.RunAsync(ctx);
                result.Key = check.Key;
                result.Module = check.Module;
                result.RequiredPermission = check.RequiredPermission;
                report.Checks.Add(result);
            }

            report.Severity = report.Checks
                .Select(c => c.Severity)
                .OrderByDescending(ActivitySeverity.Rank)
                .FirstOrDefault(s => ActivitySeverity.Rank(s) > 0);
            return report;
        }

        private async Task<bool> MayViewAsync(IActivityCheck check, string? userId, string farmId, bool enforce)
        {
            var allowed = !string.IsNullOrWhiteSpace(userId)
                          && await _iam.HasPermissionAsync(userId, farmId, check.RequiredPermission);
            if (allowed) return true;

            if (!enforce)
            {
                // Same wording as IamEnforcementFilter so one log search finds both.
                _logger.LogWarning(
                    "IAM SHADOW would hide activity check {Check}: user {UserId} on {FarmId} is missing {Permission}",
                    check.Key, userId ?? "(anonymous)", farmId, check.RequiredPermission);
                return true;
            }
            return false;
        }
    }
}
