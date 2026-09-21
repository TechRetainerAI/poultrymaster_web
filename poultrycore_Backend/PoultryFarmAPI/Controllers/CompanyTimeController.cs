// Company time (migration 298).
//
// Route is api/CompanyTime, NOT api/Companies/... -- the Next.js proxy matches
// the exact first segment "Companies" and forwards it to the Login API, so
// anything under that name would never reach this service.
// See app/api/proxy/[...path]/route.ts.
//
// Not under a vertical prefix either: a company's business day is a property of
// the company, and duplicating this per vertical is how the three modules would
// drift into disagreeing about what "today" means.

using Microsoft.AspNetCore.Mvc;
using Npgsql;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/CompanyTime")]
    public class CompanyTimeController : ControllerBase
    {
        private readonly ICompanyTimeService _svc;
        public CompanyTimeController(ICompanyTimeService svc) => _svc = svc;

        /// <summary>
        /// The company's clock. Cheap and safe to call on app boot -- a company
        /// with no timezone answers UTC with timeZoneConfirmed = false rather
        /// than 404, because "not set" is a state the UI must render, not an error.
        /// </summary>
        [HttpGet("context")]
        public async Task<ActionResult<CompanyTimeContextModel>> GetContext([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetContextAsync(farmId));

        /// <summary>
        /// Just today's date, for callers that need nothing else.
        /// Returned as yyyy-MM-dd so it cannot pick up a time component or a
        /// zone on the way through JSON -- which is the whole point.
        /// </summary>
        [HttpGet("business-date")]
        public async Task<ActionResult<object>> GetBusinessDate([FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var d = await _svc.GetBusinessDateAsync(farmId);
            return Ok(new { farmId, businessDate = d.ToString("yyyy-MM-dd") });
        }

        /// <summary>
        /// Set the company's business timezone and mark it confirmed.
        ///
        /// Changing it does NOT rewrite any historical business date -- only how
        /// future defaults, "today", and report boundaries are decided. Worth
        /// saying in the UI too, because the opposite is the natural assumption.
        /// </summary>
        [HttpPut("timezone")]
        public async Task<ActionResult<CompanyTimeZoneUpdateResult>> SetTimeZone(
            [FromQuery] string farmId, [FromBody] CompanyTimeZoneUpdateRequest body)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            // The query string wins, matching every other write on this rail: the
            // active company is context, not something a request body may claim.
            if (!string.IsNullOrWhiteSpace(farmId)) body.FarmId = farmId;
            if (string.IsNullOrWhiteSpace(body.FarmId)) return BadRequest("Company ID is required.");

            try
            {
                return Ok(await _svc.SetTimeZoneAsync(body));
            }
            catch (PostgresException ex) when (ex.SqlState == "P0001")
            {
                // RAISE EXCEPTION from the SP: an unknown zone, a fixed offset, a
                // blank id, or a company that does not exist. All of those are the
                // caller's mistake, so 400 with the SP's own wording -- which
                // already explains what to send instead.
                return BadRequest(ex.MessageText);
            }
        }

        /// <summary>
        /// The zones a company may choose, straight from the tz catalogue that
        /// Postgres itself uses for AT TIME ZONE -- so anything listed here is
        /// guaranteed to pass validation on the way back in.
        /// </summary>
        [HttpGet("zones")]
        public async Task<ActionResult<IEnumerable<CompanyTimeZoneOption>>> GetZones(
            [FromQuery] string? search)
            => Ok(await _svc.GetZonesAsync(search));
    }
}
