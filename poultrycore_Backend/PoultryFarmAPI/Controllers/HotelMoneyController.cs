using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Filters;
using PoultryFarmAPIWeb.Helpers;

namespace PoultryFarmAPIWeb.Controllers
{
    // Request bodies. Prefixed "HotelMoney" so no nested DTO name collides with
    // another controller's in the Swagger schema ids.
    public class HotelMoneyFarmRequest { public string FarmId { get; set; } = ""; }
    public class HotelMoneyReasonRequest { public string FarmId { get; set; } = ""; public string? Reason { get; set; } }
    public class HotelMoneyAccountUpdateRequest
    {
        public string FarmId { get; set; } = "";
        public string AccountName { get; set; } = "";
        public string? AccountType { get; set; }
        public bool? AllowNegativeBalance { get; set; }
        public bool? IsActive { get; set; }
        public string? Notes { get; set; }
        public string? Purpose { get; set; }
    }
    public class HotelMoneyAdjustRequest { public string FarmId { get; set; } = ""; public decimal Amount { get; set; } public string? Reason { get; set; } }
    public class HotelMoneyOwnerMoneyRequest
    {
        public string FarmId { get; set; } = "";
        public string TransactionType { get; set; } = "";
        public decimal Amount { get; set; }
        public int HotelCashAccountId { get; set; }
        public DateTime? TransactionDate { get; set; }
        public string? PaymentMethod { get; set; }
        public string? OwnerName { get; set; }
        public string? ReferenceNumber { get; set; }
        public string? Notes { get; set; }
    }
    public class HotelMoneyLoanRequest : HotelMoneyLoanInput { public string FarmId { get; set; } = ""; }
    public class HotelMoneyLoanPaymentRequest : HotelMoneyLoanPaymentInput { public string FarmId { get; set; } = ""; }
    public class HotelMoneyTransferRequest
    {
        public string FarmId { get; set; } = "";
        public int FromHotelCashAccountId { get; set; }
        public int ToHotelCashAccountId { get; set; }
        public decimal Amount { get; set; }
        public DateTime? TransferDate { get; set; }
        public string? ReferenceNumber { get; set; }
        public string? Notes { get; set; }
    }
    public class HotelMoneyReconRequest
    {
        public string FarmId { get; set; } = "";
        public int HotelCashAccountId { get; set; }
        public DateTime? ReconciliationDate { get; set; }
        public decimal? ActualBalance { get; set; }
        public string? Reason { get; set; }
        public string? Notes { get; set; }
    }

    // Owner Money, Loans (Financing), Cash Transfers, Reconciliation and the Cash
    // Account extras (migration 331). Every write is one Postgres function call;
    // its refusals (P0001) come back as 400 with the sentence, via
    // HotelBusinessRuleFilter. The acting user comes from the token, never the body.
    [ApiController][Authorize][Route("api/Hotel")][HotelBusinessRuleFilter]
    public class HotelMoneyController : ControllerBase
    {
        private readonly IHotelMoneyService _svc;
        public HotelMoneyController(IHotelMoneyService svc) { _svc = svc; }

        private string By => HotelAuthHelper.GetUserName(User);
        private IActionResult? Own(string farmId) => HotelAuthHelper.VerifyFarmOwnership(User, farmId);
        private static IActionResult? NeedReason(string? r) =>
            string.IsNullOrWhiteSpace(r) ? new BadRequestObjectResult(new { message = "A reason is required." }) : null;

        // ---- cash accounts ------------------------------------------------------
        [HttpGet("finance/cash-accounts/status")]
        public async Task<IActionResult> AccountStatus([FromQuery] string farmId)
        { var a = Own(farmId); if (a != null) return a; return Ok(await _svc.CashAccountStatusAsync(farmId)); }

        [HttpPut("finance/cash-accounts/{id:int}")]
        public async Task<IActionResult> UpdateAccount(int id, [FromBody] HotelMoneyAccountUpdateRequest req)
        {
            var a = Own(req.FarmId); if (a != null) return a;
            await _svc.UpdateCashAccountAsync(req.FarmId, id, req.AccountName, req.AccountType, req.AllowNegativeBalance, req.IsActive, req.Notes, req.Purpose);
            return Ok();
        }

        [HttpPost("finance/cash-accounts/recalculate")]
        public async Task<IActionResult> Recalculate([FromBody] HotelMoneyFarmRequest req)
        { var a = Own(req.FarmId); if (a != null) return a; return Ok(new { changed = await _svc.RecalculateAsync(req.FarmId) }); }

        [HttpPost("finance/cash-accounts/{id:int}/adjust")]
        public async Task<IActionResult> Adjust(int id, [FromBody] HotelMoneyAdjustRequest req)
        {
            var a = Own(req.FarmId); if (a != null) return a;
            var n = NeedReason(req.Reason); if (n != null) return n;
            return Ok(new { hotelCashAdjustmentId = await _svc.RecordAdjustmentAsync(req.FarmId, id, req.Amount, req.Reason!, By) });
        }

        [HttpPost("finance/cash-adjustments/{id:int}/reverse")]
        public async Task<IActionResult> ReverseAdjustment(int id, [FromBody] HotelMoneyReasonRequest req)
        {
            var a = Own(req.FarmId); if (a != null) return a;
            var n = NeedReason(req.Reason); if (n != null) return n;
            await _svc.ReverseAdjustmentAsync(req.FarmId, id, req.Reason!, By); return Ok();
        }

        // ---- owner money --------------------------------------------------------
        [HttpGet("owner-money")]
        public async Task<IActionResult> OwnerMoney([FromQuery] string farmId, [FromQuery] string? type, [FromQuery] DateTime? from, [FromQuery] DateTime? to, [FromQuery] string? status)
        { var a = Own(farmId); if (a != null) return a; return Ok(await _svc.OwnerMoneyListAsync(farmId, type, from, to, status)); }

        [HttpGet("owner-money/summary")]
        public async Task<IActionResult> OwnerMoneySummary([FromQuery] string farmId, [FromQuery] DateTime? from, [FromQuery] DateTime? to)
        { var a = Own(farmId); if (a != null) return a; return Ok(await _svc.OwnerMoneySummaryAsync(farmId, from, to)); }

        [HttpPost("owner-money")]
        public async Task<IActionResult> RecordOwnerMoney([FromBody] HotelMoneyOwnerMoneyRequest req)
        {
            var a = Own(req.FarmId); if (a != null) return a;
            var id = await _svc.RecordOwnerMoneyAsync(req.FarmId, req.TransactionType, req.Amount, req.HotelCashAccountId, req.TransactionDate,
                                                      req.PaymentMethod, req.OwnerName, req.ReferenceNumber, req.Notes, By);
            return Ok(new { hotelOwnerMoneyId = id });
        }

        [HttpPost("owner-money/{id:int}/reverse")]
        public async Task<IActionResult> ReverseOwnerMoney(int id, [FromBody] HotelMoneyReasonRequest req)
        {
            var a = Own(req.FarmId); if (a != null) return a;
            var n = NeedReason(req.Reason); if (n != null) return n;
            await _svc.ReverseOwnerMoneyAsync(req.FarmId, id, req.Reason!, By); return Ok();
        }

        // ---- loans --------------------------------------------------------------
        [HttpGet("loans")]
        public async Task<IActionResult> Loans([FromQuery] string farmId, [FromQuery] string? status)
        { var a = Own(farmId); if (a != null) return a; return Ok(await _svc.LoanListAsync(farmId, status)); }

        [HttpGet("loans/summary")]
        public async Task<IActionResult> LoanSummary([FromQuery] string farmId)
        { var a = Own(farmId); if (a != null) return a; return Ok(await _svc.LoanSummaryAsync(farmId)); }

        [HttpGet("loan-payments")]
        public async Task<IActionResult> LoanPayments([FromQuery] string farmId, [FromQuery] int? loanId)
        { var a = Own(farmId); if (a != null) return a; return Ok(await _svc.LoanPaymentListAsync(farmId, loanId)); }

        [HttpPost("loans")]
        public async Task<IActionResult> CreateLoan([FromBody] HotelMoneyLoanRequest req)
        { var a = Own(req.FarmId); if (a != null) return a; return Ok(new { hotelLoanId = await _svc.CreateLoanAsync(req.FarmId, req, By) }); }

        [HttpPut("loans/{id:int}")]
        public async Task<IActionResult> UpdateLoan(int id, [FromBody] HotelMoneyLoanRequest req)
        { var a = Own(req.FarmId); if (a != null) return a; await _svc.UpdateLoanAsync(req.FarmId, id, req, By); return Ok(); }

        [HttpPost("loans/{id:int}/cancel")]
        public async Task<IActionResult> CancelLoan(int id, [FromBody] HotelMoneyReasonRequest req)
        {
            var a = Own(req.FarmId); if (a != null) return a;
            var n = NeedReason(req.Reason); if (n != null) return n;
            await _svc.CancelLoanAsync(req.FarmId, id, req.Reason!, By); return Ok();
        }

        [HttpPost("loans/{id:int}/repayments")]
        public async Task<IActionResult> Repay(int id, [FromBody] HotelMoneyLoanPaymentRequest req)
        { var a = Own(req.FarmId); if (a != null) return a; return Ok(new { hotelLoanPaymentId = await _svc.RecordLoanPaymentAsync(req.FarmId, id, req, By) }); }

        [HttpPost("loan-payments/{id:int}/reverse")]
        public async Task<IActionResult> ReverseRepayment(int id, [FromBody] HotelMoneyReasonRequest req)
        {
            var a = Own(req.FarmId); if (a != null) return a;
            var n = NeedReason(req.Reason); if (n != null) return n;
            await _svc.ReverseLoanPaymentAsync(req.FarmId, id, req.Reason!, By); return Ok();
        }

        // ---- transfers ----------------------------------------------------------
        [HttpGet("cash-transfers")]
        public async Task<IActionResult> Transfers([FromQuery] string farmId)
        { var a = Own(farmId); if (a != null) return a; return Ok(await _svc.TransferListAsync(farmId)); }

        [HttpPost("cash-transfers")]
        public async Task<IActionResult> RecordTransfer([FromBody] HotelMoneyTransferRequest req)
        {
            var a = Own(req.FarmId); if (a != null) return a;
            var id = await _svc.RecordTransferAsync(req.FarmId, req.FromHotelCashAccountId, req.ToHotelCashAccountId, req.Amount,
                                                    req.TransferDate, req.ReferenceNumber, req.Notes, By);
            return Ok(new { hotelCashTransferId = id });
        }

        [HttpPost("cash-transfers/{id:int}/reverse")]
        public async Task<IActionResult> ReverseTransfer(int id, [FromBody] HotelMoneyReasonRequest req)
        {
            var a = Own(req.FarmId); if (a != null) return a;
            var n = NeedReason(req.Reason); if (n != null) return n;
            await _svc.ReverseTransferAsync(req.FarmId, id, req.Reason!, By); return Ok();
        }

        // ---- reconciliation -----------------------------------------------------
        [HttpGet("cash-reconciliations")]
        public async Task<IActionResult> Recons([FromQuery] string farmId, [FromQuery] int? accountId)
        { var a = Own(farmId); if (a != null) return a; return Ok(await _svc.ReconListAsync(farmId, accountId)); }

        [HttpPost("cash-reconciliations")]
        public async Task<IActionResult> CreateRecon([FromBody] HotelMoneyReconRequest req)
        {
            var a = Own(req.FarmId); if (a != null) return a;
            var id = await _svc.ReconCreateAsync(req.FarmId, req.HotelCashAccountId, req.ReconciliationDate, req.ActualBalance, req.Reason, req.Notes, By);
            return Ok(new { hotelCashReconciliationId = id });
        }

        [HttpPut("cash-reconciliations/{id:int}")]
        public async Task<IActionResult> UpdateRecon(int id, [FromBody] HotelMoneyReconRequest req)
        {
            var a = Own(req.FarmId); if (a != null) return a;
            await _svc.ReconUpdateAsync(req.FarmId, id, req.ReconciliationDate, req.ActualBalance, req.Reason, req.Notes);
            return Ok();
        }

        [HttpDelete("cash-reconciliations/{id:int}")]
        public async Task<IActionResult> DeleteRecon(int id, [FromQuery] string farmId)
        { var a = Own(farmId); if (a != null) return a; await _svc.ReconDeleteAsync(farmId, id); return Ok(); }

        [HttpPost("cash-reconciliations/{id:int}/post")]
        public async Task<IActionResult> PostRecon(int id, [FromBody] HotelMoneyFarmRequest req)
        { var a = Own(req.FarmId); if (a != null) return a; return Ok(new { adjustmentTransactionId = await _svc.ReconPostAsync(req.FarmId, id, By) }); }

        [HttpPost("cash-reconciliations/{id:int}/reverse")]
        public async Task<IActionResult> ReverseRecon(int id, [FromBody] HotelMoneyReasonRequest req)
        {
            var a = Own(req.FarmId); if (a != null) return a;
            var n = NeedReason(req.Reason); if (n != null) return n;
            await _svc.ReconReverseAsync(req.FarmId, id, req.Reason!, By); return Ok();
        }
    }
}
