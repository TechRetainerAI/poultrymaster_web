// Restaurant Internal Use (migration 330): /api/Restaurant/internal-usage.
//
// Poultry's routes (list, get, suggested cost -> "items", create, update,
// delete, post, reverse) with the Restaurant conventions: every action checks
// the caller's JWT company against farmId, the acting user comes from the token
// (never a query string), and database refusals come back as 400 with the
// database's own sentence (RestaurantBusinessRuleFilter).

using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Filters;
using PoultryFarmAPIWeb.Helpers;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Authorize]
    [RestaurantBusinessRuleFilter]
    [Route("api/Restaurant/internal-usage")]
    public class RestaurantInternalUseController : ControllerBase
    {
        private static readonly string[] Categories =
            { "StaffWelfare", "OwnerUse", "Sample", "Donation", "QualityTest", "InternalConsumption", "Other" };

        private readonly IRestaurantInternalUseService _svc;
        public RestaurantInternalUseController(IRestaurantInternalUseService svc) => _svc = svc;

        private string Me => HotelAuthHelper.GetUserName(User);
        private IActionResult? Deny(string? farmId) =>
            string.IsNullOrWhiteSpace(farmId) ? BadRequest(new { message = "Company ID is required." }) : HotelAuthHelper.VerifyFarmOwnership(User, farmId);

        [HttpGet]
        public async Task<IActionResult> List([FromQuery] string farmId, [FromQuery] string? status, [FromQuery] string? category,
            [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.ListAsync(farmId, status, category, fromDate, toDate)); }

        [HttpGet("{id:int}")]
        public async Task<IActionResult> Get(int id, [FromQuery] string farmId)
        {
            var d = Deny(farmId); if (d != null) return d;
            var rec = await _svc.GetAsync(farmId, id);
            return rec is null ? NotFound(new { message = "Internal use record not found." }) : Ok(rec);
        }

        /// <summary>What can be used: stock items, and menu items with a recipe, each with stock on hand and a suggested cost.</summary>
        [HttpGet("items")]
        public async Task<IActionResult> Items([FromQuery] string farmId)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.OptionsAsync(farmId)); }

        [HttpPost]
        public async Task<IActionResult> Create([FromBody] RestaurantInternalUseSaveRequest r)
        {
            var d = Deny(r.FarmId); if (d != null) return d;
            var bad = Validate(r); if (bad != null) return BadRequest(new { message = bad });
            var id = await _svc.CreateAsync(r, Me);
            return Ok(await _svc.GetAsync(r.FarmId, id));
        }

        [HttpPut("{id:int}")]
        public async Task<IActionResult> Update(int id, [FromBody] RestaurantInternalUseSaveRequest r)
        {
            var d = Deny(r.FarmId); if (d != null) return d;
            var bad = Validate(r); if (bad != null) return BadRequest(new { message = bad });
            await _svc.UpdateAsync(id, r, Me);
            return Ok(await _svc.GetAsync(r.FarmId, id));
        }

        [HttpDelete("{id:int}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string farmId)
        { var d = Deny(farmId); if (d != null) return d; await _svc.DeleteAsync(farmId, id, Me); return NoContent(); }

        [HttpPost("{id:int}/post")]
        public async Task<IActionResult> Post(int id, [FromQuery] string farmId)
        { var d = Deny(farmId); if (d != null) return d; await _svc.PostAsync(farmId, id, Me); return Ok(await _svc.GetAsync(farmId, id)); }

        [HttpPost("{id:int}/reverse")]
        public async Task<IActionResult> Reverse(int id, [FromBody] RestaurantInternalUseReverseRequest r)
        {
            var d = Deny(r.FarmId); if (d != null) return d;
            await _svc.ReverseAsync(r.FarmId, id, r.Reason, Me);
            return Ok(await _svc.GetAsync(r.FarmId, id));
        }

        private static string? Validate(RestaurantInternalUseSaveRequest r)
        {
            if (!Categories.Contains(r.Category)) return "Pick what the stock was used for.";
            if (r.UsageDate.Date > DateTime.UtcNow.Date) return "The date cannot be in the future.";
            if (r.Items is null || r.Items.Count == 0) return "Add at least one product.";
            if (r.Items.Exists(i => (i.ItemType == "MenuItem" ? i.MenuItemId : i.IngredientId) is null or <= 0))
                return "Every line needs a product.";
            if (r.Items.Exists(i => i.EntryQuantity <= 0)) return "Every line needs a quantity greater than zero.";
            if (r.StaffCount is <= 0) return "Staff count must be greater than zero.";
            return null;
        }
    }
}
