using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Helpers;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Authorize]
    [Route("api/Restaurant/kds")]
    public class RestaurantKdsController : ControllerBase
    {
        private readonly IRestaurantKdsService _svc;
        public RestaurantKdsController(IRestaurantKdsService svc) => _svc = svc;

        // ===== STATIONS =====

        [HttpGet("stations")]
        public async Task<IActionResult> ListStations([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.ListStationsAsync(farmId));
        }

        [HttpPost("stations")]
        public async Task<IActionResult> CreateStation([FromBody] RestaurantKdsStationModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (auth != null) return auth;
            var id = await _svc.InsertStationAsync(m);
            return Ok(new { kdsStationId = id });
        }

        [HttpPut("stations/{id}")]
        public async Task<IActionResult> UpdateStation(int id, [FromBody] RestaurantKdsStationModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (auth != null) return auth;
            m.KdsStationId = id;
            await _svc.UpdateStationAsync(m);
            return NoContent();
        }

        [HttpDelete("stations/{id}")]
        public async Task<IActionResult> DeleteStation(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            await _svc.DeleteStationAsync(id, farmId);
            return NoContent();
        }

        // ===== STATION-ITEM MAPPINGS =====

        [HttpGet("stations/{stationId}/items")]
        public async Task<IActionResult> ListStationItems(int stationId, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.ListStationItemsAsync(stationId, farmId));
        }

        [HttpPost("stations/{stationId}/items")]
        public async Task<IActionResult> AssignItem(int stationId, [FromQuery] string farmId, [FromBody] KdsStationItemAssignRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            var id = await _svc.AssignItemToStationAsync(farmId, stationId, req.MenuItemId);
            return Ok(new { kdsStationItemId = id });
        }

        [HttpDelete("stations/items/{id}")]
        public async Task<IActionResult> UnassignItem(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            await _svc.UnassignItemFromStationAsync(id, farmId);
            return NoContent();
        }

        [HttpPost("items/{menuItemId}/set-station")]
        public async Task<IActionResult> SetItemStation(int menuItemId, [FromQuery] string farmId, [FromBody] KdsSetStationRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            await _svc.SetItemStationAsync(farmId, menuItemId, req.KdsStationId);
            return NoContent();
        }

        // ===== KDS QUEUE =====

        [HttpGet("queue")]
        public async Task<IActionResult> GetQueue([FromQuery] string farmId, [FromQuery] int? stationId = null, [FromQuery] bool isExpo = false)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.GetQueueAsync(farmId, stationId, isExpo));
        }

        [HttpPost("bump/{orderItemId}")]
        public async Task<IActionResult> BumpItem(int orderItemId, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            var newStatus = await _svc.BumpItemAsync(orderItemId, farmId);
            return Ok(new { newStatus });
        }

        [HttpPost("recall/{orderItemId}")]
        public async Task<IActionResult> RecallItem(int orderItemId, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            var newStatus = await _svc.RecallItemAsync(orderItemId, farmId);
            return Ok(new { newStatus });
        }

        [HttpPost("bump-order/{orderId}")]
        public async Task<IActionResult> BumpOrder(int orderId, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            await _svc.BumpOrderAsync(orderId, farmId);
            return NoContent();
        }

        // ===== STATS =====

        [HttpGet("stats")]
        public async Task<IActionResult> GetStats([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.GetStatsAsync(farmId));
        }
    }

    public class KdsStationItemAssignRequest { public int MenuItemId { get; set; } }
    public class KdsSetStationRequest { public int KdsStationId { get; set; } }
}
