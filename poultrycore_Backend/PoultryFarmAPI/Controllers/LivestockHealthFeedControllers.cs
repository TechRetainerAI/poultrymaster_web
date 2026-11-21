// Livestock endpoints from migration 460: health records, vaccination plans
// and what is due, treatment campaigns, feed formulas and mixing, feeding many
// groups at once, days of supply, alerts.
//
// PERMISSIONS (IamPermissionMap): livestock/health, livestock/vaccination,
// livestock/treatments, livestock/feed-formulas, livestock/feed-production
// (mixing runs), livestock/feed-distribution -> livestock.production-records
// (it writes daily records), livestock/feed-supply -> livestock.items,
// livestock/alerts. Reversals and closings are POST/PUT to named segments,
// never "reverse" or "post", which the map would turn into approve.

using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NpgsqlTypes;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Filters;
using static PoultryFarmAPIWeb.Business.LivestockDb;

namespace PoultryFarmAPIWeb.Controllers
{
    internal static class LsJson
    {
        public static decimal? Dec(JsonElement b, string name)
        {
            if (b.ValueKind != JsonValueKind.Object || !b.TryGetProperty(name, out var v)) return null;
            if (v.ValueKind == JsonValueKind.Number) return v.GetDecimal();
            if (v.ValueKind == JsonValueKind.String && decimal.TryParse(v.GetString(), out var d)) return d;
            return null;
        }
        public static string Raw(JsonElement b, string name, string fallback = "[]")
            => b.ValueKind == JsonValueKind.Object && b.TryGetProperty(name, out var v) && v.ValueKind != JsonValueKind.Null ? v.GetRawText() : fallback;
        public static LsArg Num(string name, decimal? v) => new(name, v, NpgsqlDbType.Numeric);
        public static string Filter(object o) => JsonSerializer.Serialize(o);
    }

    [Authorize]
    [ApiController]
    [Route("api/Livestock/health")]
    [RequireCompanyType("Livestock")]
    public class LivestockHealthController : LivestockControllerBase
    {
        public LivestockHealthController(ILivestockDb db) : base(db) { }

        [HttpGet]
        public Task<IActionResult> List([FromQuery] string farmId, [FromQuery] int? groupId, [FromQuery] int? animalId,
                                        [FromQuery] string? kind, [FromQuery] string? status, [FromQuery] DateTime? from, [FromQuery] DateTime? to)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockhealth_list", Text("p_farmid", farmId),
                Jsonb("p_filter", LsJson.Filter(new { groupId, animalId, kind, status,
                    from = from?.ToString("yyyy-MM-dd"), to = to?.ToString("yyyy-MM-dd") })))));

        [HttpPost]
        public Task<IActionResult> Create([FromBody] JsonElement body) => Save(null, body);

        [HttpPut("{id:int}")]
        public Task<IActionResult> Update(int id, [FromBody] JsonElement body) => Save(id, body);

        private Task<IActionResult> Save(int? id, JsonElement body)
            => Write(FarmOf(body), async by => Ok(new
            {
                healthId = await Db.IntAsync("splivestockhealth_save", Text("p_farmid", FarmOf(body)),
                    Jsonb("p_h", LivestockPenController.WithId(body, "healthId", id)), Text("p_by", by)),
            }));

        [HttpDelete("{id:int}")]
        public Task<IActionResult> Delete(int id, [FromQuery] string farmId)
            => Write(farmId, async by =>
            {
                await Db.ExecAsync("splivestockhealth_delete", Text("p_farmid", farmId), Int("p_id", id), Text("p_by", by));
                return NoContent();
            });
    }

    [Authorize]
    [ApiController]
    [Route("api/Livestock/vaccination")]
    [RequireCompanyType("Livestock")]
    public class LivestockVaccinationController : LivestockControllerBase
    {
        public LivestockVaccinationController(ILivestockDb db) : base(db) { }

        /// <summary>What is due within horizonDays (and everything overdue).</summary>
        [HttpGet("due")]
        public Task<IActionResult> Due([FromQuery] string farmId, [FromQuery] int horizonDays = 60, [FromQuery] int? groupId = null)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockvaccination_due", Text("p_farmid", farmId),
                Int("p_horizondays", Math.Clamp(horizonDays, 0, 730)), Int("p_groupid", groupId))));

        [HttpGet("plans")]
        public Task<IActionResult> Plans([FromQuery] string farmId)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockplan_list", Text("p_farmid", farmId))));

        [HttpPost("plans")]
        public Task<IActionResult> CreatePlan([FromBody] JsonElement body) => SavePlan(null, body);

        [HttpPut("plans/{id:int}")]
        public Task<IActionResult> UpdatePlan(int id, [FromBody] JsonElement body) => SavePlan(id, body);

        private Task<IActionResult> SavePlan(int? id, JsonElement body)
            => Write(FarmOf(body), async by => Ok(new
            {
                planId = await Db.IntAsync("splivestockplan_save", Text("p_farmid", FarmOf(body)),
                    Jsonb("p_plan", LivestockPenController.WithId(body, "planId", id)), Text("p_by", by)),
            }));

        [HttpPost("plans/{id:int}/copy")]
        public Task<IActionResult> Copy(int id, [FromBody] JsonElement body)
            => Write(FarmOf(body), async by => Ok(new
            {
                planId = await Db.IntAsync("splivestockplan_copy", Text("p_farmid", FarmOf(body)), Int("p_planid", id), Text("p_by", by)),
            }));

        [HttpDelete("plans/{id:int}")]
        public Task<IActionResult> DeletePlan(int id, [FromQuery] string farmId)
            => Write(farmId, async by =>
            {
                await Db.ExecAsync("splivestockplan_delete", Text("p_farmid", farmId), Int("p_planid", id), Text("p_by", by));
                return NoContent();
            });

        /// <summary>Body: { farmId, speciesCode, planId (null = no plan) }.</summary>
        [HttpPut("plan-in-use")]
        public Task<IActionResult> Use([FromBody] JsonElement body)
            => Write(FarmOf(body), async by =>
            {
                await Db.ExecAsync("splivestockplan_use", Text("p_farmid", FarmOf(body)), Text("p_species", Str(body, "speciesCode")),
                    Int("p_planid", IntOf(body, "planId")), Text("p_by", by));
                return NoContent();
            });
    }

    [Authorize]
    [ApiController]
    [Route("api/Livestock/treatments")]
    [RequireCompanyType("Livestock")]
    public class LivestockTreatmentController : LivestockControllerBase
    {
        public LivestockTreatmentController(ILivestockDb db) : base(db) { }

        [HttpGet]
        public Task<IActionResult> List([FromQuery] string farmId)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestocktreatment_list", Text("p_farmid", farmId))));

        [HttpGet("{id:int}")]
        public Task<IActionResult> Get(int id, [FromQuery] string farmId)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestocktreatment_get", Text("p_farmid", farmId), Int("p_id", id))));

        [HttpGet("withdrawals")]
        public Task<IActionResult> Withdrawals([FromQuery] string farmId, [FromQuery] int? groupId)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockwithdrawals", Text("p_farmid", farmId), Int("p_groupid", groupId))));

        [HttpPost]
        public Task<IActionResult> Create([FromBody] JsonElement body)
            => Write(FarmOf(body), async by => Ok(new
            {
                treatmentId = await Db.IntAsync("splivestocktreatment_create", Text("p_farmid", FarmOf(body)),
                    Jsonb("p_t", body.GetRawText()), Text("p_by", by)),
            }));

        /// <summary>Record a day. Body: { farmId, date, notes, lines: [{ groupId, quantity }] } (lines optional).</summary>
        [HttpPost("{id:int}/days")]
        public Task<IActionResult> PostDay(int id, [FromBody] JsonElement body)
            => Write(FarmOf(body), async by => Ok(new
            {
                dayId = await Db.IntAsync("splivestocktreatment_postday", Text("p_farmid", FarmOf(body)), Int("p_id", id),
                    Date("p_date", DateOf(body, "date")), Jsonb("p_lines", LsJson.Raw(body, "lines")),
                    Text("p_notes", Str(body, "notes")), Text("p_by", by)),
            }));

        /// <summary>Body: { farmId, reason }.</summary>
        [HttpPost("days/{dayId:int}/reversal")]
        public Task<IActionResult> ReverseDay(int dayId, [FromBody] JsonElement body)
            => Write(FarmOf(body), async by =>
            {
                await Db.ExecAsync("splivestocktreatment_reverseday", Text("p_farmid", FarmOf(body)), Int("p_dayid", dayId),
                    Text("p_reason", Str(body, "reason")), Text("p_by", by));
                return NoContent();
            });

        /// <summary>Body: { farmId, action: Complete|Cancel, reason }.</summary>
        [HttpPut("{id:int}/closure")]
        public Task<IActionResult> Close(int id, [FromBody] JsonElement body)
            => Write(FarmOf(body), async by =>
            {
                await Db.ExecAsync("splivestocktreatment_close", Text("p_farmid", FarmOf(body)), Int("p_id", id),
                    Text("p_action", Str(body, "action")), Text("p_reason", Str(body, "reason")), Text("p_by", by));
                return NoContent();
            });
    }

    [Authorize]
    [ApiController]
    [Route("api/Livestock/feed-formulas")]
    [RequireCompanyType("Livestock")]
    public class LivestockFeedFormulaController : LivestockControllerBase
    {
        public LivestockFeedFormulaController(ILivestockDb db) : base(db) { }

        [HttpGet]
        public Task<IActionResult> List([FromQuery] string farmId)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockformula_list", Text("p_farmid", farmId))));

        [HttpPost]
        public Task<IActionResult> Create([FromBody] JsonElement body) => Save(null, body);

        [HttpPut("{id:int}")]
        public Task<IActionResult> Update(int id, [FromBody] JsonElement body) => Save(id, body);

        private Task<IActionResult> Save(int? id, JsonElement body)
            => Write(FarmOf(body), async by => Ok(new
            {
                formulaId = await Db.IntAsync("splivestockformula_save", Text("p_farmid", FarmOf(body)),
                    Jsonb("p_f", LivestockPenController.WithId(body, "formulaId", id)), Text("p_by", by)),
            }));

        [HttpDelete("{id:int}")]
        public Task<IActionResult> Delete(int id, [FromQuery] string farmId)
            => Write(farmId, async by =>
            {
                await Db.ExecAsync("splivestockformula_delete", Text("p_farmid", farmId), Int("p_id", id), Text("p_by", by));
                return NoContent();
            });
    }

    [Authorize]
    [ApiController]
    [Route("api/Livestock/feed-production")]
    [RequireCompanyType("Livestock")]
    public class LivestockFeedRunController : LivestockControllerBase
    {
        public LivestockFeedRunController(ILivestockDb db) : base(db) { }

        [HttpGet]
        public Task<IActionResult> List([FromQuery] string farmId)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockfeedrun_list", Text("p_farmid", farmId))));

        /// <summary>Body: { farmId, formulaId, date, batches, outputQuantity, otherCost, notes }.</summary>
        [HttpPost]
        public Task<IActionResult> Mix([FromBody] JsonElement body)
            => Write(FarmOf(body), async by => Ok(new
            {
                runId = await Db.IntAsync("splivestockfeedrun_post", Text("p_farmid", FarmOf(body)), Int("p_formulaid", IntOf(body, "formulaId")),
                    Date("p_date", DateOf(body, "date")), LsJson.Num("p_batches", LsJson.Dec(body, "batches")),
                    LsJson.Num("p_outputquantity", LsJson.Dec(body, "outputQuantity")), LsJson.Num("p_othercost", LsJson.Dec(body, "otherCost")),
                    Text("p_notes", Str(body, "notes")), Text("p_by", by)),
            }));

        /// <summary>Body: { farmId, reason }.</summary>
        [HttpPost("{id:int}/reversal")]
        public Task<IActionResult> Reverse(int id, [FromBody] JsonElement body)
            => Write(FarmOf(body), async by =>
            {
                await Db.ExecAsync("splivestockfeedrun_reverse", Text("p_farmid", FarmOf(body)), Int("p_runid", id),
                    Text("p_reason", Str(body, "reason")), Text("p_by", by));
                return NoContent();
            });
    }

    [Authorize]
    [ApiController]
    [Route("api/Livestock/feed-distribution")]
    [RequireCompanyType("Livestock")]
    public class LivestockFeedDistributionController : LivestockControllerBase
    {
        public LivestockFeedDistributionController(ILivestockDb db) : base(db) { }

        /// <summary>Body: { farmId, date, itemId, lines: [{ groupId, quantity }] }.</summary>
        [HttpPost]
        public Task<IActionResult> Distribute([FromBody] JsonElement body)
            => Write(FarmOf(body), async by => JsonText(await Db.JsonAsync("splivestockfeed_distribute", Text("p_farmid", FarmOf(body)),
                Date("p_date", DateOf(body, "date")), Int("p_itemid", IntOf(body, "itemId")),
                Jsonb("p_lines", LsJson.Raw(body, "lines")), Text("p_by", by))));
    }

    [Authorize]
    [ApiController]
    [Route("api/Livestock/feed-supply")]
    [RequireCompanyType("Livestock")]
    public class LivestockFeedSupplyController : LivestockControllerBase
    {
        public LivestockFeedSupplyController(ILivestockDb db) : base(db) { }

        [HttpGet]
        public Task<IActionResult> Get([FromQuery] string farmId, [FromQuery] int windowDays = 14)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestock_daysofsupply", Text("p_farmid", farmId),
                Int("p_window", Math.Clamp(windowDays, 1, 90)))));
    }

    [Authorize]
    [ApiController]
    [Route("api/Livestock/alerts")]
    [RequireCompanyType("Livestock")]
    public class LivestockAlertsController : LivestockControllerBase
    {
        public LivestockAlertsController(ILivestockDb db) : base(db) { }

        [HttpGet]
        public Task<IActionResult> Get([FromQuery] string farmId)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestock_alerts", Text("p_farmid", farmId))));
    }
}
