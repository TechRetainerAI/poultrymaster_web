using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // =========================================================================
    // Helper used by all three Phase-3 controllers. Keeps the Type='Generic'
    // guard in one place. Internal so it isn't exposed as an API surface.
    // =========================================================================
    internal static class GenericFarmGuard
    {
        public static async Task<ActionResult?> EnsureAsync(
            IGenericCompanyService companies, string farmId, ControllerBase controller)
        {
            if (string.IsNullOrWhiteSpace(farmId))
                return controller.BadRequest("Company ID is required.");

            var farmType = await companies.GetFarmTypeAsync(farmId);
            if (farmType is null)
                return controller.NotFound("Company not found.");
            if (!string.Equals(farmType, "Generic", StringComparison.OrdinalIgnoreCase))
                return controller.Conflict($"This company is not a Generic company (current type: {farmType}).");
            return null;
        }
    }

    // =========================================================================
    // Customers + Customer Ledger + Customer Payments.
    // =========================================================================
    [ApiController]
    [Route("api/generic-company/{farmId}")]
    public class GenericCustomerController : ControllerBase
    {
        private readonly IGenericCustomerService _customers;
        private readonly IGenericCompanyService _companies;

        public GenericCustomerController(IGenericCustomerService customers, IGenericCompanyService companies)
        {
            _customers = customers;
            _companies = companies;
        }

        // ---------------------------------------------------------------------
        // Customers
        // ---------------------------------------------------------------------
        [HttpGet("customers")]
        public async Task<ActionResult<IEnumerable<GenericCustomerModel>>> GetAll(string farmId)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _customers.GetAllAsync(farmId));
        }

        [HttpGet("customers/{id:int}")]
        public async Task<ActionResult<GenericCustomerModel>> GetById(string farmId, int id)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            var c = await _customers.GetByIdAsync(id, farmId);
            return c is null ? NotFound() : Ok(c);
        }

        [HttpPost("customers")]
        public async Task<ActionResult<GenericCustomerModel>> Create(string farmId, [FromBody] GenericCustomerModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            m.FarmId = farmId;
            var newId = await _customers.InsertAsync(m);
            var created = await _customers.GetByIdAsync(newId, farmId);
            return CreatedAtAction(nameof(GetById), new { farmId, id = newId }, created);
        }

        [HttpPut("customers/{id:int}")]
        public async Task<IActionResult> Update(string farmId, int id, [FromBody] GenericCustomerModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            m.FarmId = farmId;
            m.GenericCustomerId = id;
            await _customers.UpdateAsync(m);
            return NoContent();
        }

        [HttpDelete("customers/{id:int}")]
        public async Task<IActionResult> Delete(string farmId, int id)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            await _customers.DeleteAsync(id, farmId);
            return NoContent();
        }

        [HttpGet("customers/owing")]
        public async Task<ActionResult<IEnumerable<GenericCustomerOwingRowModel>>> GetOwing(string farmId)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _customers.GetOwingMoneyAsync(farmId));
        }

        // ---------------------------------------------------------------------
        // Ledger
        // ---------------------------------------------------------------------
        [HttpGet("customers/{id:int}/ledger")]
        public async Task<ActionResult<IEnumerable<GenericCustomerLedgerEntryModel>>> GetLedger(string farmId, int id)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _customers.GetLedgerAsync(id, farmId));
        }

        // ---------------------------------------------------------------------
        // Customer payments
        // ---------------------------------------------------------------------
        [HttpGet("customer-payments")]
        public async Task<ActionResult<IEnumerable<GenericCustomerPaymentModel>>> GetPayments(string farmId, [FromQuery] string? status)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _customers.GetPaymentsAsync(farmId, status));
        }

        [HttpGet("customer-payments/{id:int}")]
        public async Task<ActionResult<GenericCustomerPaymentModel>> GetPayment(string farmId, int id)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            var p = await _customers.GetPaymentByIdAsync(id, farmId);
            return p is null ? NotFound() : Ok(p);
        }

        [HttpPost("customer-payments")]
        public async Task<ActionResult<GenericCustomerPaymentModel>> CreatePayment(string farmId, [FromBody] GenericCustomerPaymentModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            m.FarmId = farmId;
            var newId = await _customers.InsertPaymentAsync(m);
            var created = await _customers.GetPaymentByIdAsync(newId, farmId);
            return CreatedAtAction(nameof(GetPayment), new { farmId, id = newId }, created);
        }

        [HttpPost("customer-payments/{id:int}/approve")]
        public async Task<IActionResult> ApprovePayment(string farmId, int id, [FromQuery] string? approvedBy)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            await _customers.ApprovePaymentAsync(id, farmId, approvedBy);
            return NoContent();
        }

        [HttpPost("customer-payments/{id:int}/cancel")]
        public async Task<IActionResult> CancelPayment(string farmId, int id)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            await _customers.CancelPaymentAsync(id, farmId);
            return NoContent();
        }
    }

    // =========================================================================
    // Sales (the meaty one - approval is transactional across inventory, cash,
    // and customer ledger).
    // =========================================================================
    [ApiController]
    [Route("api/generic-company/{farmId}/sales")]
    public class GenericSaleController : ControllerBase
    {
        private readonly IGenericSaleService _sales;
        private readonly IGenericCompanyService _companies;

        public GenericSaleController(IGenericSaleService sales, IGenericCompanyService companies)
        {
            _sales = sales;
            _companies = companies;
        }

        [HttpGet]
        public async Task<ActionResult<IEnumerable<GenericSaleModel>>> GetAll(string farmId, [FromQuery] string? status)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _sales.GetAllAsync(farmId, status));
        }

        [HttpGet("{id:int}")]
        public async Task<ActionResult<GenericSaleModel>> GetById(string farmId, int id)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            var s = await _sales.GetByIdAsync(id, farmId);
            return s is null ? NotFound() : Ok(s);
        }

        [HttpPost]
        public async Task<ActionResult<GenericSaleModel>> Create(
            string farmId, [FromBody] GenericSaleCreateRequest req, [FromQuery] string? createdBy)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            if (req.Items is null || req.Items.Count == 0)
                return BadRequest("Sale must have at least one item.");

            var newId = await _sales.InsertAsync(farmId, req, createdBy);
            var created = await _sales.GetByIdAsync(newId, farmId);
            return CreatedAtAction(nameof(GetById), new { farmId, id = newId }, created);
        }

        [HttpPost("{id:int}/approve")]
        public async Task<IActionResult> Approve(string farmId, int id, [FromQuery] string? approvedBy)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            await _sales.ApproveAsync(id, farmId, approvedBy);
            return NoContent();
        }

        [HttpPost("{id:int}/cancel")]
        public async Task<IActionResult> Cancel(
            string farmId, int id,
            [FromBody] GenericSaleCancelRequest? body,
            [FromQuery] string? cancelledBy)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            await _sales.CancelAsync(id, farmId, cancelledBy, body?.Reason);
            return NoContent();
        }

        [HttpPost("{id:int}/refund")]
        public async Task<IActionResult> Refund(
            string farmId, int id,
            [FromBody] GenericSaleRefundRequest? body,
            [FromQuery] string? refundedBy)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            await _sales.RefundAsync(id, farmId, refundedBy, body?.Reason);
            return NoContent();
        }
    }

    // =========================================================================
    // Cash transactions (read-only - writes happen via Sale/Payment approve,
    // plus the manual adjustment endpoint here).
    // =========================================================================
    [ApiController]
    [Route("api/generic-company/{farmId}/cash")]
    public class GenericCashController : ControllerBase
    {
        private readonly IGenericCashTransactionService _cash;
        private readonly IGenericCompanyService _companies;

        public GenericCashController(IGenericCashTransactionService cash, IGenericCompanyService companies)
        {
            _cash = cash;
            _companies = companies;
        }

        [HttpGet("transactions")]
        public async Task<ActionResult<IEnumerable<GenericCashTransactionModel>>> GetAll(
            string farmId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            return Ok(await _cash.GetByFarmAsync(farmId, fromDate, toDate));
        }

        [HttpGet("accounts/{accountId:int}/transactions")]
        public async Task<ActionResult<IEnumerable<GenericCashTransactionModel>>> GetByAccount(
            string farmId, int accountId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            return Ok(await _cash.GetByAccountAsync(accountId, farmId, fromDate, toDate));
        }

        // Manual cash adjustment on a single account. Signed Amount.
        // Reason required. Updates CashAccount.CurrentBalance atomically.
        [HttpPost("adjustments")]
        public async Task<IActionResult> CreateAdjustment(
            string farmId,
            [FromBody] GenericCashAdjustmentRequest req,
            [FromQuery] string? createdBy,
            [FromQuery] string? approvedBy)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            var newId = await _cash.InsertAdjustmentAsync(farmId, req, createdBy, approvedBy);
            return Created(string.Empty, new { GenericCashTransactionId = newId });
        }

        // Record Money In: owner contribution, loan received, supplier refund, other income.
        [HttpPost("money-in")]
        public async Task<IActionResult> MoneyIn(
            string farmId,
            [FromBody] GenericCashMovementRequest req,
            [FromQuery] string? createdBy,
            [FromQuery] string? approvedBy)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (!GenericCashMovementTypes.CashIn.Contains(req.MovementType, StringComparer.OrdinalIgnoreCase))
                return BadRequest($"MovementType must be one of: {string.Join(", ", GenericCashMovementTypes.CashIn)}.");

            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            var newId = await _cash.PostMovementAsync(farmId, "CashIn", req, createdBy, approvedBy);
            return Created(string.Empty, new { GenericCashTransactionId = newId });
        }

        // Record Money Out: owner withdrawal, loan repayment, customer refund, other cash-out.
        [HttpPost("money-out")]
        public async Task<IActionResult> MoneyOut(
            string farmId,
            [FromBody] GenericCashMovementRequest req,
            [FromQuery] string? createdBy,
            [FromQuery] string? approvedBy)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (!GenericCashMovementTypes.CashOut.Contains(req.MovementType, StringComparer.OrdinalIgnoreCase))
                return BadRequest($"MovementType must be one of: {string.Join(", ", GenericCashMovementTypes.CashOut)}.");

            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            var newId = await _cash.PostMovementAsync(farmId, "CashOut", req, createdBy, approvedBy);
            return Created(string.Empty, new { GenericCashTransactionId = newId });
        }

        // Account details header (totals + last-reconciled + unreconciled count).
        [HttpGet("accounts/{accountId:int}/details")]
        public async Task<ActionResult<GenericCashAccountDetailsModel>> GetAccountDetails(string farmId, int accountId)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            var details = await _cash.GetAccountDetailsAsync(accountId, farmId);
            return details is null ? NotFound() : Ok(details);
        }

        // Ledger-vs-stored-balance report (flags drift per account).
        [HttpGet("ledger-report")]
        public async Task<ActionResult<IEnumerable<GenericCashLedgerReportRow>>> GetLedgerReport(string farmId)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _cash.GetLedgerReportAsync(farmId));
        }

        // Company default cash-account mappings (preselect accounts per workflow).
        [HttpGet("defaults")]
        public async Task<ActionResult<IEnumerable<GenericCashAccountDefaultModel>>> GetDefaults(string farmId)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _cash.GetDefaultsAsync(farmId));
        }

        [HttpPut("defaults")]
        public async Task<IActionResult> UpsertDefault(string farmId, [FromBody] GenericCashAccountDefaultRequest req)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            await _cash.UpsertDefaultAsync(farmId, req.DefaultKey, req.GenericCashAccountId);
            return NoContent();
        }

        // Post a multi-method payment allocation set (split across accounts) for one source.
        [HttpPost("allocations")]
        public async Task<IActionResult> PostAllocations(
            string farmId,
            [FromBody] GenericCashAllocationsRequest req,
            [FromQuery] string? createdBy,
            [FromQuery] string? approvedBy)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (!string.Equals(req.Direction, "CashIn", StringComparison.OrdinalIgnoreCase) &&
                !string.Equals(req.Direction, "CashOut", StringComparison.OrdinalIgnoreCase))
                return BadRequest("Direction must be CashIn or CashOut.");

            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            var count = await _cash.PostAllocationsAsync(farmId, req, createdBy, approvedBy);
            return Created(string.Empty, new { Allocations = count });
        }

        // Reconcile an account against an actual count; posts the difference as a
        // ReconciliationAdjustment and records the last-reconciled point.
        [HttpPost("reconciliations")]
        public async Task<IActionResult> Reconcile(
            string farmId,
            [FromBody] GenericCashReconciliationRequest req,
            [FromQuery] string? requestedBy,
            [FromQuery] string? approvedBy)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            var newId = await _cash.CreateReconciliationAsync(farmId, req, requestedBy, approvedBy);
            return Created(string.Empty, new { GenericCashReconciliationId = newId });
        }

        [HttpGet("accounts/{accountId:int}/reconciliations")]
        public async Task<ActionResult<IEnumerable<GenericCashReconciliationModel>>> GetReconciliations(
            string farmId, int accountId)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            return Ok(await _cash.GetReconciliationsByAccountAsync(accountId, farmId));
        }

        // Reverse an existing Approved cash transaction: posts an equal-and-opposite
        // entry linked via ReversalOfTransactionId and marks the original Reversed.
        [HttpPost("transactions/{transactionId:long}/reverse")]
        public async Task<IActionResult> Reverse(
            string farmId,
            long transactionId,
            [FromQuery] string? reversedBy,
            [FromQuery] string? reason)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            var newId = await _cash.ReverseAsync(transactionId, farmId, reversedBy, reason);
            return Created(string.Empty, new { GenericCashTransactionId = newId });
        }
    }
}
