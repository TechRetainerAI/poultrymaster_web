// Projects & Contracts for Generic companies (migrations 482-486).
//
// Every number comes from the database engine (484): this controller only
// checks the company, the actor and the inputs, and passes JSON through.
// Routes and their permission resources (IamPermissionMap):
//   projects                          generic.projects             register
//   projects/options                  generic.project-allocations  pickers on transaction forms
//   projects/{id}/financials/*        generic.project-financials   P&L, cash, balances, history
//   projects/financials/*             generic.project-financials   compare, reconcile
//   projects/{id}/budget              generic.project-budgets
//   projects/budget-categories/{id}   generic.project-budgets
//   projects/{id}/milestones          generic.project-milestones
//   projects/{id}/reservations        generic.project-reservations
//   project-reservations              generic.project-reservations company-wide reserved stock
//   project-allocations               generic.project-allocations  assign (POST) / change (PUT)

using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Npgsql;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Filters;
using static PoultryFarmAPIWeb.Business.GenericProjectDb;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/generic-company/{farmId}")]
    [RequireCompanyType("Generic")]
    public class GenericProjectsController : ControllerBase
    {
        private readonly IGenericProjectDb _db;
        private readonly IGenericCompanyService _companies;

        public GenericProjectsController(IGenericProjectDb db, IGenericCompanyService companies)
        {
            _db = db;
            _companies = companies;
        }

        // ------------------------------------------------------------ plumbing

        private string? Actor()
            => User.FindFirst(ClaimTypes.Name)?.Value ?? User.FindFirst(ClaimTypes.NameIdentifier)?.Value
               ?? User.Identity?.Name;

        private ContentResult JsonText(string json) => Content(json, "application/json");

        private static string Raw(JsonElement body) =>
            body.ValueKind is JsonValueKind.Object or JsonValueKind.Array ? body.GetRawText() : "{}";

        private static string? Str(JsonElement body, string name)
            => body.ValueKind == JsonValueKind.Object && body.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String
                ? v.GetString() : null;

        private static int? IntOf(JsonElement body, string name)
        {
            if (body.ValueKind != JsonValueKind.Object || !body.TryGetProperty(name, out var v)) return null;
            if (v.ValueKind == JsonValueKind.Number && v.TryGetInt32(out var i)) return i;
            if (v.ValueKind == JsonValueKind.String && int.TryParse(v.GetString(), out var s)) return s;
            return null;
        }

        private static decimal? DecOf(JsonElement body, string name)
        {
            if (body.ValueKind != JsonValueKind.Object || !body.TryGetProperty(name, out var v)) return null;
            if (v.ValueKind == JsonValueKind.Number && v.TryGetDecimal(out var d)) return d;
            if (v.ValueKind == JsonValueKind.String && decimal.TryParse(v.GetString(), out var s)) return s;
            return null;
        }

        private static DateTime? DateOf(JsonElement body, string name)
            => DateTime.TryParse(Str(body, name), out var d) ? d.Date : null;

        private static JsonElement? Prop(JsonElement body, string name)
            => body.ValueKind == JsonValueKind.Object && body.TryGetProperty(name, out var v) ? v : null;

        private static int[]? Ids(string? csv)
        {
            if (string.IsNullOrWhiteSpace(csv)) return null;
            var list = new List<int>();
            foreach (var p in csv.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
                if (int.TryParse(p, out var i) && i > 0) list.Add(i);
            return list.Count == 0 ? null : list.Distinct().ToArray();
        }

        /// <summary>Company check, actor check, refusals as readable 400s.</summary>
        private async Task<IActionResult> Run(string farmId, bool write, Func<string, Task<IActionResult>> run)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            var by = Actor();
            if (write && by is null) return Unauthorized(new { message = "Sign in again." });
            try
            {
                return await run(by ?? "system");
            }
            catch (PostgresException ex) when (ex.SqlState is "P0001" or "23514" or "23505")
            {
                return BadRequest(new { message = ex.MessageText });
            }
        }

        // ------------------------------------------------------------ register

        [HttpGet("projects")]
        public Task<IActionResult> List(string farmId, [FromQuery] string? search, [FromQuery] string? status,
            [FromQuery] string? kind, [FromQuery] int? customerId, [FromQuery] int? page, [FromQuery] int? pageSize)
            => Run(farmId, false, async _ => JsonText(await _db.JsonAsync("spgenericproject_list",
                Text("p_farmid", farmId),
                Jsonb("p_filter", JsonSerializer.Serialize(new { search, status, kind, customerId, page, pageSize })))));

        [HttpGet("projects/options")]
        public Task<IActionResult> Options(string farmId, [FromQuery] bool includeClosed = false)
            => Run(farmId, false, async _ => JsonText(await _db.JsonAsync("spgenericproject_options",
                Text("p_farmid", farmId), Bool("p_includeclosed", includeClosed))));

        [HttpGet("projects/{id:int}")]
        public Task<IActionResult> Get(string farmId, int id)
            => Run(farmId, false, async _ => JsonText(await _db.JsonAsync("spgenericproject_get",
                Text("p_farmid", farmId), Int("p_projectid", id))));

        [HttpPost("projects")]
        public Task<IActionResult> Create(string farmId, [FromBody] JsonElement body)
            => Run(farmId, true, async by =>
            {
                var id = await _db.IntAsync("spgenericproject_save", Text("p_farmid", farmId),
                    Jsonb("p_project", StripId(body)), Text("p_by", by));
                return JsonText(await _db.JsonAsync("spgenericproject_get", Text("p_farmid", farmId), Int("p_projectid", id)));
            });

        [HttpPut("projects/{id:int}")]
        public Task<IActionResult> Update(string farmId, int id, [FromBody] JsonElement body)
            => Run(farmId, true, async by =>
            {
                var withId = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(Raw(body)) ?? new();
                withId["projectId"] = JsonSerializer.SerializeToElement(id);
                await _db.IntAsync("spgenericproject_save", Text("p_farmid", farmId),
                    Jsonb("p_project", JsonSerializer.Serialize(withId)), Text("p_by", by));
                return JsonText(await _db.JsonAsync("spgenericproject_get", Text("p_farmid", farmId), Int("p_projectid", id)));
            });

        private static string StripId(JsonElement body)
        {
            var d = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(Raw(body)) ?? new();
            d.Remove("projectId");
            return JsonSerializer.Serialize(d);
        }

        [HttpPut("projects/{id:int}/status")]
        public Task<IActionResult> SetStatus(string farmId, int id, [FromBody] JsonElement body)
            => Run(farmId, true, async by =>
            {
                await _db.ExecAsync("spgenericproject_setstatus", Text("p_farmid", farmId), Int("p_projectid", id),
                    Text("p_status", Str(body, "status")), Text("p_note", Str(body, "note")), Text("p_by", by));
                return JsonText(await _db.JsonAsync("spgenericproject_get", Text("p_farmid", farmId), Int("p_projectid", id)));
            });

        /// <summary>Archive (never delete). Nothing linked to the project changes.</summary>
        [HttpDelete("projects/{id:int}")]
        public Task<IActionResult> Archive(string farmId, int id, [FromQuery] string? note)
            => Run(farmId, true, async by =>
            {
                await _db.ExecAsync("spgenericproject_archive", Text("p_farmid", farmId), Int("p_projectid", id),
                    Bool("p_archive", true), Text("p_note", note), Text("p_by", by));
                return NoContent();
            });

        [HttpPut("projects/{id:int}/restore")]
        public Task<IActionResult> Restore(string farmId, int id)
            => Run(farmId, true, async by =>
            {
                await _db.ExecAsync("spgenericproject_archive", Text("p_farmid", farmId), Int("p_projectid", id),
                    Bool("p_archive", false), Text("p_note", null), Text("p_by", by));
                return JsonText(await _db.JsonAsync("spgenericproject_get", Text("p_farmid", farmId), Int("p_projectid", id)));
            });

        // ------------------------------------------------------------ financials

        [HttpGet("projects/{id:int}/financials/summary")]
        public Task<IActionResult> Summary(string farmId, int id, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
            => Run(farmId, false, async _ =>
            {
                var json = await _db.JsonAsync("spgenericproject_summary", Text("p_farmid", farmId),
                    Ints("p_projectids", new[] { id }), Date("p_from", fromDate), Date("p_to", toDate));
                using var doc = JsonDocument.Parse(json);
                return doc.RootElement.GetArrayLength() == 0
                    ? NotFound(new { message = "That project or contract was not found in this company." })
                    : JsonText(doc.RootElement[0].GetRawText());
            });

        [HttpGet("projects/{id:int}/financials/cashflow")]
        public Task<IActionResult> CashFlow(string farmId, int id, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
            => Run(farmId, false, async _ =>
            {
                await _db.JsonAsync("spgenericproject_get", Text("p_farmid", farmId), Int("p_projectid", id));
                return JsonText(await _db.JsonAsync("spgenericproject_cashflow", Text("p_farmid", farmId),
                    Text("p_scope", "projects"), Ints("p_projectids", new[] { id }),
                    Date("p_from", fromDate ?? new DateTime(1900, 1, 1)), Date("p_to", toDate ?? new DateTime(2999, 12, 31))));
            });

        [HttpGet("projects/{id:int}/financials/transactions")]
        public Task<IActionResult> Transactions(string farmId, int id, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
            => Run(farmId, false, async _ => JsonText(await _db.JsonAsync("spgenericproject_transactions",
                Text("p_farmid", farmId), Int("p_projectid", id), Date("p_from", fromDate), Date("p_to", toDate))));

        /// <summary>Cash flow for any scope: project=all|general|12|12,15 (the Cash Flow page filter).</summary>
        [HttpGet("projects/financials/cashflow")]
        public Task<IActionResult> ScopedCashFlow(string farmId, [FromQuery] string? project,
            [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
            => Run(farmId, false, async _ =>
            {
                var (scope, ids) = GenericProjectScope.Parse(project);
                if (scope is null) return BadRequest(new { message = "Unknown project filter." });
                return JsonText(await _db.JsonAsync("spgenericproject_cashflow", Text("p_farmid", farmId),
                    Text("p_scope", scope), Ints("p_projectids", ids),
                    Date("p_from", fromDate ?? new DateTime(1900, 1, 1)), Date("p_to", toDate ?? new DateTime(2999, 12, 31))));
            });

        [HttpGet("projects/financials/compare")]
        public Task<IActionResult> Compare(string farmId, [FromQuery] string? ids,
            [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
            => Run(farmId, false, async _ => JsonText(await _db.JsonAsync("spgenericproject_compare",
                Text("p_farmid", farmId), Ints("p_projectids", Ids(ids)), Date("p_from", fromDate), Date("p_to", toDate))));

        [HttpGet("projects/financials/reconcile")]
        public Task<IActionResult> Reconcile(string farmId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
            => Run(farmId, false, async _ => JsonText(await _db.JsonAsync("spgenericproject_reconcile",
                Text("p_farmid", farmId), Date("p_from", fromDate ?? new DateTime(1900, 1, 1)),
                Date("p_to", toDate ?? new DateTime(2999, 12, 31)))));

        /// <summary>Project labels for a list page: which projects each document belongs to.</summary>
        [HttpGet("project-allocations/labels")]
        public Task<IActionResult> Labels(string farmId, [FromQuery] string sourceType, [FromQuery] string? ids)
            => Run(farmId, false, async _ => JsonText(await _db.JsonAsync("spgenericproject_labels",
                Text("p_farmid", farmId), Text("p_sourcetype", sourceType), Ints("p_ids", Ids(ids)))));

        /// <summary>493: Financial Activity -- each event's projects and shares in the period.</summary>
        [HttpGet("project-allocations/activity-shares")]
        public Task<IActionResult> ActivityShares(string farmId, [FromQuery] DateTime fromDate, [FromQuery] DateTime toDate)
            => Run(farmId, false, async _ => JsonText(await _db.JsonAsync("spgenericproject_activityshares",
                Text("p_farmid", farmId), Date("p_from", fromDate), Date("p_to", toDate))));

        /// <summary>501: Cash &amp; Accounts / Reconciliation -- each cash-ledger entry's projects and shares (optionally one account).</summary>
        [HttpGet("project-allocations/cash-shares")]
        public Task<IActionResult> CashShares(string farmId, [FromQuery] int? accountId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
            => Run(farmId, false, async _ => JsonText(await _db.JsonAsync("spgenericproject_cashshares",
                Text("p_farmid", farmId), Int("p_accountid", accountId), Date("p_from", fromDate), Date("p_to", toDate))));

        /// <summary>493: Customer / Supplier Balances -- every open document with its party and project shares.</summary>
        [HttpGet("project-allocations/open-balances")]
        public Task<IActionResult> OpenBalances(string farmId, [FromQuery] string side)
            => side is "customer" or "supplier"
                ? Run(farmId, false, async _ => JsonText(await _db.JsonAsync("spgenericproject_openbalances",
                    Text("p_farmid", farmId), Text("p_side", side))))
                : Task.FromResult<IActionResult>(BadRequest(new { message = "side must be customer or supplier." }));

        // ------------------------------------------------------------ assignment

        [HttpGet("project-allocations")]
        public Task<IActionResult> GetAllocations(string farmId, [FromQuery] string sourceType, [FromQuery] int sourceId)
            => Run(farmId, false, async _ => JsonText(await _db.JsonAsync("spgenericproject_allocations_get",
                Text("p_farmid", farmId), Text("p_sourcetype", sourceType), Int("p_sourceid", sourceId))));

        /// <summary>
        /// Change an existing transaction's projects (correction / reassignment).
        /// Body: {sourceType, sourceId, lineId?, splits:[...], reason}
        ///   or  {documentType, documentId, projectId|null, costClass?, reason}  (whole document)
        ///   or  {documentType, documentId, lines:[[...],...], reason}           (per line)
        /// Never creates or changes the transaction itself.
        /// </summary>
        [HttpPut("project-allocations")]
        public Task<IActionResult> ChangeAllocations(string farmId, [FromBody] JsonElement body)
            => Run(farmId, true, async by =>
            {
                var reason = Str(body, "reason");
                var docType = Str(body, "documentType");
                var docId = IntOf(body, "documentId");
                if (docType is not null && docId is not null)
                {
                    if (Prop(body, "lines") is { } lines)
                        await _db.IntAsync("spgenericproject_allocatelines", Text("p_farmid", farmId),
                            Text("p_documenttype", docType), Int("p_documentid", docId),
                            Jsonb("p_lines", lines.GetRawText()), Text("p_reason", reason), Text("p_by", by));
                    else
                        await _db.IntAsync("spgenericproject_allocatedocument", Text("p_farmid", farmId),
                            Text("p_documenttype", docType), Int("p_documentid", docId), Int("p_projectid", IntOf(body, "projectId")),
                            Text("p_costclass", Str(body, "costClass")), Text("p_reason", reason), Text("p_by", by));
                    return JsonText(await _db.JsonAsync("spgenericproject_allocations_get", Text("p_farmid", farmId),
                        Text("p_sourcetype", docType), Int("p_sourceid", docId)));
                }

                var sourceType = Str(body, "sourceType");
                var sourceId = IntOf(body, "sourceId");
                if (sourceType is null || sourceId is null)
                    return BadRequest(new { message = "Say which transaction to change." });
                await _db.IntAsync("spgenericproject_allocate", Text("p_farmid", farmId), Text("p_sourcetype", sourceType),
                    Int("p_sourceid", sourceId), Int("p_lineid", IntOf(body, "lineId")),
                    Jsonb("p_splits", Prop(body, "splits")?.GetRawText() ?? "[]"), Text("p_reason", reason), Text("p_by", by));
                return JsonText(await _db.JsonAsync("spgenericproject_allocations_get", Text("p_farmid", farmId),
                    Text("p_sourcetype", sourceType), Int("p_sourceid", sourceId)));
            });

        // ------------------------------------------------------------ linking older transactions

        [HttpGet("project-allocations/link-candidates")]
        public Task<IActionResult> LinkCandidates(string farmId, [FromQuery] string documentType, [FromQuery] DateTime? fromDate,
            [FromQuery] DateTime? toDate, [FromQuery] string? search, [FromQuery] int? partyId, [FromQuery] bool onlyUnassigned = true)
            => Run(farmId, false, async _ => JsonText(await _db.JsonAsync("spgenericproject_linkcandidates",
                Text("p_farmid", farmId), Jsonb("p_filter", JsonSerializer.Serialize(new
                {
                    documentType, from = fromDate?.ToString("yyyy-MM-dd"), to = toDate?.ToString("yyyy-MM-dd"),
                    search, partyId, onlyUnassigned,
                })))));

        /// <summary>What linking would add (changes nothing). Body: {projectId, items:[{documentType, documentId}]}</summary>
        [HttpPost("project-allocations/link-preview")]
        public Task<IActionResult> LinkPreview(string farmId, [FromBody] JsonElement body)
            => Run(farmId, false, async _ => JsonText(await _db.JsonAsync("spgenericproject_linkpreview",
                Text("p_farmid", farmId), Int("p_projectid", IntOf(body, "projectId")),
                Jsonb("p_items", Prop(body, "items")?.GetRawText() ?? "[]"))));

        /// <summary>Link older transactions to a project. Body: {projectId, items:[...], reason}</summary>
        [HttpPut("project-allocations/link")]
        public Task<IActionResult> Link(string farmId, [FromBody] JsonElement body)
            => Run(farmId, true, async by =>
            {
                var n = await _db.IntAsync("spgenericproject_link", Text("p_farmid", farmId),
                    Int("p_projectid", IntOf(body, "projectId")), Jsonb("p_items", Prop(body, "items")?.GetRawText() ?? "[]"),
                    Text("p_reason", Str(body, "reason")), Text("p_by", by));
                return Ok(new { linked = n });
            });

        // ------------------------------------------------------------ stock reservations

        [HttpGet("projects/{id:int}/reservations")]
        public Task<IActionResult> Inventory(string farmId, int id)
            => Run(farmId, false, async _ => JsonText(await _db.JsonAsync("spgenericproject_inventory",
                Text("p_farmid", farmId), Int("p_projectid", id))));

        /// <summary>Body: {productId, action: Reserve|Release|Transfer, quantity, toProjectId?, date?, note?}</summary>
        [HttpPost("projects/{id:int}/reservations")]
        public Task<IActionResult> Reserve(string farmId, int id, [FromBody] JsonElement body)
            => Run(farmId, true, async by =>
            {
                await _db.IntAsync("spgenericproject_reservestock", Text("p_farmid", farmId), Int("p_projectid", id),
                    Int("p_productid", IntOf(body, "productId")), Text("p_action", Str(body, "action")),
                    Num("p_quantity", DecOf(body, "quantity")), Int("p_toprojectid", IntOf(body, "toProjectId")),
                    Date("p_date", DateOf(body, "date")), Text("p_note", Str(body, "note")), Text("p_by", by));
                return JsonText(await _db.JsonAsync("spgenericproject_inventory", Text("p_farmid", farmId), Int("p_projectid", id)));
            });

        /// <summary>Undo a wrong reservation entry (both halves of a transfer). Body: {reason}</summary>
        [HttpPost("projects/{id:int}/reservations/{entryId:int}/undo")]
        public Task<IActionResult> UndoReservation(string farmId, int id, int entryId, [FromBody] JsonElement body)
            => Run(farmId, true, async by =>
            {
                await _db.ExecAsync("spgenericproject_reversereservation", Text("p_farmid", farmId),
                    Int("p_entryid", entryId), Text("p_reason", Str(body, "reason")), Text("p_by", by));
                return JsonText(await _db.JsonAsync("spgenericproject_inventory", Text("p_farmid", farmId), Int("p_projectid", id)));
            });

        [HttpGet("project-reservations")]
        public Task<IActionResult> ReservedStock(string farmId)
            => Run(farmId, false, async _ => JsonText(await _db.JsonAsync("spgenericproject_reservedstock", Text("p_farmid", farmId))));

        // ------------------------------------------------------------ budget

        [HttpGet("projects/{id:int}/budget")]
        public Task<IActionResult> Budget(string farmId, int id)
            => Run(farmId, false, async _ => JsonText(await _db.JsonAsync("spgenericproject_budget",
                Text("p_farmid", farmId), Int("p_projectid", id))));

        /// <summary>Body: {lines:[{category, plannedAmount, notes?}], effectiveDate?} -- saves a new budget version.</summary>
        [HttpPut("projects/{id:int}/budget")]
        public Task<IActionResult> SaveBudget(string farmId, int id, [FromBody] JsonElement body)
            => Run(farmId, true, async by =>
            {
                await _db.IntAsync("spgenericproject_savebudget", Text("p_farmid", farmId), Int("p_projectid", id),
                    Jsonb("p_lines", Prop(body, "lines")?.GetRawText() ?? "[]"), Date("p_effectivedate", DateOf(body, "effectiveDate")),
                    Text("p_by", by));
                return JsonText(await _db.JsonAsync("spgenericproject_budget", Text("p_farmid", farmId), Int("p_projectid", id)));
            });

        /// <summary>Which budget line an expense category counts against. Body: {budgetCategory|null}</summary>
        [HttpPut("projects/budget-categories/{categoryId:int}")]
        public Task<IActionResult> SetCategoryBudget(string farmId, int categoryId, [FromBody] JsonElement body)
            => Run(farmId, true, async by =>
            {
                await _db.ExecAsync("spgenericproject_setexpensecategorybudget", Text("p_farmid", farmId),
                    Int("p_categoryid", categoryId), Text("p_budgetcategory", Str(body, "budgetCategory")), Text("p_by", by));
                return NoContent();
            });

        // ------------------------------------------------------------ milestones

        [HttpGet("projects/{id:int}/milestones")]
        public Task<IActionResult> Milestones(string farmId, int id)
            => Run(farmId, false, async _ => JsonText(await _db.JsonAsync("spgenericproject_milestones",
                Text("p_farmid", farmId), Int("p_projectid", id))));

        [HttpPost("projects/{id:int}/milestones")]
        public Task<IActionResult> AddMilestone(string farmId, int id, [FromBody] JsonElement body)
            => Run(farmId, true, async by =>
            {
                var d = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(Raw(body)) ?? new();
                d.Remove("milestoneId");
                await _db.IntAsync("spgenericproject_savemilestone", Text("p_farmid", farmId), Int("p_projectid", id),
                    Jsonb("p_milestone", JsonSerializer.Serialize(d)), Text("p_by", by));
                return JsonText(await _db.JsonAsync("spgenericproject_milestones", Text("p_farmid", farmId), Int("p_projectid", id)));
            });

        [HttpPut("projects/{id:int}/milestones/{milestoneId:int}")]
        public Task<IActionResult> UpdateMilestone(string farmId, int id, int milestoneId, [FromBody] JsonElement body)
            => Run(farmId, true, async by =>
            {
                var d = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(Raw(body)) ?? new();
                d["milestoneId"] = JsonSerializer.SerializeToElement(milestoneId);
                await _db.IntAsync("spgenericproject_savemilestone", Text("p_farmid", farmId), Int("p_projectid", id),
                    Jsonb("p_milestone", JsonSerializer.Serialize(d)), Text("p_by", by));
                return JsonText(await _db.JsonAsync("spgenericproject_milestones", Text("p_farmid", farmId), Int("p_projectid", id)));
            });

        [HttpDelete("projects/{id:int}/milestones/{milestoneId:int}")]
        public Task<IActionResult> DeleteMilestone(string farmId, int id, int milestoneId)
            => Run(farmId, true, async by =>
            {
                await _db.ExecAsync("spgenericproject_deletemilestone", Text("p_farmid", farmId), Int("p_projectid", id),
                    Int("p_milestoneid", milestoneId), Text("p_by", by));
                return NoContent();
            });

        // ---------------------------------------------------------------- team (500)

        [HttpGet("projects/{id:int}/team")]
        public Task<IActionResult> Team(string farmId, int id)
            => Run(farmId, false, async _ => JsonText(await _db.JsonAsync("spgenericproject_team",
                Text("p_farmid", farmId), Int("p_projectid", id))));

        /// <summary>Replace the team. Body: [{staffId, role?, startDate?, endDate?}].</summary>
        [HttpPut("projects/{id:int}/team")]
        public Task<IActionResult> SaveTeam(string farmId, int id, [FromBody] JsonElement body)
            => Run(farmId, true, async by => JsonText(await _db.JsonAsync("spgenericproject_saveteam",
                Text("p_farmid", farmId), Int("p_projectid", id), Jsonb("p_members", Raw(body)), Text("p_by", by))));

        /// <summary>Every staff member on an active team, with their projects (people-page filters).</summary>
        [HttpGet("projects/team/by-staff")]
        public Task<IActionResult> TeamByStaff(string farmId)
            => Run(farmId, false, async _ => JsonText(await _db.JsonAsync("spgenericproject_teamofstaff",
                Text("p_farmid", farmId))));
    }
}
