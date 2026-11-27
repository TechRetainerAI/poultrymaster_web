using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Filters;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // =========================================================================
    // Loans
    // =========================================================================
    [ApiController]
    [Route("api/generic-company/{farmId}/loans")]
    [RequireCompanyType("Generic")]
    public class GenericLoanController : ControllerBase
    {
        private readonly IGenericLoanService _svc;
        public GenericLoanController(IGenericLoanService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<GenericLoanModel>>> List(string farmId)
            => Ok(await _svc.ListAsync(farmId));

        // 455: the SPs raise the user-facing rules (no account, overdraw, more
        // than is owed, cancel with repayments, ...) as P0001, returned as 400.
        [HttpPost]
        public async Task<ActionResult<int>> Create(string farmId, [FromBody] GenericLoanCreateRequest req)
        {
            req.FarmId = farmId;
            try { return Ok(await _svc.CreateAsync(req)); }
            catch (Npgsql.PostgresException ex) when (ex.SqlState == "P0001") { return BadRequest(ex.MessageText); }
        }

        [HttpPut("{loanId:int}")]
        public async Task<IActionResult> Update(string farmId, int loanId, [FromBody] GenericLoanUpdateRequest req)
        {
            req.FarmId = farmId;
            try { await _svc.UpdateAsync(loanId, req); return NoContent(); }
            catch (Npgsql.PostgresException ex) when (ex.SqlState == "P0001") { return BadRequest(ex.MessageText); }
        }

        [HttpPost("{loanId:int}/cancel")]
        public async Task<IActionResult> Cancel(string farmId, int loanId, [FromBody] GenericLoanReasonRequest req)
        {
            try { await _svc.CancelAsync(loanId, farmId, req.Reason, req.By); return NoContent(); }
            catch (Npgsql.PostgresException ex) when (ex.SqlState == "P0001") { return BadRequest(ex.MessageText); }
        }

        // 509: Draft -> Active (the money posts).
        [HttpPost("{loanId:int}/approve")]
        public async Task<IActionResult> Approve(string farmId, int loanId, [FromBody] GenericLoanReasonRequest? req)
        {
            try { await _svc.ApproveAsync(loanId, farmId, req?.By); return NoContent(); }
            catch (Npgsql.PostgresException ex) when (ex.SqlState == "P0001") { return BadRequest(ex.MessageText); }
        }

        // 509: an approved loan goes back to Draft (the money received comes back out).
        [HttpPost("{loanId:int}/reverse")]
        public async Task<IActionResult> Reverse(string farmId, int loanId, [FromBody] GenericLoanReasonRequest req)
        {
            try { await _svc.ReverseAsync(loanId, farmId, req.Reason, req.By); return NoContent(); }
            catch (Npgsql.PostgresException ex) when (ex.SqlState == "P0001") { return BadRequest(ex.MessageText); }
        }

        /// <summary>Every repayment of the company, newest first, reversed ones included.</summary>
        [HttpGet("payments")]
        public async Task<ActionResult<IEnumerable<GenericLoanPaymentModel>>> AllPayments(string farmId)
            => Ok(await _svc.ListPaymentsAsync(null, farmId));

        [HttpGet("{loanId:int}/payments")]
        public async Task<ActionResult<IEnumerable<GenericLoanPaymentModel>>> Payments(string farmId, int loanId)
            => Ok(await _svc.ListPaymentsAsync(loanId, farmId));

        [HttpPost("{loanId:int}/repay")]
        public async Task<ActionResult<int>> Repay(string farmId, int loanId, [FromBody] GenericLoanRepayRequest req)
        {
            req.FarmId = farmId;
            try { return Ok(await _svc.RepayAsync(loanId, req)); }
            catch (Npgsql.PostgresException ex) when (ex.SqlState == "P0001") { return BadRequest(ex.MessageText); }
        }

        [HttpPost("payments/{paymentId:int}/reverse")]
        public async Task<IActionResult> ReversePayment(string farmId, int paymentId, [FromBody] GenericLoanReasonRequest req)
        {
            try { await _svc.ReversePaymentAsync(paymentId, farmId, req.Reason, req.By); return NoContent(); }
            catch (Npgsql.PostgresException ex) when (ex.SqlState == "P0001") { return BadRequest(ex.MessageText); }
        }
    }

    // =========================================================================
    // Assets
    // =========================================================================
    [ApiController]
    [Route("api/generic-company/{farmId}/assets")]
    [RequireCompanyType("Generic")]
    public class GenericAssetController : ControllerBase
    {
        private readonly IGenericAssetService _svc;
        public GenericAssetController(IGenericAssetService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<GenericAssetModel>>> List(string farmId)
            => Ok(await _svc.ListAsync(farmId));

        [HttpPost]
        public async Task<ActionResult<int>> Create(string farmId, [FromBody] GenericAssetCreateRequest req)
        {
            req.FarmId = farmId;
            return Ok(await _svc.CreateAsync(req));
        }

        [HttpPost("{assetId:int}/dispose")]
        public async Task<IActionResult> Dispose(string farmId, int assetId, [FromBody] GenericAssetDisposeRequest req)
        {
            req.FarmId = farmId;
            await _svc.DisposeAsync(assetId, req);
            return Ok();
        }

        [HttpPost("{assetId:int}/depreciate")]
        public async Task<IActionResult> Depreciate(string farmId, int assetId, [FromBody] decimal amount)
        {
            if (amount <= 0 || decimal.Round(amount, 2) != amount)
                return BadRequest("Enter a positive amount with at most two decimal places.");
            if (!await _svc.DepreciateAsync(assetId, farmId, amount))
                return BadRequest("Choose an active asset and an amount within its remaining book value.");
            return Ok();
        }
    }
}
