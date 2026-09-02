using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Helpers;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // =========================================================================
    // ADMIN ENDPOINTS (authenticated)
    // =========================================================================
    [ApiController]
    [Authorize]
    [Route("api/Restaurant/online")]
    public class RestaurantOnlineOrderController : ControllerBase
    {
        private readonly IRestaurantOnlineOrderService _svc;
        public RestaurantOnlineOrderController(IRestaurantOnlineOrderService svc) => _svc = svc;

        // Settings
        [HttpGet("settings")]
        public async Task<IActionResult> GetSettings([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            var s = await _svc.GetSettingsAsync(farmId);
            return Ok(s ?? new RestaurantOnlineOrderingSettingsModel { FarmId = farmId });
        }

        [HttpPost("settings")]
        public async Task<IActionResult> UpsertSettings([FromBody] RestaurantOnlineOrderingSettingsModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (auth != null) return auth;
            await _svc.UpsertSettingsAsync(m);
            return NoContent();
        }

        [HttpPatch("settings/toggle")]
        public async Task<IActionResult> ToggleAccepting([FromQuery] string farmId, [FromBody] ToggleAcceptingRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            await _svc.ToggleAcceptingOrdersAsync(farmId, req.Accepting, req.Reason);
            return NoContent();
        }

        // QR Codes
        [HttpGet("qr-codes")]
        public async Task<IActionResult> ListQrCodes([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.ListQrCodesAsync(farmId));
        }

        [HttpPost("qr-codes")]
        public async Task<IActionResult> GenerateQrCode([FromQuery] string farmId, [FromBody] GenerateQrRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            var (id, token) = await _svc.GenerateQrCodeAsync(farmId, req.TableId, req.TableNumber);
            return Ok(new { qrCodeId = id, qrToken = token });
        }

        [HttpDelete("qr-codes/{id}")]
        public async Task<IActionResult> DeleteQrCode(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            await _svc.DeleteQrCodeAsync(id, farmId);
            return NoContent();
        }

        // Promo Codes
        [HttpGet("promo-codes")]
        public async Task<IActionResult> ListPromoCodes([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.ListPromoCodesAsync(farmId));
        }

        [HttpPost("promo-codes")]
        public async Task<IActionResult> CreatePromoCode([FromBody] RestaurantPromoCodeModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (auth != null) return auth;
            var id = await _svc.InsertPromoCodeAsync(m);
            return Ok(new { promoCodeId = id });
        }

        [HttpPut("promo-codes/{id}")]
        public async Task<IActionResult> UpdatePromoCode(int id, [FromBody] RestaurantPromoCodeModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (auth != null) return auth;
            m.PromoCodeId = id;
            await _svc.UpdatePromoCodeAsync(m);
            return NoContent();
        }

        [HttpDelete("promo-codes/{id}")]
        public async Task<IActionResult> DeletePromoCode(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            await _svc.DeletePromoCodeAsync(id, farmId);
            return NoContent();
        }

        // Delivery Addresses
        [HttpGet("delivery-addresses")]
        public async Task<IActionResult> ListAddresses([FromQuery] string farmId, [FromQuery] string? phone = null, [FromQuery] string? email = null)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.ListDeliveryAddressesAsync(farmId, phone, email));
        }

        // Throttle check
        [HttpGet("throttle-check")]
        public async Task<IActionResult> ThrottleCheck([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.CheckThrottleAsync(farmId));
        }
    }

    // =========================================================================
    // PUBLIC ENDPOINTS (no auth — for customers)
    // =========================================================================
    [ApiController]
    [Route("api/Restaurant/public")]
    public class RestaurantPublicController : ControllerBase
    {
        private readonly IRestaurantOnlineOrderService _svc;
        public RestaurantPublicController(IRestaurantOnlineOrderService svc) => _svc = svc;

        [HttpGet("{farmId}/menu")]
        public async Task<IActionResult> GetPublicMenu(string farmId) =>
            Ok(await _svc.GetPublicMenuAsync(farmId));

        [HttpGet("{farmId}/categories")]
        public async Task<IActionResult> GetPublicCategories(string farmId) =>
            Ok(await _svc.GetPublicCategoriesAsync(farmId));

        [HttpGet("{farmId}/settings")]
        public async Task<IActionResult> GetPublicSettings(string farmId)
        {
            var s = await _svc.GetSettingsAsync(farmId);
            if (s == null || !s.IsEnabled) return Ok(new { isEnabled = false, acceptingOrders = false });
            return Ok(new
            {
                s.IsEnabled, s.AcceptingOrders, s.PausedReason,
                s.AllowDineInQr, s.AllowTakeaway, s.AllowDelivery,
                s.MinOrderAmount, s.DeliveryFeeType, s.DeliveryFeeAmount,
                s.FreeDeliveryAbove, s.WelcomeMessage,
                s.EstimatedPrepMinsDine, s.EstimatedPrepMinsTake, s.EstimatedPrepminsDeliv,
            });
        }

        [HttpGet("qr/{token}")]
        public async Task<IActionResult> ScanQrCode(string token)
        {
            var result = await _svc.ScanQrCodeAsync(token);
            if (result == null) return NotFound(new { message = "Invalid QR code" });
            if (!result.IsActive) return BadRequest(new { message = "QR code is inactive" });
            return Ok(new { result.FarmId, result.TableId, result.TableNumber });
        }

        [HttpPost("{farmId}/validate-promo")]
        public async Task<IActionResult> ValidatePromo(string farmId, [FromBody] ValidatePromoRequest req) =>
            Ok(await _svc.ValidatePromoCodeAsync(farmId, req.Code, req.OrderAmount, req.Channel));

        [HttpPost("{farmId}/place-order")]
        public async Task<IActionResult> PlaceOrder(string farmId, [FromBody] OnlineOrderCreateRequest req)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            req.FarmId = farmId;

            // Throttle check
            var throttle = await _svc.CheckThrottleAsync(farmId);
            if (!throttle.CanAccept) return StatusCode(429, new { message = throttle.Message });

            var (orderId, orderNumber, trackingToken) = await _svc.PlaceOnlineOrderAsync(req);
            return Ok(new { orderId, orderNumber, trackingToken });
        }

        [HttpGet("track/{token}")]
        public async Task<IActionResult> TrackOrder(string token)
        {
            var result = await _svc.TrackOrderAsync(token);
            if (result == null) return NotFound(new { message = "Order not found" });
            return Ok(result);
        }

        [HttpPost("{farmId}/delivery-address")]
        public async Task<IActionResult> SaveAddress(string farmId, [FromBody] RestaurantDeliveryAddressModel m)
        {
            m.FarmId = farmId;
            var id = await _svc.InsertDeliveryAddressAsync(m);
            return Ok(new { deliveryAddressId = id });
        }

        [HttpGet("{farmId}/delivery-addresses")]
        public async Task<IActionResult> GetAddresses(string farmId, [FromQuery] string? phone = null) =>
            Ok(await _svc.ListDeliveryAddressesAsync(farmId, phone, null));
    }

    // Request DTOs
    public class ToggleAcceptingRequest { public bool Accepting { get; set; } public string? Reason { get; set; } }
    public class GenerateQrRequest { public int TableId { get; set; } public string TableNumber { get; set; } = string.Empty; }
    public class ValidatePromoRequest { public string Code { get; set; } = string.Empty; public decimal OrderAmount { get; set; } public string? Channel { get; set; } }
}
