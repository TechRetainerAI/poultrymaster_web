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

    // Body for POST cash-accounts/{id}/adjust.
    public class WaterCashAdjustRequest
    {
        public decimal Amount { get; set; }
        public string Reason { get; set; } = string.Empty;
        public string? CreatedBy { get; set; }
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

        // Manual balance adjustment (signed amount; + adds cash, - removes it).
        [HttpPost("{id:int}/adjust")]
        public async Task<IActionResult> Adjust(int id, [FromQuery] string farmId, [FromBody] WaterCashAdjustRequest req)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            if (req is null || req.Amount == 0) return BadRequest("A non-zero amount is required.");
            if (string.IsNullOrWhiteSpace(req.Reason)) return BadRequest("A reason is required for an adjustment.");
            await _svc.AdjustAsync(id, farmId, req.Amount, req.Reason, req.CreatedBy);
            return NoContent();
        }

        [HttpGet("transactions")]
        public async Task<ActionResult<IEnumerable<WaterCashTransactionModel>>> GetTransactions(
            [FromQuery] string farmId,
            [FromQuery] int? cashAccountId,
            [FromQuery] DateTime? fromDate,
            [FromQuery] DateTime? toDate,
            [FromQuery] string? clearingStatus)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetTransactionsAsync(farmId, cashAccountId, fromDate, toDate, clearingStatus));
        }
    }

    // ====================================================================
    // Cash reconciliation (migration 222)
    // ====================================================================
    // A cash COUNT. Distinct from cash-accounts/reconcile-balances, which
    // recomputes the cached balance from the ledger and moves no money.
    //
    // The /post and /reverse segments are deliberate: IamPermissionMap's
    // ResolveAction treats both as the `approve` action, so these routes map to
    // water.cash-reconciliation.approve without any special-casing.
    [ApiController]
    [Route("api/Water/cash-reconciliations")]
    public class WaterCashReconciliationController : ControllerBase
    {
        private readonly IWaterCashReconciliationService _svc;
        public WaterCashReconciliationController(IWaterCashReconciliationService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<WaterCashReconciliationModel>>> GetAll(
            [FromQuery] string farmId, [FromQuery] int? cashAccountId, [FromQuery] string? status,
            [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetAllAsync(farmId, cashAccountId, status, fromDate, toDate));
        }

        [HttpGet("{id:int}")]
        public async Task<ActionResult<WaterCashReconciliationModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var model = await _svc.GetByIdAsync(id, farmId);
            return model is null ? NotFound() : Ok(model);
        }

        [HttpGet("account/{cashAccountId:int}")]
        public async Task<ActionResult<IEnumerable<WaterCashReconciliationModel>>> GetByAccount(
            int cashAccountId, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetByAccountAsync(cashAccountId, farmId));
        }

        // Badge feed for the accounts list: days since counted, uncleared
        // totals, cache drift, open draft.
        [HttpGet("account-status")]
        public async Task<ActionResult<IEnumerable<WaterCashAccountReconStatusModel>>> GetAccountStatus(
            [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetAccountStatusAsync(farmId));
        }

        [HttpPost]
        public async Task<ActionResult<object>> Create(
            [FromQuery] string farmId, [FromBody] WaterCashReconciliationModel body)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            if (body is null) return BadRequest("Nothing to save.");
            if (body.WaterCashAccountId <= 0) return BadRequest("Pick a cash account first.");
            var id = await _svc.InsertAsync(farmId, body.WaterCashAccountId,
                body.ReconciliationDate == default ? null : body.ReconciliationDate,
                body.ActualBalance, body.Reason, body.Notes, body.CreatedBy);
            return Ok(new { WaterCashReconciliationId = id });
        }

        [HttpPut("{id:int}")]
        public async Task<IActionResult> Update(
            int id, [FromQuery] string farmId, [FromBody] WaterCashReconciliationModel body)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            if (body is null) return BadRequest("Nothing to save.");
            await _svc.UpdateAsync(id, farmId,
                body.ReconciliationDate == default ? null : body.ReconciliationDate,
                body.ActualBalance, body.Reason, body.Notes, body.CreatedBy);
            return NoContent();
        }

        [HttpDelete("{id:int}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string farmId, [FromQuery] string? userId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.DeleteAsync(id, farmId, userId);
            return NoContent();
        }

        [HttpPost("{id:int}/post")]
        public async Task<ActionResult<object>> Post(
            int id, [FromQuery] string farmId, [FromBody] WaterCashReconciliationPostRequest? body)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var adjustmentId = await _svc.PostAsync(id, farmId, body?.PostedBy, body?.ClearedTransactionIds);
            // A null id is the balanced case, not a failure.
            return Ok(new { AdjustmentTransactionId = adjustmentId });
        }

        [HttpPost("{id:int}/reverse")]
        public async Task<IActionResult> Reverse(
            int id, [FromQuery] string farmId, [FromBody] WaterCashReconciliationReverseRequest? body)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.ReverseAsync(id, farmId, body?.Reason, body?.ReversedBy);
            return NoContent();
        }

        [HttpPost("clearing")]
        public async Task<ActionResult<object>> SetClearing(
            [FromQuery] string farmId, [FromBody] WaterCashClearingRequest body)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            if (body is null || body.TransactionIds.Count == 0) return BadRequest("Pick at least one transaction.");
            if (body.WaterCashAccountId <= 0) return BadRequest("Cash account is required.");
            var n = await _svc.SetClearingAsync(farmId, body.WaterCashAccountId, body.TransactionIds,
                                                body.ClearingStatus, body.ClearingNotes, body.UserId);
            return Ok(new { Updated = n });
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

        /// <summary>
        /// Set how much of a bill has been paid, and when it falls due.
        ///
        /// Its own endpoint rather than fields on the create/update body, because
        /// amountPaid has to be able to say "not supplied" separately from "zero"
        /// — a nullable in a JSON body carries that, a decimal on the expense
        /// model cannot, and getting it wrong turns a paid bill into a debt.
        /// </summary>
        [HttpPost("{id:int}/payment")]
        public async Task<IActionResult> SetPayment(int id, [FromQuery] string farmId,
                                                    [FromBody] WaterExpensePaymentRequest body)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.SetPaymentAsync(id, farmId, body?.AmountPaid, body?.DueDate);
            var updated = await _svc.GetByIdAsync(id, farmId);
            return updated is null ? NotFound() : Ok(updated);
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
