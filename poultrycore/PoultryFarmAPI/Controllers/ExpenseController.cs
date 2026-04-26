using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class ExpenseController : ControllerBase
    {
        private readonly IExpenseService _expenseService;

        public ExpenseController(IExpenseService expenseService)
        {
            _expenseService = expenseService;
        }

        // GET: api/Expense?userId=xxx&farmId=yyy
        [HttpGet]
        public async Task<ActionResult<IEnumerable<ExpenseModel>>> GetAll([FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId))
                return BadRequest("UserId is required.");
            if (string.IsNullOrEmpty(farmId))
                return BadRequest("FarmId is required.");

            var allExpenses = await _expenseService.GetAll(userId, farmId);
            return Ok(allExpenses);
        }

        // GET: api/Expense/5?userId=xxx&farmId=yyy
        [HttpGet("{id}")]
        public async Task<ActionResult<ExpenseModel>> GetById(int id, [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId))
                return BadRequest("UserId is required.");
            if (string.IsNullOrEmpty(farmId))
                return BadRequest("FarmId is required.");

            var expense = await _expenseService.GetById(id, userId, farmId);
            if (expense == null)
                return NotFound();
            return Ok(expense);
        }

        // POST: api/Expense
        [HttpPost]
        public async Task<ActionResult<ExpenseModel>> Create([FromBody] ExpenseModel model)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);

            if (string.IsNullOrEmpty(model.UserId))
                return BadRequest("UserId is required in the expense model.");
            if (string.IsNullOrEmpty(model.FarmId))
                return BadRequest("FarmId is required in the expense model.");

            var newId = await _expenseService.Insert(model);
            
            // Return the created expense with the new ID instead of fetching from DB
            // (spExpense_GetById doesn't return FarmId and UserId)
            var createdExpense = new ExpenseModel
            {
                ExpenseId = newId,
                FarmId = model.FarmId,
                UserId = model.UserId,
                ExpenseDate = model.ExpenseDate,
                Category = model.Category,
                Description = model.Description,
                Amount = model.Amount,
                PaymentMethod = model.PaymentMethod,
                FlockId = model.FlockId,
                CreatedDate = model.CreatedDate
            };
            
            return CreatedAtAction(nameof(GetById), new { id = newId, userId = model.UserId, farmId = model.FarmId }, createdExpense);
        }

        // PUT: api/Expense/5
        [HttpPut("{id}")]
        public async Task<IActionResult> Update(int id, [FromBody] ExpenseModel model)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);

            if (string.IsNullOrEmpty(model.UserId))
                return BadRequest("UserId is required in the expense model.");
            if (string.IsNullOrEmpty(model.FarmId))
                return BadRequest("FarmId is required in the expense model.");

            var existing = await _expenseService.GetById(id, model.UserId, model.FarmId);
            if (existing == null)
                return NotFound();

            model.ExpenseId = id;
            await _expenseService.Update(model);
            return NoContent();
        }

        // DELETE: api/Expense/5?userId=xxx&farmId=yyy
        [HttpDelete("{id}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId))
                return BadRequest("UserId is required.");
            if (string.IsNullOrEmpty(farmId))
                return BadRequest("FarmId is required.");

            var existing = await _expenseService.GetById(id, userId, farmId);
            if (existing == null)
                return NotFound();

            await _expenseService.Delete(id, userId, farmId);
            return NoContent();
        }

        // GET: api/Expense/ByFlock/{flockId}?userId=xxx&farmId=yyy
        [HttpGet("ByFlock/{flockId}")]
        public async Task<ActionResult<IEnumerable<ExpenseModel>>> GetByFlock(int flockId, [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId))
                return BadRequest("UserId is required.");
            if (string.IsNullOrEmpty(farmId))
                return BadRequest("FarmId is required.");

            var records = await _expenseService.GetByFlock(flockId, userId, farmId);
            return Ok(records);
        }
    }
}
