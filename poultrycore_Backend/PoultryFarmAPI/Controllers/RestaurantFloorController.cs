using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Helpers;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Authorize]
    [Route("api/Restaurant/floor")]
    public class RestaurantFloorController : ControllerBase
    {
        private readonly IRestaurantFloorService _svc;
        public RestaurantFloorController(IRestaurantFloorService svc) => _svc = svc;

        // ===== FLOORS =====

        [HttpGet("floors")]
        public async Task<IActionResult> ListFloors([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.ListFloorsAsync(farmId));
        }

        [HttpPost("floors")]
        public async Task<IActionResult> CreateFloor([FromBody] RestaurantFloorModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (auth != null) return auth;
            var id = await _svc.InsertFloorAsync(m);
            return Ok(new { floorId = id });
        }

        [HttpPut("floors/{id}")]
        public async Task<IActionResult> UpdateFloor(int id, [FromBody] RestaurantFloorModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (auth != null) return auth;
            m.FloorId = id;
            await _svc.UpdateFloorAsync(m);
            return NoContent();
        }

        [HttpDelete("floors/{id}")]
        public async Task<IActionResult> DeleteFloor(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            await _svc.DeleteFloorAsync(id, farmId);
            return NoContent();
        }

        // ===== TABLES =====

        [HttpGet("tables")]
        public async Task<IActionResult> ListTables([FromQuery] string farmId, [FromQuery] int? floorId = null, [FromQuery] string? status = null)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.ListTablesAsync(farmId, floorId, status));
        }

        [HttpGet("tables/{id}")]
        public async Task<IActionResult> GetTable(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            var t = await _svc.GetTableAsync(id, farmId);
            if (t == null) return NotFound();
            return Ok(t);
        }

        [HttpPost("tables")]
        public async Task<IActionResult> CreateTable([FromBody] RestaurantTableModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (auth != null) return auth;
            var id = await _svc.InsertTableAsync(m);
            var created = await _svc.GetTableAsync(id, m.FarmId);
            return CreatedAtAction(nameof(GetTable), new { id, farmId = m.FarmId }, created);
        }

        [HttpPut("tables/{id}")]
        public async Task<IActionResult> UpdateTable(int id, [FromBody] RestaurantTableModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (auth != null) return auth;
            m.TableId = id;
            await _svc.UpdateTableAsync(m);
            return NoContent();
        }

        [HttpDelete("tables/{id}")]
        public async Task<IActionResult> DeleteTable(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            await _svc.DeleteTableAsync(id, farmId);
            return NoContent();
        }

        [HttpPatch("tables/{id}/status")]
        public async Task<IActionResult> UpdateTableStatus(int id, [FromQuery] string farmId, [FromQuery] string status)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            await _svc.UpdateTableStatusAsync(id, farmId, status);
            return NoContent();
        }

        [HttpPatch("tables/{id}/position")]
        public async Task<IActionResult> UpdateTablePosition(int id, [FromQuery] string farmId, [FromBody] TablePositionRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            await _svc.UpdateTablePositionAsync(id, farmId, req.PositionX, req.PositionY);
            return NoContent();
        }
    }

    public class TablePositionRequest
    {
        public int PositionX { get; set; }
        public int PositionY { get; set; }
    }
}
