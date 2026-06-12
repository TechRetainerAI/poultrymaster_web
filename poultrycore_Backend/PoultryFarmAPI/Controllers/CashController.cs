using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class CashController : ControllerBase
    {
        private readonly ICashAdjustmentService _cashAdjustmentService;
        private readonly ISaleService _saleService;
        private readonly IExpenseService _expenseService;

        public CashController(
            ICashAdjustmentService cashAdjustmentService,
            ISaleService saleService,
            IExpenseService expenseService)
        {
            _cashAdjustmentService = cashAdjustmentService;
            _saleService = saleService;
            _expenseService = expenseService;
        }

        // GET: api/Cash?userId=xxx&farmId=yyy
        [HttpGet]
        public async Task<ActionResult<CashSummaryModel>> GetSummary([FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(farmId))
                return BadRequest("FarmId is required.");

            var adjustments = await _cashAdjustmentService.GetAllAsync(farmId);
            var sales = await _saleService.GetAll(userId ?? "", farmId);
            var expenses = await _expenseService.GetAll(userId ?? "", farmId);

            var transactions = new List<CashTransactionDto>();
            decimal runningBalance = 0;

            // Build unified list with sort key
            var items = new List<(string sortKey, CashTransactionDto dto)>();

            foreach (var a in adjustments)
            {
                var dateStr = a.AdjustmentDate.ToString("yyyy-MM-dd");
                var typeName = FormatAdjustmentType(a.AdjustmentType);
                var amt = a.Amount;
                var dto = new CashTransactionDto
                {
                    Date = dateStr,
                    Type = typeName,
                    Description = a.Description ?? typeName,
                    In = amt > 0 ? amt : 0,
                    Out = amt < 0 ? Math.Abs(amt) : 0,
                    Balance = 0,
                    SortKey = a.AdjustmentDate.ToString("yyyy-MM-dd HH:mm:ss") + "_" + a.AdjustmentId
                };
                items.Add((dto.SortKey, dto));
            }

            foreach (var s in sales)
            {
                var dateStr = (s.SaleDate != default ? s.SaleDate : s.CreatedDate).ToString("yyyy-MM-dd");
                var desc = !string.IsNullOrEmpty(s.SaleDescription) ? s.SaleDescription : $"{s.Product} - {s.CustomerName ?? ""}".Trim();
                if (string.IsNullOrEmpty(desc)) desc = "Sale";
                var dto = new CashTransactionDto
                {
                    Date = dateStr,
                    Type = "Sale",
                    Description = desc,
                    In = s.Paid ? s.TotalAmount : 0,
                    Owed = s.Paid ? 0 : s.TotalAmount,
                    Out = 0,
                    Balance = 0,
                    SortKey = (s.SaleDate != default ? s.SaleDate : s.CreatedDate).ToString("yyyy-MM-dd HH:mm:ss") + "_s" + s.SaleId
                };
                items.Add((dto.SortKey, dto));
            }

            foreach (var e in expenses)
            {
                var dateStr = (e.ExpenseDate != default ? e.ExpenseDate : e.CreatedDate).ToString("yyyy-MM-dd");
                var desc = !string.IsNullOrEmpty(e.Description) ? e.Description : e.Category;
                if (string.IsNullOrEmpty(desc)) desc = "Expense";
                var dto = new CashTransactionDto
                {
                    Date = dateStr,
                    Type = "Expense",
                    Description = desc,
                    In = 0,
                    Out = e.Amount,
                    Balance = 0,
                    SortKey = (e.ExpenseDate != default ? e.ExpenseDate : e.CreatedDate).ToString("yyyy-MM-dd HH:mm:ss") + "_e" + e.ExpenseId
                };
                items.Add((dto.SortKey, dto));
            }

            items.Sort((a, b) => string.Compare(a.sortKey, b.sortKey, StringComparison.Ordinal));

            foreach (var (_, dto) in items)
            {
                runningBalance += dto.In - dto.Out;
                dto.Balance = runningBalance;
                transactions.Add(dto);
            }

            var summary = new CashSummaryModel
            {
                CurrentCash = runningBalance,
                LastUpdated = DateTime.UtcNow,
                Transactions = transactions
            };

            return Ok(summary);
        }

        // GET: api/Cash/Adjustment/5?farmId=yyy
        [HttpGet("Adjustment/{id}")]
        public async Task<ActionResult<CashAdjustmentModel>> GetAdjustment(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(farmId))
                return BadRequest("FarmId is required.");

            var adj = await _cashAdjustmentService.GetByIdAsync(id, farmId);
            if (adj == null)
                return NotFound();
            return Ok(adj);
        }

        // POST: api/Cash/Adjustment
        [HttpPost("Adjustment")]
        public async Task<ActionResult<CashAdjustmentModel>> CreateAdjustment([FromBody] CashAdjustmentModel model)
        {
            if (string.IsNullOrEmpty(model.UserId))
                return BadRequest("UserId is required.");
            if (string.IsNullOrEmpty(model.FarmId))
                return BadRequest("FarmId is required.");
            if (string.IsNullOrEmpty(model.AdjustmentType))
                return BadRequest("AdjustmentType is required.");

            var validTypes = new[] { "OpeningBalance", "OwnerInjection", "LoanReceived", "Withdrawal", "Correction" };
            if (!validTypes.Contains(model.AdjustmentType, StringComparer.OrdinalIgnoreCase))
                return BadRequest($"AdjustmentType must be one of: {string.Join(", ", validTypes)}.");

            var newId = await _cashAdjustmentService.InsertAsync(model);
            model.AdjustmentId = newId;
            model.CreatedDate = DateTime.UtcNow;
            return CreatedAtAction(nameof(GetAdjustment), new { id = newId, farmId = model.FarmId }, model);
        }

        // PUT: api/Cash/Adjustment/5
        [HttpPut("Adjustment/{id}")]
        public async Task<IActionResult> UpdateAdjustment(int id, [FromBody] CashAdjustmentModel model)
        {
            if (string.IsNullOrEmpty(model.FarmId))
                return BadRequest("FarmId is required.");
            if (string.IsNullOrEmpty(model.AdjustmentType))
                return BadRequest("AdjustmentType is required.");

            var existing = await _cashAdjustmentService.GetByIdAsync(id, model.FarmId);
            if (existing == null)
                return NotFound();

            model.AdjustmentId = id;
            await _cashAdjustmentService.UpdateAsync(model);
            return NoContent();
        }

        // DELETE: api/Cash/Adjustment/5?farmId=yyy
        [HttpDelete("Adjustment/{id}")]
        public async Task<IActionResult> DeleteAdjustment(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(farmId))
                return BadRequest("FarmId is required.");

            var existing = await _cashAdjustmentService.GetByIdAsync(id, farmId);
            if (existing == null)
                return NotFound();

            await _cashAdjustmentService.DeleteAsync(id, farmId);
            return NoContent();
        }

        private static string FormatAdjustmentType(string type)
        {
            return type switch
            {
                "OpeningBalance" => "Opening Balance",
                "OwnerInjection" => "Owner injection",
                "LoanReceived" => "Loan received",
                "Withdrawal" => "Withdrawal",
                "Correction" => "Correction",
                _ => type
            };
        }
    }
}
