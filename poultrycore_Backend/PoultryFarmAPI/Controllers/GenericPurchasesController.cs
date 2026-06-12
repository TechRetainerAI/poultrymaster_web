using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // =========================================================================
    // Suppliers + Supplier Ledger + Supplier Payments.
    // =========================================================================
    [ApiController]
    [Route("api/generic-company/{farmId}")]
    public class GenericSupplierController : ControllerBase
    {
        private readonly IGenericSupplierService _suppliers;
        private readonly IGenericCompanyService _companies;

        public GenericSupplierController(IGenericSupplierService suppliers, IGenericCompanyService companies)
        {
            _suppliers = suppliers;
            _companies = companies;
        }

        // ---------------------------------------------------------------------
        // Suppliers
        // ---------------------------------------------------------------------
        [HttpGet("suppliers")]
        public async Task<ActionResult<IEnumerable<GenericSupplierModel>>> GetAll(string farmId)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _suppliers.GetAllAsync(farmId));
        }

        [HttpGet("suppliers/{id:int}")]
        public async Task<ActionResult<GenericSupplierModel>> GetById(string farmId, int id)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            var s = await _suppliers.GetByIdAsync(id, farmId);
            return s is null ? NotFound() : Ok(s);
        }

        [HttpPost("suppliers")]
        public async Task<ActionResult<GenericSupplierModel>> Create(string farmId, [FromBody] GenericSupplierModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            m.FarmId = farmId;
            var newId = await _suppliers.InsertAsync(m);
            var created = await _suppliers.GetByIdAsync(newId, farmId);
            return CreatedAtAction(nameof(GetById), new { farmId, id = newId }, created);
        }

        [HttpPut("suppliers/{id:int}")]
        public async Task<IActionResult> Update(string farmId, int id, [FromBody] GenericSupplierModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            m.FarmId = farmId;
            m.GenericSupplierId = id;
            await _suppliers.UpdateAsync(m);
            return NoContent();
        }

        [HttpDelete("suppliers/{id:int}")]
        public async Task<IActionResult> Delete(string farmId, int id)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            await _suppliers.DeleteAsync(id, farmId);
            return NoContent();
        }

        [HttpGet("suppliers/owed")]
        public async Task<ActionResult<IEnumerable<GenericSupplierOwedRowModel>>> GetOwed(string farmId)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _suppliers.GetOwedToThemAsync(farmId));
        }

        [HttpGet("suppliers/{id:int}/ledger")]
        public async Task<ActionResult<IEnumerable<GenericSupplierLedgerEntryModel>>> GetLedger(string farmId, int id)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _suppliers.GetLedgerAsync(id, farmId));
        }

        // ---------------------------------------------------------------------
        // Supplier payments
        // ---------------------------------------------------------------------
        [HttpGet("supplier-payments")]
        public async Task<ActionResult<IEnumerable<GenericSupplierPaymentModel>>> GetPayments(string farmId, [FromQuery] string? status)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _suppliers.GetPaymentsAsync(farmId, status));
        }

        [HttpGet("supplier-payments/{id:int}")]
        public async Task<ActionResult<GenericSupplierPaymentModel>> GetPayment(string farmId, int id)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            var p = await _suppliers.GetPaymentByIdAsync(id, farmId);
            return p is null ? NotFound() : Ok(p);
        }

        [HttpPost("supplier-payments")]
        public async Task<ActionResult<GenericSupplierPaymentModel>> CreatePayment(string farmId, [FromBody] GenericSupplierPaymentModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            m.FarmId = farmId;
            var newId = await _suppliers.InsertPaymentAsync(m);
            var created = await _suppliers.GetPaymentByIdAsync(newId, farmId);
            return CreatedAtAction(nameof(GetPayment), new { farmId, id = newId }, created);
        }

        [HttpPost("supplier-payments/{id:int}/approve")]
        public async Task<IActionResult> ApprovePayment(string farmId, int id, [FromQuery] string? approvedBy)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            await _suppliers.ApprovePaymentAsync(id, farmId, approvedBy);
            return NoContent();
        }

        [HttpPost("supplier-payments/{id:int}/cancel")]
        public async Task<IActionResult> CancelPayment(string farmId, int id)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            await _suppliers.CancelPaymentAsync(id, farmId);
            return NoContent();
        }
    }

    // =========================================================================
    // Purchases (atomic approval mirror of Sale_Approve)
    // =========================================================================
    [ApiController]
    [Route("api/generic-company/{farmId}/purchases")]
    public class GenericPurchaseController : ControllerBase
    {
        private readonly IGenericPurchaseService _purchases;
        private readonly IGenericCompanyService _companies;

        public GenericPurchaseController(IGenericPurchaseService purchases, IGenericCompanyService companies)
        {
            _purchases = purchases;
            _companies = companies;
        }

        [HttpGet]
        public async Task<ActionResult<IEnumerable<GenericPurchaseModel>>> GetAll(string farmId, [FromQuery] string? status)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _purchases.GetAllAsync(farmId, status));
        }

        [HttpGet("{id:int}")]
        public async Task<ActionResult<GenericPurchaseModel>> GetById(string farmId, int id)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            var p = await _purchases.GetByIdAsync(id, farmId);
            return p is null ? NotFound() : Ok(p);
        }

        [HttpPost]
        public async Task<ActionResult<GenericPurchaseModel>> Create(
            string farmId, [FromBody] GenericPurchaseCreateRequest req, [FromQuery] string? createdBy)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            if (req.Items is null || req.Items.Count == 0)
                return BadRequest("Purchase must have at least one item.");

            var newId = await _purchases.InsertAsync(farmId, req, createdBy);
            var created = await _purchases.GetByIdAsync(newId, farmId);
            return CreatedAtAction(nameof(GetById), new { farmId, id = newId }, created);
        }

        [HttpPost("{id:int}/approve")]
        public async Task<IActionResult> Approve(string farmId, int id, [FromQuery] string? approvedBy)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            await _purchases.ApproveAsync(id, farmId, approvedBy);
            return NoContent();
        }

        [HttpPost("{id:int}/cancel")]
        public async Task<IActionResult> Cancel(
            string farmId, int id,
            [FromBody] GenericPurchaseCancelRequest? body,
            [FromQuery] string? cancelledBy)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            await _purchases.CancelAsync(id, farmId, cancelledBy, body?.Reason);
            return NoContent();
        }
    }

    // =========================================================================
    // Expenses (Approve branches on PaymentMethod: Credit → SupplierLedger,
    // anything else → CashOut from the named cash account).
    // =========================================================================
    [ApiController]
    [Route("api/generic-company/{farmId}/expenses")]
    public class GenericExpenseRecordController : ControllerBase
    {
        private readonly IGenericExpenseRecordService _expenses;
        private readonly IGenericCompanyService _companies;

        public GenericExpenseRecordController(IGenericExpenseRecordService expenses, IGenericCompanyService companies)
        {
            _expenses = expenses;
            _companies = companies;
        }

        [HttpGet]
        public async Task<ActionResult<IEnumerable<GenericExpenseModel>>> GetAll(
            string farmId,
            [FromQuery] string? status,
            [FromQuery] DateTime? fromDate,
            [FromQuery] DateTime? toDate)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _expenses.GetAllAsync(farmId, status, fromDate, toDate));
        }

        [HttpGet("{id:int}")]
        public async Task<ActionResult<GenericExpenseModel>> GetById(string farmId, int id)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            var e = await _expenses.GetByIdAsync(id, farmId);
            return e is null ? NotFound() : Ok(e);
        }

        [HttpPost]
        public async Task<ActionResult<GenericExpenseModel>> Create(string farmId, [FromBody] GenericExpenseModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            m.FarmId = farmId;
            var newId = await _expenses.InsertAsync(m);
            var created = await _expenses.GetByIdAsync(newId, farmId);
            return CreatedAtAction(nameof(GetById), new { farmId, id = newId }, created);
        }

        [HttpPost("{id:int}/approve")]
        public async Task<IActionResult> Approve(string farmId, int id, [FromQuery] string? approvedBy)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            await _expenses.ApproveAsync(id, farmId, approvedBy);
            return NoContent();
        }

        [HttpPost("{id:int}/reject")]
        public async Task<IActionResult> Reject(
            string farmId, int id,
            [FromBody] GenericExpenseRejectRequest body,
            [FromQuery] string? approvedBy)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            await _expenses.RejectAsync(id, farmId, body.RejectionReason, approvedBy);
            return NoContent();
        }
    }

    // =========================================================================
    // Cash transfers (Approve writes a paired TransferOut + TransferIn).
    // =========================================================================
    [ApiController]
    [Route("api/generic-company/{farmId}/cash-transfers")]
    public class GenericCashTransferController : ControllerBase
    {
        private readonly IGenericCashTransferService _transfers;
        private readonly IGenericCompanyService _companies;

        public GenericCashTransferController(IGenericCashTransferService transfers, IGenericCompanyService companies)
        {
            _transfers = transfers;
            _companies = companies;
        }

        [HttpGet]
        public async Task<ActionResult<IEnumerable<GenericCashTransferModel>>> GetAll(string farmId, [FromQuery] string? status)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _transfers.GetAllAsync(farmId, status));
        }

        [HttpGet("{id:int}")]
        public async Task<ActionResult<GenericCashTransferModel>> GetById(string farmId, int id)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            var t = await _transfers.GetByIdAsync(id, farmId);
            return t is null ? NotFound() : Ok(t);
        }

        [HttpPost]
        public async Task<ActionResult<GenericCashTransferModel>> Create(string farmId, [FromBody] GenericCashTransferModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            m.FarmId = farmId;
            var newId = await _transfers.InsertAsync(m);
            var created = await _transfers.GetByIdAsync(newId, farmId);
            return CreatedAtAction(nameof(GetById), new { farmId, id = newId }, created);
        }

        [HttpPost("{id:int}/approve")]
        public async Task<IActionResult> Approve(string farmId, int id, [FromQuery] string? approvedBy)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            await _transfers.ApproveAsync(id, farmId, approvedBy);
            return NoContent();
        }

        [HttpPost("{id:int}/cancel")]
        public async Task<IActionResult> Cancel(string farmId, int id)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            await _transfers.CancelAsync(id, farmId);
            return NoContent();
        }
    }
}
