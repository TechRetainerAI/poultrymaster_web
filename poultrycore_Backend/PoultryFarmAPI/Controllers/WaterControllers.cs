using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Filters;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // =========================================================================
    // Products
    // =========================================================================
    [PoultryFarmAPIWeb.Filters.SetupAdminOnly]
    [ApiController]
    [Route("api/Water/products")]
    [RequireCompanyType("Water")]
    public class WaterProductController : ControllerBase
    {
        private readonly IWaterProductService _svc;
        public WaterProductController(IWaterProductService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<WaterProductModel>>> GetAll([FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetAll(farmId));
        }

        [HttpGet("{id:int}")]
        public async Task<ActionResult<WaterProductModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var model = await _svc.GetById(id, farmId);
            return model is null ? NotFound() : Ok(model);
        }

        // Reconcile finished-product stock from the transaction ledger (in/out
        // breakdown). Read-only: finished stock is derived, not stored.
        [HttpGet("reconcile-stock")]
        public async Task<ActionResult<IEnumerable<ProductReconcileRow>>> ReconcileStock([FromQuery] string farmId, [FromQuery] int? productId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.ReconcileStockAsync(farmId, productId));

        // Set a finished product's stock to a physical count (writes a correcting
        // Adjust transaction for the difference).
        [PoultryFarmAPIWeb.Filters.AllowStaffSetupWrite]
        [HttpPost("{id:int}/set-stock")]
        public async Task<ActionResult<object>> SetStock(int id, [FromBody] ProductSetStockRequest body)
        {
            if (body is null || string.IsNullOrWhiteSpace(body.FarmId)) return BadRequest("Company ID is required.");
            if (body.TargetQuantity < 0) return BadRequest("Count cannot be negative.");
            var current = await _svc.SetStockAsync(id, body);
            return Ok(new { CurrentStock = current });
        }

        [HttpPost]
        public async Task<ActionResult<WaterProductModel>> Create([FromBody] WaterProductModel model)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(model.FarmId)) return BadRequest("Company ID is required.");
            var newId = await _svc.Insert(model);
            var created = await _svc.GetById(newId, model.FarmId);
            return CreatedAtAction(nameof(GetById), new { id = newId, farmId = model.FarmId }, created);
        }

        [HttpPut("{id:int}")]
        public async Task<IActionResult> Update(int id, [FromBody] WaterProductModel model)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(model.FarmId)) return BadRequest("Company ID is required.");
            var existing = await _svc.GetById(id, model.FarmId);
            if (existing is null) return NotFound();
            model.WaterProductId = id;
            await _svc.Update(model);
            return NoContent();
        }

        [HttpDelete("{id:int}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.Delete(id, farmId);
            return NoContent();
        }
    }

    // =========================================================================
    // Customers
    // =========================================================================
    [PoultryFarmAPIWeb.Filters.SetupAdminOnly]
    [ApiController]
    [Route("api/Water/customers")]
    [RequireCompanyType("Water")]
    public class WaterCustomerController : ControllerBase
    {
        private readonly IWaterCustomerService _svc;
        public WaterCustomerController(IWaterCustomerService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<WaterCustomerModel>>> GetAll([FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetAll(farmId));
        }

        [HttpGet("{id:int}")]
        public async Task<ActionResult<WaterCustomerModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var c = await _svc.GetById(id, farmId);
            return c is null ? NotFound() : Ok(c);
        }

        [PoultryFarmAPIWeb.Filters.AllowStaffSetupWrite]
        [HttpPost]
        public async Task<ActionResult<WaterCustomerModel>> Create([FromBody] WaterCustomerModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            var newId = await _svc.Insert(m);
            var created = await _svc.GetById(newId, m.FarmId);
            return CreatedAtAction(nameof(GetById), new { id = newId, farmId = m.FarmId }, created);
        }

        [HttpPut("{id:int}")]
        public async Task<IActionResult> Update(int id, [FromBody] WaterCustomerModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            var existing = await _svc.GetById(id, m.FarmId);
            if (existing is null) return NotFound();
            m.WaterCustomerId = id;
            await _svc.Update(m);
            return NoContent();
        }

        [HttpDelete("{id:int}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.Delete(id, farmId);
            return NoContent();
        }

        // Migration 082 — POST /Water/customers/create-defaults
        // Idempotently creates GeneralSales / GeneralDelivery / GeneralCredit
        // for the active farm. Returns 200 with one row per default type
        // (wasCreated=false on rows that already existed).
        [HttpPost("create-defaults")]
        public async Task<ActionResult<IEnumerable<WaterDefaultCustomerResult>>> CreateDefaults(
            [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var rows = await _svc.CreateDefaultsAsync(farmId);
            return Ok(rows);
        }
    }

    // =========================================================================
    // Stock transactions
    // =========================================================================
    [ApiController]
    [Route("api/Water/stock")]
    [RequireCompanyType("Water")]
    public class WaterStockController : ControllerBase
    {
        private readonly IWaterStockService _svc;
        public WaterStockController(IWaterStockService svc) => _svc = svc;

        [HttpGet("transactions")]
        public async Task<ActionResult<IEnumerable<WaterStockTransactionModel>>> Transactions(
            [FromQuery] string farmId, [FromQuery] int? productId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetTransactions(farmId, productId));
        }

        [HttpPost("transactions")]
        public async Task<ActionResult<int>> AddTransaction([FromBody] WaterStockTransactionModel model)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(model.FarmId)) return BadRequest("Company ID is required.");
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
    [RequireCompanyType("Water")]
    public class WaterSaleController : ControllerBase
    {
        private readonly IWaterSaleService _svc;
        public WaterSaleController(IWaterSaleService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<WaterSaleModel>>> GetAll([FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetAll(farmId));
        }

        [HttpGet("{id:int}")]
        public async Task<ActionResult<WaterSaleModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var sale = await _svc.GetById(id, farmId);
            return sale is null ? NotFound() : Ok(sale);
        }

        [HttpPost]
        public async Task<ActionResult<WaterSaleModel>> Create([FromBody] CreateWaterSaleRequest req)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest("Company ID is required.");
            if (req.Items is null || req.Items.Count == 0) return BadRequest("At least one item is required.");

            int newId;
            try { newId = await _svc.Create(req); }
            catch (SaleRuleException ex) { return BadRequest(new { message = ex.Message }); }
            var sale = await _svc.GetById(newId, req.FarmId);
            return CreatedAtAction(nameof(GetById), new { id = newId, farmId = req.FarmId }, sale);
        }

        // 458: Cancel and Delete are refused by the database -- a saved sale is
        // reversed (POST {id}/reverse). Kept so old clients get the reason.
        [HttpPost("{id:int}/cancel")]
        public async Task<IActionResult> Cancel(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            try { await _svc.Cancel(id, farmId); }
            catch (Npgsql.PostgresException ex) when (ex.SqlState == "P0001") { return Conflict(new { message = ex.MessageText }); }
            return NoContent();
        }

        [HttpDelete("{id:int}")]
        public async Task<IActionResult> Delete(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            try { await _svc.Delete(id, farmId); }
            catch (Npgsql.PostgresException ex) when (ex.SqlState == "P0001") { return Conflict(new { message = ex.MessageText }); }
            return NoContent();
        }

        // GET api/Water/sales/5/reversal-preview?farmId=  -- what reversing it would do.
        [HttpGet("{id:int}/reversal-preview")]
        public async Task<IActionResult> ReversalPreview(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest(new { message = "Company ID is required." });
            return Content(await _svc.GetReversalPreview(id, farmId), "application/json");
        }

        // GET api/Water/sales/5/reversal?farmId=  -- the reversal of a reversed sale.
        [HttpGet("{id:int}/reversal")]
        public async Task<IActionResult> Reversal(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest(new { message = "Company ID is required." });
            var json = await _svc.GetReversal(id, farmId);
            return json is null ? NotFound(new { message = "This sale has not been reversed." }) : Content(json, "application/json");
        }

        // POST api/Water/sales/5/reverse  -- resolves to water.sales.approve.
        [HttpPost("{id:int}/reverse")]
        public async Task<IActionResult> Reverse(int id, [FromBody] SaleReverseRequest req)
        {
            if (req is null || string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest(new { message = "Company ID is required." });
            if (string.IsNullOrWhiteSpace(req.ReasonCode) && string.IsNullOrWhiteSpace(req.Reason))
                return BadRequest(new { message = "Give a reason for reversing this sale." });
            // The person on the token, not whatever the body claims.
            req.UserId = User?.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value ?? req.UserId;
            try
            {
                var reversalId = await _svc.Reverse(id, req);
                var j = await _svc.GetReversal(id, req.FarmId);
                return Ok(new { salereversalid = reversalId,
                                reversal = j is null ? (System.Text.Json.JsonElement?)null : System.Text.Json.JsonDocument.Parse(j).RootElement });
            }
            catch (SaleRuleException ex) when (ex.Stale)
            {
                return Conflict(new { message = ex.Message, stale = true });
            }
            catch (SaleRuleException ex)
            {
                return BadRequest(new { message = ex.Message });
            }
        }
    }

    // =========================================================================
    // Payments
    // =========================================================================
    [ApiController]
    [Route("api/Water/payments")]
    [RequireCompanyType("Water")]
    public class WaterPaymentController : ControllerBase
    {
        private readonly IWaterPaymentService _svc;
        public WaterPaymentController(IWaterPaymentService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<WaterPaymentModel>>> GetAll([FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetAll(farmId));
        }

        [HttpGet("by-sale/{saleId:int}")]
        public async Task<ActionResult<IEnumerable<WaterPaymentModel>>> GetBySale(int saleId, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Ok(await _svc.GetBySale(saleId, farmId));
        }

        [HttpPost]
        public async Task<ActionResult<int>> Record([FromBody] WaterPaymentModel m)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.Record(m);
            return Ok(new { waterPaymentId = id });
        }
    }

    // =========================================================================
    // Dashboard
    // =========================================================================
    [ApiController]
    [Route("api/Water/dashboard")]
    [RequireCompanyType("Water")]
    public class WaterDashboardController : ControllerBase
    {
        private readonly IWaterDashboardService _svc;
        private readonly IIamDataGuard _guard;
        public WaterDashboardController(IWaterDashboardService svc, IIamDataGuard guard) { _svc = svc; _guard = guard; }

        /// <summary>Counts for every member; money figures need water.dashboard-financials.view.</summary>
        [HttpGet("summary")]
        public async Task<ActionResult<WaterDashboardSummaryModel>> Summary([FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var summary = await _svc.GetSummary(farmId);
            if (summary is not null && !await _guard.AllowsAsync(User, farmId, "water.dashboard-financials.view"))
            {
                summary.SalesToday = 0;
                summary.SalesThisMonth = 0;
                summary.OutstandingReceivables = 0;
            }
            return Ok(summary);
        }
    }
}
