using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // Poultry products / stock / recipes / batches / losses / daily-closing controllers.
    // Additive; routes under /api/Poultry/*. Mirrors the Water production controllers.

    [ApiController]
    [Route("api/Poultry/products")]
    public class PoultryProductController : ControllerBase
    {
        private readonly IPoultryProductService _svc;
        private readonly IPoultryProductionRecipeService _recipes;
        public PoultryProductController(IPoultryProductService svc, IPoultryProductionRecipeService recipes) { _svc = svc; _recipes = recipes; }

        [HttpGet] public async Task<ActionResult<IEnumerable<PoultryProductModel>>> GetAll([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetAllAsync(farmId));

        [HttpGet("{id:int}")] public async Task<ActionResult<PoultryProductModel>> GetById(int id, [FromQuery] string farmId)
        { if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required."); var m = await _svc.GetByIdAsync(id, farmId); return m is null ? NotFound() : Ok(m); }

        [HttpPost] public async Task<ActionResult<PoultryProductModel>> Create([FromBody] PoultryProductModel m)
        { if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required."); var id = await _svc.InsertAsync(m); return CreatedAtAction(nameof(GetById), new { id, farmId = m.FarmId }, await _svc.GetByIdAsync(id, m.FarmId)); }

        [HttpPut("{id:int}")] public async Task<IActionResult> Update(int id, [FromBody] PoultryProductModel m)
        { if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required."); m.PoultryProductId = id; await _svc.UpdateAsync(m); return NoContent(); }

        [HttpDelete("{id:int}")] public async Task<IActionResult> Delete(int id, [FromQuery] string farmId)
        { if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required."); await _svc.DeleteAsync(id, farmId); return NoContent(); }

        // Recipe (bill of materials) for a product.
        [HttpGet("{id:int}/recipe")] public async Task<ActionResult<PoultryProductionRecipeModel>> GetRecipe(int id, [FromQuery] string farmId)
        { if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required."); var r = await _recipes.GetByProductAsync(farmId, id); return r is null ? Ok(null) : Ok(r); }

        [HttpPut("{id:int}/recipe")] public async Task<IActionResult> UpsertRecipe(int id, [FromBody] PoultryProductionRecipeUpsertRequest req)
        { if (string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required."); var rid = await _recipes.UpsertAsync(req.FarmId, id, req); return Ok(new { poultryProductionRecipeId = rid }); }

        [HttpDelete("{id:int}/recipe/{recipeId:int}")] public async Task<IActionResult> DeleteRecipe(int id, int recipeId, [FromQuery] string farmId)
        { if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required."); await _recipes.DeleteAsync(farmId, recipeId); return NoContent(); }
    }

    [ApiController]
    [Route("api/Poultry/stock")]
    public class PoultryStockController : ControllerBase
    {
        private readonly IPoultryStockService _svc;
        public PoultryStockController(IPoultryStockService svc) => _svc = svc;

        [HttpGet("transactions")] public async Task<ActionResult<IEnumerable<PoultryStockTransactionModel>>> GetTransactions([FromQuery] string farmId, [FromQuery] int? productId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetTransactionsAsync(farmId, productId));

        [HttpPost("transactions")] public async Task<ActionResult<int>> AddTransaction([FromBody] PoultryStockTransactionModel m)
        { if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required."); var id = await _svc.AddTransactionAsync(m); return Ok(new { poultryStockTransactionId = id }); }
    }

    [ApiController]
    [Route("api/Poultry/production-batches")]
    public class PoultryProductionBatchController : ControllerBase
    {
        private readonly IPoultryProductionBatchService _svc;
        public PoultryProductionBatchController(IPoultryProductionBatchService svc) => _svc = svc;

        [HttpGet] public async Task<ActionResult<IEnumerable<PoultryProductionBatchModel>>> GetAll([FromQuery] string farmId, [FromQuery] string? status, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetAllAsync(farmId, status, fromDate, toDate));

        [HttpGet("{id:int}/materials")] public async Task<ActionResult<IEnumerable<PoultryProductionMaterialUsageInput>>> GetMaterials(int id, [FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetMaterialsAsync(farmId, id));

        [HttpPost] public async Task<ActionResult<int>> Create([FromBody] PoultryProductionBatchModel m)
        { if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required."); var id = await _svc.InsertAsync(m); return Ok(new { poultryProductionBatchId = id }); }

        [HttpPut("{id:int}")] public async Task<IActionResult> Update(int id, [FromBody] PoultryProductionBatchModel m)
        { if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required."); m.PoultryProductionBatchId = id; await _svc.UpdateAsync(m); return NoContent(); }

        [HttpPost("{id:int}/approve")] public async Task<IActionResult> Approve(int id, [FromQuery] string farmId, [FromQuery] string? approvedBy)
        { if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required."); await _svc.ApproveAsync(id, farmId, approvedBy); return NoContent(); }

        [HttpPost("{id:int}/cancel")] public async Task<IActionResult> Cancel(int id, [FromQuery] string farmId)
        { if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required."); await _svc.CancelAsync(id, farmId); return NoContent(); }
    }

    [ApiController]
    [Route("api/Poultry/production-losses")]
    public class PoultryProductionLossController : ControllerBase
    {
        private readonly IPoultryProductionBatchService _svc;
        public PoultryProductionLossController(IPoultryProductionBatchService svc) => _svc = svc;

        [HttpGet] public async Task<ActionResult<IEnumerable<PoultryProductionLossModel>>> GetAll([FromQuery] string farmId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetProductionLossesAsync(farmId, fromDate, toDate));
    }

    [ApiController]
    [Route("api/Poultry/loss-records")]
    public class PoultryLossRecordController : ControllerBase
    {
        private readonly IPoultryLossRecordService _svc;
        public PoultryLossRecordController(IPoultryLossRecordService svc) => _svc = svc;

        [HttpGet] public async Task<ActionResult<IEnumerable<PoultryLossRecordModel>>> GetAll([FromQuery] string farmId, [FromQuery] string? lossType, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetAllAsync(farmId, lossType, fromDate, toDate));

        [HttpPost] public async Task<ActionResult<int>> Create([FromBody] PoultryLossRecordModel m)
        { if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required."); var id = await _svc.InsertAsync(m); return Ok(new { poultryLossRecordId = id }); }

        [HttpPut("{id:int}")] public async Task<IActionResult> Update(int id, [FromBody] PoultryLossRecordModel m)
        { if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required."); m.PoultryLossRecordId = id; await _svc.UpdateAsync(m); return NoContent(); }

        [HttpPost("{id:int}/approve")] public async Task<IActionResult> Approve(int id, [FromQuery] string farmId, [FromQuery] string? approvedBy)
        { if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required."); await _svc.ApproveAsync(id, farmId, approvedBy); return NoContent(); }

        [HttpPost("{id:int}/unapprove")] public async Task<IActionResult> Unapprove(int id, [FromQuery] string farmId)
        { if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required."); await _svc.UnapproveAsync(id, farmId); return NoContent(); }

        [HttpDelete("{id:int}")] public async Task<IActionResult> Delete(int id, [FromQuery] string farmId)
        { if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required."); await _svc.DeleteAsync(id, farmId); return NoContent(); }
    }

    [ApiController]
    [Route("api/Poultry/daily-closings")]
    public class PoultryDailyClosingController : ControllerBase
    {
        private readonly IPoultryDailyClosingService _svc;
        public PoultryDailyClosingController(IPoultryDailyClosingService svc) => _svc = svc;

        [HttpGet] public async Task<ActionResult<IEnumerable<PoultryDailyClosingModel>>> GetAll([FromQuery] string farmId, [FromQuery] string? status, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetAllAsync(farmId, status, fromDate, toDate));

        [HttpGet("{id:int}")] public async Task<ActionResult<PoultryDailyClosingModel>> GetById(int id, [FromQuery] string farmId)
        { if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required."); var m = await _svc.GetByIdAsync(id, farmId); return m is null ? NotFound() : Ok(m); }

        [HttpPost] public async Task<ActionResult<int>> Create([FromBody] PoultryDailyClosingCreateRequest req)
        { if (string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required."); var id = await _svc.InsertAsync(req.FarmId, req.ClosingDate, req.ManagerNotes, req.CreatedBy); return Ok(new { poultryDailyClosingId = id }); }

        [HttpPost("{id:int}/submit")] public async Task<IActionResult> Submit(int id, [FromBody] PoultryDailyClosingSubmitRequest req)
        { if (string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required."); await _svc.SubmitAsync(id, req); return NoContent(); }

        [HttpPost("{id:int}/approve")] public async Task<IActionResult> Approve(int id, [FromQuery] string farmId, [FromQuery] string? approvedBy)
        { if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required."); await _svc.ApproveAsync(id, farmId, approvedBy); return NoContent(); }

        [HttpPost("{id:int}/reject")] public async Task<IActionResult> Reject(int id, [FromQuery] string farmId, [FromQuery] string? reason)
        { if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required."); await _svc.RejectAsync(id, farmId, reason); return NoContent(); }

        [HttpDelete("{id:int}")] public async Task<IActionResult> Delete(int id, [FromQuery] string farmId)
        { if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required."); await _svc.DeleteAsync(id, farmId); return NoContent(); }
    }

    public class PoultryDailyClosingCreateRequest
    {
        public string FarmId { get; set; } = string.Empty;
        public DateTime ClosingDate { get; set; }
        public string? ManagerNotes { get; set; }
        public string? CreatedBy { get; set; }
    }
}
