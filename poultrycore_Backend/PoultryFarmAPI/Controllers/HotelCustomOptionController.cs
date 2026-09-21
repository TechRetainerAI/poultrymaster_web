using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Helpers;

namespace PoultryFarmAPIWeb.Controllers
{
    /// <summary>
    /// The values an operator typed into an "Other" box on a Hotel dropdown.
    /// See Migrations/300 for why one generic farm-scoped list serves nine
    /// dropdowns, and why the existing hotel lookup tables could not be used.
    /// </summary>
    [ApiController]
    [Authorize]
    [Route("api/Hotel/custom-options")]
    public class HotelCustomOptionController : ControllerBase
    {
        private readonly IHotelCustomOptionService _svc;
        public HotelCustomOptionController(IHotelCustomOptionService svc) => _svc = svc;

        // Kept as an allow-list rather than accepting any string: listkey is free
        // text in the database on purpose (a tenth list should not need a
        // migration), but an open endpoint would let a caller fill the table with
        // arbitrary keys. Adding a list here is a one-line change.
        private static readonly HashSet<string> KnownListKeys = new(StringComparer.OrdinalIgnoreCase)
        {
            "CommSubject",        // hotel-communications        -> Log Guest Communication / Subject
            "RequestType",        // hotel-guest-requests        -> New Guest Request / Type
            "LostFoundCategory",  // hotel-lost-found            -> Log Lost Item / Category
            "HKTaskType",         // hotel-housekeeping-schedule -> Add Schedule Entry / Task Type
            "MenuCategory",       // hotel-menu                  -> Add Menu Item / Category
            "SupplyCategory",     // hotel-inventory             -> Add Supply Item / Category
            "SupplyItemName",     // hotel-inventory             -> Add Supply Item / Name
            "MaintenanceAsset",   // hotel-maintenance           -> New Maintenance Request / Asset / Area
            "TableLocation",      // hotel-restaurant-tables     -> Add Table / Location
        };

        [HttpGet]
        public async Task<IActionResult> List([FromQuery] string farmId, [FromQuery] string? listKey)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;

            if (string.IsNullOrWhiteSpace(listKey))
                return Ok(await _svc.ListAllAsync(farmId));

            if (!KnownListKeys.Contains(listKey))
                return BadRequest(new { message = $"Unknown list '{listKey}'." });

            return Ok(await _svc.ListAsync(farmId, listKey));
        }

        /// <summary>
        /// Named Hotel* rather than plain CustomOptionCreateRequest: Swashbuckle's
        /// default schemaId is the bare type NAME, ignoring the declaring class, so
        /// this and RestaurantCustomOptionController's request DTO collided and
        /// /swagger/v1/swagger.json returned a 500 for the whole API. It is the only
        /// such collision among 283 nested controller classes, so the duplicate name
        /// was the defect — not the nesting pattern.
        /// </summary>
        public class HotelCustomOptionCreateRequest
        {
            public string FarmId { get; set; } = string.Empty;
            public string ListKey { get; set; } = string.Empty;
            public string Value { get; set; } = string.Empty;
        }

        [HttpPost]
        public async Task<IActionResult> Create([FromBody] HotelCustomOptionCreateRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;

            if (string.IsNullOrWhiteSpace(req.ListKey) || !KnownListKeys.Contains(req.ListKey))
                return BadRequest(new { message = "A known list is required." });
            if (string.IsNullOrWhiteSpace(req.Value))
                return BadRequest(new { message = "Value is required." });

            var value = req.Value.Trim();
            if (value.Length > 120)
                return BadRequest(new { message = "Value cannot exceed 120 characters." });

            // Stops "Other" itself being saved as an option, which would give the
            // dropdown two entries both reading "Other" — one real, one custom.
            if (value.Equals("Other", StringComparison.OrdinalIgnoreCase))
                return BadRequest(new { message = "Type the actual value, not \"Other\"." });

            var createdBy = User.Identity?.Name;
            var created = await _svc.InsertAsync(req.FarmId, req.ListKey, value, createdBy);
            if (created == null) return StatusCode(500, new { message = "Could not save the value." });
            return Ok(created);
        }

        [HttpDelete("{id:int}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            var ok = await _svc.DeleteAsync(farmId, id);
            if (!ok) return NotFound(new { message = "Option not found." });
            return Ok(new { message = "Removed." });
        }
    }
}
