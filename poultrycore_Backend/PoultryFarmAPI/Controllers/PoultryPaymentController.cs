using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // Poultry customer payments (partial payments against a Sale).
    // Mirrors WaterPaymentController.
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
    [Route("api/Poultry/payments")]
    public class PoultryPaymentController : ControllerBase
    {
        private readonly IPoultryPaymentService _svc;
        public PoultryPaymentController(IPoultryPaymentService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<PoultryPaymentModel>>> GetAll([FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetAll(farmId));
        }

        [HttpGet("by-sale/{saleId:int}")]
        public async Task<ActionResult<IEnumerable<PoultryPaymentModel>>> GetBySale(int saleId, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetBySale(saleId, farmId));
        }

        [HttpPost]
        public async Task<ActionResult<int>> Record([FromBody] PoultryPaymentModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.Record(m);
            return Ok(new { poultryPaymentId = id });
        }
    }
}
