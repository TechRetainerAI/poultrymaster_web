using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Helpers;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController][Authorize][Route("api/Hotel/front-desk")]
    public class HotelFrontDeskController : ControllerBase
    {
        private readonly IHotelFrontDeskService _svc;
        private readonly IHotelEmailService _hotelEmail;
        public HotelFrontDeskController(IHotelFrontDeskService svc, IHotelEmailService hotelEmail) { _svc = svc; _hotelEmail = hotelEmail; }

        [HttpPost("check-in")]
        public async Task<IActionResult> CheckIn([FromBody] CheckInRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            var v1 = HotelValidation.ValidatePositiveInt(req.HotelBookingId, "Booking ID"); if (v1 != null) return v1;
            var v2 = HotelValidation.ValidatePositiveInt(req.HotelRoomId, "Room ID"); if (v2 != null) return v2;
            var v3 = HotelValidation.ValidateAmount(req.DepositAmount, "Deposit amount"); if (v3 != null) return v3;

            var result = await _svc.CheckInAsync(req.FarmId, req.HotelBookingId, req.HotelRoomId, req.KeyCardNumber, req.DepositAmount, req.DepositMethod, req.Notes);
            _ = Task.Run(async () => { try { await _hotelEmail.SendCheckInConfirmationAsync(req.FarmId, req.HotelBookingId); } catch { } });
            return Ok(result);
        }

        [HttpPost("check-out")]
        public async Task<IActionResult> CheckOut([FromBody] CheckOutRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            var v1 = HotelValidation.ValidatePositiveInt(req.HotelBookingId, "Booking ID"); if (v1 != null) return v1;
            var v2 = HotelValidation.ValidatePositiveInt(req.HotelRoomId, "Room ID"); if (v2 != null) return v2;
            var v3 = HotelValidation.ValidateAmount(req.LateFee, "Late fee"); if (v3 != null) return v3;
            var v4 = HotelValidation.ValidateAmount(req.DamageCharges, "Damage charges"); if (v4 != null) return v4;

            var result = await _svc.CheckOutAsync(req.FarmId, req.HotelBookingId, req.HotelRoomId, req.LateFee, req.DamageCharges, req.KeyReturned, req.Notes);
            _ = Task.Run(async () => { try { await _hotelEmail.SendCheckOutReceiptAsync(req.FarmId, req.HotelBookingId, 0, 0); } catch { } });
            return Ok(result);
        }
    }

    public class CheckInRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public int HotelBookingId { get; set; }
        public int HotelRoomId { get; set; }
        public string? KeyCardNumber { get; set; }
        public decimal DepositAmount { get; set; }
        public string? DepositMethod { get; set; }
        public string? Notes { get; set; }
    }

    public class CheckOutRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public int HotelBookingId { get; set; }
        public int HotelRoomId { get; set; }
        public decimal LateFee { get; set; }
        public decimal DamageCharges { get; set; }
        public bool KeyReturned { get; set; } = true;
        public string? Notes { get; set; }
    }

    [ApiController][Authorize][Route("api/Hotel/housekeeping")]
    public class HotelHousekeepingController : ControllerBase
    {
        private readonly IHotelHousekeepingService _svc;
        public HotelHousekeepingController(IHotelHousekeepingService svc) => _svc = svc;

        [HttpGet]
        public async Task<IActionResult> GetAll([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.ListAsync(farmId));
        }

        [HttpPost]
        public async Task<IActionResult> Create([FromBody] CreateHousekeepingRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            var v1 = HotelValidation.ValidatePositiveInt(req.HotelRoomId, "Room ID"); if (v1 != null) return v1;

            var id = await _svc.InsertAsync(req.FarmId, req.HotelRoomId, req.TaskType ?? "Cleaning", req.Priority ?? "Normal", req.AssignedTo, req.ScheduledDate, req.Notes);
            return Ok(new { hotelHousekeepingTaskId = id });
        }

        [HttpPatch("{id}/status")]
        public async Task<IActionResult> UpdateStatus(int id, [FromQuery] string farmId, [FromBody] UpdateStatusRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            var v1 = HotelValidation.ValidateRequiredString(req.Status, "Status"); if (v1 != null) return v1;

            await _svc.UpdateStatusAsync(id, farmId, req.Status);
            return NoContent();
        }
    }

    public class CreateHousekeepingRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public int HotelRoomId { get; set; }
        public string? TaskType { get; set; }
        public string? Priority { get; set; }
        public string? AssignedTo { get; set; }
        public string? ScheduledDate { get; set; }
        public string? Notes { get; set; }
    }
}
