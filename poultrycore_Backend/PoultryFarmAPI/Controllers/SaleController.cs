using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
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
        public async Task<ActionResult<IEnumerable<SaleModel>>> GetAll([FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId) || string.IsNullOrEmpty(farmId))
                return BadRequest("UserId and FarmId are required.");

            var allSales = await _saleService.GetAll(userId, farmId);
            return Ok(allSales);
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

            var newId = await _saleService.Insert(model);
            var createdRecord = await _saleService.GetById(newId, model.UserId, model.FarmId);
            return CreatedAtAction(nameof(GetById), new { id = newId, userId = model.UserId, farmId = model.FarmId }, createdRecord);
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
            await _saleService.Update(model);
            return NoContent();
        }

        // DELETE: api/Sale/5?userId=xxx&farmId=xxx
        [HttpDelete("{id}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId) || string.IsNullOrEmpty(farmId))
                return BadRequest("UserId and FarmId are required.");

            var existing = await _saleService.GetById(id, userId, farmId);
            if (existing == null) return NotFound();

            await _saleService.Delete(id, userId, farmId);
            return NoContent();
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
