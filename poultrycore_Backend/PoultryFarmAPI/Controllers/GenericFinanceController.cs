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

        [HttpPost]
        public async Task<ActionResult<int>> Create(string farmId, [FromBody] GenericLoanCreateRequest req)
        {
            req.FarmId = farmId;
            return Ok(await _svc.CreateAsync(req));
        }

        [HttpGet("{loanId:int}/payments")]
        public async Task<ActionResult<IEnumerable<GenericLoanPaymentModel>>> Payments(string farmId, int loanId)
            => Ok(await _svc.ListPaymentsAsync(loanId, farmId));

        [HttpPost("{loanId:int}/repay")]
        public async Task<ActionResult<int>> Repay(string farmId, int loanId, [FromBody] GenericLoanRepayRequest req)
        {
            req.FarmId = farmId;
            return Ok(await _svc.RepayAsync(loanId, req));
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
            await _svc.DepreciateAsync(assetId, farmId, amount);
            return Ok();
        }
    }
}
