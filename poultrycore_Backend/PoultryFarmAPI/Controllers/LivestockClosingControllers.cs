// Livestock endpoints from migration 464: daily closing, missing records,
// drivers / vehicles / routes, deliveries and driver returns.
//
// PERMISSIONS (IamPermissionMap): livestock/daily-closing, livestock/missing-records
// (-> livestock.production-records), livestock/drivers, livestock/vehicles,
// livestock/routes, livestock/deliveries, livestock/driver-returns.
// A closed day refuses every change dated on it (LV006, 409) -- enforced by
// triggers in the database, not here.

using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Filters;
using static PoultryFarmAPIWeb.Business.LivestockDb;

namespace PoultryFarmAPIWeb.Controllers
{
    [Authorize]
    [ApiController]
    [Route("api/Livestock/daily-closing")]
    [RequireCompanyType("Livestock")]
    public class LivestockDailyClosingController : LivestockControllerBase
    {
        public LivestockDailyClosingController(ILivestockDb db) : base(db) { }

        [HttpGet]
        public Task<IActionResult> List([FromQuery] string farmId, [FromQuery] int days = 60)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockday_list", Text("p_farmid", farmId), Int("p_days", Math.Clamp(days, 1, 366)))));

        [HttpGet("{date}")]
        public Task<IActionResult> Summary(DateTime date, [FromQuery] string farmId)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockday_summary", Text("p_farmid", farmId), Date("p_date", date))));

        /// <summary>Body: { farmId, acknowledge, notes }.</summary>
        [HttpPut("{date}/closure")]
        public Task<IActionResult> Close(DateTime date, [FromBody] JsonElement body)
            => Write(FarmOf(body), async by => JsonText(await Db.JsonAsync("splivestockday_close", Text("p_farmid", FarmOf(body)), Date("p_date", date),
                Bool("p_acknowledge", body.TryGetProperty("acknowledge", out var a) && a.ValueKind == JsonValueKind.True),
                Text("p_notes", Str(body, "notes")), Text("p_by", by))));

        /// <summary>Body: { farmId, reason }.</summary>
        [HttpPut("{date}/reopening")]
        public Task<IActionResult> Reopen(DateTime date, [FromBody] JsonElement body)
            => Write(FarmOf(body), async by =>
            {
                await Db.ExecAsync("splivestockday_reopen", Text("p_farmid", FarmOf(body)), Date("p_date", date),
                    Text("p_reason", Str(body, "reason")), Text("p_by", by));
                return NoContent();
            });
    }

    [Authorize]
    [ApiController]
    [Route("api/Livestock/missing-records")]
    [RequireCompanyType("Livestock")]
    public class LivestockMissingRecordsController : LivestockControllerBase
    {
        public LivestockMissingRecordsController(ILivestockDb db) : base(db) { }

        [HttpGet]
        public Task<IActionResult> Get([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestock_missingdays", Text("p_farmid", farmId), Date("p_from", from), Date("p_to", to))));
    }

    /// <summary>Drivers, vehicles and routes share one shape.</summary>
    public abstract class LivestockFleetController : LivestockControllerBase
    {
        private readonly string _kind;
        protected LivestockFleetController(ILivestockDb db, string kind) : base(db) => _kind = kind;

        [HttpGet]
        public Task<IActionResult> List([FromQuery] string farmId, [FromQuery] bool includeInactive = false)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockfleet_list", Text("p_farmid", farmId), Text("p_kind", _kind),
                Bool("p_includeinactive", includeInactive))));

        [HttpPost]
        public Task<IActionResult> Create([FromBody] JsonElement body) => Save(null, body);

        [HttpPut("{id:int}")]
        public Task<IActionResult> Update(int id, [FromBody] JsonElement body) => Save(id, body);

        private Task<IActionResult> Save(int? id, JsonElement body)
            => Write(FarmOf(body), async by => Ok(new
            {
                id = await Db.IntAsync("splivestockfleet_save", Text("p_farmid", FarmOf(body)), Text("p_kind", _kind),
                    Jsonb("p_x", LivestockPenController.WithId(body, "id", id)), Text("p_by", by)),
            }));
    }

    [Authorize, ApiController, SetupAdminOnly, Route("api/Livestock/drivers"), RequireCompanyType("Livestock")]
    public class LivestockDriverController : LivestockFleetController { public LivestockDriverController(ILivestockDb db) : base(db, "Driver") { } }

    [Authorize, ApiController, SetupAdminOnly, Route("api/Livestock/vehicles"), RequireCompanyType("Livestock")]
    public class LivestockVehicleController : LivestockFleetController { public LivestockVehicleController(ILivestockDb db) : base(db, "Vehicle") { } }

    [Authorize, ApiController, SetupAdminOnly, Route("api/Livestock/routes"), RequireCompanyType("Livestock")]
    public class LivestockRouteController : LivestockFleetController { public LivestockRouteController(ILivestockDb db) : base(db, "Route") { } }

    [Authorize]
    [ApiController]
    [Route("api/Livestock/deliveries")]
    [RequireCompanyType("Livestock")]
    public class LivestockDeliveryController : LivestockControllerBase
    {
        public LivestockDeliveryController(ILivestockDb db) : base(db) { }

        [HttpGet]
        public Task<IActionResult> List([FromQuery] string farmId, [FromQuery] string? status, [FromQuery] int? driverId,
                                        [FromQuery] DateTime? from, [FromQuery] DateTime? to)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockdelivery_list", Text("p_farmid", farmId),
                Jsonb("p_filter", LsJson.Filter(new { status, driverId, from = from?.ToString("yyyy-MM-dd"), to = to?.ToString("yyyy-MM-dd") })))));

        /// <summary>Sales a driver can take.</summary>
        [HttpGet("options")]
        public Task<IActionResult> Options([FromQuery] string farmId)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockdelivery_options", Text("p_farmid", farmId))));

        [HttpGet("driver-report")]
        public Task<IActionResult> DriverReport([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockdriver_report", Text("p_farmid", farmId), Date("p_from", from), Date("p_to", to))));

        /// <summary>Body: { farmId, date, driverId, vehicleId, routeId, notes, saleIds: [] }.</summary>
        [HttpPost]
        public Task<IActionResult> SendOut([FromBody] JsonElement body)
            => Write(FarmOf(body), async by => Ok(new
            {
                deliveryId = await Db.IntAsync("splivestockdelivery_post", Text("p_farmid", FarmOf(body)), Jsonb("p_d", body.GetRawText()), Text("p_by", by)),
            }));

        [HttpPut("{id:int}/cancellation")]
        public Task<IActionResult> Cancel(int id, [FromBody] JsonElement body)
            => Write(FarmOf(body), async by =>
            {
                await Db.ExecAsync("splivestockdelivery_cancel", Text("p_farmid", FarmOf(body)), Int("p_id", id), Text("p_by", by));
                return NoContent();
            });
    }

    [Authorize]
    [ApiController]
    [Route("api/Livestock/driver-returns")]
    [RequireCompanyType("Livestock")]
    public class LivestockDriverReturnController : LivestockControllerBase
    {
        public LivestockDriverReturnController(ILivestockDb db) : base(db) { }

        /// <summary>Body: { farmId, accountId, notes, collections: [{ saleId, amount }] }.</summary>
        [HttpPost("{deliveryId:int}")]
        public Task<IActionResult> Return(int deliveryId, [FromBody] JsonElement body)
            => Write(FarmOf(body), async by => JsonText(await Db.JsonAsync("splivestockdelivery_return", Text("p_farmid", FarmOf(body)),
                Int("p_id", deliveryId), Jsonb("p_r", body.GetRawText()), Text("p_by", by))));
    }
}
