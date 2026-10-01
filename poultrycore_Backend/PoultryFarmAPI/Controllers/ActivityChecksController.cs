// Missing Activity Detector (migration 332): "what expected farm activities have
// not been completed yet?" for one company and business date.
//
// Route is api/ActivityChecks, not api/Poultry/...: the report is shaped to
// carry checks from any module, and a Business Office "My Tasks" view will call
// it once per company regardless of type. The first path segment must also not
// be one the Next.js proxy sends to the Login API (Companies, UserProfile...).
//
// Read-only, and derived on every call -- nothing here writes a task row.

using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Npgsql;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // [Authorize] is authentication only, as on PoultryBalancesController: this
    // lists which flocks a farm has not recorded, which is not something an
    // anonymous caller should be able to ask about any company id it guesses.
    // WHICH checks the caller sees is decided per check in ActivityCheckService,
    // because the route map can only name one permission and this report spans
    // several (see the "activitychecks" entry in IamPermissionMap.Exempt).
    [Authorize]
    [ApiController]
    [Route("api/ActivityChecks")]
    public class ActivityChecksController : ControllerBase
    {
        private readonly IActivityCheckService _svc;
        private readonly IConfiguration _config;
        private readonly IPoultryProductionGapService _gaps;
        private readonly IIamService _iam;

        public ActivityChecksController(
            IActivityCheckService svc, IConfiguration config, IPoultryProductionGapService gaps, IIamService iam)
        {
            _svc = svc;
            _config = config;
            _gaps = gaps;
            _iam = iam;
        }

        /// <summary>
        /// Every missing production day for one flock in the last `days` days
        /// (default 30, max 366), newest first -- the dropdown under a row on
        /// Farm Completeness. Same permission as the production check itself.
        /// </summary>
        /// <summary>
        /// Every missing (date, flock) farm-wide in the last `days` days
        /// (default 30, max 366), newest date first -- the "By date" view.
        /// </summary>
        [HttpGet("production/missing-by-date")]
        public async Task<ActionResult<MissingProductionByDate>> GetMissingByDate(
            [FromQuery] string farmId, [FromQuery] DateTime? businessDate, [FromQuery] int days = 30)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            if (!await MayViewProductionAsync(farmId))
                return StatusCode(403, new { message = "You do not have permission to view production records." });
            try
            {
                return Ok(await _gaps.GetMissingByDateAsync(farmId, businessDate?.Date, days));
            }
            catch (PostgresException ex) when (ex.SqlState == "P0001")
            {
                return BadRequest(new { message = ex.MessageText });
            }
        }

        /// <summary>Same rule as the check itself; only enforced once Iam:Enforced is on.</summary>
        private async Task<bool> MayViewProductionAsync(string farmId)
        {
            if (!_config.GetValue("Iam:Enforced", false)) return true;
            var userId = User?.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            return !string.IsNullOrWhiteSpace(userId)
                   && await _iam.HasPermissionAsync(userId, farmId, PoultryProductionCompletenessCheck.Permission);
        }

        [HttpGet("production/missing-dates")]
        public async Task<ActionResult<FlockMissingProductionDates>> GetMissingDates(
            [FromQuery] string farmId, [FromQuery] int flockId,
            [FromQuery] DateTime? businessDate, [FromQuery] int days = 30)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            if (flockId <= 0) return BadRequest("A flock is required.");

            if (!await MayViewProductionAsync(farmId))
                return StatusCode(403, new { message = "You do not have permission to view production records." });

            try
            {
                return Ok(await _gaps.GetMissingDatesAsync(farmId, flockId, businessDate?.Date, days));
            }
            catch (PostgresException ex) when (ex.SqlState == "P0001")
            {
                return BadRequest(new { message = ex.MessageText });
            }
        }

        /// <summary>
        /// Every check the caller may see for the company.
        /// businessDate is optional (yyyy-MM-dd) and defaults to the company's
        /// today; a date after the company's today is a 400.
        /// </summary>
        [HttpGet]
        public async Task<ActionResult<ActivityCompletenessReport>> Get(
            [FromQuery] string farmId, [FromQuery] DateTime? businessDate)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");

            var userId = User?.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            var enforce = _config.GetValue("Iam:Enforced", false);
            try
            {
                var report = await _svc.RunAsync(farmId, userId, businessDate?.Date, enforce);

                // Under enforcement, a caller who may see none of the checks that
                // apply to this company gets a clear 403 rather than an empty
                // report that reads as "nothing is missing".
                if (report.Checks.Count == 0 && report.HiddenCheckCount > 0)
                    return StatusCode(403, new { message = "You do not have permission to view activity checks for this company." });

                return Ok(report);
            }
            catch (ArgumentException ex)
            {
                return BadRequest(new { message = ex.Message });
            }
        }
    }
}
