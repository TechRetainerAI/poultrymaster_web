using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // =========================================================================
    // Phase W1 controllers — boreholes, machines, production batches,
    // quality tests, daily pumping logs.
    // Same FarmId-from-query pattern as the existing WaterControllers.cs.
    // =========================================================================

    [ApiController]
    [Route("api/Water/boreholes")]
    public class WaterBoreholeController : ControllerBase
    {
        private readonly IWaterBoreholeService _svc;
        public WaterBoreholeController(IWaterBoreholeService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<WaterBoreholeModel>>> GetAll([FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetAllAsync(farmId));
        }

        [HttpGet("{id:int}")]
        public async Task<ActionResult<WaterBoreholeModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var m = await _svc.GetByIdAsync(id, farmId);
            return m is null ? NotFound() : Ok(m);
        }

        [HttpPost]
        public async Task<ActionResult<WaterBoreholeModel>> Create([FromBody] WaterBoreholeModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.InsertAsync(m);
            var created = await _svc.GetByIdAsync(id, m.FarmId);
            return CreatedAtAction(nameof(GetById), new { id, farmId = m.FarmId }, created);
        }

        [HttpPut("{id:int}")]
        public async Task<IActionResult> Update(int id, [FromBody] WaterBoreholeModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            m.WaterBoreholeId = id;
            await _svc.UpdateAsync(m);
            return NoContent();
        }

        [HttpDelete("{id:int}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.DeleteAsync(id, farmId);
            return NoContent();
        }
    }

    [ApiController]
    [Route("api/Water/machines")]
    public class WaterMachineController : ControllerBase
    {
        private readonly IWaterMachineService _svc;
        public WaterMachineController(IWaterMachineService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<WaterMachineModel>>> GetAll([FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetAllAsync(farmId));
        }

        [HttpGet("{id:int}")]
        public async Task<ActionResult<WaterMachineModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var m = await _svc.GetByIdAsync(id, farmId);
            return m is null ? NotFound() : Ok(m);
        }

        [HttpPost]
        public async Task<ActionResult<WaterMachineModel>> Create([FromBody] WaterMachineModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.InsertAsync(m);
            var created = await _svc.GetByIdAsync(id, m.FarmId);
            return CreatedAtAction(nameof(GetById), new { id, farmId = m.FarmId }, created);
        }

        [HttpPut("{id:int}")]
        public async Task<IActionResult> Update(int id, [FromBody] WaterMachineModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            m.WaterMachineId = id;
            await _svc.UpdateAsync(m);
            return NoContent();
        }

        [HttpDelete("{id:int}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.DeleteAsync(id, farmId);
            return NoContent();
        }
    }

    [ApiController]
    [Route("api/Water/production-batches")]
    public class WaterProductionBatchController : ControllerBase
    {
        private readonly IWaterProductionBatchService _svc;
        public WaterProductionBatchController(IWaterProductionBatchService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<WaterProductionBatchModel>>> GetAll(
            [FromQuery] string farmId,
            [FromQuery] string? status,
            [FromQuery] DateTime? fromDate,
            [FromQuery] DateTime? toDate)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetAllAsync(farmId, status, fromDate, toDate));
        }

        [HttpGet("{id:int}")]
        public async Task<ActionResult<WaterProductionBatchModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var m = await _svc.GetByIdAsync(id, farmId);
            return m is null ? NotFound() : Ok(m);
        }

        [HttpPost]
        public async Task<ActionResult<WaterProductionBatchModel>> Create([FromBody] WaterProductionBatchModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.InsertAsync(m);
            var created = await _svc.GetByIdAsync(id, m.FarmId);
            return CreatedAtAction(nameof(GetById), new { id, farmId = m.FarmId }, created);
        }

        [HttpPut("{id:int}")]
        public async Task<IActionResult> Update(int id, [FromBody] WaterProductionBatchModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            m.WaterProductionBatchId = id;
            await _svc.UpdateAsync(m);
            return NoContent();
        }

        [HttpPost("{id:int}/approve")]
        public async Task<IActionResult> Approve(int id, [FromQuery] string farmId, [FromQuery] string? approvedBy)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.ApproveAsync(id, farmId, approvedBy);
            return NoContent();
        }

        [HttpPost("{id:int}/cancel")]
        public async Task<IActionResult> Cancel(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.CancelAsync(id, farmId);
            return NoContent();
        }

        [HttpPost("{id:int}/reopen")]
        public async Task<IActionResult> Reopen(int id, [FromQuery] string farmId, [FromQuery] string? reopenedBy)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.ReopenAsync(id, farmId, reopenedBy);
            return NoContent();
        }

        // Migration 063: list the raw materials consumed for this batch so the
        // edit modal can re-render them on reopen and the receipt view can show
        // them on detail.
        [HttpGet("{id:int}/materials")]
        public async Task<ActionResult<IEnumerable<WaterProductionMaterialUsageRow>>> GetMaterials(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetMaterialsUsedAsync(id, farmId));
        }

        // Migration 067 — Details view: linked loss records, expenses, stock txns.
        [HttpGet("{id:int}/linked-losses")]
        public async Task<ActionResult<IEnumerable<WaterProductionLossModel>>> GetLinkedLosses(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetLinkedLossesAsync(id, farmId));
        }

        [HttpGet("{id:int}/linked-expenses")]
        public async Task<ActionResult<IEnumerable<WaterProductionLinkedExpenseRow>>> GetLinkedExpenses(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetLinkedExpensesAsync(id, farmId));
        }

        [HttpGet("{id:int}/linked-stock-txns")]
        public async Task<ActionResult<IEnumerable<WaterProductionLinkedStockTxnRow>>> GetLinkedStockTxns(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetLinkedStockTxnsAsync(id, farmId));
        }
    }

    // =========================================================================
    // Production Losses (Migration 067) — standalone Loss page.
    // =========================================================================
    [ApiController]
    [Route("api/Water/production-losses")]
    public class WaterProductionLossController : ControllerBase
    {
        private readonly IWaterProductionLossService _svc;
        public WaterProductionLossController(IWaterProductionLossService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<WaterProductionLossModel>>> GetAll(
            [FromQuery] string farmId,
            [FromQuery] DateTime? fromDate,
            [FromQuery] DateTime? toDate,
            [FromQuery] string? status)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetAllAsync(farmId, fromDate, toDate, status));
        }
    }

    // =========================================================================
    // Production Recipes — per-finished-product bill of materials.
    // Route shape matches the prompt: /products/{productId}/recipe
    // =========================================================================
    [ApiController]
    [Route("api/Water/products/{productId:int}/recipe")]
    public class WaterProductionRecipeController : ControllerBase
    {
        private readonly IWaterProductionRecipeService _svc;
        public WaterProductionRecipeController(IWaterProductionRecipeService svc) => _svc = svc;

        // Returns 200 with the recipe object, or 200 with null when the product
        // has no recipe yet (frontend treats null as "set one up").
        [HttpGet]
        public async Task<ActionResult<WaterProductionRecipeModel?>> Get(int productId, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var recipe = await _svc.GetByProductAsync(farmId, productId);
            return Ok(recipe);
        }

        [HttpPut]
        public async Task<ActionResult<int>> Upsert(int productId, [FromQuery] string farmId, [FromQuery] string? updatedBy,
            [FromBody] WaterProductionRecipeUpsertRequest req)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var id = await _svc.UpsertAsync(farmId, productId, req, updatedBy);
            return Ok(new { WaterProductionRecipeId = id });
        }

        [HttpDelete("{recipeId:int}")]
        public async Task<IActionResult> Delete(int productId, int recipeId, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.DeleteAsync(farmId, recipeId);
            return NoContent();
        }
    }

    // =========================================================================
    // Raw-material usage history endpoint — backs the Usage History tab on
    // the Raw Materials page. The legacy /raw-material-usage endpoint exists
    // but only filters by batchId/date; this one supports itemId too.
    // =========================================================================
    [ApiController]
    [Route("api/Water/raw-material-usage/history")]
    public class WaterRawMaterialUsageHistoryController : ControllerBase
    {
        private readonly IWaterProductionRecipeService _svc;
        public WaterRawMaterialUsageHistoryController(IWaterProductionRecipeService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<WaterProductionMaterialUsageRow>>> Get(
            [FromQuery] string farmId,
            [FromQuery] int? itemId,
            [FromQuery] DateTime? fromDate,
            [FromQuery] DateTime? toDate)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetUsageHistoryAsync(farmId, itemId, fromDate, toDate));
        }
    }

    [ApiController]
    [Route("api/Water/quality-tests")]
    public class WaterQualityTestController : ControllerBase
    {
        private readonly IWaterQualityTestService _svc;
        public WaterQualityTestController(IWaterQualityTestService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<WaterQualityTestModel>>> GetAll(
            [FromQuery] string farmId,
            [FromQuery] int? boreholeId,
            [FromQuery] int? batchId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetAllAsync(farmId, boreholeId, batchId));
        }

        [HttpPost]
        public async Task<ActionResult<int>> Create([FromBody] WaterQualityTestModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.InsertAsync(m);
            return Ok(new { WaterQualityTestId = id });
        }
    }

    [ApiController]
    [Route("api/Water/pumping-logs")]
    public class WaterDailyPumpingLogController : ControllerBase
    {
        private readonly IWaterDailyPumpingLogService _svc;
        public WaterDailyPumpingLogController(IWaterDailyPumpingLogService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<WaterDailyPumpingLogModel>>> GetAll(
            [FromQuery] string farmId,
            [FromQuery] DateTime? fromDate,
            [FromQuery] DateTime? toDate)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetAllAsync(farmId, fromDate, toDate));
        }

        [HttpPost]
        public async Task<ActionResult<int>> Create([FromBody] WaterDailyPumpingLogModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.InsertAsync(m);
            return Ok(new { WaterDailyPumpingLogId = id });
        }
    }
}
