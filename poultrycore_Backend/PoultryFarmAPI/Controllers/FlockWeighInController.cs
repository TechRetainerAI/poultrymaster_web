// Flock weigh-ins (migration 400).
//
// PERMISSIONS: the route maps to poultry.production-records in
// IamPermissionMap -- weighing birds is a daily flock record, done by the same
// people. GET = view, POST = create, PUT = edit, DELETE = delete.

using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Npgsql;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Filters;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [Authorize]
    [ApiController]
    [Route("api/Poultry/weigh-ins")]
    [RequireCompanyType("Poultry")]
    public class FlockWeighInController : ControllerBase
    {
        private readonly IFlockWeighInService _svc;

        public FlockWeighInController(IFlockWeighInService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<FlockWeighIn>>> List([FromQuery] string farmId, [FromQuery] int? flockId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.ListAsync(farmId, flockId));

        [HttpPost]
        public Task<IActionResult> Create([FromBody] FlockWeighInSaveRequest req) => Save(req, null);

        [HttpPut("{id:int}")]
        public Task<IActionResult> Update(int id, [FromBody] FlockWeighInSaveRequest req) => Save(req, id);

        [HttpDelete("{id:int}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string farmId, [FromQuery] string? reason)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return await Refusals(async () => { await _svc.DeleteAsync(id, farmId, Actor(), reason); return NoContent(); });
        }

        private async Task<IActionResult> Save(FlockWeighInSaveRequest req, int? id)
        {
            if (string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest(new { message = "Company ID is required." });
            if (req.FlockId <= 0) return BadRequest(new { message = "Choose the flock that was weighed." });
            if (req.WeightsG is { Length: > 5000 })
                return BadRequest(new { message = "A weigh-in can hold at most 5,000 individual birds." });
            return await Refusals(async () =>
            {
                var newId = await _svc.SaveAsync(req, Actor(), id);
                return id is null ? Ok(new { weighInId = newId }) : NoContent();
            });
        }

        private async Task<IActionResult> Refusals(Func<Task<IActionResult>> run)
        {
            try
            {
                return await run();
            }
            catch (PostgresException ex) when (ex.SqlState == "23505")
            {
                return Conflict(new { message = "That flock was just given a weigh-in for this date by someone else. Refresh and edit it." });
            }
            catch (PostgresException ex) when (ex.SqlState is "P0001" or "23514")
            {
                return BadRequest(new { message = ex.MessageText });
            }
        }

        private string? Actor()
            => User.FindFirst(ClaimTypes.Name)?.Value ?? User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
    }
}
