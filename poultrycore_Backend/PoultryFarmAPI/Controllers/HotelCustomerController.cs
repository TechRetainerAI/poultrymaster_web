using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Helpers;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController][Authorize][Route("api/Hotel")]
    public class HotelCustomerController : ControllerBase
    {
        private readonly IHotelCustomerService _svc;
        public HotelCustomerController(IHotelCustomerService svc) { _svc = svc; }

        private string? UserId => User.FindFirst("UserId")?.Value ?? User.FindFirst("sub")?.Value;

        // ── Customers ────────────────────────────────────────────────────

        [HttpGet("customers")]
        public async Task<IActionResult> GetAll([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.GetAllAsync(farmId));
        }

        [HttpGet("customers/{id}")]
        public async Task<IActionResult> GetById(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            var m = await _svc.GetByIdAsync(id, farmId);
            return m == null ? NotFound() : Ok(m);
        }

        [HttpPost("customers")]
        public async Task<IActionResult> Create([FromBody] HotelCustomerModel m)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (auth != null) return auth;
            try { var id = await _svc.InsertAsync(m, UserId); return Ok(new { hotelCustomerId = id }); }
            catch (Exception ex) { return BadRequest(ex.Message); }
        }

        [HttpPut("customers/{id}")]
        public async Task<IActionResult> Update(int id, [FromBody] HotelCustomerModel m)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (auth != null) return auth;
            m.HotelCustomerId = id;
            await _svc.UpdateAsync(m);
            return Ok();
        }

        [HttpDelete("customers/{id}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            await _svc.DeleteAsync(id, farmId);
            return Ok();
        }

        [HttpGet("customers/owed")]
        public async Task<IActionResult> GetOwed([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.GetOwedAsync(farmId));
        }

        [HttpGet("customers/balance-summary")]
        public async Task<IActionResult> GetBalanceSummary([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.GetBalanceSummaryAsync(farmId));
        }

        // ── Ledger ───────────────────────────────────────────────────────

        [HttpGet("customers/{id}/ledger")]
        public async Task<IActionResult> GetLedger(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.GetLedgerAsync(id, farmId));
        }

        [HttpPost("customers/post-invoice")]
        public async Task<IActionResult> PostInvoice([FromBody] HotelCustomerInvoicePostRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            try { await _svc.PostInvoiceAsync(req.FarmId, req.HotelCustomerId, req.InvoiceId, req.Amount, req.Description, UserId); return Ok(); }
            catch (Exception ex) { return BadRequest(ex.Message); }
        }

        [HttpPost("customers/post-adjustment")]
        public async Task<IActionResult> PostAdjustment([FromBody] HotelCustomerAdjustmentRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            try { await _svc.PostAdjustmentAsync(req.FarmId, req.HotelCustomerId, req.Amount, req.Description, UserId); return Ok(); }
            catch (Exception ex) { return BadRequest(ex.Message); }
        }

        // ── Payments ─────────────────────────────────────────────────────

        [HttpGet("customer-payments")]
        public async Task<IActionResult> GetPayments([FromQuery] string farmId, [FromQuery] string? status)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            return Ok(await _svc.GetPaymentsAsync(farmId, status));
        }

        [HttpGet("customer-payments/{id}")]
        public async Task<IActionResult> GetPaymentById(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            var m = await _svc.GetPaymentByIdAsync(id, farmId);
            return m == null ? NotFound() : Ok(m);
        }

        [HttpPost("customer-payments")]
        public async Task<IActionResult> CreatePayment([FromBody] HotelCustomerPaymentCreateRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            try
            {
                var m = new HotelCustomerPaymentModel
                {
                    FarmId = req.FarmId,
                    HotelCustomerId = req.HotelCustomerId,
                    Amount = req.Amount,
                    PaymentMethod = req.PaymentMethod,
                    HotelCashAccountId = req.HotelCashAccountId,
                    Reference = req.Reference,
                    LinkedInvoiceId = req.LinkedInvoiceId,
                    Notes = req.Notes,
                    PaymentDate = string.IsNullOrEmpty(req.PaymentDate) ? DateTime.UtcNow : DateTime.Parse(req.PaymentDate),
                };
                var id = await _svc.InsertPaymentAsync(m, UserId);
                return Ok(new { hotelCustomerPaymentId = id });
            }
            catch (Exception ex) { return BadRequest(ex.Message); }
        }

        [HttpPost("customer-payments/{id}/approve")]
        public async Task<IActionResult> ApprovePayment(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            try { await _svc.ApprovePaymentAsync(id, farmId, UserId); return Ok(); }
            catch (Exception ex) { return BadRequest(ex.Message); }
        }

        [HttpPost("customer-payments/{id}/cancel")]
        public async Task<IActionResult> CancelPayment(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            try { await _svc.CancelPaymentAsync(id, farmId); return Ok(); }
            catch (Exception ex) { return BadRequest(ex.Message); }
        }
    }
}
