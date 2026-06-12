// Water Company finance controllers — Expenses, Cash Accounts, Cash Transfers,
// Customer Ledger. Same flat per-resource [Route] style as the other Water
// controllers (WaterPhase3Controllers.cs). FarmId is passed as a query string,
// matching the convention used by the existing Water controllers — the Generic
// Company controllers embed it in the route, but Water is consistent the other
// way and the frontend already expects this shape.

using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // ====================================================================
    // Expense categories
    // ====================================================================
    [ApiController]
    [Route("api/Water/expense-categories")]
    public class WaterExpenseCategoryController : ControllerBase
    {
        private readonly IWaterExpenseCategoryService _svc;
        public WaterExpenseCategoryController(IWaterExpenseCategoryService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<WaterExpenseCategoryModel>>> GetAll([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetAllAsync(farmId));

        [HttpPost]
        public async Task<ActionResult<int>> Create([FromBody] WaterExpenseCategoryModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.InsertAsync(m);
            return Ok(new { WaterExpenseCategoryId = id });
        }

        [HttpPut("{id:int}")]
        public async Task<IActionResult> Update(int id, [FromBody] WaterExpenseCategoryModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            m.WaterExpenseCategoryId = id;
            await _svc.UpdateAsync(m);
            return NoContent();
        }

        [HttpDelete("{id:int}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.DeleteAsync(id, farmId);
            return NoContent();
        }
    }

    // ====================================================================
    // Cash accounts (+ transactions read)
    // ====================================================================
    [ApiController]
    [Route("api/Water/cash-accounts")]
    public class WaterCashAccountController : ControllerBase
    {
        private readonly IWaterCashAccountService _svc;
        public WaterCashAccountController(IWaterCashAccountService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<WaterCashAccountModel>>> GetAll([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetAllAsync(farmId));

        [HttpGet("{id:int}")]
        public async Task<ActionResult<WaterCashAccountModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var m = await _svc.GetByIdAsync(id, farmId);
            return m is null ? NotFound() : Ok(m);
        }

        [HttpPost]
        public async Task<ActionResult<int>> Create([FromBody] WaterCashAccountModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.InsertAsync(m);
            return Ok(new { WaterCashAccountId = id });
        }

        [HttpPut("{id:int}")]
        public async Task<IActionResult> Update(int id, [FromBody] WaterCashAccountModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            m.WaterCashAccountId = id;
            await _svc.UpdateAsync(m);
            return NoContent();
        }

        [HttpDelete("{id:int}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.DeleteAsync(id, farmId);
            return NoContent();
        }

        // Recompute CurrentBalance from OpeningBalance + SUM(WaterCashTransactions.Amount).
        [HttpPost("reconcile-balances")]
        public async Task<IActionResult> Reconcile([FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.ReconcileBalanceAsync(farmId);
            return NoContent();
        }

        [HttpGet("transactions")]
        public async Task<ActionResult<IEnumerable<WaterCashTransactionModel>>> GetTransactions(
            [FromQuery] string farmId,
            [FromQuery] int? cashAccountId,
            [FromQuery] DateTime? fromDate,
            [FromQuery] DateTime? toDate)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetTransactionsAsync(farmId, cashAccountId, fromDate, toDate));
        }
    }

    // ====================================================================
    // Cash transfers
    // ====================================================================
    [ApiController]
    [Route("api/Water/cash-transfers")]
    public class WaterCashTransferController : ControllerBase
    {
        private readonly IWaterCashTransferService _svc;
        public WaterCashTransferController(IWaterCashTransferService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<WaterCashTransferModel>>> GetAll(
            [FromQuery] string farmId, [FromQuery] string? status)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetAllAsync(farmId, status));

        [HttpGet("{id:int}")]
        public async Task<ActionResult<WaterCashTransferModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var m = await _svc.GetByIdAsync(id, farmId);
            return m is null ? NotFound() : Ok(m);
        }

        [HttpPost]
        public async Task<ActionResult<int>> Create([FromBody] WaterCashTransferModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.InsertAsync(m);
            return Ok(new { WaterCashTransferId = id });
        }

        [HttpPost("{id:int}/approve")]
        public async Task<IActionResult> Approve(int id, [FromQuery] string farmId, [FromQuery] string? approvedBy)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.ApproveAsync(id, farmId, approvedBy);
            return NoContent();
        }

        [HttpPost("{id:int}/cancel")]
        public async Task<IActionResult> Cancel(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.CancelAsync(id, farmId);
            return NoContent();
        }
    }

    // ====================================================================
    // Expenses (Draft → Submitted → Approved/Rejected/Cancelled)
    // ====================================================================
    [ApiController]
    [Route("api/Water/expenses")]
    public class WaterExpenseController : ControllerBase
    {
        private readonly IWaterExpenseService _svc;
        public WaterExpenseController(IWaterExpenseService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<WaterExpenseModel>>> GetAll(
            [FromQuery] string farmId,
            [FromQuery] string? status,
            [FromQuery] DateTime? fromDate,
            [FromQuery] DateTime? toDate)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetAllAsync(farmId, status, fromDate, toDate));

        [HttpGet("{id:int}")]
        public async Task<ActionResult<WaterExpenseModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var m = await _svc.GetByIdAsync(id, farmId);
            return m is null ? NotFound() : Ok(m);
        }

        [HttpPost]
        public async Task<ActionResult<WaterExpenseModel>> Create([FromBody] WaterExpenseModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.InsertAsync(m);
            var created = await _svc.GetByIdAsync(id, m.FarmId);
            return CreatedAtAction(nameof(GetById), new { id, farmId = m.FarmId }, created);
        }

        [HttpPost("{id:int}/submit")]
        public async Task<IActionResult> Submit(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.SubmitAsync(id, farmId);
            return NoContent();
        }

        [HttpPost("{id:int}/approve")]
        public async Task<IActionResult> Approve(int id, [FromQuery] string farmId, [FromQuery] string? approvedBy)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.ApproveAsync(id, farmId, approvedBy);
            return NoContent();
        }

        [HttpPost("{id:int}/reject")]
        public async Task<IActionResult> Reject(int id, [FromQuery] string farmId, [FromQuery] string? approvedBy,
                                                [FromBody] WaterExpenseRejectRequest body)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.RejectAsync(id, farmId, approvedBy, body?.Reason);
            return NoContent();
        }

        [HttpPost("{id:int}/cancel")]
        public async Task<IActionResult> Cancel(int id, [FromQuery] string farmId, [FromQuery] string? cancelledBy,
                                                [FromBody] WaterExpenseCancelRequest body)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.CancelAsync(id, farmId, cancelledBy, body?.Reason);
            return NoContent();
        }

        [HttpDelete("{id:int}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.DeleteAsync(id, farmId);
            return NoContent();
        }

        // Seed default expense categories + cash accounts for a farm. Safe to
        // run multiple times (the SP skips rows that already exist).
        [HttpPost("seed-defaults")]
        public async Task<IActionResult> SeedDefaults([FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var (cats, accts) = await _svc.SeedDefaultsAsync(farmId);
            return Ok(new { ExpenseCategoryCount = cats, CashAccountCount = accts });
        }
    }

    // ====================================================================
    // Customer ledger
    // ====================================================================
    [ApiController]
    [Route("api/Water/customers")]
    public class WaterCustomerLedgerController : ControllerBase
    {
        private readonly IWaterCustomerLedgerService _svc;
        public WaterCustomerLedgerController(IWaterCustomerLedgerService svc) => _svc = svc;

        [HttpGet("{customerId:int}/ledger")]
        public async Task<ActionResult<IEnumerable<WaterCustomerLedgerEntryModel>>> GetLedger(
            int customerId, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetForCustomerAsync(farmId, customerId));
        }

        [HttpPost("{customerId:int}/ledger")]
        public async Task<ActionResult<object>> AddEntry(
            int customerId, [FromQuery] string farmId, [FromQuery] string? createdBy,
            [FromBody] WaterCustomerLedgerAddRequest body)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            body.WaterCustomerId = customerId;
            var (id, balance) = await _svc.AddEntryAsync(farmId, body, createdBy);
            return Ok(new { WaterCustomerLedgerId = id, BalanceAfterTransaction = balance });
        }
    }

    // ====================================================================
    // Suppliers — migration 076. CRUD master list used by the standalone
    // /water-suppliers page, the Setup tab, and the SupplierSelect dropdown
    // on Expense + RawMaterialPurchase forms.
    // ====================================================================
    [ApiController]
    [Route("api/Water/suppliers")]
    public class WaterSupplierController : ControllerBase
    {
        private readonly IWaterSupplierService _svc;
        public WaterSupplierController(IWaterSupplierService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<WaterSupplierModel>>> List(
            [FromQuery] string farmId,
            [FromQuery] bool includeInactive = false,
            [FromQuery] bool includeDeleted = false,
            [FromQuery] string? search = null)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.ListAsync(farmId, includeInactive, includeDeleted, search));

        [HttpGet("{id:int}")]
        public async Task<ActionResult<WaterSupplierModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var m = await _svc.GetByIdAsync(id, farmId);
            return m is null ? NotFound() : Ok(m);
        }

        [HttpPost]
        public async Task<ActionResult<WaterSupplierModel>> Create([FromBody] WaterSupplierModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.InsertAsync(m);
            var created = await _svc.GetByIdAsync(id, m.FarmId);
            return CreatedAtAction(nameof(GetById), new { id, farmId = m.FarmId }, created);
        }

        [HttpPut("{id:int}")]
        public async Task<ActionResult<WaterSupplierModel>> Update(int id, [FromBody] WaterSupplierModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            m.WaterSupplierId = id;
            await _svc.UpdateAsync(m);
            return Ok(await _svc.GetByIdAsync(id, m.FarmId));
        }

        [HttpDelete("{id:int}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string farmId, [FromQuery] string? deletedBy)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.DeleteAsync(id, farmId, deletedBy);
            return NoContent();
        }
    }
}
