// Livestock endpoints from migration 459: stock items and their ledger, daily
// production records, breeding & births, weigh-ins and growth.
//
// PERMISSIONS (IamPermissionMap): livestock/items -> livestock.items,
// livestock/stock -> livestock.stock, livestock/production-records ->
// livestock.production-records, livestock/breeding -> livestock.breeding,
// livestock/weigh-ins -> livestock.weigh-ins. Reversals are POSTs to
// .../reversal, never a segment named "reverse".

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
    [Route("api/Livestock/items")]
    [RequireCompanyType("Livestock")]
    public class LivestockItemController : LivestockControllerBase
    {
        public LivestockItemController(ILivestockDb db) : base(db) { }

        /// <summary>category: Feed | Medication | Vaccine | Supply | Other | Health (medication + vaccine).</summary>
        [HttpGet]
        public Task<IActionResult> List([FromQuery] string farmId, [FromQuery] string? category, [FromQuery] bool includeInactive = false)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockitem_list", Text("p_farmid", farmId),
                Text("p_category", string.IsNullOrWhiteSpace(category) ? null : category), Bool("p_includeinactive", includeInactive))));

        [HttpGet("{id:int}")]
        public Task<IActionResult> Get(int id, [FromQuery] string farmId)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockitem_get", Text("p_farmid", farmId), Int("p_itemid", id))));

        [HttpPost]
        public Task<IActionResult> Create([FromBody] JsonElement body) => Save(null, body);

        [HttpPut("{id:int}")]
        public Task<IActionResult> Update(int id, [FromBody] JsonElement body) => Save(id, body);

        private Task<IActionResult> Save(int? id, JsonElement body)
            => Write(FarmOf(body), async by => Ok(new
            {
                itemId = await Db.IntAsync("splivestockitem_save", Text("p_farmid", FarmOf(body)),
                    Jsonb("p_item", LivestockPenController.WithId(body, "itemId", id)), Text("p_by", by)),
            }));

        [HttpDelete("{id:int}")]
        public Task<IActionResult> Delete(int id, [FromQuery] string farmId)
            => Write(farmId, async by =>
            {
                await Db.ExecAsync("splivestockitem_delete", Text("p_farmid", farmId), Int("p_itemid", id), Text("p_by", by));
                return NoContent();
            });
    }

    [Authorize]
    [ApiController]
    [Route("api/Livestock/stock")]
    [RequireCompanyType("Livestock")]
    public class LivestockStockController : LivestockControllerBase
    {
        public LivestockStockController(ILivestockDb db) : base(db) { }

        /// <summary>Body: { farmId, itemId, date, type: StockIn|Adjustment, quantity (signed for Adjustment), unitCost, notes }.</summary>
        [HttpPost]
        public Task<IActionResult> Adjust([FromBody] JsonElement body)
            => Write(FarmOf(body), async by =>
            {
                decimal? qty = body.TryGetProperty("quantity", out var q) && q.ValueKind == JsonValueKind.Number ? q.GetDecimal() : null;
                decimal? cost = body.TryGetProperty("unitCost", out var c) && c.ValueKind == JsonValueKind.Number ? c.GetDecimal() : null;
                return JsonText(await Db.JsonAsync("splivestockstock_adjust", Text("p_farmid", FarmOf(body)),
                    Int("p_itemid", IntOf(body, "itemId")), Date("p_date", DateOf(body, "date")), Text("p_type", Str(body, "type")),
                    new LsArg("p_quantity", qty, NpgsqlTypes.NpgsqlDbType.Numeric),
                    new LsArg("p_unitcost", cost, NpgsqlTypes.NpgsqlDbType.Numeric),
                    Text("p_notes", Str(body, "notes")), Text("p_by", by)));
            });

        /// <summary>Body: { farmId, reason }.</summary>
        [HttpPost("{movementId:int}/reversal")]
        public Task<IActionResult> Reverse(int movementId, [FromBody] JsonElement body)
            => Write(FarmOf(body), async by =>
            {
                await Db.ExecAsync("splivestockstock_reverse", Text("p_farmid", FarmOf(body)), Int("p_movementid", movementId),
                    Text("p_reason", Str(body, "reason")), Text("p_by", by));
                return NoContent();
            });
    }

    [Authorize]
    [ApiController]
    [Route("api/Livestock/production-records")]
    [RequireCompanyType("Livestock")]
    public class LivestockProductionController : LivestockControllerBase
    {
        public LivestockProductionController(ILivestockDb db) : base(db) { }

        [HttpGet]
        public Task<IActionResult> List([FromQuery] string farmId, [FromQuery] int? groupId, [FromQuery] string? speciesCode,
                                        [FromQuery] DateTime? from, [FromQuery] DateTime? to)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockproduction_list", Text("p_farmid", farmId),
                Jsonb("p_filter", JsonSerializer.Serialize(new
                {
                    groupId, speciesCode, from = from?.ToString("yyyy-MM-dd"), to = to?.ToString("yyyy-MM-dd"),
                })))));

        [HttpGet("{id:int}")]
        public Task<IActionResult> Get(int id, [FromQuery] string farmId)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockproduction_get", Text("p_farmid", farmId), Int("p_recordid", id))));

        /// <summary>What the form needs for a group on a date (head that morning, an existing record, outputs).</summary>
        [HttpGet("form")]
        public Task<IActionResult> Form([FromQuery] string farmId, [FromQuery] int groupId, [FromQuery] DateTime date)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockproduction_form", Text("p_farmid", farmId),
                Int("p_groupid", groupId), Date("p_date", date))));

        [HttpPost]
        public Task<IActionResult> Create([FromBody] JsonElement body) => Save(null, body);

        [HttpPut("{id:int}")]
        public Task<IActionResult> Update(int id, [FromBody] JsonElement body) => Save(id, body);

        private Task<IActionResult> Save(int? id, JsonElement body)
            => Write(FarmOf(body), async by => Ok(new
            {
                recordId = await Db.IntAsync("splivestockproduction_save", Text("p_farmid", FarmOf(body)),
                    Jsonb("p_record", LivestockPenController.WithId(body, "recordId", id)), Text("p_by", by)),
            }));

        [HttpDelete("{id:int}")]
        public Task<IActionResult> Delete(int id, [FromQuery] string farmId)
            => Write(farmId, async by =>
            {
                await Db.ExecAsync("splivestockproduction_delete", Text("p_farmid", farmId), Int("p_recordid", id), Text("p_by", by));
                return NoContent();
            });
    }

    [Authorize]
    [ApiController]
    [Route("api/Livestock/breeding")]
    [RequireCompanyType("Livestock")]
    public class LivestockBreedingController : LivestockControllerBase
    {
        public LivestockBreedingController(ILivestockDb db) : base(db) { }

        [HttpGet]
        public Task<IActionResult> List([FromQuery] string farmId, [FromQuery] int? damId, [FromQuery] int? groupId,
                                        [FromQuery] string? speciesCode, [FromQuery] string? eventType,
                                        [FromQuery] DateTime? from, [FromQuery] DateTime? to)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockbreeding_list", Text("p_farmid", farmId),
                Jsonb("p_filter", JsonSerializer.Serialize(new
                {
                    damId, groupId, speciesCode, eventType, from = from?.ToString("yyyy-MM-dd"), to = to?.ToString("yyyy-MM-dd"),
                })))));

        /// <summary>Females mated and not yet resolved, by due date.</summary>
        [HttpGet("due")]
        public Task<IActionResult> Due([FromQuery] string farmId)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockbreeding_due", Text("p_farmid", farmId))));

        [HttpPost]
        public Task<IActionResult> Create([FromBody] JsonElement body) => Save(null, body);

        [HttpPut("{id:int}")]
        public Task<IActionResult> Update(int id, [FromBody] JsonElement body) => Save(id, body);

        private Task<IActionResult> Save(int? id, JsonElement body)
            => Write(FarmOf(body), async by => Ok(new
            {
                eventId = await Db.IntAsync("splivestockbreeding_save", Text("p_farmid", FarmOf(body)),
                    Jsonb("p_event", LivestockPenController.WithId(body, "eventId", id)), Text("p_by", by)),
            }));

        [HttpDelete("{id:int}")]
        public Task<IActionResult> Delete(int id, [FromQuery] string farmId)
            => Write(farmId, async by =>
            {
                await Db.ExecAsync("splivestockbreeding_delete", Text("p_farmid", farmId), Int("p_eventid", id), Text("p_by", by));
                return NoContent();
            });
    }

    [Authorize]
    [ApiController]
    [Route("api/Livestock/weigh-ins")]
    [RequireCompanyType("Livestock")]
    public class LivestockWeighInController : LivestockControllerBase
    {
        public LivestockWeighInController(ILivestockDb db) : base(db) { }

        /// <summary>A group's weigh-ins with daily gain and feed conversion.</summary>
        [HttpGet("growth/{groupId:int}")]
        public Task<IActionResult> Growth(int groupId, [FromQuery] string farmId)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockgrowth", Text("p_farmid", farmId), Int("p_groupid", groupId))));

        [HttpGet("animal/{animalId:int}")]
        public Task<IActionResult> Animal(int animalId, [FromQuery] string farmId)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockweighin_animal", Text("p_farmid", farmId), Int("p_animalid", animalId))));

        [HttpPost]
        public Task<IActionResult> Create([FromBody] JsonElement body) => Save(null, body);

        [HttpPut("{id:int}")]
        public Task<IActionResult> Update(int id, [FromBody] JsonElement body) => Save(id, body);

        private Task<IActionResult> Save(int? id, JsonElement body)
            => Write(FarmOf(body), async by => Ok(new
            {
                weighInId = await Db.IntAsync("splivestockweighin_save", Text("p_farmid", FarmOf(body)),
                    Jsonb("p_w", LivestockPenController.WithId(body, "weighInId", id)), Text("p_by", by)),
            }));

        [HttpDelete("{id:int}")]
        public Task<IActionResult> Delete(int id, [FromQuery] string farmId)
            => Write(farmId, async by =>
            {
                await Db.ExecAsync("splivestockweighin_delete", Text("p_farmid", farmId), Int("p_weighinid", id), Text("p_by", by));
                return NoContent();
            });
    }
}
