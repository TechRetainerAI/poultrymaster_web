using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class FarmObservationController : ControllerBase
    {
        private readonly IFarmObservationService _service;

        public FarmObservationController(IFarmObservationService service)
        {
            _service = service;
        }

        // GET: api/FarmObservation?farmId=xxx
        [HttpGet]
        public async Task<ActionResult<IEnumerable<FarmObservationModel>>> GetAll([FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(farmId)) return BadRequest("FarmId is required.");
            return Ok(await _service.GetAll(farmId));
        }

        // GET: api/FarmObservation/by-week?farmId=xxx&weekStartDate=2026-05-11
        [HttpGet("by-week")]
        public async Task<ActionResult<FarmObservationModel?>> GetByWeek([FromQuery] string farmId, [FromQuery] DateTime weekStartDate)
        {
            if (string.IsNullOrEmpty(farmId)) return BadRequest("FarmId is required.");
            var row = await _service.GetByWeek(farmId, weekStartDate);
            return Ok(row); // null is a valid "no notes yet" response
        }

        // POST: api/FarmObservation  — upsert (insert or update by FarmId + WeekStartDate)
        [HttpPost]
        public async Task<ActionResult<FarmObservationModel?>> Upsert([FromBody] FarmObservationModel model)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrEmpty(model.FarmId)) return BadRequest("FarmId is required.");
            if (model.WeekStartDate == default) return BadRequest("WeekStartDate is required.");

            var saved = await _service.Upsert(model);
            return Ok(saved);
        }
    }
}
