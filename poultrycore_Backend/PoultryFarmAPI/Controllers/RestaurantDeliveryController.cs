using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Helpers;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Authorize]
    [Route("api/Restaurant/delivery")]
    public class RestaurantDeliveryController : ControllerBase
    {
        private readonly IRestaurantDeliveryService _svc;
        public RestaurantDeliveryController(IRestaurantDeliveryService svc) => _svc = svc;

        // ===== DRIVERS =====
        [HttpGet("drivers")]
        public async Task<IActionResult> ListDrivers([FromQuery] string farmId, [FromQuery] string? status = null)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; return Ok(await _svc.ListDriversAsync(farmId, status)); }

        [HttpPost("drivers")]
        public async Task<IActionResult> CreateDriver([FromBody] RestaurantDriverModel m)
        { if (!ModelState.IsValid) return BadRequest(ModelState); var a = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (a != null) return a; return Ok(new { driverId = await _svc.InsertDriverAsync(m) }); }

        [HttpPut("drivers/{id}")]
        public async Task<IActionResult> UpdateDriver(int id, [FromBody] RestaurantDriverModel m)
        { if (!ModelState.IsValid) return BadRequest(ModelState); var a = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (a != null) return a; m.DriverId = id; await _svc.UpdateDriverAsync(m); return NoContent(); }

        [HttpDelete("drivers/{id}")]
        public async Task<IActionResult> DeleteDriver(int id, [FromQuery] string farmId)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; await _svc.DeleteDriverAsync(id, farmId); return NoContent(); }

        [HttpPatch("drivers/{id}/status")]
        public async Task<IActionResult> UpdateDriverStatus(int id, [FromQuery] string farmId, [FromBody] DriverStatusReq req)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; await _svc.UpdateDriverStatusAsync(id, farmId, req.Status); return NoContent(); }

        [HttpPatch("drivers/{id}/location")]
        public async Task<IActionResult> UpdateDriverLocation(int id, [FromQuery] string farmId, [FromBody] DriverLocationReq req)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; await _svc.UpdateDriverLocationAsync(id, farmId, req.Latitude, req.Longitude); return NoContent(); }

        [HttpGet("drivers/{id}/stats")]
        public async Task<IActionResult> GetDriverStats(int id, [FromQuery] string farmId, [FromQuery] DateTime? fromDate = null, [FromQuery] DateTime? toDate = null)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; return Ok(await _svc.GetDriverStatsAsync(id, farmId, fromDate, toDate)); }

        // ===== ZONES =====
        [HttpGet("zones")]
        public async Task<IActionResult> ListZones([FromQuery] string farmId)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; return Ok(await _svc.ListZonesAsync(farmId)); }

        [HttpPost("zones")]
        public async Task<IActionResult> CreateZone([FromBody] RestaurantDeliveryZoneModel m)
        { if (!ModelState.IsValid) return BadRequest(ModelState); var a = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (a != null) return a; return Ok(new { deliveryZoneId = await _svc.InsertZoneAsync(m) }); }

        [HttpPut("zones/{id}")]
        public async Task<IActionResult> UpdateZone(int id, [FromBody] RestaurantDeliveryZoneModel m)
        { if (!ModelState.IsValid) return BadRequest(ModelState); var a = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (a != null) return a; m.DeliveryZoneId = id; await _svc.UpdateZoneAsync(m); return NoContent(); }

        [HttpDelete("zones/{id}")]
        public async Task<IActionResult> DeleteZone(int id, [FromQuery] string farmId)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; await _svc.DeleteZoneAsync(id, farmId); return NoContent(); }

        // ===== ASSIGNMENTS =====
        [HttpGet("assignments")]
        public async Task<IActionResult> ListAssignments([FromQuery] string farmId, [FromQuery] string? status = null, [FromQuery] int? driverId = null)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; return Ok(await _svc.ListAssignmentsAsync(farmId, status, driverId)); }

        [HttpPost("assignments")]
        public async Task<IActionResult> CreateAssignment([FromQuery] string farmId, [FromBody] CreateAssignmentReq req)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a;
          var id = await _svc.CreateAssignmentAsync(farmId, req.OrderId, req.OrderNumber, req.DriverId, req.DeliveryAddress, req.DeliveryNotes, req.DeliveryZoneId, req.DeliveryFee, req.EstimatedMins);
          return Ok(new { deliveryAssignmentId = id }); }

        [HttpPatch("assignments/{id}/status")]
        public async Task<IActionResult> UpdateAssignmentStatus(int id, [FromQuery] string farmId, [FromBody] AssignmentStatusReq req)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; await _svc.UpdateAssignmentStatusAsync(id, farmId, req.Status, req.FailReason); return NoContent(); }

        [HttpPost("assignments/{id}/rate")]
        public async Task<IActionResult> RateAssignment(int id, [FromQuery] string farmId, [FromBody] RateReq req)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; await _svc.RateAssignmentAsync(id, farmId, req.Rating); return NoContent(); }

        [HttpPost("assignments/{id}/proof")]
        public async Task<IActionResult> AddProof(int id, [FromQuery] string farmId, [FromBody] ProofReq req)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; await _svc.AddProofAsync(id, farmId, req.ProofType, req.ProofData); return NoContent(); }

        // ===== THIRD-PARTY PLATFORMS =====
        [HttpGet("platforms")]
        public async Task<IActionResult> ListPlatforms([FromQuery] string farmId)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; return Ok(await _svc.ListPlatformsAsync(farmId)); }

        [HttpPost("platforms")]
        public async Task<IActionResult> CreatePlatform([FromBody] RestaurantThirdPartyPlatformModel m)
        { if (!ModelState.IsValid) return BadRequest(ModelState); var a = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (a != null) return a; return Ok(new { platformId = await _svc.InsertPlatformAsync(m) }); }

        [HttpPut("platforms/{id}")]
        public async Task<IActionResult> UpdatePlatform(int id, [FromBody] RestaurantThirdPartyPlatformModel m)
        { if (!ModelState.IsValid) return BadRequest(ModelState); var a = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (a != null) return a; m.PlatformId = id; await _svc.UpdatePlatformAsync(m); return NoContent(); }

        [HttpDelete("platforms/{id}")]
        public async Task<IActionResult> DeletePlatform(int id, [FromQuery] string farmId)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; await _svc.DeletePlatformAsync(id, farmId); return NoContent(); }

        // ===== THIRD-PARTY ORDERS =====
        [HttpGet("third-party-orders")]
        public async Task<IActionResult> ListThirdPartyOrders([FromQuery] string farmId, [FromQuery] string? status = null, [FromQuery] int? platformId = null)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; return Ok(await _svc.ListThirdPartyOrdersAsync(farmId, status, platformId)); }

        [HttpPatch("third-party-orders/{id}/status")]
        public async Task<IActionResult> UpdateThirdPartyOrderStatus(int id, [FromQuery] string farmId, [FromBody] ThirdPartyStatusReq req)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; await _svc.UpdateThirdPartyOrderStatusAsync(id, farmId, req.Status, req.RejectReason); return NoContent(); }

        // ===== STATS =====
        [HttpGet("stats")]
        public async Task<IActionResult> GetStats([FromQuery] string farmId, [FromQuery] DateTime? date = null)
        { var a = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (a != null) return a; return Ok(await _svc.GetDeliveryStatsAsync(farmId, date)); }
    }

    // Request DTOs
    public class DriverStatusReq { public string Status { get; set; } = string.Empty; }
    public class DriverLocationReq { public decimal Latitude { get; set; } public decimal Longitude { get; set; } }
    public class CreateAssignmentReq { public int OrderId { get; set; } public string OrderNumber { get; set; } = ""; public int DriverId { get; set; } public string? DeliveryAddress { get; set; } public string? DeliveryNotes { get; set; } public int? DeliveryZoneId { get; set; } public decimal DeliveryFee { get; set; } public int? EstimatedMins { get; set; } }
    public class AssignmentStatusReq { public string Status { get; set; } = string.Empty; public string? FailReason { get; set; } }
    public class RateReq { public int Rating { get; set; } }
    public class ProofReq { public string ProofType { get; set; } = ""; public string ProofData { get; set; } = ""; }
    public class ThirdPartyStatusReq { public string Status { get; set; } = string.Empty; public string? RejectReason { get; set; } }
}
