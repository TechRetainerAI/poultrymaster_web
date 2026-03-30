using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class CustomerController : ControllerBase
    {
        private readonly ICustomerService _customerService;

        public CustomerController(ICustomerService customerService)
        {
            _customerService = customerService;
        }

        // GET: api/Customer?userId=xxx&farmId=xxx
        [HttpGet]
        public async Task<ActionResult<IEnumerable<CustomerModel>>> GetAll([FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId))
                return BadRequest("UserId is required.");

            if (string.IsNullOrEmpty(farmId))
                return BadRequest("FarmId is required.");

            var allCustomers = await _customerService.GetAll(userId, farmId);
            return Ok(allCustomers);
        }

        // GET: api/Customer/5?userId=xxx&farmId=xxx
        [HttpGet("{id}")]
        public async Task<ActionResult<CustomerModel>> GetById(int id, [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId))
                return BadRequest("UserId is required.");

            if (string.IsNullOrEmpty(farmId))
                return BadRequest("FarmId is required.");

            var customer = await _customerService.GetById(id, userId, farmId);
            if (customer == null) return NotFound();
            return Ok(customer);
        }

        // POST: api/Customer
        [HttpPost]
        public async Task<ActionResult<CustomerModel>> Create([FromBody] CustomerModel model)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);

            if (string.IsNullOrEmpty(model.UserId))
                return BadRequest("UserId is required in the model.");

            if (string.IsNullOrEmpty(model.FarmId))
                return BadRequest("FarmId is required in the model.");

            var newId = await _customerService.Insert(model);
            var createdRecord = await _customerService.GetById(newId, model.UserId, model.FarmId);
            return CreatedAtAction(nameof(GetById), new { id = newId, userId = model.UserId, farmId = model.FarmId }, createdRecord);
        }

        // PUT: api/Customer/5
        [HttpPut("{id}")]
        public async Task<IActionResult> Update(int id, [FromBody] CustomerModel model)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);

            if (string.IsNullOrEmpty(model.UserId))
                return BadRequest("UserId is required in the model.");

            if (string.IsNullOrEmpty(model.FarmId))
                return BadRequest("FarmId is required in the model.");

            var existing = await _customerService.GetById(id, model.UserId, model.FarmId);
            if (existing == null) return NotFound();

            model.CustomerId = id;
            await _customerService.Update(model);
            return NoContent();
        }

        // DELETE: api/Customer/5?userId=xxx&farmId=xxx
        [HttpDelete("{id}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string userId, [FromQuery] string farmId)
        {
            if (string.IsNullOrEmpty(userId))
                return BadRequest("UserId is required.");

            if (string.IsNullOrEmpty(farmId))
                return BadRequest("FarmId is required.");

            var existing = await _customerService.GetById(id, userId, farmId);
            if (existing == null) return NotFound();

            await _customerService.Delete(id, userId, farmId);
            return NoContent();
        }
    }
}
