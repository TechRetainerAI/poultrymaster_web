using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;
using PoultryFarmAPIWeb.Filters;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/generic-company/{farmId}/production-records")]
    [Authorize]
    public class GenericProductionRecordController : ControllerBase
    {
        private readonly IGenericProductionRecordService _service;

        public GenericProductionRecordController(IGenericProductionRecordService service)
        {
            _service = service;
        }

        [HttpGet]
        public async Task<IActionResult> GetAll(string farmId, [FromQuery] string? status = null)
        {
            var records = await _service.GetAllAsync(farmId, status);
            return Ok(records);
        }

        [HttpPost]
        public async Task<IActionResult> Create(string farmId, [FromBody] GenericProductionRecordCreateInput input)
        {
            var userId = User.FindFirst("sub")?.Value ?? User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;

            var model = new GenericProductionRecordModel
            {
                FarmId = farmId,
                GenericProductId = input.GenericProductId,
                QuantityProduced = input.QuantityProduced,
                ProductionDate = input.ProductionDate ?? DateTime.UtcNow,
                UnitCost = input.UnitCost,
                BatchNumber = input.BatchNumber,
                MaterialsUsed = input.MaterialsUsed,
                Notes = input.Notes,
                CreatedBy = userId,
            };

            var id = await _service.InsertAsync(model);
            return Ok(new { genericProductionRecordId = id });
        }

        [HttpPost("{id}/reverse")]
        public async Task<IActionResult> Reverse(string farmId, int id, [FromBody] GenericProductionRecordReverseInput input)
        {
            var userId = User.FindFirst("sub")?.Value ?? User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;
            await _service.ReverseAsync(id, farmId, input.Reason, input.ReversedBy ?? userId);
            return NoContent();
        }
    }
}
