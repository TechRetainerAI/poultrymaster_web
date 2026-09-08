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

        /// <summary>
        /// Cancels a DRAFT. A draft moved no money, so there is nothing to put
        /// back -- an approved transfer is undone with /reverse instead.
        /// </summary>
        [HttpPost("{id:int}/cancel")]
        public async Task<IActionResult> Cancel(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.CancelAsync(id, farmId);
            return NoContent();
        }

        /// <summary>
        /// Reverses an APPROVED transfer: two opposite ledger rows, both
        /// accounts restored, the original rows kept.
        ///
        /// The reason travels in the body rather than the query string on
        /// purpose -- it is free text a person types, it lands in the audit
        /// trail, and query strings end up in access logs.
        /// </summary>
        [HttpPost("{id:int}/reverse")]
        public async Task<IActionResult> Reverse(
            int id, [FromQuery] string farmId, [FromQuery] string? reversedBy,
            [FromBody] PoultryCashTransferReverseRequest body)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.ReverseAsync(id, farmId, body.Reason, reversedBy);
            return NoContent();
        }
    }

    // ====================================================================
    // Owner money (migration 253)
    // ====================================================================
    // Contributions and draws. Neither is trading, so nothing here creates a
    // sale, an expense, a customer payment or a supplier payment -- the SP
    // writes the record and exactly one cash row.
    [ApiController]
    [Route("api/Poultry/owner-money")]
    public class PoultryOwnerMoneyController : ControllerBase
    {
        private readonly IPoultryOwnerMoneyService _svc;
        public PoultryOwnerMoneyController(IPoultryOwnerMoneyService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<PoultryOwnerMoneyModel>>> GetAll(
            [FromQuery] string farmId, [FromQuery] string? type,
            [FromQuery] DateTime? from, [FromQuery] DateTime? to, [FromQuery] string? status)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetAllAsync(farmId, type, from, to, status));

        [HttpGet("summary")]
        public async Task<ActionResult<PoultryOwnerMoneySummary>> Summary(
            [FromQuery] string farmId, [FromQuery] DateTime? from, [FromQuery] DateTime? to)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetSummaryAsync(farmId, from, to));

        /// <summary>
        /// Records a contribution or a draw. One endpoint rather than two: the
        /// two differ by a single field, and splitting them would mean two
        /// copies of the same validation.
        /// </summary>
        [HttpPost]
        public async Task<ActionResult<int>> Record([FromBody] PoultryOwnerMoneyRecordRequest r)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(r.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.RecordAsync(r);
            return Ok(new { PoultryOwnerMoneyId = id });
        }

        [HttpPost("{id:int}/reverse")]
        public async Task<IActionResult> Reverse(
            int id, [FromQuery] string farmId, [FromQuery] string? reversedBy,
            [FromBody] PoultryOwnerMoneyReverseRequest body)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.ReverseAsync(id, farmId, body.Reason, reversedBy);
            return NoContent();
        }
    }

    // ====================================================================
    // Loans and repayments (migration 254)
    // ====================================================================
    // Repaying principal is not an expense, a repayment moves cash exactly
    // once for its total, and a lender is never a supplier. All three are
    // enforced in the SPs; nothing here can route around them.
    [ApiController]
    [Route("api/Poultry/loans")]
    public class PoultryLoanController : ControllerBase
    {
        private readonly IPoultryLoanService _svc;
        public PoultryLoanController(IPoultryLoanService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<PoultryLoanModel>>> GetAll(
            [FromQuery] string farmId, [FromQuery] string? status)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetAllAsync(farmId, status));

        [HttpGet("summary")]
        public async Task<ActionResult<PoultryLoanSummary>> Summary([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetSummaryAsync(farmId));

        [HttpGet("{id:int}")]
        public async Task<ActionResult<PoultryLoanModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var m = await _svc.GetByIdAsync(id, farmId);
            return m is null ? NotFound() : Ok(m);
        }

        [HttpPost]
        public async Task<ActionResult<int>> Create([FromBody] PoultryLoanCreateRequest r)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(r.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.CreateAsync(r);
            return Ok(new { PoultryLoanId = id });
        }

        /// <summary>
        /// Edits the descriptive fields only. Principal, amount received and the
        /// running totals are consequences of postings, and a form that could
        /// rewrite them is how a loan stops matching its own payments.
        /// </summary>
        [HttpPut("{id:int}")]
        public async Task<IActionResult> Update(
            int id, [FromQuery] string farmId, [FromQuery] string? updatedBy,
            [FromBody] PoultryLoanUpdateRequest r)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.UpdateAsync(id, farmId, r, updatedBy);
            return NoContent();
        }

        [HttpPost("{id:int}/cancel")]
        public async Task<IActionResult> Cancel(
            int id, [FromQuery] string farmId, [FromQuery] string? cancelledBy,
            [FromBody] PoultryLoanReasonRequest body)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.CancelAsync(id, farmId, body.Reason, cancelledBy);
            return NoContent();
        }

        [HttpGet("{id:int}/repayments")]
        public async Task<ActionResult<IEnumerable<PoultryLoanPaymentModel>>> Repayments(
            int id, [FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetPaymentsAsync(farmId, id, null, null));

        [HttpPost("{id:int}/record-repayment")]
        public async Task<ActionResult<int>> RecordRepayment(
            int id, [FromBody] PoultryLoanPaymentRequest r)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(r.FarmId)) return BadRequest("Company ID is required.");
            r.PoultryLoanId = id;
            var paymentId = await _svc.RecordPaymentAsync(r);
            return Ok(new { PoultryLoanPaymentId = paymentId });
        }
    }

    [ApiController]
    [Route("api/Poultry/loan-payments")]
    public class PoultryLoanPaymentController : ControllerBase
    {
        private readonly IPoultryLoanService _svc;
        public PoultryLoanPaymentController(IPoultryLoanService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<PoultryLoanPaymentModel>>> GetAll(
            [FromQuery] string farmId, [FromQuery] int? loanId,
            [FromQuery] DateTime? from, [FromQuery] DateTime? to)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetPaymentsAsync(farmId, loanId, from, to));

        [HttpPost("{paymentId:int}/reverse")]
        public async Task<IActionResult> Reverse(
            int paymentId, [FromQuery] string farmId, [FromQuery] string? reversedBy,
            [FromBody] PoultryLoanReasonRequest body)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.ReversePaymentAsync(paymentId, farmId, body.Reason, reversedBy);
            return NoContent();
        }
    }
}
