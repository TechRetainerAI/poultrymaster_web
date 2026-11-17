using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Filters;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // Water Customer Balances and Supplier Balances -- the payment allocation
    // control pages (migration 227). The poultry twin is
    // PoultryBalancesController; the route shapes are identical on purpose,
    // because lib/api/balances.ts is one client for all three modules and only
    // swaps the prefix.
    //
    // These are working pages, not reports: they summarise what is owed AND take
    // the payment. A payment posted here writes back to the sale or purchase it
    // was applied to, which is the whole reason the feature exists.
    //
    // The existing per-document endpoints (api/Water/payments and the raw
    // material pay-balance route) are untouched and keep working -- they now go
    // through the same SQL with a single allocation, so both routes produce
    // identical records.
    //
    // The statement routes deliberately sit at api/Water/customers/{id}/statement
    // and api/Water/suppliers/{id}/statement -- the shared client builds those
    // paths -- and neither WaterCustomerController nor the suppliers controller
    // defines a {id}/statement template, so there is no route collision.
    //
    // AuditLogActionFilter is registered globally, so every write below is
    // audited without any code here.
    // Authentication is REQUIRED here. These endpoints take money in, allocate
    // it across a customer's sales and reverse it again, and until this
    // attribute was added they were reachable with no token at all -- the
    // frontend's usePermissions() gate was the only thing in front of them,
    // which is exactly the "frontend hiding alone is not enough" case.
    //
    // [Authorize] is authentication only. WHICH user may do WHAT is the job of
    // IamEnforcementFilter, which runs globally in shadow mode by default
    // (Iam:Enforced); a [RequirePermission] here would enforce immediately and
    // could lock out staff whose roles have not been granted yet.
    [Authorize]
    [ApiController]
    [Route("api/Water")]
    [RequireCompanyType("Water")]
    public class WaterBalancesController : ControllerBase
    {
        private readonly IWaterBalanceService _svc;
        public WaterBalancesController(IWaterBalanceService svc) => _svc = svc;

        private static BalanceQuery BuildQuery(string farmId, DateTime? from, DateTime? to,
            int? partyId, string? status, decimal? minBalance, string? search) => new()
        {
            FarmId = farmId,
            From = from,
            To = to,
            PartyId = partyId,
            Status = status,
            MinBalance = minBalance,
            Search = search,
        };

        // ------------------------------------------------------ customer balances

        [HttpGet("customer-balances")]
        public async Task<ActionResult<IEnumerable<PartyBalanceRow>>> GetCustomerBalances(
            [FromQuery] string farmId, [FromQuery] DateTime? from, [FromQuery] DateTime? to,
            [FromQuery] int? customerId, [FromQuery] string? status,
            [FromQuery] decimal? minBalance, [FromQuery] string? search)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetCustomerBalances(
                BuildQuery(farmId, from, to, customerId, status, minBalance, search)));
        }

        [HttpGet("customer-balances/summary")]
        public async Task<ActionResult<BalanceSummary>> GetCustomerSummary([FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetCustomerSummary(farmId));
        }

        [HttpGet("customer-balances/{customerId:int}/open-sales")]
        public async Task<ActionResult<IEnumerable<OpenDocumentRow>>> GetOpenSales(
            int customerId, [FromQuery] string farmId,
            [FromQuery] DateTime? from, [FromQuery] DateTime? to, [FromQuery] string? status)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetOpenSales(farmId, customerId, from, to, status));
        }

        [HttpPost("customer-payments")]
        public async Task<ActionResult> RecordCustomerPayment([FromBody] RecordPaymentRequest r)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(r.FarmId)) return BadRequest("Company ID is required.");
            if (r.PartyId is null or 0) return BadRequest("A customer is required to receive a payment.");
            // 424: a payment may be applied to nothing -- it is then the customer's credit.
            // 425 (382): only the owner / an admin may keep a payment off Profit & Loss.
            if (r.ExcludeFromPL && !await CanSetPL()) return StatusCode(403, new
            {
                message = "Only the account owner or an admin can keep a payment off Profit & Loss.",
            });
            try
            {
                var groupId = await _svc.RecordCustomerPayment(r);
                return Ok(new { paymentId = groupId });
            }
            catch (Npgsql.PostgresException ex) when (ex.SqlState == "P0001")
            {
                return BadRequest(new { message = ex.MessageText });
            }
        }

        private string? Me() => User?.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;
        private async Task<bool> CanSetPL()
        {
            var me = Me();
            return !string.IsNullOrWhiteSpace(me) && await SetupAdminOnlyAttribute.IsSetupAdminAsync(HttpContext, me);
        }

        // 425 (382): a payment on a customer debt is revenue unless the owner / an admin excludes it.
        [HttpPost("customer-payments/{paymentId:guid}/pl-exclusion")]
        [SetupAdminOnly]
        public async Task<ActionResult> SetCustomerPaymentPLExclusion(Guid paymentId, [FromBody] PLExclusionRequest r)
        {
            if (string.IsNullOrWhiteSpace(r.FarmId)) return BadRequest("Company ID is required.");
            try
            {
                await _svc.SetCustomerPaymentPLExclusion(r.FarmId, paymentId, r.Exclude, Me());
                return Ok(new { paymentId, excludedFromPL = r.Exclude });
            }
            catch (Npgsql.PostgresException ex) when (ex.SqlState == "P0001")
            {
                return BadRequest(new { message = ex.MessageText });
            }
        }

        // 427 (382): a payment on a supplier debt is an operating expense unless the owner / an admin excludes it.
        [HttpPost("supplier-payments/{paymentId:int}/pl-exclusion")]
        [SetupAdminOnly]
        public async Task<ActionResult> SetSupplierPaymentPLExclusion(int paymentId, [FromBody] PLExclusionRequest r)
        {
            if (string.IsNullOrWhiteSpace(r.FarmId)) return BadRequest("Company ID is required.");
            try
            {
                await _svc.SetSupplierPaymentPLExclusion(r.FarmId, paymentId, r.Exclude, Me());
                return Ok(new { paymentId, excludedFromPL = r.Exclude });
            }
            catch (Npgsql.PostgresException ex) when (ex.SqlState == "P0001")
            {
                return BadRequest(new { message = ex.MessageText });
            }
        }

        // 425: customer debt -- owed without a sale. Recording or reversing one is
        // the owner's / an admin's call, like manual credit.
        [HttpGet("customer-debts")]
        public async Task<ActionResult<IEnumerable<CustomerDebtRow>>> GetCustomerDebts([FromQuery] string farmId, [FromQuery] int? customerId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest(new { message = "Company ID is required." });
            return Ok(await _svc.GetCustomerDebts(farmId, customerId));
        }

        [HttpPost("customer-debts")]
        [SetupAdminOnly]
        public async Task<ActionResult> CreateCustomerDebt([FromBody] CustomerDebtRequest r)
        {
            if (r is null || string.IsNullOrWhiteSpace(r.FarmId)) return BadRequest(new { message = "Company ID is required." });
            if (string.IsNullOrWhiteSpace(r.Description)) return BadRequest(new { message = "Describe what the debt is for." });
            r.CreatedBy = Me() ?? r.CreatedBy;
            try { return Content(await _svc.CreateCustomerDebt(r), "application/json"); }
            catch (Npgsql.PostgresException ex) when (ex.SqlState == "P0001") { return BadRequest(new { message = ex.MessageText }); }
        }

        [HttpPost("customer-debts/{debtId:int}/reverse")]
        [SetupAdminOnly]
        public async Task<ActionResult> ReverseCustomerDebt(int debtId, [FromBody] CustomerDebtReverseRequest r)
        {
            if (r is null || string.IsNullOrWhiteSpace(r.FarmId)) return BadRequest(new { message = "Company ID is required." });
            if (string.IsNullOrWhiteSpace(r.Reason)) return BadRequest(new { message = "Give a reason for reversing the debt." });
            r.ReversedBy = Me() ?? r.ReversedBy;
            try { return Ok(new { debtId = await _svc.ReverseCustomerDebt(debtId, r) }); }
            catch (Npgsql.PostgresException ex) when (ex.SqlState == "P0001") { return BadRequest(new { message = ex.MessageText }); }
        }

        // -------------------------------------------- 426 supplier credit / debt
        // Same routes and shapes as PoultryBalancesController (370).

        private async Task<ActionResult> Run(Func<Task<object>> f)
        {
            try { return Ok(await f()); }
            catch (Npgsql.PostgresException ex) when (ex.SqlState == "P0001") { return BadRequest(new { message = ex.MessageText }); }
        }

        [HttpGet("supplier-credits")]
        public async Task<ActionResult<IEnumerable<SupplierCreditSummaryRow>>> GetSupplierCredits([FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest(new { message = "Company ID is required." });
            return Ok(await _svc.GetSupplierCreditSummary(farmId));
        }

        [HttpGet("supplier-credits/events")]
        public async Task<ActionResult<IEnumerable<SupplierCreditEventRow>>> GetSupplierCreditEvents([FromQuery] string farmId, [FromQuery] int? supplierId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest(new { message = "Company ID is required." });
            return Ok(await _svc.GetSupplierCreditEvents(farmId, supplierId));
        }

        [HttpGet("supplier-credits/applications")]
        public async Task<ActionResult<IEnumerable<SupplierCreditApplicationRow>>> GetSupplierCreditApplications([FromQuery] string farmId, [FromQuery] int? supplierId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest(new { message = "Company ID is required." });
            return Ok(await _svc.GetSupplierCreditApplications(farmId, supplierId));
        }

        [HttpPost("supplier-credits/manual")]
        [SetupAdminOnly]
        public Task<ActionResult> CreateSupplierCredit([FromBody] SupplierCreditCreateRequest r)
        {
            r.CreatedBy = Me() ?? r.CreatedBy;
            return Run(async () => new { paymentId = await _svc.CreateSupplierCredit(r) });
        }

        [HttpPost("supplier-credits/{paymentId:int}/reverse")]
        [SetupAdminOnly]
        public Task<ActionResult> ReverseSupplierCredit(int paymentId, [FromBody] SupplierReasonRequest r)
        {
            r.By = Me() ?? r.By;
            return Run(async () => new { reversed = await _svc.ReverseSupplierCredit(paymentId, r) });
        }

        [HttpPost("supplier-credits/apply")]
        public Task<ActionResult> ApplySupplierCredit([FromBody] SupplierCreditApplyRequest r)
        {
            r.CreatedBy = Me() ?? r.CreatedBy;
            return Run(async () => new { allocationId = await _svc.ApplySupplierCredit(r) });
        }

        [HttpPost("supplier-credits/applications/{allocationId:int}/reverse")]
        [SetupAdminOnly]
        public Task<ActionResult> UnapplySupplierCredit(int allocationId, [FromBody] SupplierReasonRequest r)
        {
            r.By = Me() ?? r.By;
            return Run(async () => new { allocationId = await _svc.UnapplySupplierCredit(allocationId, r) });
        }

        [HttpGet("supplier-credits/refunds")]
        public async Task<ActionResult<IEnumerable<SupplierRefundRow>>> GetSupplierRefunds([FromQuery] string farmId, [FromQuery] int? supplierId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest(new { message = "Company ID is required." });
            return Ok(await _svc.GetSupplierRefunds(farmId, supplierId));
        }

        [HttpPost("supplier-credits/refunds")]
        public Task<ActionResult> RecordSupplierRefund([FromBody] SupplierRefundRequest r)
        {
            r.CreatedBy = Me() ?? r.CreatedBy;
            return Run(async () => new { refundId = await _svc.RecordSupplierRefund(r) });
        }

        [HttpPost("supplier-credits/refunds/{refundId:int}/reverse")]
        [SetupAdminOnly]
        public Task<ActionResult> ReverseSupplierRefund(int refundId, [FromBody] SupplierReasonRequest r)
        {
            r.By = Me() ?? r.By;
            return Run(async () => new { refundId = await _svc.ReverseSupplierRefund(refundId, r) });
        }

        [HttpGet("supplier-debts")]
        public async Task<ActionResult<IEnumerable<SupplierDebtRow>>> GetSupplierDebts([FromQuery] string farmId, [FromQuery] int? supplierId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest(new { message = "Company ID is required." });
            return Ok(await _svc.GetSupplierDebts(farmId, supplierId));
        }

        [HttpPost("supplier-debts")]
        [SetupAdminOnly]
        public async Task<ActionResult> CreateSupplierDebt([FromBody] SupplierDebtRequest r)
        {
            r.CreatedBy = Me() ?? r.CreatedBy;
            try { return Content(await _svc.CreateSupplierDebt(r), "application/json"); }
            catch (Npgsql.PostgresException ex) when (ex.SqlState == "P0001") { return BadRequest(new { message = ex.MessageText }); }
        }

        [HttpPost("supplier-debts/{debtId:int}/reverse")]
        [SetupAdminOnly]
        public Task<ActionResult> ReverseSupplierDebt(int debtId, [FromBody] SupplierReasonRequest r)
        {
            r.By = Me() ?? r.By;
            return Run(async () => new { debtId = await _svc.ReverseSupplierDebt(debtId, r) });
        }

        // -------------------------------------------- 424 customer credit / refunds
        // Same routes and shapes as PoultryBalancesController, so the shared
        // credit pages only swap the prefix. Under customer-payments on purpose:
        // the same permission keys (water.customer-payments.*).

        [HttpGet("customer-payments/credit")]
        public async Task<ActionResult<IEnumerable<CustomerCreditSummaryRow>>> GetCreditSummary([FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest(new { message = "Company ID is required." });
            return Ok(await _svc.GetCustomerCreditSummary(farmId));
        }

        [HttpGet("customer-payments/credit/{customerId:int}")]
        public async Task<ActionResult<IEnumerable<CustomerCreditRow>>> GetCustomerCredit(int customerId, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest(new { message = "Company ID is required." });
            return Ok(await _svc.GetCustomerCredit(farmId, customerId));
        }

        [HttpGet("customer-payments/credit/events")]
        public async Task<ActionResult<IEnumerable<CustomerCreditEventRow>>> GetCustomerCreditEvents([FromQuery] string farmId, [FromQuery] int? customerId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest(new { message = "Company ID is required." });
            return Ok(await _svc.GetCustomerCreditEvents(farmId, customerId));
        }

        [HttpPost("customer-payments/apply-credit")]
        public async Task<ActionResult> ApplyCustomerCredit([FromBody] CustomerCreditApplyRequest r)
        {
            if (r is null || string.IsNullOrWhiteSpace(r.FarmId)) return BadRequest(new { message = "Company ID is required." });
            r.CreatedBy = User?.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value ?? r.CreatedBy;
            try { return Ok(new { applied = await _svc.ApplyCustomerCredit(r) }); }
            catch (Npgsql.PostgresException ex) when (ex.SqlState == "P0001") { return BadRequest(new { message = ex.MessageText }); }
        }

        [HttpGet("customer-payments/refunds")]
        public async Task<ActionResult<IEnumerable<CustomerRefundRow>>> GetCustomerRefunds([FromQuery] string farmId, [FromQuery] int? customerId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest(new { message = "Company ID is required." });
            return Ok(await _svc.GetCustomerRefunds(farmId, customerId));
        }

        [HttpPost("customer-payments/refunds")]
        public async Task<ActionResult> RecordCustomerRefund([FromBody] CustomerRefundRequest r)
        {
            if (r is null || string.IsNullOrWhiteSpace(r.FarmId)) return BadRequest(new { message = "Company ID is required." });
            if (string.IsNullOrWhiteSpace(r.Reason)) return BadRequest(new { message = "Give a reason for the refund." });
            r.CreatedBy = User?.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value ?? r.CreatedBy;
            try { return Ok(new { refundId = await _svc.RecordCustomerRefund(r) }); }
            catch (Npgsql.PostgresException ex) when (ex.SqlState == "P0001") { return BadRequest(new { message = ex.MessageText }); }
        }

        // Reversing a refund puts money back and the credit back -- owner / admin only.
        [HttpPost("customer-payments/refunds/{refundId:int}/reverse")]
        [SetupAdminOnly]
        public async Task<ActionResult> ReverseCustomerRefund(int refundId, [FromBody] CustomerRefundReverseRequest r)
        {
            if (r is null || string.IsNullOrWhiteSpace(r.FarmId)) return BadRequest(new { message = "Company ID is required." });
            if (string.IsNullOrWhiteSpace(r.Reason)) return BadRequest(new { message = "Give a reason for reversing the refund." });
            r.ReversedBy = User?.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value ?? r.ReversedBy;
            try { return Ok(new { refundId = await _svc.ReverseCustomerRefund(refundId, r) }); }
            catch (Npgsql.PostgresException ex) when (ex.SqlState == "P0001") { return BadRequest(new { message = ex.MessageText }); }
        }

        // Credit added by hand: owner / admin only -- a typed-in credit could
        // otherwise pay for goods nobody paid for.
        [HttpGet("customer-payments/credit/manual")]
        public async Task<ActionResult<IEnumerable<ManualCreditRow>>> GetManualCredits([FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest(new { message = "Company ID is required." });
            return Ok(await _svc.GetManualCredits(farmId));
        }

        [HttpPost("customer-payments/credit/manual")]
        [SetupAdminOnly]
        public async Task<ActionResult> CreateManualCredit([FromBody] ManualCreditRequest r)
        {
            if (r is null || string.IsNullOrWhiteSpace(r.FarmId)) return BadRequest(new { message = "Company ID is required." });
            if (string.IsNullOrWhiteSpace(r.Reason)) return BadRequest(new { message = "Give a reason for the credit." });
            r.CreatedBy = User?.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value ?? r.CreatedBy;
            try { return Content(await _svc.CreateManualCredit(r), "application/json"); }
            catch (Npgsql.PostgresException ex) when (ex.SqlState == "P0001") { return BadRequest(new { message = ex.MessageText }); }
        }

        [HttpPost("customer-payments/credit/manual/{paymentGroupId:guid}/reverse")]
        [SetupAdminOnly]
        public async Task<ActionResult> ReverseManualCredit(Guid paymentGroupId, [FromBody] ManualCreditReverseRequest r)
        {
            if (r is null || string.IsNullOrWhiteSpace(r.FarmId)) return BadRequest(new { message = "Company ID is required." });
            if (string.IsNullOrWhiteSpace(r.Reason)) return BadRequest(new { message = "Give a reason for reversing the credit." });
            r.ReversedBy = User?.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value ?? r.ReversedBy;
            try { return Ok(new { reversed = await _svc.ReverseManualCredit(paymentGroupId, r) }); }
            catch (Npgsql.PostgresException ex) when (ex.SqlState == "P0001") { return BadRequest(new { message = ex.MessageText }); }
        }

        [HttpPost("customer-payments/{paymentId:guid}/reverse")]
        public async Task<ActionResult> ReverseCustomerPayment(Guid paymentId, [FromBody] ReversePaymentRequest r)
        {
            if (string.IsNullOrWhiteSpace(r.FarmId)) return BadRequest("Company ID is required.");
            var count = await _svc.ReverseCustomerPayment(r.FarmId, paymentId, r.Reason, r.ReversedBy);
            return Ok(new { reversedAllocations = count });
        }

        // NOTE: this is api/Water/customer-payments, NOT the legacy
        // api/Water/payments (WaterPaymentController), which lists the raw
        // per-sale rows. Both read waterpayments; this one groups them the way
        // the payment was actually made.
        [HttpGet("customer-payments")]
        public async Task<ActionResult<IEnumerable<PaymentHistoryRow>>> GetCustomerPayments(
            [FromQuery] string farmId, [FromQuery] int? customerId, [FromQuery] int? saleId,
            [FromQuery] DateTime? from, [FromQuery] DateTime? to)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetCustomerPayments(farmId, customerId, saleId, from, to));
        }

        [HttpGet("customer-payments/{paymentId:guid}")]
        public async Task<ActionResult> GetCustomerPayment(Guid paymentId, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var payments = await _svc.GetCustomerPayments(farmId, null, null, null, null);
            var header = payments.FirstOrDefault(p =>
                string.Equals(p.PaymentId, paymentId.ToString(), StringComparison.OrdinalIgnoreCase));
            if (header is null) return NotFound();
            return Ok(new
            {
                payment = header,
                allocations = await _svc.GetCustomerPaymentAllocations(farmId, paymentId),
            });
        }

        [HttpGet("customers/{customerId:int}/statement")]
        public async Task<ActionResult<IEnumerable<StatementLine>>> GetCustomerStatement(
            int customerId, [FromQuery] string farmId,
            [FromQuery] DateTime? from, [FromQuery] DateTime? to)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetCustomerStatement(farmId, customerId, from, to));
        }

        // ------------------------------------------------------ supplier balances

        [HttpGet("supplier-balances")]
        public async Task<ActionResult<IEnumerable<PartyBalanceRow>>> GetSupplierBalances(
            [FromQuery] string farmId, [FromQuery] DateTime? from, [FromQuery] DateTime? to,
            [FromQuery] int? supplierId, [FromQuery] string? status,
            [FromQuery] decimal? minBalance, [FromQuery] string? search)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetSupplierBalances(
                BuildQuery(farmId, from, to, supplierId, status, minBalance, search)));
        }

        [HttpGet("supplier-balances/summary")]
        public async Task<ActionResult<BalanceSummary>> GetSupplierSummary([FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetSupplierSummary(farmId));
        }

        [HttpGet("supplier-balances/{supplierId:int}/open-purchases")]
        public async Task<ActionResult<IEnumerable<OpenDocumentRow>>> GetOpenPurchases(
            int supplierId, [FromQuery] string farmId,
            [FromQuery] DateTime? from, [FromQuery] DateTime? to, [FromQuery] string? status)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetOpenPurchases(farmId, supplierId, from, to, status));
        }

        [HttpPost("supplier-payments")]
        public async Task<ActionResult> RecordSupplierPayment([FromBody] RecordPaymentRequest r)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(r.FarmId)) return BadRequest("Company ID is required.");
            // 427 (382): only the owner / an admin may keep a payment off Profit & Loss.
            if (r.ExcludeFromPL && !await CanSetPL()) return StatusCode(403, new
            {
                message = "Only the account owner or an admin can keep a payment off Profit & Loss.",
            });
            // 426: a payment may be applied to nothing -- it is then an advance (supplier credit).
            if ((r.Allocations.Count == 0 || r.Allocations.Sum(a => a.Amount) < r.Amount) && r.PartyId is null or 0)
                return BadRequest("Choose the supplier -- money not applied to anything is kept as their credit.");
            try
            {
                var id = await _svc.RecordSupplierPayment(r);
                return Ok(new { paymentId = id });
            }
            catch (Npgsql.PostgresException ex) when (ex.SqlState == "P0001")
            {
                return BadRequest(new { message = ex.MessageText });
            }
        }

        [HttpPost("supplier-payments/{paymentId:int}/reverse")]
        public async Task<ActionResult> ReverseSupplierPayment(int paymentId, [FromBody] ReversePaymentRequest r)
        {
            if (string.IsNullOrWhiteSpace(r.FarmId)) return BadRequest("Company ID is required.");
            var count = await _svc.ReverseSupplierPayment(r.FarmId, paymentId, r.Reason, r.ReversedBy);
            return Ok(new { reversedAllocations = count });
        }

        [HttpGet("supplier-payments")]
        public async Task<ActionResult<IEnumerable<PaymentHistoryRow>>> GetSupplierPayments(
            [FromQuery] string farmId, [FromQuery] int? supplierId,
            [FromQuery] string? documentType, [FromQuery] int? documentId,
            [FromQuery] DateTime? from, [FromQuery] DateTime? to)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetSupplierPayments(farmId, supplierId, documentType, documentId, from, to));
        }

        [HttpGet("supplier-payments/{paymentId:int}")]
        public async Task<ActionResult> GetSupplierPayment(int paymentId, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var payments = await _svc.GetSupplierPayments(farmId, null, null, null, null, null);
            var header = payments.FirstOrDefault(p => p.PaymentId == paymentId.ToString());
            if (header is null) return NotFound();
            return Ok(new
            {
                payment = header,
                allocations = await _svc.GetSupplierPaymentAllocations(farmId, paymentId),
            });
        }

        [HttpGet("suppliers/{supplierId:int}/statement")]
        public async Task<ActionResult<IEnumerable<StatementLine>>> GetSupplierStatement(
            int supplierId, [FromQuery] string farmId,
            [FromQuery] DateTime? from, [FromQuery] DateTime? to)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetSupplierStatement(farmId, supplierId, from, to));
        }

        // ----------------------------------------------------------------- audit

        /// <summary>
        /// Documents whose allocations disagree with their amountpaid. Should
        /// always return an empty list; a non-empty one means a payment path has
        /// drifted and the balances on screen can no longer be trusted.
        ///
        /// One known exception on water: purchases that were part-paid BEFORE
        /// migration 227 have no allocation rows to reconstruct from, so they
        /// report a one-time opening difference. See the note at the end of 227.
        /// </summary>
        [HttpGet("balances/audit")]
        public async Task<ActionResult<IEnumerable<BalanceAuditRow>>> Audit([FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.Audit(farmId));
        }
    }
}
