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
