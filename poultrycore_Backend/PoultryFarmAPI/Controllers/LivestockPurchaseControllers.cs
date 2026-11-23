// Livestock endpoints from migration 461: cash accounts, purchases, supplier
// payments and balances, stock losses, head counts, and the animal stock report.
//
// Suppliers themselves are the shared api/Supplier (the same list every
// company type uses; IamPermissionMap's *.suppliers resolves to
// livestock.suppliers on a Livestock farm).
//
// PERMISSIONS (IamPermissionMap): livestock/cash-accounts -> livestock.cash,
// livestock/purchases -> livestock.purchases, livestock/supplier-payments ->
// livestock.supplier-payments, livestock/supplier-balances ->
// livestock.supplier-balances, livestock/losses -> livestock.losses,
// livestock/head-count -> livestock.head-count, livestock/animal-stock ->
// livestock.animal-stock. Reversals are POSTs to .../reversal.

using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Filters;
using static PoultryFarmAPIWeb.Business.LivestockDb;

namespace PoultryFarmAPIWeb.Controllers
{
    [Authorize]
    [ApiController]
    [Route("api/Livestock/cash-accounts")]
    [RequireCompanyType("Livestock")]
    public class LivestockCashAccountController : LivestockControllerBase
    {
        public LivestockCashAccountController(ILivestockDb db) : base(db) { }

        [HttpGet]
        public Task<IActionResult> List([FromQuery] string farmId, [FromQuery] bool includeInactive = false)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockcashaccount_list", Text("p_farmid", farmId),
                Bool("p_includeinactive", includeInactive))));

        [HttpGet("{id:int}")]
        public Task<IActionResult> Get(int id, [FromQuery] string farmId, [FromQuery] DateTime? from, [FromQuery] DateTime? to)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockcashaccount_get", Text("p_farmid", farmId),
                Int("p_accountid", id), Date("p_from", from), Date("p_to", to))));

        [HttpPost]
        public Task<IActionResult> Create([FromBody] JsonElement body) => Save(null, body);

        [HttpPut("{id:int}")]
        public Task<IActionResult> Update(int id, [FromBody] JsonElement body) => Save(id, body);

        private Task<IActionResult> Save(int? id, JsonElement body)
            => Write(FarmOf(body), async by => Ok(new
            {
                accountId = await Db.IntAsync("splivestockcashaccount_save", Text("p_farmid", FarmOf(body)),
                    Jsonb("p_a", LivestockPenController.WithId(body, "accountId", id)), Text("p_by", by)),
            }));
    }

    [Authorize]
    [ApiController]
    [Route("api/Livestock/purchases")]
    [RequireCompanyType("Livestock")]
    public class LivestockPurchaseController : LivestockControllerBase
    {
        public LivestockPurchaseController(ILivestockDb db) : base(db) { }

        [HttpGet]
        public Task<IActionResult> List([FromQuery] string farmId, [FromQuery] int? supplierId, [FromQuery] string? status,
                                        [FromQuery] DateTime? from, [FromQuery] DateTime? to)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockpurchase_list", Text("p_farmid", farmId),
                Jsonb("p_filter", LsJson.Filter(new { supplierId, status, from = from?.ToString("yyyy-MM-dd"), to = to?.ToString("yyyy-MM-dd") })))));

        [HttpGet("{id:int}")]
        public Task<IActionResult> Get(int id, [FromQuery] string farmId)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockpurchase_get", Text("p_farmid", farmId), Int("p_id", id))));

        /// <summary>Body: { farmId, supplierId, date, reference, dueDate, notes, lines: [...], amountPaid, accountId }.</summary>
        [HttpPost]
        public Task<IActionResult> Create([FromBody] JsonElement body)
            => Write(FarmOf(body), async by => Ok(new
            {
                purchaseId = await Db.IntAsync("splivestockpurchase_post", Text("p_farmid", FarmOf(body)),
                    Jsonb("p_p", body.GetRawText()), Text("p_by", by)),
            }));

        /// <summary>Body: { farmId, reason }.</summary>
        [HttpPost("{id:int}/reversal")]
        public Task<IActionResult> Reverse(int id, [FromBody] JsonElement body)
            => Write(FarmOf(body), async by =>
            {
                await Db.ExecAsync("splivestockpurchase_reverse", Text("p_farmid", FarmOf(body)), Int("p_id", id),
                    Text("p_reason", Str(body, "reason")), Text("p_by", by));
                return NoContent();
            });
    }

    [Authorize]
    [ApiController]
    [Route("api/Livestock/supplier-payments")]
    [RequireCompanyType("Livestock")]
    public class LivestockSupplierPaymentController : LivestockControllerBase
    {
        public LivestockSupplierPaymentController(ILivestockDb db) : base(db) { }

        [HttpGet]
        public Task<IActionResult> List([FromQuery] string farmId, [FromQuery] int? supplierId)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestocksupplierpayment_list", Text("p_farmid", farmId),
                Int("p_supplierid", supplierId))));

        /// <summary>Body: { farmId, supplierId, date, amount, accountId, reference, notes, purchaseId? }.</summary>
        [HttpPost]
        public Task<IActionResult> Pay([FromBody] JsonElement body)
            => Write(FarmOf(body), async by => Ok(new
            {
                paymentId = await Db.IntAsync("splivestocksupplierpayment_post", Text("p_farmid", FarmOf(body)),
                    Jsonb("p_pay", body.GetRawText()), Text("p_by", by)),
            }));

        [HttpPost("{id:int}/reversal")]
        public Task<IActionResult> Reverse(int id, [FromBody] JsonElement body)
            => Write(FarmOf(body), async by =>
            {
                await Db.ExecAsync("splivestocksupplierpayment_reverse", Text("p_farmid", FarmOf(body)), Int("p_paymentid", id),
                    Text("p_reason", Str(body, "reason")), Text("p_by", by));
                return NoContent();
            });
    }

    [Authorize]
    [ApiController]
    [Route("api/Livestock/supplier-balances")]
    [RequireCompanyType("Livestock")]
    public class LivestockSupplierBalanceController : LivestockControllerBase
    {
        public LivestockSupplierBalanceController(ILivestockDb db) : base(db) { }

        [HttpGet]
        public Task<IActionResult> List([FromQuery] string farmId)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestocksupplier_balances", Text("p_farmid", farmId))));

        [HttpGet("{supplierId:int}")]
        public Task<IActionResult> Statement(int supplierId, [FromQuery] string farmId)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestocksupplier_statement", Text("p_farmid", farmId),
                Int("p_supplierid", supplierId))));
    }

    [Authorize]
    [ApiController]
    [Route("api/Livestock/losses")]
    [RequireCompanyType("Livestock")]
    public class LivestockLossController : LivestockControllerBase
    {
        public LivestockLossController(ILivestockDb db) : base(db) { }

        [HttpGet]
        public Task<IActionResult> List([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestock_losses", Text("p_farmid", farmId),
                Date("p_from", from), Date("p_to", to))));

        /// <summary>Body: { farmId, itemId, date, quantity, reason, notes }.</summary>
        [HttpPost]
        public Task<IActionResult> Record([FromBody] JsonElement body)
            => Write(FarmOf(body), async by => Ok(new
            {
                movementId = await Db.IntAsync("splivestockstock_loss", Text("p_farmid", FarmOf(body)), Int("p_itemid", IntOf(body, "itemId")),
                    Date("p_date", DateOf(body, "date")), LsJson.Num("p_quantity", LsJson.Dec(body, "quantity")),
                    Text("p_reason", Str(body, "reason")), Text("p_notes", Str(body, "notes")), Text("p_by", by)),
            }));
    }

    [Authorize]
    [ApiController]
    [Route("api/Livestock/head-count")]
    [RequireCompanyType("Livestock")]
    public class LivestockHeadCountController : LivestockControllerBase
    {
        public LivestockHeadCountController(ILivestockDb db) : base(db) { }

        [HttpGet]
        public Task<IActionResult> Sheet([FromQuery] string farmId, [FromQuery] DateTime date, [FromQuery] string? speciesCode, [FromQuery] int? batchId)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockheadcount_sheet", Text("p_farmid", farmId),
                Date("p_date", date), Text("p_speciescode", string.IsNullOrWhiteSpace(speciesCode) ? null : speciesCode), Int("p_batchid", batchId))));

        /// <summary>Body: { farmId, date, notes, lines: [{ groupId, counted }] }.</summary>
        [HttpPost]
        public Task<IActionResult> Post([FromBody] JsonElement body)
            => Write(FarmOf(body), async by => JsonText(await Db.JsonAsync("splivestockheadcount_post", Text("p_farmid", FarmOf(body)),
                Date("p_date", DateOf(body, "date")), Jsonb("p_lines", LsJson.Raw(body, "lines")), Text("p_notes", Str(body, "notes")), Text("p_by", by))));
    }

    [Authorize]
    [ApiController]
    [Route("api/Livestock/animal-stock")]
    [RequireCompanyType("Livestock")]
    public class LivestockAnimalStockController : LivestockControllerBase
    {
        public LivestockAnimalStockController(ILivestockDb db) : base(db) { }

        [HttpGet]
        public Task<IActionResult> Get([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to, [FromQuery] string? speciesCode)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestock_animalstock", Text("p_farmid", farmId),
                Date("p_from", from), Date("p_to", to), Text("p_speciescode", string.IsNullOrWhiteSpace(speciesCode) ? null : speciesCode))));
    }
}
