using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Helpers;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Authorize]
    [Route("api/Hotel/setup")]
    public class HotelSetupController : ControllerBase
    {
        private readonly IHotelSetupService _svc;
        public HotelSetupController(IHotelSetupService svc) => _svc = svc;

        // =====================================================================
        // PROFILE
        // =====================================================================

        [HttpGet("profile")]
        public async Task<IActionResult> GetProfile([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            var p = await _svc.GetProfileAsync(farmId);
            if (p == null) return NotFound();
            return Ok(p);
        }

        [HttpPost("profile")]
        public async Task<IActionResult> UpsertProfile([FromBody] HotelProfileModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (auth != null) return auth;
            var result = await _svc.UpsertProfileAsync(m);
            return Ok(result);
        }

        // =====================================================================
        // ROOM CATEGORIES (system-wide lookup)
        // =====================================================================

        [HttpGet("room-categories")]
        public async Task<IActionResult> ListRoomCategories()
        {
            return Ok(await _svc.ListRoomCategoriesAsync());
        }

        // =====================================================================
        // RESTAURANT MENU CATEGORY TYPES (system-wide lookup)
        // =====================================================================

        [HttpGet("menu-category-types")]
        public async Task<IActionResult> ListMenuCategoryTypes()
        {
            return Ok(await _svc.ListMenuCategoryTypesAsync());
        }

        // =====================================================================
        // SUPPLY CATEGORIES & ITEMS (system-wide lookup)
        // =====================================================================

        [HttpGet("supply-categories")]
        public async Task<IActionResult> ListSupplyCategories()
        {
            return Ok(await _svc.ListSupplyCategoriesAsync());
        }

        [HttpGet("supply-items")]
        public async Task<IActionResult> ListSupplyItems()
        {
            return Ok(await _svc.ListSupplyItemsAsync());
        }

        // =====================================================================
        // MAINTENANCE ASSETS (system-wide lookup)
        // =====================================================================

        [HttpGet("maintenance-assets")]
        public async Task<IActionResult> ListMaintenanceAssets()
        {
            return Ok(await _svc.ListMaintenanceAssetsAsync());
        }

        // =====================================================================
        // TABLE LOCATIONS (system-wide lookup)
        // =====================================================================

        [HttpGet("table-locations")]
        public async Task<IActionResult> ListTableLocations()
        {
            return Ok(await _svc.ListTableLocationsAsync());
        }

        // =====================================================================
        // HK TASK TYPES (system-wide lookup)
        // =====================================================================

        [HttpGet("hk-task-types")]
        public async Task<IActionResult> ListHKTaskTypes()
        {
            return Ok(await _svc.ListHKTaskTypesAsync());
        }

        // =====================================================================
        // GUEST REQUEST TYPES (system-wide lookup)
        // =====================================================================

        [HttpGet("request-types")]
        public async Task<IActionResult> ListRequestTypes()
        {
            return Ok(await _svc.ListRequestTypesAsync());
        }

        // =====================================================================
        // COMMUNICATION SUBJECTS (system-wide lookup)
        // =====================================================================

        [HttpGet("comm-subjects")]
        public async Task<IActionResult> ListCommSubjects()
        {
            return Ok(await _svc.ListCommSubjectsAsync());
        }

        // =====================================================================
        // ID TYPES (system-wide lookup)
        // =====================================================================

        [HttpGet("id-types")]
        public async Task<IActionResult> ListIdTypes()
        {
            return Ok(await _svc.ListIdTypesAsync());
        }

        // =====================================================================
        // BED TYPES (system-wide lookup)
        // =====================================================================

        [HttpGet("bed-types")]
        public async Task<IActionResult> ListBedTypes()
        {
            return Ok(await _svc.ListBedTypesAsync());
        }

        // =====================================================================
        // ROOM TYPES
        // =====================================================================

        [HttpGet("room-types")]
        public async Task<IActionResult> ListRoomTypes([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.ListRoomTypesAsync(farmId));
        }

        [HttpGet("room-types/{id}")]
        public async Task<IActionResult> GetRoomType(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            var rt = await _svc.GetRoomTypeAsync(id, farmId);
            if (rt == null) return NotFound();
            return Ok(rt);
        }

        [HttpPost("room-types")]
        public async Task<IActionResult> CreateRoomType([FromBody] HotelRoomTypeModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (auth != null) return auth;
            var id = await _svc.InsertRoomTypeAsync(m);
            var created = await _svc.GetRoomTypeAsync(id, m.FarmId);
            return CreatedAtAction(nameof(GetRoomType), new { id, farmId = m.FarmId }, created);
        }

        [HttpPut("room-types/{id}")]
        public async Task<IActionResult> UpdateRoomType(int id, [FromBody] HotelRoomTypeModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (auth != null) return auth;
            m.HotelRoomTypeId = id;
            await _svc.UpdateRoomTypeAsync(m);
            return NoContent();
        }

        [HttpDelete("room-types/{id}")]
        public async Task<IActionResult> DeleteRoomType(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            await _svc.DeleteRoomTypeAsync(id, farmId);
            return NoContent();
        }

        // =====================================================================
        // FLOORS
        // =====================================================================

        [HttpGet("floors")]
        public async Task<IActionResult> ListFloors([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.ListFloorsAsync(farmId));
        }

        [HttpPost("floors")]
        public async Task<IActionResult> CreateFloor([FromBody] HotelFloorModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (auth != null) return auth;
            var id = await _svc.InsertFloorAsync(m);
            return Ok(new { hotelFloorId = id });
        }

        [HttpPut("floors/{id}")]
        public async Task<IActionResult> UpdateFloor(int id, [FromBody] HotelFloorModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (auth != null) return auth;
            m.HotelFloorId = id;
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

        // =====================================================================
        // AMENITIES
        // =====================================================================

        [HttpGet("amenities")]
        public async Task<IActionResult> ListAmenities([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.ListAmenitiesAsync(farmId));
        }

        [HttpPost("amenities")]
        public async Task<IActionResult> CreateAmenity([FromBody] HotelAmenityModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (auth != null) return auth;
            var id = await _svc.InsertAmenityAsync(m);
            return Ok(new { hotelAmenityId = id });
        }

        [HttpPut("amenities/{id}")]
        public async Task<IActionResult> UpdateAmenity(int id, [FromBody] HotelAmenityModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (auth != null) return auth;
            m.HotelAmenityId = id;
            await _svc.UpdateAmenityAsync(m);
            return NoContent();
        }

        [HttpDelete("amenities/{id}")]
        public async Task<IActionResult> DeleteAmenity(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            await _svc.DeleteAmenityAsync(id, farmId);
            return NoContent();
        }
    }
}
