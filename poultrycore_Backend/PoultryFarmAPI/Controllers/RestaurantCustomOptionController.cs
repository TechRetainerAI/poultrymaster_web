using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Helpers;

namespace PoultryFarmAPIWeb.Controllers
{
    /// <summary>
    /// The values an operator typed into an "Other" box on a Restaurant dropdown.
    /// See Migrations/291 for why one generic list serves four dropdowns.
    /// </summary>
    [ApiController]
    [Authorize]
    [Route("api/Restaurant/custom-options")]
    public class RestaurantCustomOptionController : ControllerBase
    {
        private readonly IRestaurantCustomOptionService _svc;
        public RestaurantCustomOptionController(IRestaurantCustomOptionService svc) => _svc = svc;

        // Kept as an allow-list rather than accepting any string: listkey is free
        // text in the database on purpose (a fifth list should not need a
        // migration), but an open endpoint would let a caller fill the table with
        // arbitrary keys. Adding a list here is a one-line change.
        private static readonly HashSet<string> KnownListKeys = new(StringComparer.OrdinalIgnoreCase)
        {
            "IngredientCategory",   // restaurant-inventory  -> Add Ingredient / Category
            "WasteReason",          // restaurant-inventory  -> Log Waste / Reason
            "ReservationOccasion",  // restaurant-reservations -> New Reservation / Occasion
            "CuisineType",          // restaurant-setup      -> Profile / Cuisine Type
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

        public class CustomOptionCreateRequest
        {
            public string FarmId { get; set; } = string.Empty;
            public string ListKey { get; set; } = string.Empty;
            public string Value { get; set; } = string.Empty;
        }

        [HttpPost]
        public async Task<IActionResult> Create([FromBody] CustomOptionCreateRequest req)
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
