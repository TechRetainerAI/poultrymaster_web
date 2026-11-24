using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Filters;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/generic-company/{farmId}/customer-credits")]
    [RequireCompanyType("Generic")]
    public class GenericCustomerCreditController : ControllerBase
    {
        private readonly IGenericCustomerCreditService _svc;
        public GenericCustomerCreditController(IGenericCustomerCreditService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<GenericCustomerCreditModel>>> List(string farmId)
            => Ok(await _svc.ListAsync(farmId));

        [HttpPost]
        public async Task<ActionResult<int>> Create(string farmId, [FromBody] GenericCustomerCreditCreateRequest req)
        {
            req.FarmId = farmId;
            return Ok(await _svc.CreateAsync(req));
        }
    }

    [ApiController]
    [Route("api/generic-company/{farmId}/supplier-credits")]
    [RequireCompanyType("Generic")]
    public class GenericSupplierCreditController : ControllerBase
    {
        private readonly IGenericSupplierCreditService _svc;
        public GenericSupplierCreditController(IGenericSupplierCreditService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<GenericSupplierCreditModel>>> List(string farmId)
            => Ok(await _svc.ListAsync(farmId));

        [HttpPost]
        public async Task<ActionResult<int>> Create(string farmId, [FromBody] GenericSupplierCreditCreateRequest req)
        {
            req.FarmId = farmId;
            return Ok(await _svc.CreateAsync(req));
        }
    }

    // =========================================================================
    // Credit Applications (Phase A — read-only, written by sale approve)
    // =========================================================================
    [ApiController]
    [Route("api/generic-company/{farmId}/credit-applications")]
    [RequireCompanyType("Generic")]
    public class GenericCustomerCreditApplicationController : ControllerBase
    {
        private readonly IGenericCustomerCreditApplicationService _svc;
        public GenericCustomerCreditApplicationController(IGenericCustomerCreditApplicationService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<GenericCustomerCreditApplicationModel>>> List(string farmId)
            => Ok(await _svc.ListAsync(farmId));
    }

    // =========================================================================
    // Bulk Payment Allocation (Phase B)
    // =========================================================================
    [ApiController]
    [Route("api/generic-company/{farmId}/bulk-payments")]
    [RequireCompanyType("Generic")]
    public class GenericBulkPaymentController : ControllerBase
    {
        private readonly IGenericBulkPaymentService _svc;
        public GenericBulkPaymentController(IGenericBulkPaymentService svc) => _svc = svc;

        [HttpPost]
        public async Task<ActionResult> Create(string farmId, [FromBody] GenericBulkPaymentRequest req)
        {
            if (req.Allocations == null || req.Allocations.Count == 0)
                return BadRequest("At least one allocation is required.");

            req.FarmId = farmId;
            var groupId = await _svc.BulkInsertAsync(req);
            return Created(string.Empty, new { PaymentGroupId = groupId });
        }
    }

    // =========================================================================
    // Credit Refunds (Phase C)
    // =========================================================================
    [ApiController]
    [Route("api/generic-company/{farmId}/credit-refunds")]
    [RequireCompanyType("Generic")]
    public class GenericCustomerCreditRefundController : ControllerBase
    {
        private readonly IGenericCustomerCreditRefundService _svc;
        public GenericCustomerCreditRefundController(IGenericCustomerCreditRefundService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<GenericCustomerCreditRefundModel>>> List(string farmId)
            => Ok(await _svc.ListAsync(farmId));

        [HttpPost]
        public async Task<ActionResult<int>> Create(string farmId, [FromBody] GenericCustomerCreditRefundRequest req)
        {
            if (req.Amount <= 0)
                return BadRequest("Refund amount must be greater than zero.");
            if (req.GenericCashAccountId == null)
                return BadRequest("Cash account is required for a credit refund.");

            req.FarmId = farmId;
            return Ok(await _svc.CreateAsync(req));
        }
    }

    // =========================================================================
    // Deferred Inventory Cost (read-only report)
    // =========================================================================
    [ApiController]
    [Route("api/generic-company/{farmId}/deferred-costs")]
    [RequireCompanyType("Generic")]
    public class GenericDeferredCostController : ControllerBase
    {
        private readonly IGenericDeferredCostService _svc;
        public GenericDeferredCostController(IGenericDeferredCostService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<GenericDeferredCostRow>>> List(string farmId)
            => Ok(await _svc.ListAsync(farmId));
    }
}
