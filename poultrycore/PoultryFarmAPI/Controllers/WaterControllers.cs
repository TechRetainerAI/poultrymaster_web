using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // =========================================================================
    // Products
    // =========================================================================
    [ApiController]
    [Route("api/Water/products")]
    public class WaterProductController : ControllerBase
    {
        private readonly IWaterProductService _svc;
        public WaterProductController(IWaterProductService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<WaterProductModel>>> GetAll([FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("FarmId is required.");
            return Ok(await _svc.GetAll(farmId));
        }

        [HttpGet("{id:int}")]
        public async Task<ActionResult<WaterProductModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("FarmId is required.");
            var model = await _svc.GetById(id, farmId);
            return model is null ? NotFound() : Ok(model);
        }

        [HttpPost]
        public async Task<ActionResult<WaterProductModel>> Create([FromBody] WaterProductModel model)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(model.FarmId)) return BadRequest("FarmId is required.");
            var newId = await _svc.Insert(model);
            var created = await _svc.GetById(newId, model.FarmId);
            return CreatedAtAction(nameof(GetById), new { id = newId, farmId = model.FarmId }, created);
        }

        [HttpPut("{id:int}")]
        public async Task<IActionResult> Update(int id, [FromBody] WaterProductModel model)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(model.FarmId)) return BadRequest("FarmId is required.");
            var existing = await _svc.GetById(id, model.FarmId);
            if (existing is null) return NotFound();
            model.WaterProductId = id;
            await _svc.Update(model);
            return NoContent();
        }

        [HttpDelete("{id:int}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("FarmId is required.");
            await _svc.Delete(id, farmId);
            return NoContent();
        }
    }

    // =========================================================================
    // Customers
    // =========================================================================
    [ApiController]
    [Route("api/Water/customers")]
    public class WaterCustomerController : ControllerBase
    {
        private readonly IWaterCustomerService _svc;
        public WaterCustomerController(IWaterCustomerService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<WaterCustomerModel>>> GetAll([FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("FarmId is required.");
            return Ok(await _svc.GetAll(farmId));
        }

        [HttpGet("{id:int}")]
        public async Task<ActionResult<WaterCustomerModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("FarmId is required.");
            var c = await _svc.GetById(id, farmId);
            return c is null ? NotFound() : Ok(c);
        }

        [HttpPost]
        public async Task<ActionResult<WaterCustomerModel>> Create([FromBody] WaterCustomerModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("FarmId is required.");
            var newId = await _svc.Insert(m);
            var created = await _svc.GetById(newId, m.FarmId);
            return CreatedAtAction(nameof(GetById), new { id = newId, farmId = m.FarmId }, created);
        }

        [HttpPut("{id:int}")]
        public async Task<IActionResult> Update(int id, [FromBody] WaterCustomerModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("FarmId is required.");
            var existing = await _svc.GetById(id, m.FarmId);
            if (existing is null) return NotFound();
            m.WaterCustomerId = id;
            await _svc.Update(m);
            return NoContent();
        }

        [HttpDelete("{id:int}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("FarmId is required.");
            await _svc.Delete(id, farmId);
            return NoContent();
        }
    }

    // =========================================================================
    // Stock transactions
    // =========================================================================
    [ApiController]
    [Route("api/Water/stock")]
    public class WaterStockController : ControllerBase
    {
        private readonly IWaterStockService _svc;
        public WaterStockController(IWaterStockService svc) => _svc = svc;

        [HttpGet("transactions")]
        public async Task<ActionResult<IEnumerable<WaterStockTransactionModel>>> Transactions(
            [FromQuery] string farmId, [FromQuery] int? productId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("FarmId is required.");
            return Ok(await _svc.GetTransactions(farmId, productId));
        }

        [HttpPost("transactions")]
        public async Task<ActionResult<int>> AddTransaction([FromBody] WaterStockTransactionModel model)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(model.FarmId)) return BadRequest("FarmId is required.");
            if (model.TxnType is not ("Restock" or "Adjust" or "Return"))
                return BadRequest("TxnType must be Restock, Adjust, or Return. Sale txns are created by spWaterSale_Create.");
            var id = await _svc.AddTransaction(model);
            return Ok(new { stockTxnId = id });
        }
    }

    // =========================================================================
    // Sales
    // =========================================================================
    [ApiController]
    [Route("api/Water/sales")]
    public class WaterSaleController : ControllerBase
    {
        private readonly IWaterSaleService _svc;
        public WaterSaleController(IWaterSaleService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<WaterSaleModel>>> GetAll([FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("FarmId is required.");
            return Ok(await _svc.GetAll(farmId));
        }

        [HttpGet("{id:int}")]
        public async Task<ActionResult<WaterSaleModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("FarmId is required.");
            var sale = await _svc.GetById(id, farmId);
            return sale is null ? NotFound() : Ok(sale);
        }

        [HttpPost]
        public async Task<ActionResult<WaterSaleModel>> Create([FromBody] CreateWaterSaleRequest req)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("FarmId is required.");
            if (req.Items is null || req.Items.Count == 0) return BadRequest("At least one item is required.");

            var newId = await _svc.Create(req);
            var sale = await _svc.GetById(newId, req.FarmId);
            return CreatedAtAction(nameof(GetById), new { id = newId, farmId = req.FarmId }, sale);
        }

        [HttpPost("{id:int}/cancel")]
        public async Task<IActionResult> Cancel(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("FarmId is required.");
            await _svc.Cancel(id, farmId);
            return NoContent();
        }
    }

    // =========================================================================
    // Payments
    // =========================================================================
    [ApiController]
    [Route("api/Water/payments")]
    public class WaterPaymentController : ControllerBase
    {
        private readonly IWaterPaymentService _svc;
        public WaterPaymentController(IWaterPaymentService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<WaterPaymentModel>>> GetAll([FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("FarmId is required.");
            return Ok(await _svc.GetAll(farmId));
        }

        [HttpGet("by-sale/{saleId:int}")]
        public async Task<ActionResult<IEnumerable<WaterPaymentModel>>> GetBySale(int saleId, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("FarmId is required.");
            return Ok(await _svc.GetBySale(saleId, farmId));
        }

        [HttpPost]
        public async Task<ActionResult<int>> Record([FromBody] WaterPaymentModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("FarmId is required.");
            var id = await _svc.Record(m);
            return Ok(new { waterPaymentId = id });
        }
    }

    // =========================================================================
    // Dashboard
    // =========================================================================
    [ApiController]
    [Route("api/Water/dashboard")]
    public class WaterDashboardController : ControllerBase
    {
        private readonly IWaterDashboardService _svc;
        public WaterDashboardController(IWaterDashboardService svc) => _svc = svc;

        [HttpGet("summary")]
        public async Task<ActionResult<WaterDashboardSummaryModel>> Summary([FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("FarmId is required.");
            return Ok(await _svc.GetSummary(farmId));
        }
    }
}
