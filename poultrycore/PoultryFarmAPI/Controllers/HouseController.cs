using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;
using System.Collections.Generic;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class HouseController : ControllerBase
    {
        private readonly IHouseService _service;

        public HouseController(IHouseService service)
        {
            _service = service;
        }

        // GET: api/House?userId=...&farmId=...
        [HttpGet]
        public ActionResult<List<HouseModel>> GetAll([FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId)) return BadRequest("UserId is required.");
            if (string.IsNullOrEmpty(farmId)) return BadRequest("FarmId is required.");
            var list = _service.GetAll(userId, farmId);
            return Ok(list);
        }

        // GET: api/House/{id}?userId=...&farmId=...
        [HttpGet("{id:int}")]
        public ActionResult<HouseModel> Get(int id, [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId)) return BadRequest("UserId is required.");
            if (string.IsNullOrEmpty(farmId)) return BadRequest("FarmId is required.");
            var item = _service.GetById(id, userId, farmId);
            if (item == null) return NotFound();
            return Ok(item);
        }

        // POST: api/House
        [HttpPost]
        public ActionResult Create([FromBody] HouseModel model)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrEmpty(model.UserId)) return BadRequest("UserId is required.");
            if (string.IsNullOrEmpty(model.FarmId)) return BadRequest("FarmId is required.");
            var id = _service.Create(model);
            var created = _service.GetById(id, model.UserId, model.FarmId);
            return CreatedAtAction(nameof(Get), new { id, userId = model.UserId, farmId = model.FarmId }, created);
        }

        // PUT: api/House/{id}
        [HttpPut("{id:int}")]
        public ActionResult Update(int id, [FromBody] HouseModel model)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrEmpty(model.UserId)) return BadRequest("UserId is required.");
            if (string.IsNullOrEmpty(model.FarmId)) return BadRequest("FarmId is required.");
            var existing = _service.GetById(id, model.UserId, model.FarmId);
            if (existing == null) return NotFound();
            model.HouseId = id;
            _service.Update(model);
            return NoContent();
        }

        // DELETE: api/House/{id}?userId=...&farmId=...
        [HttpDelete("{id:int}")]
        public ActionResult Delete(int id, [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId)) return BadRequest("UserId is required.");
            if (string.IsNullOrEmpty(farmId)) return BadRequest("FarmId is required.");
            var existing = _service.GetById(id, userId, farmId);
            if (existing == null) return NotFound();
            _service.Delete(id, userId, farmId);
            return NoContent();
        }
    }
}
