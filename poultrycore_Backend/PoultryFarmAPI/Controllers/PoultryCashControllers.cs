// Poultry Cash Account controllers — Cash Accounts, Cash Transfers (port of the
// Water finance controllers). Flat per-resource [Route] with FarmId on the query
// string, matching the Water convention the frontend already expects.

using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // ====================================================================
    // Cash accounts (+ transactions read)
    // ====================================================================
    [ApiController]
    [Route("api/Poultry/cash-accounts")]
    public class PoultryCashAccountController : ControllerBase
    {
        private readonly IPoultryCashAccountService _svc;
        public PoultryCashAccountController(IPoultryCashAccountService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<PoultryCashAccountModel>>> GetAll([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetAllAsync(farmId));

        [HttpGet("{id:int}")]
        public async Task<ActionResult<PoultryCashAccountModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var m = await _svc.GetByIdAsync(id, farmId);
            return m is null ? NotFound() : Ok(m);
        }

        [HttpPost]
        public async Task<ActionResult<int>> Create([FromBody] PoultryCashAccountModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.InsertAsync(m);
            return Ok(new { PoultryCashAccountId = id });
        }

        [HttpPut("{id:int}")]
        public async Task<IActionResult> Update(int id, [FromBody] PoultryCashAccountModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            m.PoultryCashAccountId = id;
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

        [HttpPost("reconcile-balances")]
        public async Task<IActionResult> Reconcile([FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.ReconcileBalanceAsync(farmId);
            return NoContent();
        }

        [HttpPost("{id:int}/adjust")]
        public async Task<IActionResult> Adjust(int id, [FromQuery] string farmId, [FromBody] PoultryCashAdjustRequest req)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            if (req is null || req.Amount == 0) return BadRequest("A non-zero amount is required.");
            if (string.IsNullOrWhiteSpace(req.Reason)) return BadRequest("A reason is required for an adjustment.");
            await _svc.AdjustAsync(id, farmId, req.Amount, req.Reason, req.CreatedBy);
            return NoContent();
        }

        [HttpGet("transactions")]
        public async Task<ActionResult<IEnumerable<PoultryCashTransactionModel>>> GetTransactions(
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
    // Cash reconciliation (migration 223)
    // ====================================================================
    // A cash COUNT. Distinct from cash-accounts/reconcile-balances, which
    // recomputes the cached balance from the ledger and moves no money.
    //
    // The /post and /reverse segments are deliberate: IamPermissionMap's
    // ResolveAction treats both as the `approve` action, so these routes map to
    // poultry.cash-reconciliation.approve without any special-casing.
    [ApiController]
    [Route("api/Poultry/cash-reconciliations")]
    public class PoultryCashReconciliationController : ControllerBase
    {
        private readonly IPoultryCashReconciliationService _svc;
        public PoultryCashReconciliationController(IPoultryCashReconciliationService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<PoultryCashReconciliationModel>>> GetAll(
            [FromQuery] string farmId, [FromQuery] int? cashAccountId, [FromQuery] string? status,
            [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetAllAsync(farmId, cashAccountId, status, fromDate, toDate));
        }

        [HttpGet("{id:int}")]
        public async Task<ActionResult<PoultryCashReconciliationModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var model = await _svc.GetByIdAsync(id, farmId);
            return model is null ? NotFound() : Ok(model);
        }

        [HttpGet("account/{cashAccountId:int}")]
        public async Task<ActionResult<IEnumerable<PoultryCashReconciliationModel>>> GetByAccount(
            int cashAccountId, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetByAccountAsync(cashAccountId, farmId));
        }

        // Badge feed for the accounts list: days since counted, uncleared
        // totals, cache drift, open draft.
        [HttpGet("account-status")]
        public async Task<ActionResult<IEnumerable<PoultryCashAccountReconStatusModel>>> GetAccountStatus(
            [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetAccountStatusAsync(farmId));
        }

        [HttpPost]
        public async Task<ActionResult<object>> Create(
            [FromQuery] string farmId, [FromBody] PoultryCashReconciliationModel body)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            if (body is null) return BadRequest("Nothing to save.");
            if (body.PoultryCashAccountId <= 0) return BadRequest("Pick a cash account first.");
            var id = await _svc.InsertAsync(farmId, body.PoultryCashAccountId,
                body.ReconciliationDate == default ? null : body.ReconciliationDate,
                body.ActualBalance, body.Reason, body.Notes, body.CreatedBy);
            return Ok(new { PoultryCashReconciliationId = id });
        }

        [HttpPut("{id:int}")]
        public async Task<IActionResult> Update(
            int id, [FromQuery] string farmId, [FromBody] PoultryCashReconciliationModel body)
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
            int id, [FromQuery] string farmId, [FromBody] PoultryCashReconciliationPostRequest? body)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var adjustmentId = await _svc.PostAsync(id, farmId, body?.PostedBy, body?.ClearedTransactionIds);
            // A null id is the balanced case, not a failure.
            return Ok(new { AdjustmentTransactionId = adjustmentId });
        }

        [HttpPost("{id:int}/reverse")]
        public async Task<IActionResult> Reverse(
            int id, [FromQuery] string farmId, [FromBody] PoultryCashReconciliationReverseRequest? body)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.ReverseAsync(id, farmId, body?.Reason, body?.ReversedBy);
            return NoContent();
        }

        [HttpPost("clearing")]
        public async Task<ActionResult<object>> SetClearing(
            [FromQuery] string farmId, [FromBody] PoultryCashClearingRequest body)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            if (body is null || body.TransactionIds.Count == 0) return BadRequest("Pick at least one transaction.");
            if (body.PoultryCashAccountId <= 0) return BadRequest("Cash account is required.");
            var n = await _svc.SetClearingAsync(farmId, body.PoultryCashAccountId, body.TransactionIds,
                                                body.ClearingStatus, body.ClearingNotes, body.UserId);
            return Ok(new { Updated = n });
        }
    }

    // ====================================================================
    // Cash transfers
    // ====================================================================
    [ApiController]
    [Route("api/Poultry/cash-transfers")]
    public class PoultryCashTransferController : ControllerBase
    {
        private readonly IPoultryCashTransferService _svc;
        public PoultryCashTransferController(IPoultryCashTransferService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<PoultryCashTransferModel>>> GetAll(
            [FromQuery] string farmId, [FromQuery] string? status)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetAllAsync(farmId, status));

        [HttpGet("{id:int}")]
        public async Task<ActionResult<PoultryCashTransferModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var m = await _svc.GetByIdAsync(id, farmId);
            return m is null ? NotFound() : Ok(m);
        }

        [HttpPost]
        public async Task<ActionResult<int>> Create([FromBody] PoultryCashTransferModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.InsertAsync(m);
            return Ok(new { PoultryCashTransferId = id });
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
}
