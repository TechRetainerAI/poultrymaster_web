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
                // Cash in is what has actually been collected, not an all-or-nothing read of
                // the Paid flag — that flag only flips once payments reach the full total
                // (migration 145), so a part-paid sale used to show zero cash and the whole
                // amount as owed. Paid sales still use TotalAmount so nothing regresses on
                // databases where AmountPaid is absent and defaults to 0.
                var received = s.Paid ? s.TotalAmount : Math.Clamp(s.AmountPaid, 0m, s.TotalAmount);
                var dto = new CashTransactionDto
                {
                    Date = dateStr,
                    Type = "Sale",
                    Description = desc,
                    In = received,
                    Owed = s.TotalAmount - received,
                    Out = 0,
                    Balance = 0,
                    SortKey = (s.SaleDate != default ? s.SaleDate : s.CreatedDate).ToString("yyyy-MM-dd HH:mm:ss") + "_s" + s.SaleId
                };
                items.Add((dto.SortKey, dto));
            }

            foreach (var e in expenses)
            {
                // This is a CASH ledger, so two kinds of expense do not belong in it.
                //
                // NonCash is internal use (migration 216): stock left the store, no
                // money left an account. Cash Flow has excluded it since 231; this
                // page never did, which is why the two disagreed.
                //
                // AmountPaid rather than Amount because migration 238 made an
                // expense part-payable. Before it, every expense was paid in full
                // and the two were the same number; now a 1,000 bill with 400 paid
                // must show 400 here, not 1,000. AmountPaid arrives already
                // resolved from the SP, so a row predating 238 still reads as its
                // full amount and nothing historical moves.
                if (string.Equals(e.PaymentMethod, "NonCash", StringComparison.OrdinalIgnoreCase))
                    continue;
                // Null only if the row came from a source that never set it;
                // the legacy reading of that is "paid in full".
                var paidOut = e.AmountPaid ?? e.Amount;
                if (paidOut <= 0) continue;   // recorded but not yet paid: no cash moved

                var dateStr = (e.ExpenseDate != default ? e.ExpenseDate : e.CreatedDate).ToString("yyyy-MM-dd");
                var desc = !string.IsNullOrEmpty(e.Description) ? e.Description : e.Category;
                if (string.IsNullOrEmpty(desc)) desc = "Expense";
                var dto = new CashTransactionDto
                {
                    Date = dateStr,
                    Type = "Expense",
                    Description = desc,
                    In = 0,
                    Out = paidOut,
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
