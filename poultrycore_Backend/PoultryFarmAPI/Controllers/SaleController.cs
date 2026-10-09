using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // 351: authentication is REQUIRED. These routes post revenue, stock and
    // money and -- from 351 -- reverse them; the frontend permission gate alone
    // is not enough (same reasoning as PoultryBalancesController). Which user may
    // do what stays with IamEnforcementFilter ("sale" -> "*.sales"; "reverse" is
    // one of ResolveAction's approve segments).
    //
    // A posted sale is immutable: PUT accepts a description change only, DELETE
    // is refused, and a wrong sale is reversed (POST {id}/reverse) and, if
    // needed, entered again with CorrectsSaleId pointing back at it.
    [Authorize]
    [ApiController]
    [Route("api/[controller]")]
    public class SaleController : ControllerBase
    {
        private readonly ISaleService _saleService;

        public SaleController(ISaleService saleService)
        {
            _saleService = saleService;
        }

        // GET: api/Sale?userId=xxx&farmId=xxx
        [HttpGet]
        public async Task<ActionResult<IEnumerable<SaleModel>>> GetAll([FromQuery] string userId, [FromQuery] string farmId,
                                                                       [FromQuery] bool includeReversed = false)
        {
            if (string.IsNullOrEmpty(userId) || string.IsNullOrEmpty(farmId))
                return BadRequest("UserId and FarmId are required.");

            var allSales = await _saleService.GetAll(userId, farmId);
            // 351: a reversed sale is not a sale. Dashboards, trackers and
            // reports read this list and must not count one, so it is left out
            // unless the caller asks -- only the Sales page does, to list them
            // under its Reversed / All filters.
            return Ok(includeReversed ? allSales : allSales.Where(s => s.Status != "Reversed").ToList());
        }

        // GET: api/Sale/5?userId=xxx&farmId=xxx
        [HttpGet("{id}")]
        public async Task<ActionResult<SaleModel>> GetById(int id, [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId) || string.IsNullOrEmpty(farmId))
                return BadRequest("UserId and FarmId are required.");

            var sale = await _saleService.GetById(id, userId, farmId);
            if (sale == null) return NotFound();
            return Ok(sale);
        }

        // POST: api/Sale
        [HttpPost]
        public async Task<ActionResult<SaleModel>> Create([FromBody] SaleModel model)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);

            if (string.IsNullOrEmpty(model.UserId) || string.IsNullOrEmpty(model.FarmId))
                return BadRequest("UserId and FarmId are required in the model.");

            try
            {
                var newId = await _saleService.Insert(model);
                var createdRecord = await _saleService.GetById(newId, model.UserId, model.FarmId);
                return CreatedAtAction(nameof(GetById), new { id = newId, userId = model.UserId, farmId = model.FarmId }, createdRecord);
            }
            catch (SaleRuleException ex)
            {
                return BadRequest(new { message = ex.Message });
            }
        }

        // POST: api/Sale/group -- one sale of several egg classes (migration 343).
        // Every line is a sale row sharing one sale number; a paid sale to a
        // known customer becomes ONE payment across them. All or nothing.
        [HttpPost("group")]
        public async Task<ActionResult<SaleGroupResult>> CreateGroup([FromBody] SaleGroupRequest request)
        {
            if (string.IsNullOrEmpty(request.UserId) || string.IsNullOrEmpty(request.FarmId))
                return BadRequest("UserId and FarmId are required.");
            if (request.Lines is null || request.Lines.Count == 0)
                return BadRequest(new { message = "Add at least one line to the sale." });
            try
            {
                return Ok(await _saleService.CreateGroup(request));
            }
            catch (Npgsql.PostgresException ex) when (ex.SqlState == "P0001")
            {
                return BadRequest(new { message = ex.MessageText });
            }
            catch (SaleRuleException ex)
            {
                return BadRequest(new { message = ex.Message });
            }
        }

        // POST: api/Sale/5/group?userId=xxx&farmId=xxx -- the sale's SG number,
        // given one first if it has none (migration 349), so egg sizes added
        // on edit join this sale.
        [HttpPost("{id}/group")]
        public async Task<IActionResult> EnsureGroup(int id, [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId) || string.IsNullOrEmpty(farmId))
                return BadRequest("UserId and FarmId are required.");
            try
            {
                return Ok(new { saleGroupNo = await _saleService.EnsureGroup(id, farmId, userId) });
            }
            catch (Npgsql.PostgresException ex) when (ex.SqlState == "P0001")
            {
                return BadRequest(new { message = ex.MessageText });
            }
        }

        // PUT: api/Sale/5
        [HttpPut("{id}")]
        public async Task<IActionResult> Update(int id, [FromBody] SaleModel model)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);

            if (string.IsNullOrEmpty(model.UserId) || string.IsNullOrEmpty(model.FarmId))
                return BadRequest("UserId and FarmId are required in the model.");

            var existing = await _saleService.GetById(id, model.UserId, model.FarmId);
            if (existing == null) return NotFound();

            model.SaleId = id;
            try
            {
                await _saleService.Update(model);
            }
            catch (SaleRuleException ex)
            {
                // A posted sale's money and stock cannot be edited; the message
                // names what was changed and points at Reverse / Correct Sale.
                return Conflict(new { message = ex.Message });
            }
            return NoContent();
        }

        // DELETE: api/Sale/5 -- refused (351). A posted sale is never deleted:
        // reversing it keeps the history and undoes its stock and money properly.
        [HttpDelete("{id}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId) || string.IsNullOrEmpty(farmId))
                return BadRequest("UserId and FarmId are required.");

            var existing = await _saleService.GetById(id, userId, farmId);
            if (existing == null) return NotFound();

            return Conflict(new { message = $"Sale #{id} is posted and cannot be deleted. Reverse it instead -- the sale stays in the history and its stock and money are undone." });
        }

        // GET: api/Sale/5/reversal-preview?farmId=  -- what reversing it would do.
        [HttpGet("{id:int}/reversal-preview")]
        public async Task<IActionResult> ReversalPreview(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest(new { message = "Company ID is required." });
            return Content(await _saleService.GetReversalPreview(id, farmId), "application/json");
        }

        // GET: api/Sale/5/reversal?farmId=  -- the reversal of a reversed sale.
        [HttpGet("{id:int}/reversal")]
        public async Task<IActionResult> Reversal(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest(new { message = "Company ID is required." });
            var json = await _saleService.GetReversal(id, farmId);
            return json is null ? NotFound(new { message = "This sale has not been reversed." }) : Content(json, "application/json");
        }

        // POST: api/Sale/5/reverse?farmId=
        [HttpPost("{id:int}/reverse")]
        public async Task<IActionResult> Reverse(int id, [FromBody] SaleReverseRequest req)
        {
            if (req is null || string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest(new { message = "Company ID is required." });
            // 354: a reason picked from the list is enough; the note is optional
            // (the database still asks for one when the reason is "Other").
            if (string.IsNullOrWhiteSpace(req.ReasonCode) && string.IsNullOrWhiteSpace(req.Reason))
                return BadRequest(new { message = "Give a reason for reversing this sale." });
            // The person on the token, not whatever the body claims.
            req.UserId = User?.FindFirst(ClaimTypes.NameIdentifier)?.Value ?? req.UserId;
            try
            {
                var reversalId = await _saleService.Reverse(id, req);
                return Ok(new { salereversalid = reversalId, reversal = await _saleService.GetReversal(id, req.FarmId) is string j
                                                                         ? System.Text.Json.JsonDocument.Parse(j).RootElement
                                                                         : (System.Text.Json.JsonElement?)null });
            }
            catch (SaleRuleException ex) when (ex.Stale)
            {
                return Conflict(new { message = ex.Message, stale = true });
            }
            catch (SaleRuleException ex)
            {
                return BadRequest(new { message = ex.Message });
            }
        }

        // GET: api/Sale/ByFlock/{flockId}?userId=xxx&farmId=xxx
        [HttpGet("ByFlock/{flockId}")]
        public async Task<ActionResult<IEnumerable<SaleModel>>> GetByFlock(int flockId, [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId) || string.IsNullOrEmpty(farmId))
                return BadRequest("UserId and FarmId are required.");

            var records = await _saleService.GetByFlock(flockId, userId, farmId);
            return Ok(records);
        }
    }
}
