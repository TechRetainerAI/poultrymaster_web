// Restaurant finance (migration 323): accounts, till shifts, transfers, owner
// money, loans, cash counts, daily closing, P&L lines.
//
// Every action checks the caller's JWT company against farmId, and the acting
// user is taken from the token -- never from the request -- so the audit
// columns (createdby, closedby, reversedby...) cannot be forged by the client.

using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Filters;
using PoultryFarmAPIWeb.Helpers;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Authorize]
    [RestaurantBusinessRuleFilter]
    [Route("api/Restaurant/finance")]
    public class RestaurantFinanceController : ControllerBase
    {
        private readonly IRestaurantFinanceService _svc;
        public RestaurantFinanceController(IRestaurantFinanceService svc) => _svc = svc;

        private string Me => HotelAuthHelper.GetUserName(User);
        private IActionResult? Deny(string? farmId) => HotelAuthHelper.VerifyFarmOwnership(User, farmId);

        // ===== ACCOUNTS =====

        [HttpGet("accounts")]
        public async Task<IActionResult> ListAccounts([FromQuery] string farmId)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.ListAccountsAsync(farmId)); }

        [HttpPost("accounts")]
        public async Task<IActionResult> CreateAccount([FromBody] RestaurantCashAccountCreateRequest req)
        {
            var d = Deny(req.FarmId); if (d != null) return d;
            return Ok(new { cashAccountId = await _svc.CreateAccountAsync(req, Me) });
        }

        [HttpPut("accounts/{id:int}")]
        public async Task<IActionResult> UpdateAccount(int id, [FromQuery] string farmId, [FromBody] RestaurantCashAccountUpdateRequest req)
        { var d = Deny(farmId); if (d != null) return d; await _svc.UpdateAccountAsync(id, farmId, req); return NoContent(); }

        [HttpGet("accounts/{id:int}/ledger")]
        public async Task<IActionResult> Ledger(int id, [FromQuery] string farmId, [FromQuery] DateTime? from = null, [FromQuery] DateTime? to = null)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.LedgerAsync(farmId, id, from, to)); }

        // ===== SHIFTS =====

        [HttpGet("shifts")]
        public async Task<IActionResult> ListShifts([FromQuery] string farmId, [FromQuery] string? status = null,
            [FromQuery] DateTime? from = null, [FromQuery] DateTime? to = null)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.ListShiftsAsync(farmId, status, from, to)); }

        [HttpPost("shifts")]
        public async Task<IActionResult> OpenShift([FromQuery] string farmId, [FromBody] RestaurantShiftOpenRequest req)
        { var d = Deny(farmId); if (d != null) return d; return Ok(new { shiftId = await _svc.OpenShiftAsync(farmId, req, Me) }); }

        [HttpPost("shifts/{id:int}/close")]
        public async Task<IActionResult> CloseShift(int id, [FromQuery] string farmId, [FromBody] RestaurantShiftCloseRequest req)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.CloseShiftAsync(farmId, id, req, Me)); }

        [HttpGet("shifts/{id:int}/z-report")]
        public async Task<IActionResult> ZReport(int id, [FromQuery] string farmId)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.ZReportAsync(farmId, id)); }

        // ===== TRANSFERS =====

        [HttpGet("transfers")]
        public async Task<IActionResult> ListTransfers([FromQuery] string farmId, [FromQuery] DateTime? from = null, [FromQuery] DateTime? to = null)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.ListTransfersAsync(farmId, from, to)); }

        [HttpPost("transfers")]
        public async Task<IActionResult> CreateTransfer([FromQuery] string farmId, [FromBody] RestaurantTransferRequest req)
        { var d = Deny(farmId); if (d != null) return d; return Ok(new { transferId = await _svc.CreateTransferAsync(farmId, req, Me) }); }

        [HttpPost("transfers/{id:int}/reverse")]
        public async Task<IActionResult> ReverseTransfer(int id, [FromQuery] string farmId, [FromBody] RestaurantReverseRequest req)
        { var d = Deny(farmId); if (d != null) return d; await _svc.ReverseTransferAsync(farmId, id, req.Reason, Me); return NoContent(); }

        // ===== OWNER MONEY =====

        [HttpGet("owner-money")]
        public async Task<IActionResult> ListOwnerMoney([FromQuery] string farmId, [FromQuery] DateTime? from = null, [FromQuery] DateTime? to = null)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.ListOwnerMoneyAsync(farmId, from, to)); }

        [HttpPost("owner-money")]
        public async Task<IActionResult> RecordOwnerMoney([FromQuery] string farmId, [FromBody] RestaurantOwnerMoneyRequest req)
        { var d = Deny(farmId); if (d != null) return d; return Ok(new { ownerMoneyId = await _svc.RecordOwnerMoneyAsync(farmId, req, Me) }); }

        [HttpPost("owner-money/{id:int}/reverse")]
        public async Task<IActionResult> ReverseOwnerMoney(int id, [FromQuery] string farmId, [FromBody] RestaurantReverseRequest req)
        { var d = Deny(farmId); if (d != null) return d; await _svc.ReverseOwnerMoneyAsync(farmId, id, req.Reason, Me); return NoContent(); }

        // ===== LOANS =====

        [HttpGet("loans")]
        public async Task<IActionResult> ListLoans([FromQuery] string farmId)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.ListLoansAsync(farmId)); }

        /// <summary>Every repayment on every loan, newest first (Money Movement report).</summary>
        [HttpGet("loans/payments")]
        public async Task<IActionResult> ListAllLoanPayments([FromQuery] string farmId)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.ListLoanPaymentsAsync(farmId, 0)); }

        [HttpGet("loans/{id:int}/payments")]
        public async Task<IActionResult> ListLoanPayments(int id, [FromQuery] string farmId)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.ListLoanPaymentsAsync(farmId, id)); }

        [HttpPost("loans")]
        public async Task<IActionResult> CreateLoan([FromQuery] string farmId, [FromBody] RestaurantLoanCreateRequest req)
        { var d = Deny(farmId); if (d != null) return d; return Ok(new { loanId = await _svc.CreateLoanAsync(farmId, req, Me) }); }

        [HttpPost("loans/{id:int}/repay")]
        public async Task<IActionResult> RepayLoan(int id, [FromQuery] string farmId, [FromBody] RestaurantLoanRepayRequest req)
        { var d = Deny(farmId); if (d != null) return d; return Ok(new { loanPaymentId = await _svc.RepayLoanAsync(farmId, id, req, Me) }); }

        [HttpPost("loans/payments/{paymentId:int}/reverse")]
        public async Task<IActionResult> ReverseLoanPayment(int paymentId, [FromQuery] string farmId, [FromBody] RestaurantReverseRequest req)
        { var d = Deny(farmId); if (d != null) return d; await _svc.ReverseLoanPaymentAsync(farmId, paymentId, req.Reason, Me); return NoContent(); }

        [HttpPost("loans/{id:int}/cancel")]
        public async Task<IActionResult> CancelLoan(int id, [FromQuery] string farmId, [FromBody] RestaurantReverseRequest req)
        { var d = Deny(farmId); if (d != null) return d; await _svc.CancelLoanAsync(farmId, id, req.Reason, Me); return NoContent(); }

        // ===== CASH COUNTS =====

        [HttpGet("counts")]
        public async Task<IActionResult> ListCounts([FromQuery] string farmId, [FromQuery] int? accountId = null)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.ListCountsAsync(farmId, accountId)); }

        [HttpPost("counts")]
        public async Task<IActionResult> PostCount([FromQuery] string farmId, [FromBody] RestaurantCashCountRequest req)
        { var d = Deny(farmId); if (d != null) return d; return Ok(new { countId = await _svc.PostCountAsync(farmId, req, Me) }); }

        [HttpPost("counts/{id:int}/reverse")]
        public async Task<IActionResult> ReverseCount(int id, [FromQuery] string farmId, [FromBody] RestaurantReverseRequest req)
        { var d = Deny(farmId); if (d != null) return d; await _svc.ReverseCountAsync(farmId, id, req.Reason, Me); return NoContent(); }

        // ===== DAILY CLOSING =====

        [HttpGet("daily-closing/preview")]
        public async Task<IActionResult> PreviewDay([FromQuery] string farmId, [FromQuery] DateTime date)
        {
            var d = Deny(farmId); if (d != null) return d;
            var p = await _svc.PreviewDayAsync(farmId, date);
            return p == null ? NotFound() : Ok(p);
        }

        [HttpGet("daily-closing")]
        public async Task<IActionResult> ListClosings([FromQuery] string farmId, [FromQuery] int limit = 60,
            [FromQuery] DateTime? from = null, [FromQuery] DateTime? to = null)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.ListClosingsAsync(farmId, Math.Clamp(limit, 1, 366), from, to)); }

        [HttpPost("daily-closing")]
        public async Task<IActionResult> CloseDay([FromQuery] string farmId, [FromBody] RestaurantDayCloseRequest req)
        { var d = Deny(farmId); if (d != null) return d; return Ok(new { closingId = await _svc.CloseDayAsync(farmId, req.ClosingDate, req.Notes, Me) }); }

        [HttpPost("daily-closing/reopen")]
        public async Task<IActionResult> ReopenDay([FromQuery] string farmId, [FromBody] RestaurantDayReopenRequest req)
        { var d = Deny(farmId); if (d != null) return d; await _svc.ReopenDayAsync(farmId, req.ClosingDate, req.Reason, Me); return NoContent(); }

        // ===== REPORTS (migration 324) =====

        [HttpGet("ledger/period")]
        public async Task<IActionResult> LedgerPeriod([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.LedgerPeriodAsync(farmId, from, to)); }

        [HttpGet("ledger/rows")]
        public async Task<IActionResult> LedgerRows([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to,
            [FromQuery] int? accountId = null)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.LedgerRowsAsync(farmId, from, to, accountId)); }

        [HttpGet("reports/takings-by-account")]
        public async Task<IActionResult> TakingsByAccount([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.TakingsByAccountAsync(farmId, from, to)); }

        [HttpGet("reports/profit-vs-cash")]
        public async Task<IActionResult> ProfitVsCash([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.CashProfitBridgeAsync(farmId, from, to)); }

        // ===== P&L STATEMENT =====

        [HttpGet("pnl-lines")]
        public async Task<IActionResult> PnlLines([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.PnlLinesAsync(farmId, from, to)); }
    }
}
