using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Helpers;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController][Authorize][Route("api/Hotel")]
    public class HotelSupplierController : ControllerBase
    {
        private readonly IHotelSupplierService _svc;
        public HotelSupplierController(IHotelSupplierService svc) { _svc = svc; }
        private string? UserId => User.FindFirst("UserId")?.Value ?? User.FindFirst("sub")?.Value;

        [HttpGet("suppliers")]
        public async Task<IActionResult> GetAll([FromQuery] string farmId)
        { var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth; return Ok(await _svc.GetAllAsync(farmId)); }

        [HttpGet("suppliers/{id}")]
        public async Task<IActionResult> GetById(int id, [FromQuery] string farmId)
        { var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth; var m = await _svc.GetByIdAsync(id, farmId); return m == null ? NotFound() : Ok(m); }

        [HttpPost("suppliers")]
        public async Task<IActionResult> Create([FromBody] HotelSupplierModel m)
        { var auth = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (auth != null) return auth;
          try { return Ok(new { hotelSupplierId = await _svc.InsertAsync(m, UserId) }); } catch (Exception ex) { return BadRequest(ex.Message); } }

        [HttpPut("suppliers/{id}")]
        public async Task<IActionResult> Update(int id, [FromBody] HotelSupplierModel m)
        { var auth = HotelAuthHelper.VerifyFarmOwnership(User, m.FarmId); if (auth != null) return auth; m.HotelSupplierId = id; await _svc.UpdateAsync(m); return Ok(); }

        [HttpDelete("suppliers/{id}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string farmId)
        { var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth; await _svc.DeleteAsync(id, farmId); return Ok(); }

        [HttpGet("suppliers/owed")]
        public async Task<IActionResult> GetOwed([FromQuery] string farmId)
        { var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth; return Ok(await _svc.GetOwedAsync(farmId)); }

        [HttpGet("suppliers/balance-summary")]
        public async Task<IActionResult> GetBalanceSummary([FromQuery] string farmId)
        { var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth; return Ok(await _svc.GetBalanceSummaryAsync(farmId)); }

        [HttpGet("suppliers/{id}/ledger")]
        public async Task<IActionResult> GetLedger(int id, [FromQuery] string farmId)
        { var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth; return Ok(await _svc.GetLedgerAsync(id, farmId)); }

        [HttpPost("suppliers/post-expense")]
        public async Task<IActionResult> PostExpense([FromBody] HotelSupplierAdjustmentRequest req)
        { var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
          try { await _svc.PostExpenseAsync(req.FarmId, req.HotelSupplierId, 0, req.Amount, req.Description, UserId); return Ok(); } catch (Exception ex) { return BadRequest(ex.Message); } }

        [HttpPost("suppliers/post-adjustment")]
        public async Task<IActionResult> PostAdjustment([FromBody] HotelSupplierAdjustmentRequest req)
        { var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
          try { await _svc.PostAdjustmentAsync(req.FarmId, req.HotelSupplierId, req.Amount, req.Description, UserId); return Ok(); } catch (Exception ex) { return BadRequest(ex.Message); } }

        [HttpGet("supplier-payments")]
        public async Task<IActionResult> GetPayments([FromQuery] string farmId, [FromQuery] string? status)
        { var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth; return Ok(await _svc.GetPaymentsAsync(farmId, status)); }

        [HttpPost("supplier-payments")]
        public async Task<IActionResult> CreatePayment([FromBody] HotelSupplierPaymentCreateRequest req)
        { var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
          try { var m = new HotelSupplierPaymentModel { FarmId = req.FarmId, HotelSupplierId = req.HotelSupplierId, Amount = req.Amount, PaymentMethod = req.PaymentMethod, HotelCashAccountId = req.HotelCashAccountId, Reference = req.Reference, LinkedExpenseId = req.LinkedExpenseId, Notes = req.Notes, PaymentDate = string.IsNullOrEmpty(req.PaymentDate) ? DateTime.UtcNow : DateTime.Parse(req.PaymentDate) };
            return Ok(new { hotelSupplierPaymentId = await _svc.InsertPaymentAsync(m, UserId) }); } catch (Exception ex) { return BadRequest(ex.Message); } }

        [HttpPost("supplier-payments/{id}/approve")]
        public async Task<IActionResult> ApprovePayment(int id, [FromQuery] string farmId)
        { var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
          try { await _svc.ApprovePaymentAsync(id, farmId, UserId); return Ok(); } catch (Exception ex) { return BadRequest(ex.Message); } }

        [HttpPost("supplier-payments/{id}/cancel")]
        public async Task<IActionResult> CancelPayment(int id, [FromQuery] string farmId)
        { var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
          try { await _svc.CancelPaymentAsync(id, farmId); return Ok(); } catch (Exception ex) { return BadRequest(ex.Message); } }
    }
}
