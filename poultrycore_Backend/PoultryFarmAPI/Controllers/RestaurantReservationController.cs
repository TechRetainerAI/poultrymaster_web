using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Helpers;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Authorize]
    [Route("api/Restaurant/reservations")]
    public class RestaurantReservationController : ControllerBase
    {
        private readonly IRestaurantReservationService _svc;
        public RestaurantReservationController(IRestaurantReservationService svc) => _svc = svc;

        // ===== SETTINGS =====

        [HttpGet("settings")]
        public async Task<IActionResult> GetSettings([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            var s = await _svc.GetSettingsAsync(farmId);
            return Ok(s ?? new RestaurantReservationSettingsModel { FarmId = farmId });
        }

        [HttpPost("settings")]
        public async Task<IActionResult> UpsertSettings([FromBody] RestaurantReservationSettingsModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (auth != null) return auth;
            await _svc.UpsertSettingsAsync(m);
            return NoContent();
        }

        // ===== RESERVATIONS =====

        [HttpGet]
        public async Task<IActionResult> List([FromQuery] string farmId, [FromQuery] DateTime? date = null,
            [FromQuery] string? status = null, [FromQuery] DateTime? fromDate = null, [FromQuery] DateTime? toDate = null)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.ListReservationsAsync(farmId, date, status, fromDate, toDate));
        }

        [HttpGet("{id}")]
        public async Task<IActionResult> Get(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            var r = await _svc.GetReservationAsync(id, farmId);
            if (r == null) return NotFound();
            return Ok(r);
        }

        [HttpPost]
        public async Task<IActionResult> Create([FromBody] RestaurantReservationModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (auth != null) return auth;
            m.CreatedBy ??= HotelAuthHelper.GetUserName(User);
            var settings = await _svc.GetSettingsAsync(m.FarmId);
            var autoConfirm = settings?.AutoConfirm ?? true;
            var (id, number) = await _svc.CreateReservationAsync(m, autoConfirm);
            return Ok(new { reservationId = id, reservationNumber = number });
        }

        [HttpPut("{id}")]
        public async Task<IActionResult> Update(int id, [FromBody] RestaurantReservationModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (auth != null) return auth;
            m.ReservationId = id;
            await _svc.UpdateReservationAsync(m);
            return NoContent();
        }

        [HttpPatch("{id}/status")]
        public async Task<IActionResult> UpdateStatus(int id, [FromQuery] string farmId, [FromBody] ReservationStatusRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            await _svc.UpdateReservationStatusAsync(id, farmId, req.Status, req.Reason);
            return NoContent();
        }

        [HttpDelete("{id}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            await _svc.DeleteReservationAsync(id, farmId);
            return NoContent();
        }

        [HttpGet("auto-assign-table")]
        public async Task<IActionResult> AutoAssignTable([FromQuery] string farmId, [FromQuery] int partySize,
            [FromQuery] DateTime date, [FromQuery] string time)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.AutoAssignTableAsync(farmId, partySize, date, time));
        }

        [HttpGet("stats")]
        public async Task<IActionResult> GetStats([FromQuery] string farmId, [FromQuery] DateTime date)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.GetReservationStatsAsync(farmId, date));
        }

        // ===== WAITLIST =====

        [HttpGet("waitlist")]
        public async Task<IActionResult> ListWaitlist([FromQuery] string farmId, [FromQuery] string? status = null)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.ListWaitlistAsync(farmId, status));
        }

        [HttpPost("waitlist")]
        public async Task<IActionResult> AddToWaitlist([FromBody] RestaurantWaitlistModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (auth != null) return auth;
            var id = await _svc.AddToWaitlistAsync(m);
            return Ok(new { waitlistId = id });
        }

        [HttpPatch("waitlist/{id}/status")]
        public async Task<IActionResult> UpdateWaitlistStatus(int id, [FromQuery] string farmId, [FromBody] WaitlistStatusRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            await _svc.UpdateWaitlistStatusAsync(id, farmId, req.Status, req.TableId, req.TableNumber);
            return NoContent();
        }

        [HttpDelete("waitlist/{id}")]
        public async Task<IActionResult> DeleteFromWaitlist(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            await _svc.DeleteFromWaitlistAsync(id, farmId);
            return NoContent();
        }

        [HttpGet("waitlist/stats")]
        public async Task<IActionResult> GetWaitlistStats([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.GetWaitlistStatsAsync(farmId));
        }
    }

    public class ReservationStatusRequest
    {
        public string Status { get; set; } = string.Empty;
        public string? Reason { get; set; }
    }

    public class WaitlistStatusRequest
    {
        public string Status { get; set; } = string.Empty;
        public int? TableId { get; set; }
        public string? TableNumber { get; set; }
    }
}
