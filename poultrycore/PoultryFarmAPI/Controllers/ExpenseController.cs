using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class ExpenseController : ControllerBase
    {
        private const int MaxAttachmentBytes = 4 * 1024 * 1024;

        private static readonly HashSet<string> AllowedAttachmentContentTypes = new(StringComparer.OrdinalIgnoreCase)
        {
            "image/jpeg", "image/png", "image/webp"
        };

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

        // GET: api/Expense/ByFlock/{flockId}?userId=xxx&farmId=yyy
        [HttpGet("ByFlock/{flockId:int}")]
        public async Task<ActionResult<IEnumerable<ExpenseModel>>> GetByFlock(int flockId, [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId))
                return BadRequest("UserId is required.");
            if (string.IsNullOrEmpty(farmId))
                return BadRequest("FarmId is required.");

            var records = await _expenseService.GetByFlock(flockId, userId, farmId);
            return Ok(records);
        }

        [HttpGet("{id:int}/attachment")]
        public async Task<IActionResult> GetAttachment(int id, [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId))
                return BadRequest("UserId is required.");
            if (string.IsNullOrEmpty(farmId))
                return BadRequest("FarmId is required.");

            var blob = await _expenseService.GetAttachment(id, userId, farmId);
            if (blob == null)
                return NotFound();

            return File(blob.Value.Body, blob.Value.ContentType);
        }

        // GET: api/Expense/5?userId=xxx&farmId=yyy
        [HttpGet("{id:int}")]
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

            var attErr = ValidateOptionalAttachment(model.AttachmentImage, model.AttachmentContentType);
            if (attErr != null)
                return BadRequest(attErr);

            var newId = await _expenseService.Insert(model);

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
                CreatedDate = model.CreatedDate,
                Supplier = model.Supplier,
                HasAttachmentImage = model.AttachmentImage != null && model.AttachmentImage.Length > 0
            };

            return CreatedAtAction(nameof(GetById), new { id = newId, userId = model.UserId, farmId = model.FarmId }, createdExpense);
        }

        // PUT: api/Expense/5
        [HttpPut("{id:int}")]
        public async Task<IActionResult> Update(int id, [FromBody] ExpenseModel model)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);

            if (string.IsNullOrEmpty(model.UserId))
                return BadRequest("UserId is required in the expense model.");
            if (string.IsNullOrEmpty(model.FarmId))
                return BadRequest("FarmId is required in the expense model.");

            if (model.SetAttachmentImage)
            {
                var attErr = ValidateAttachmentForUpdate(model);
                if (attErr != null)
                    return BadRequest(attErr);
            }

            var existing = await _expenseService.GetById(id, model.UserId, model.FarmId);
            if (existing == null)
                return NotFound();

            model.ExpenseId = id;
            await _expenseService.Update(model);
            return NoContent();
        }

        // DELETE: api/Expense/5?userId=xxx&farmId=yyy
        [HttpDelete("{id:int}")]
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

        private static string? ValidateOptionalAttachment(byte[]? image, string? contentType)
        {
            if (image == null || image.Length == 0)
                return null;
            if (image.Length > MaxAttachmentBytes)
                return "Attachment too large (max 4 MB).";
            if (string.IsNullOrWhiteSpace(contentType) || !AllowedAttachmentContentTypes.Contains(contentType.Trim()))
                return "Attachment content type must be image/jpeg, image/png, or image/webp.";
            return null;
        }

        private static string? ValidateAttachmentForUpdate(ExpenseModel model)
        {
            if (model.AttachmentImage == null || model.AttachmentImage.Length == 0)
                return null;
            return ValidateOptionalAttachment(model.AttachmentImage, model.AttachmentContentType);
        }
    }
}
