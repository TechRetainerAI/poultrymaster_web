// Livestock foundation endpoints (migration 458): species kept, pens, intake
// batches, groups and their head changes, tagged animals, and the overview.
//
// PERMISSIONS (IamPermissionMap): api/Livestock/<resource> -> livestock.<resource>,
// action from the verb. Each livestock key mirrors its poultry twin
// (pens <- houses, groups <- flocks, batches <- flock-batches). Species and
// pens are company setup, so writes are owner/admin only (SetupAdminOnly), the
// same as poultry houses; groups, batches and animals are daily work.
// Reversals are POSTs to .../reversal -- never a segment named "reverse",
// which the map would turn into the approve action.

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
    [SetupAdminOnly]
    [Route("api/Livestock/species")]
    [RequireCompanyType("Livestock")]
    public class LivestockSpeciesController : LivestockControllerBase
    {
        public LivestockSpeciesController(ILivestockDb db) : base(db) { }

        [HttpGet]
        public Task<IActionResult> List([FromQuery] string farmId)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockspecies_list", Text("p_farmid", farmId))));

        /// <summary>Body: { farmId, speciesCodes: ["goat", "rabbit"] } -- the full set the farm keeps.</summary>
        [HttpPut]
        public Task<IActionResult> Set([FromBody] JsonElement body)
            => Write(FarmOf(body), async by =>
            {
                var codes = body.TryGetProperty("speciesCodes", out var a) && a.ValueKind == JsonValueKind.Array
                    ? a.EnumerateArray().Where(e => e.ValueKind == JsonValueKind.String).Select(e => e.GetString()!).ToArray()
                    : Array.Empty<string>();
                return JsonText(await Db.JsonAsync("splivestockspecies_set",
                    Text("p_farmid", FarmOf(body)), TextArray("p_codes", codes), Text("p_by", by)));
            });
    }

    [Authorize]
    [ApiController]
    [SetupAdminOnly]
    [Route("api/Livestock/pens")]
    [RequireCompanyType("Livestock")]
    public class LivestockPenController : LivestockControllerBase
    {
        public LivestockPenController(ILivestockDb db) : base(db) { }

        [HttpGet]
        public Task<IActionResult> List([FromQuery] string farmId)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockpen_list", Text("p_farmid", farmId))));

        [HttpPost]
        public Task<IActionResult> Create([FromBody] JsonElement body) => Save(null, body);

        [HttpPut("{id:int}")]
        public Task<IActionResult> Update(int id, [FromBody] JsonElement body) => Save(id, body);

        private Task<IActionResult> Save(int? id, JsonElement body)
            => Write(FarmOf(body), async by =>
            {
                var pen = WithId(body, "penId", id);
                var newId = await Db.IntAsync("splivestockpen_save", Text("p_farmid", FarmOf(body)), Jsonb("p_pen", pen), Text("p_by", by));
                return Ok(new { penId = newId });
            });

        [HttpDelete("{id:int}")]
        public Task<IActionResult> Delete(int id, [FromQuery] string farmId)
            => Write(farmId, async by =>
            {
                await Db.ExecAsync("splivestockpen_delete", Text("p_farmid", farmId), Int("p_penid", id), Text("p_by", by));
                return NoContent();
            });

        /// <summary>The body with the route id written into it, so a body cannot edit a different row.</summary>
        internal static string WithId(JsonElement body, string key, int? id)
        {
            var dict = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(body.GetRawText()) ?? new();
            dict.Remove(key);
            var json = JsonSerializer.Serialize(dict);
            if (id is null) return json;
            return json.Length <= 2 ? $"{{\"{key}\":{id}}}" : $"{{\"{key}\":{id},{json[1..]}";
        }
    }

    [Authorize]
    [ApiController]
    [Route("api/Livestock/batches")]
    [RequireCompanyType("Livestock")]
    public class LivestockBatchController : LivestockControllerBase
    {
        public LivestockBatchController(ILivestockDb db) : base(db) { }

        [HttpGet]
        public Task<IActionResult> List([FromQuery] string farmId)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockbatch_list", Text("p_farmid", farmId))));

        [HttpPost]
        public Task<IActionResult> Create([FromBody] JsonElement body) => Save(null, body);

        [HttpPut("{id:int}")]
        public Task<IActionResult> Update(int id, [FromBody] JsonElement body) => Save(id, body);

        private Task<IActionResult> Save(int? id, JsonElement body)
            => Write(FarmOf(body), async by =>
            {
                var newId = await Db.IntAsync("splivestockbatch_save", Text("p_farmid", FarmOf(body)),
                    Jsonb("p_batch", LivestockPenController.WithId(body, "batchId", id)), Text("p_by", by));
                return Ok(new { batchId = newId });
            });

        [HttpDelete("{id:int}")]
        public Task<IActionResult> Delete(int id, [FromQuery] string farmId)
            => Write(farmId, async by =>
            {
                await Db.ExecAsync("splivestockbatch_delete", Text("p_farmid", farmId), Int("p_batchid", id), Text("p_by", by));
                return NoContent();
            });

        /// <summary>Divide into groups. Body: { farmId, startDate, groups: [{ name, penId, quantity, purpose, notes }] }.</summary>
        [HttpPost("{id:int}/groups")]
        public Task<IActionResult> Divide(int id, [FromBody] JsonElement body)
            => Write(FarmOf(body), async by =>
            {
                var groups = body.TryGetProperty("groups", out var g) ? g.GetRawText() : "[]";
                return JsonText(await Db.JsonAsync("splivestockbatch_divide", Text("p_farmid", FarmOf(body)), Int("p_batchid", id),
                    Date("p_startdate", DateOf(body, "startDate")), Jsonb("p_groups", groups), Text("p_by", by)));
            });
    }

    [Authorize]
    [ApiController]
    [Route("api/Livestock/groups")]
    [RequireCompanyType("Livestock")]
    public class LivestockGroupController : LivestockControllerBase
    {
        public LivestockGroupController(ILivestockDb db) : base(db) { }

        [HttpGet]
        public Task<IActionResult> List([FromQuery] string farmId, [FromQuery] bool includeClosed = false)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockgroup_list",
                Text("p_farmid", farmId), Bool("p_includeclosed", includeClosed))));

        [HttpGet("{id:int}")]
        public Task<IActionResult> Get(int id, [FromQuery] string farmId)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockgroup_get", Text("p_farmid", farmId), Int("p_groupid", id))));

        [HttpPost]
        public Task<IActionResult> Create([FromBody] JsonElement body) => Save(null, body);

        [HttpPut("{id:int}")]
        public Task<IActionResult> Update(int id, [FromBody] JsonElement body) => Save(id, body);

        private Task<IActionResult> Save(int? id, JsonElement body)
            => Write(FarmOf(body), async by =>
            {
                var newId = await Db.IntAsync("splivestockgroup_save", Text("p_farmid", FarmOf(body)),
                    Jsonb("p_group", LivestockPenController.WithId(body, "groupId", id)), Text("p_by", by));
                return Ok(new { groupId = newId });
            });

        [HttpDelete("{id:int}")]
        public Task<IActionResult> Delete(int id, [FromQuery] string farmId)
            => Write(farmId, async by =>
            {
                await Db.ExecAsync("splivestockgroup_delete", Text("p_farmid", farmId), Int("p_groupid", id), Text("p_by", by));
                return NoContent();
            });

        /// <summary>Body: { farmId, date, reason }.</summary>
        [HttpPut("{id:int}/closure")]
        public Task<IActionResult> Close(int id, [FromBody] JsonElement body)
            => Write(FarmOf(body), async by =>
            {
                await Db.ExecAsync("splivestockgroup_close", Text("p_farmid", FarmOf(body)), Int("p_groupid", id),
                    Date("p_date", DateOf(body, "date")), Text("p_reason", Str(body, "reason")), Text("p_by", by));
                return NoContent();
            });

        [HttpPut("{id:int}/reopening")]
        public Task<IActionResult> Reopen(int id, [FromBody] JsonElement body)
            => Write(FarmOf(body), async by =>
            {
                await Db.ExecAsync("splivestockgroup_reopen", Text("p_farmid", FarmOf(body)), Int("p_groupid", id), Text("p_by", by));
                return NoContent();
            });

        /// <summary>A manual head change. Body: { farmId, date, type: Death|Cull|Correction|Transfer, quantity, notes, toGroupId }.</summary>
        [HttpPost("{id:int}/movements")]
        public Task<IActionResult> Adjust(int id, [FromBody] JsonElement body)
            => Write(FarmOf(body), async by => JsonText(await Db.JsonAsync("splivestockhead_adjust",
                Text("p_farmid", FarmOf(body)), Int("p_groupid", id), Date("p_date", DateOf(body, "date")),
                Text("p_type", Str(body, "type")), Int("p_quantity", IntOf(body, "quantity")),
                Text("p_notes", Str(body, "notes")), Text("p_by", by), Int("p_togroupid", IntOf(body, "toGroupId")))));

        /// <summary>Body: { farmId, reason }.</summary>
        [HttpPost("movements/{movementId:int}/reversal")]
        public Task<IActionResult> Reverse(int movementId, [FromBody] JsonElement body)
            => Write(FarmOf(body), async by =>
            {
                await Db.ExecAsync("splivestockhead_reverse", Text("p_farmid", FarmOf(body)), Int("p_movementid", movementId),
                    Text("p_reason", Str(body, "reason")), Text("p_by", by));
                return NoContent();
            });
    }

    [Authorize]
    [ApiController]
    [Route("api/Livestock/animals")]
    [RequireCompanyType("Livestock")]
    public class LivestockAnimalController : LivestockControllerBase
    {
        public LivestockAnimalController(ILivestockDb db) : base(db) { }

        [HttpGet]
        public Task<IActionResult> List([FromQuery] string farmId, [FromQuery] int? groupId, [FromQuery] string? speciesCode,
                                        [FromQuery] string? status, [FromQuery] string? search)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockanimal_list", Text("p_farmid", farmId),
                Jsonb("p_filter", JsonSerializer.Serialize(new { groupId, speciesCode, status, search })))));

        [HttpGet("{id:int}")]
        public Task<IActionResult> Get(int id, [FromQuery] string farmId)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockanimal_get", Text("p_farmid", farmId), Int("p_animalid", id))));

        [HttpPost]
        public Task<IActionResult> Create([FromBody] JsonElement body) => Save(null, body);

        /// <summary>
        /// Tag several animals into one group at once (468). Body: { farmId, groupId, addsToHead,
        /// source, acquiredDate, purchaseCost, breed, animals: [{ tagNumber, name, sex, breed, birthDate, notes,
        /// damId, sireId, damTag, sireTag }] }. damTag / sireTag name a parent in the same list (472).
        /// All or nothing. Returns { animalIds: [...] }.
        /// </summary>
        [HttpPost("many")]
        public Task<IActionResult> CreateMany([FromBody] JsonElement body)
            => Write(FarmOf(body), async by =>
            {
                var ids = await Db.JsonAsync("splivestockanimal_savemany", Text("p_farmid", FarmOf(body)),
                    Jsonb("p_animals", body.GetRawText()), Text("p_by", by));
                return JsonText($"{{\"animalIds\":{ids}}}");
            });

        [HttpPut("{id:int}")]
        public Task<IActionResult> Update(int id, [FromBody] JsonElement body) => Save(id, body);

        private Task<IActionResult> Save(int? id, JsonElement body)
            => Write(FarmOf(body), async by =>
            {
                var newId = await Db.IntAsync("splivestockanimal_save", Text("p_farmid", FarmOf(body)),
                    Jsonb("p_animal", LivestockPenController.WithId(body, "animalId", id)), Text("p_by", by));
                return Ok(new { animalId = newId });
            });

        [HttpDelete("{id:int}")]
        public Task<IActionResult> Delete(int id, [FromQuery] string farmId)
            => Write(farmId, async by =>
            {
                await Db.ExecAsync("splivestockanimal_delete", Text("p_farmid", farmId), Int("p_animalid", id), Text("p_by", by));
                return NoContent();
            });

        /// <summary>Body: { farmId, status: Active|Sold|Dead|Culled, date, notes }.</summary>
        [HttpPut("{id:int}/status")]
        public Task<IActionResult> SetStatus(int id, [FromBody] JsonElement body)
            => Write(FarmOf(body), async by =>
            {
                await Db.ExecAsync("splivestockanimal_setstatus", Text("p_farmid", FarmOf(body)), Int("p_animalid", id),
                    Text("p_status", Str(body, "status")), Date("p_date", DateOf(body, "date")),
                    Text("p_notes", Str(body, "notes")), Text("p_by", by));
                return NoContent();
            });

        /// <summary>Body: { farmId, toGroupId, date }.</summary>
        [HttpPut("{id:int}/group")]
        public Task<IActionResult> Move(int id, [FromBody] JsonElement body)
            => Write(FarmOf(body), async by =>
            {
                await Db.ExecAsync("splivestockanimal_move", Text("p_farmid", FarmOf(body)), Int("p_animalid", id),
                    Int("p_togroupid", IntOf(body, "toGroupId")), Date("p_date", DateOf(body, "date")), Text("p_by", by));
                return NoContent();
            });
    }

    [Authorize]
    [ApiController]
    [Route("api/Livestock/overview")]
    [RequireCompanyType("Livestock")]
    public class LivestockOverviewController : LivestockControllerBase
    {
        public LivestockOverviewController(ILivestockDb db) : base(db) { }

        [HttpGet]
        public Task<IActionResult> Get([FromQuery] string farmId)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestock_overview", Text("p_farmid", farmId))));
    }
}
