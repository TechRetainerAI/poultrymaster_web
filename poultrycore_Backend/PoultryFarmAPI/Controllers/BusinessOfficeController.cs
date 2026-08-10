using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;

namespace PoultryFarmAPIWeb.Controllers
{
    // Business Office company cards. Anonymous like the rest of the Farm API —
    // the caller passes the farm context, and the Business Office only ever asks
    // about companies the Login API already listed for this user.
    [ApiController]
    [Route("api/BusinessOffice")]
    public class BusinessOfficeController : ControllerBase
    {
        private readonly IBusinessOfficeService _svc;
        public BusinessOfficeController(IBusinessOfficeService svc) => _svc = svc;

        // GET /api/BusinessOffice/company-snapshot?farmId=&type=Water&today=2026-08-04
        // `today` is the caller's local date; omitted, the server's UTC date is used.
        [HttpGet("company-snapshot")]
        public async Task<IActionResult> GetCompanySnapshot(
            [FromQuery] string farmId,
            [FromQuery] string type,
            [FromQuery] DateTime? today = null)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("farmId is required.");
            if (string.IsNullOrWhiteSpace(type)) return BadRequest("type is required.");
            return Ok(await _svc.GetCompanySnapshotAsync(farmId, type, today));
        }
    }
}
