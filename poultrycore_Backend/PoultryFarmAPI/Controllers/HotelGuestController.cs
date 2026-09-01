using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Npgsql;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Helpers;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController][Authorize][Route("api/Hotel/guests")]
    public class HotelGuestController : ControllerBase
    {
        private readonly IHotelGuestService _svc;
        public HotelGuestController(IHotelGuestService svc) => _svc = svc;

        [HttpGet]
        public async Task<IActionResult> GetAll([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.ListAsync(farmId));
        }

        [HttpGet("{id}")]
        public async Task<IActionResult> GetById(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            var g = await _svc.GetByIdAsync(id, farmId);
            return g == null ? NotFound() : Ok(g);
        }

        [HttpGet("search")]
        public async Task<IActionResult> Search([FromQuery] string farmId, [FromQuery] string q)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.SearchAsync(farmId, q ?? ""));
        }

        [HttpPost]
        public async Task<IActionResult> Create([FromBody] HotelGuestModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (auth != null) return auth;
            var id = await _svc.InsertAsync(m);
            var created = await _svc.GetByIdAsync(id, m.FarmId);
            return CreatedAtAction(nameof(GetById), new { id, farmId = m.FarmId }, created);
        }

        [HttpPut("{id}")]
        public async Task<IActionResult> Update(int id, [FromBody] HotelGuestModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (auth != null) return auth;
            m.HotelGuestId = id;
            await _svc.UpdateAsync(m);
            return NoContent();
        }

        [HttpDelete("{id}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            await _svc.DeleteAsync(id, farmId);
            return NoContent();
        }
    }

    [ApiController][Authorize][Route("api/Hotel/bookings")]
    public class HotelBookingController : ControllerBase
    {
        private readonly IHotelBookingService _svc;
        private readonly string _cs;
        private readonly IHotelEmailService _hotelEmail;
        public HotelBookingController(IHotelBookingService svc, IConfiguration config, IHotelEmailService hotelEmail) { _svc = svc; _cs = config.GetConnectionString("PoultryConn") ?? ""; _hotelEmail = hotelEmail; }

        [HttpGet]
        public async Task<IActionResult> GetAll([FromQuery] string farmId, [FromQuery] int? page, [FromQuery] int? pageSize)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            if (page == null || page <= 0) return Ok(await _svc.ListAsync(farmId));

            int ps = Math.Clamp(pageSize ?? 20, 1, 100);
            int offset = (page.Value - 1) * ps;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            int total;
            using (var cnt = new NpgsqlCommand("SELECT COUNT(*) FROM hotelbookings WHERE farmid=@f", conn)) { cnt.Parameters.AddWithValue("@f", farmId); total = Convert.ToInt32(await cnt.ExecuteScalarAsync()); }
            using var cmd = new NpgsqlCommand(
                "SELECT b.*, g.firstname AS guestfirstname, g.lastname AS guestlastname, g.phone AS guestphone, r.roomnumber, rt.name AS roomtypename " +
                "FROM hotelbookings b LEFT JOIN hotelguests g ON b.hotelguestid=g.hotelguestid LEFT JOIN hotelrooms r ON b.hotelroomid=r.hotelroomid LEFT JOIN hotelroomtypes rt ON b.hotelroomtypeid=rt.hotelroomtypeid " +
                "WHERE b.farmid=@f ORDER BY b.checkindate DESC LIMIT @lim OFFSET @off", conn);
            cmd.Parameters.AddWithValue("@f", farmId); cmd.Parameters.AddWithValue("@lim", ps); cmd.Parameters.AddWithValue("@off", offset);
            using var rd = await cmd.ExecuteReaderAsync();
            var data = new List<Dictionary<string, object?>>();
            while (await rd.ReadAsync()) { var d = new Dictionary<string, object?>(); for (int i = 0; i < rd.FieldCount; i++) { var n = rd.GetName(i); d[char.ToLower(n[0]) + n[1..]] = rd.IsDBNull(i) ? null : rd.GetValue(i); } data.Add(d); }
            return Ok(new { data, total, page = page.Value, pageSize = ps });
        }

        [HttpGet("{id}")]
        public async Task<IActionResult> GetById(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            var b = await _svc.GetByIdAsync(id, farmId);
            return b == null ? NotFound() : Ok(b);
        }

        [HttpGet("today-arrivals")]
        public async Task<IActionResult> TodayArrivals([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.TodayArrivalsAsync(farmId));
        }

        [HttpGet("today-departures")]
        public async Task<IActionResult> TodayDepartures([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.TodayDeparturesAsync(farmId));
        }

        [HttpPost]
        public async Task<IActionResult> Create([FromBody] HotelBookingModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (auth != null) return auth;
            // Generate unique booking reference server-side (GUID-based, guaranteed unique)
            m.BookingRef = $"BK-{DateTime.UtcNow:yyyyMMdd}-{Guid.NewGuid().ToString("N")[..6].ToUpper()}";
            var id = await _svc.InsertAsync(m);
            var created = await _svc.GetByIdAsync(id, m.FarmId);
            _ = Task.Run(async () => { try { await _hotelEmail.SendBookingConfirmationAsync(m.FarmId, id); } catch { } });
            return CreatedAtAction(nameof(GetById), new { id, farmId = m.FarmId }, created);
        }

        [HttpPut("{id}")]
        public async Task<IActionResult> Update(int id, [FromBody] HotelBookingUpdateModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (auth != null) return auth;
            var full = new HotelBookingModel
            {
                HotelBookingId = id, FarmId = m.FarmId, HotelRoomId = m.HotelRoomId,
                HotelRoomTypeId = m.HotelRoomTypeId, CheckInDate = m.CheckInDate, CheckOutDate = m.CheckOutDate,
                NumberOfGuests = m.NumberOfGuests, Adults = m.Adults, Children = m.Children,
                NightlyRate = m.NightlyRate, TotalAmount = m.TotalAmount, Source = m.Source,
                SpecialRequests = m.SpecialRequests,
            };
            await _svc.UpdateAsync(full);
            return NoContent();
        }

        [HttpPatch("{id}/status")]
        public async Task<IActionResult> UpdateStatus(int id, [FromQuery] string farmId, [FromBody] UpdateStatusRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            await _svc.UpdateStatusAsync(id, farmId, req.Status);
            return NoContent();
        }

        [HttpPost("{id}/cancel")]
        public async Task<IActionResult> Cancel(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            await _svc.CancelAsync(id, farmId);
            return NoContent();
        }
    }
}
