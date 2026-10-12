using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using Npgsql;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    /// <summary>
    /// Recurring Expense Engine (migration 348), for every company type.
    ///
    /// <para>IamPermissionMap maps "recurring-expenses" to "*.expenses", so the
    /// filter resolves poultry.expenses / water.expenses / generic.expenses /
    /// hotel.expenses / restaurant.expenses from the company's own type:</para>
    /// <list type="bullet">
    /// <item>GET    → *.expenses.view</item>
    /// <item>POST   → *.expenses.create  (new template, generate, post a draft -- "record")</item>
    /// <item>PUT    → *.expenses.edit    (edit template/draft, pause/resume/end, skip/restore/release/link)</item>
    /// <item>DELETE → *.expenses.delete  (a template that never produced anything)</item>
    /// </list>
    /// <para>The post route is ".../record", not ".../post": ResolveAction turns a
    /// "post" segment into approve, and recording an expense is the create right
    /// people already hold. A module that approves expenses (Water, Generic,
    /// Hotel) still approves the posted expense on its own Expenses page.</para>
    /// </summary>
    [ApiController]
    [Route("api/recurring-expenses")]
    public class RecurringExpensesController : ControllerBase
    {
        private readonly IRecurringExpenseService _svc;
        public RecurringExpensesController(IRecurringExpenseService svc) => _svc = svc;

        private string? Actor() =>
            User?.FindFirst(ClaimTypes.NameIdentifier)?.Value ?? User?.FindFirst(ClaimTypes.Name)?.Value;

        private static IActionResult? NeedFarm(string? farmId) =>
            string.IsNullOrWhiteSpace(farmId) ? new BadRequestObjectResult(new { message = "Company ID is required." }) : null;

        private async Task<IActionResult> Run(Func<Task<IActionResult>> body)
        {
            try { return await body(); }
            catch (PostgresException ex) when (ex.SqlState == PostgresErrorCodes.RaiseException)
            {
                return BadRequest(new { message = ex.MessageText });
            }
            catch (Exception ex) when (ex.InnerException is PostgresException pg && pg.SqlState == PostgresErrorCodes.RaiseException)
            {
                // Module services wrap database refusals (e.g. "Error inserting expense record.").
                return BadRequest(new { message = pg.MessageText });
            }
            catch (InvalidOperationException ex)
            {
                return BadRequest(new { message = ex.Message });
            }
        }

        // ------------------------------------------------------------ templates
        [HttpGet("templates")]
        public async Task<IActionResult> Templates([FromQuery] string farmId)
            => NeedFarm(farmId) ?? Ok(await _svc.GetTemplatesAsync(farmId));

        [HttpPost("templates")]
        public Task<IActionResult> Create([FromBody] RecurringExpenseTemplateRequest req) => Run(async () =>
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var id = await _svc.SaveTemplateAsync(null, req, Actor());
            return Ok(new { templateId = id });
        });

        [HttpPut("templates/{id:int}")]
        public Task<IActionResult> Update(int id, [FromBody] RecurringExpenseTemplateRequest req) => Run(async () =>
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            await _svc.SaveTemplateAsync(id, req, Actor());
            return Ok(new { templateId = id });
        });

        [HttpPut("templates/{id:int}/status")]
        public Task<IActionResult> SetStatus(int id, [FromBody] RecurringExpenseStatusRequest req) => Run(async () =>
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var status = await _svc.SetStatusAsync(id, req, Actor());
            return Ok(new { status });
        });

        [HttpDelete("templates/{id:int}")]
        public Task<IActionResult> Delete(int id, [FromQuery] string farmId) => Run(async () =>
        {
            if (NeedFarm(farmId) is { } bad) return bad;
            await _svc.DeleteTemplateAsync(farmId, id, Actor());
            return NoContent();
        });

        [HttpGet("templates/{id:int}/history")]
        public async Task<IActionResult> History(int id, [FromQuery] string farmId)
            => NeedFarm(farmId) ?? Ok(await _svc.GetHistoryAsync(farmId, id));

        // ---------------------------------------------------------- occurrences
        // POST api/recurring-expenses/generate?farmId= -- raise every draft now due.
        // Idempotent: calling it again creates nothing it already created.
        [HttpPost("generate")]
        public Task<IActionResult> Generate([FromQuery] string farmId) => Run(async () =>
        {
            if (NeedFarm(farmId) is { } bad) return bad;
            return Ok(await _svc.GenerateAsync(farmId, Actor()));
        });

        [HttpGet("upcoming")]
        public async Task<IActionResult> Upcoming([FromQuery] string farmId, [FromQuery] int days = 30)
            => NeedFarm(farmId) ?? Ok(await _svc.GetUpcomingAsync(farmId, Math.Clamp(days, 1, 366)));

        [HttpGet("occurrences")]
        public async Task<IActionResult> Occurrences([FromQuery] string farmId, [FromQuery] string? status, [FromQuery] int? templateId)
            => NeedFarm(farmId) ?? Ok(await _svc.GetOccurrencesAsync(farmId, status, templateId));

        [HttpPut("occurrences/{id:int}")]
        public Task<IActionResult> Edit(int id, [FromBody] RecurringExpenseOccurrenceEditRequest req) => Run(async () =>
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            await _svc.EditOccurrenceAsync(id, req, Actor());
            return NoContent();
        });

        [HttpPost("occurrences/{id:int}/record")]
        public Task<IActionResult> Record(int id, [FromQuery] string farmId) => Run(async () =>
        {
            if (NeedFarm(farmId) is { } bad) return bad;
            return Ok(await _svc.PostAsync(farmId, id, Actor()));
        });

        [HttpPut("occurrences/{id:int}/skip")]
        public Task<IActionResult> Skip(int id, [FromBody] RecurringExpenseReasonRequest req) => Run(async () =>
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            await _svc.SkipAsync(req.FarmId, id, req.Reason ?? string.Empty, Actor());
            return NoContent();
        });

        [HttpPut("occurrences/{id:int}/restore")]
        public Task<IActionResult> Restore(int id, [FromBody] RecurringExpenseReasonRequest req) => Run(async () =>
        {
            await _svc.RestoreAsync(req.FarmId, id, Actor());
            return NoContent();
        });

        [HttpPut("occurrences/{id:int}/release")]
        public Task<IActionResult> Release(int id, [FromBody] RecurringExpenseReasonRequest req) => Run(async () =>
        {
            await _svc.ReleaseAsync(req.FarmId, id, req.Reason, Actor());
            return NoContent();
        });

        [HttpPut("occurrences/{id:int}/link")]
        public Task<IActionResult> Link(int id, [FromBody] RecurringExpenseReasonRequest req) => Run(async () =>
        {
            if (req.ExpenseId is null) return BadRequest(new { message = "Give the id of the expense that was created." });
            await _svc.LinkExpenseAsync(req.FarmId, id, req.ExpenseId.Value, Actor());
            return NoContent();
        });
    }
}
