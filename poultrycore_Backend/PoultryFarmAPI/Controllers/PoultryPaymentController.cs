using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // Poultry customer payments (partial payments against a Sale).
    // Mirrors WaterPaymentController.
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
