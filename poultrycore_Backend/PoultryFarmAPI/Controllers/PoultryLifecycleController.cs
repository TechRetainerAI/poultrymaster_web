using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using Npgsql;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    /// <summary>
    /// Flock Lifecycle Assistant (migration 347).
    ///
    /// <para>Permissions come from IamPermissionMap's "poultry/lifecycle" entry:</para>
    /// <list type="bullet">
    /// <item>GET    → poultry.lifecycle.view   (tasks, summary, history, plans, assignments)</item>
    /// <item>POST   → poultry.lifecycle.create (new plan, assign a plan)</item>
    /// <item>PUT    → poultry.lifecycle.edit   (edit a plan; complete / skip / reopen a task)</item>
    /// <item>DELETE → poultry.lifecycle.delete (delete a plan, remove an assignment)</item>
    /// </list>
    /// <para>
    /// farmId travels in the query string on every route, because that is where
    /// the IAM filter reads the company from. That is also what lets Business
    /// Office "My Tasks" ask each company separately: the filter answers per
    /// company, which the browser cannot (its can() only knows the active one).
    /// </para>
    /// <para>Nothing here performs an operational transaction. Tasks carry an
    /// action TYPE; the browser turns it into a link to the ordinary page.</para>
    /// </summary>
    [ApiController]
    [Route("api/Poultry/lifecycle")]
    public class PoultryLifecycleController : ControllerBase
    {
        private readonly IPoultryLifecycleService _svc;
        public PoultryLifecycleController(IPoultryLifecycleService svc) => _svc = svc;

        private string? Actor(string? fallback = null) =>
            User?.FindFirst(ClaimTypes.Name)?.Value
            ?? User?.FindFirst(ClaimTypes.NameIdentifier)?.Value
            ?? fallback;

        private static ActionResult? NeedFarm(string? farmId) =>
            string.IsNullOrWhiteSpace(farmId) ? new BadRequestObjectResult(new { message = "Company ID is required." }) : null;

        private async Task<IActionResult> Run(Func<Task<IActionResult>> body)
        {
            try { return await body(); }
            catch (PostgresException ex) when (ex.SqlState == PostgresErrorCodes.RaiseException)
            {
                return BadRequest(new { message = ex.MessageText });
            }
            catch (PostgresException ex) when (ex.SqlState == PostgresErrorCodes.UniqueViolation)
            {
                return Conflict(new { message = "That already exists. Refresh and try again." });
            }
        }

        // ------------------------------------------------------------- tasks
        // GET api/Poultry/lifecycle/tasks?farmId=&view=Open|Upcoming|Due|Overdue|Completed|Skipped|Scheduled|All&flockId=
        [HttpGet("tasks")]
        public async Task<IActionResult> Tasks([FromQuery] string farmId, [FromQuery] string? view, [FromQuery] int? flockId)
            => NeedFarm(farmId) ?? Ok(await _svc.GetTasksAsync(farmId, view, flockId));

        // GET api/Poultry/lifecycle/summary?farmId=
        [HttpGet("summary")]
        public async Task<IActionResult> Summary([FromQuery] string farmId)
            => NeedFarm(farmId) ?? Ok(await _svc.GetSummaryAsync(farmId));

        // GET api/Poultry/lifecycle/tasks/history?farmId=&flockId=&milestoneId=
        [HttpGet("tasks/history")]
        public async Task<IActionResult> History([FromQuery] string farmId, [FromQuery] int flockId, [FromQuery] int? milestoneId)
            => NeedFarm(farmId) ?? Ok(await _svc.GetHistoryAsync(farmId, flockId, milestoneId));

        // PUT api/Poultry/lifecycle/tasks/status?farmId=
        [HttpPut("tasks/status")]
        public Task<IActionResult> SetStatus([FromBody] LifecycleTaskStatusRequest req) => Run(async () =>
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var taskId = await _svc.SetTaskStatusAsync(req, Actor());
            return Ok(new { taskId });
        });

        // --------------------------------------------------------- templates
        [HttpGet("templates")]
        public async Task<IActionResult> Templates([FromQuery] string farmId)
            => NeedFarm(farmId) ?? Ok(await _svc.GetTemplatesAsync(farmId));

        [HttpGet("templates/{id:int}")]
        public async Task<IActionResult> Template(int id, [FromQuery] string farmId)
        {
            if (NeedFarm(farmId) is { } bad) return bad;
            var t = await _svc.GetTemplateAsync(farmId, id);
            return t is null ? NotFound(new { message = "Lifecycle plan not found for this company." }) : Ok(t);
        }

        [HttpPost("templates")]
        public Task<IActionResult> CreateTemplate([FromBody] LifecycleTemplateSaveRequest req) => Run(async () =>
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var id = await _svc.SaveTemplateAsync(null, req, Actor());
            return Ok(await _svc.GetTemplateAsync(req.FarmId, id));
        });

        [HttpPut("templates/{id:int}")]
        public Task<IActionResult> UpdateTemplate(int id, [FromBody] LifecycleTemplateSaveRequest req) => Run(async () =>
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            await _svc.SaveTemplateAsync(id, req, Actor());
            return Ok(await _svc.GetTemplateAsync(req.FarmId, id));
        });

        [HttpDelete("templates/{id:int}")]
        public Task<IActionResult> DeleteTemplate(int id, [FromQuery] string farmId) => Run(async () =>
        {
            if (NeedFarm(farmId) is { } bad) return bad;
            var outcome = await _svc.DeleteTemplateAsync(farmId, id, Actor());
            return Ok(new { outcome });
        });

        // ------------------------------------------------------- assignments
        [HttpGet("assignments")]
        public async Task<IActionResult> Assignments([FromQuery] string farmId)
            => NeedFarm(farmId) ?? Ok(await _svc.GetAssignmentsAsync(farmId));

        [HttpPost("assignments")]
        public Task<IActionResult> Assign([FromBody] LifecycleAssignRequest req) => Run(async () =>
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if ((req.BatchId is null) == (req.FlockId is null))
                return BadRequest(new { message = "Assign the plan to either a batch or a flock." });
            var id = await _svc.AssignAsync(req, Actor());
            return Ok(new { assignmentId = id });
        });

        [HttpDelete("assignments/{id:int}")]
        public Task<IActionResult> Unassign(int id, [FromQuery] string farmId) => Run(async () =>
        {
            if (NeedFarm(farmId) is { } bad) return bad;
            await _svc.UnassignAsync(farmId, id, Actor());
            return NoContent();
        });
    }
}
