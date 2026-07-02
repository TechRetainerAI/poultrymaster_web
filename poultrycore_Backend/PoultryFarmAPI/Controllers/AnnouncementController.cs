using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // Prompt 4 — Business Office announcements / notifications. Anonymous like
    // the rest of the Farm API (the caller passes userId/org context).
    [ApiController]
    [Route("api/Announcements")]
    public class AnnouncementController : ControllerBase
    {
        private readonly IAnnouncementService _svc;
        public AnnouncementController(IAnnouncementService svc) => _svc = svc;

        // GET /api/Announcements?userId=&orgOwnerUserId=&isAdmin=&farmId=
        [HttpGet]
        public async Task<IActionResult> ListForUser(
            [FromQuery] string userId,
            [FromQuery] string? orgOwnerUserId = null,
            [FromQuery] bool isAdmin = false,
            [FromQuery] string? farmId = null)
        {
            if (string.IsNullOrWhiteSpace(userId)) return BadRequest("userId is required.");
            return Ok(await _svc.ListForUserAsync(userId, orgOwnerUserId, isAdmin, farmId));
        }

        // GET /api/Announcements/manage?orgOwnerUserId=
        [HttpGet("manage")]
        public async Task<IActionResult> ListManage([FromQuery] string orgOwnerUserId)
        {
            if (string.IsNullOrWhiteSpace(orgOwnerUserId)) return BadRequest("orgOwnerUserId is required.");
            return Ok(await _svc.ListManageAsync(orgOwnerUserId));
        }

        // POST /api/Announcements
        [HttpPost]
        public async Task<IActionResult> Create([FromBody] CreateAnnouncementRequest req)
        {
            if (req == null || string.IsNullOrWhiteSpace(req.Title)) return BadRequest("Title is required.");
            var id = await _svc.CreateAsync(req);
            return Ok(new { announcementId = id });
        }

        // POST /api/Announcements/{id}/receipt?userId=&action=Read|Dismiss|Ack
        [HttpPost("{id:int}/receipt")]
        public async Task<IActionResult> Receipt(int id, [FromQuery] string userId, [FromQuery] string action)
        {
            if (string.IsNullOrWhiteSpace(userId)) return BadRequest("userId is required.");
            var a = (action ?? "").Trim();
            if (a != "Read" && a != "Dismiss" && a != "Ack") return BadRequest("action must be Read, Dismiss or Ack.");
            await _svc.SetReceiptAsync(id, userId, a);
            return Ok(new { success = true });
        }

        // DELETE /api/Announcements/{id}?orgOwnerUserId=
        [HttpDelete("{id:int}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string orgOwnerUserId)
        {
            if (string.IsNullOrWhiteSpace(orgOwnerUserId)) return BadRequest("orgOwnerUserId is required.");
            await _svc.DeleteAsync(id, orgOwnerUserId);
            return Ok(new { success = true });
        }
    }
}
