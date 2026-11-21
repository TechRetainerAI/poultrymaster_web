// Livestock reports and trackers (migration 465). Read-only.
// PERMISSIONS: api/Livestock/reports -> livestock.reports (view).

using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Filters;
using static PoultryFarmAPIWeb.Business.LivestockDb;

namespace PoultryFarmAPIWeb.Controllers
{
    [Authorize]
    [ApiController]
    [Route("api/Livestock/reports")]
    [RequireCompanyType("Livestock")]
    public class LivestockReportController : LivestockControllerBase
    {
        public LivestockReportController(ILivestockDb db) : base(db) { }

        private Task<IActionResult> Period(string fn, string farmId, DateTime from, DateTime to)
            => Read(farmId, async () => JsonText(await Db.JsonAsync(fn, Text("p_farmid", farmId), Date("p_from", from), Date("p_to", to))));

        [HttpGet("production")]
        public Task<IActionResult> Production([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to, [FromQuery] string? speciesCode)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockreport_production", Text("p_farmid", farmId),
                Date("p_from", from), Date("p_to", to), Text("p_speciescode", string.IsNullOrWhiteSpace(speciesCode) ? null : speciesCode))));

        [HttpGet("feed")]
        public Task<IActionResult> Feed([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to)
            => Period("splivestockreport_feed", farmId, from, to);

        [HttpGet("medicine")]
        public Task<IActionResult> Medicine([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to)
            => Period("splivestockreport_medicine", farmId, from, to);

        [HttpGet("sales")]
        public Task<IActionResult> Sales([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to)
            => Period("splivestockreport_sales", farmId, from, to);

        [HttpGet("mortality")]
        public Task<IActionResult> Mortality([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to)
            => Period("splivestockreport_mortality", farmId, from, to);

        [HttpGet("breeding")]
        public Task<IActionResult> Breeding([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to)
            => Period("splivestockreport_breeding", farmId, from, to);

        [HttpGet("herd")]
        public Task<IActionResult> Herd([FromQuery] string farmId)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockreport_herd", Text("p_farmid", farmId))));

        [HttpGet("group-summary/{groupId:int}")]
        public Task<IActionResult> GroupSummary(int groupId, [FromQuery] string farmId)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockreport_groupsummary", Text("p_farmid", farmId), Int("p_groupid", groupId))));

        /// <summary>kind: Deaths | Eggs | Milk | Feed | Head; month: any date in the month.</summary>
        [HttpGet("tracker")]
        public Task<IActionResult> Tracker([FromQuery] string farmId, [FromQuery] DateTime month, [FromQuery] string kind)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestocktracker", Text("p_farmid", farmId), Date("p_month", month), Text("p_kind", kind))));
    }
}
