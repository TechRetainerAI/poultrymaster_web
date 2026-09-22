// User Quick Links (migration 318).
//
// The caller passes userId and farmId on the query string, the way the rest of
// this API does (see AnnouncementController).
//
// The route is "UserQuickLinks" rather than anything under "UserProfile":
// the frontend proxy routes by EXACT first path segment, and UserProfile is one
// of the five it sends to the Login API. A route that merely began with "User"
// would have been fine; one that WAS "UserProfile" would have gone to the wrong
// service entirely.

using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/UserQuickLinks")]
    public class UserQuickLinkController : ControllerBase
    {
        private readonly IUserQuickLinkService _svc;
        public UserQuickLinkController(IUserQuickLinkService svc) => _svc = svc;

        /// <summary>
        /// What this user chose for this company. `customised` false means they
        /// never have -- the caller shows its own defaults and must not read an
        /// empty list as a choice.
        /// </summary>
        [HttpGet]
        public async Task<ActionResult<UserQuickLinksModel>> Get(
            [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(userId)) return BadRequest("userId is required.");
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetAsync(userId, farmId));
        }

        /// <summary>
        /// Replace the whole bar. Returns what was STORED after 318 cleaned it,
        /// which is not always what was sent.
        /// </summary>
        [HttpPut]
        public async Task<ActionResult<UserQuickLinksModel>> Save([FromBody] UserQuickLinksSaveRequest r)
        {
            if (r is null) return BadRequest("A body is required.");
            if (string.IsNullOrWhiteSpace(r.UserId)) return BadRequest("userId is required.");
            if (string.IsNullOrWhiteSpace(r.FarmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.SaveAsync(r));
        }

        /// <summary>
        /// Back to the page's defaults. This DELETES the choice rather than
        /// storing today's default list, so a user who resets keeps getting
        /// shortcuts added to the product later.
        /// </summary>
        [HttpDelete]
        public async Task<IActionResult> Reset(
            [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(userId)) return BadRequest("userId is required.");
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.ResetAsync(userId, farmId);
            return NoContent();
        }
    }
}
