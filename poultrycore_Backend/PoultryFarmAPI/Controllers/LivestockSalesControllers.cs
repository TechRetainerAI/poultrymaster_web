// Livestock endpoints from migration 462: sales, customer payments and
// balances, paid expenses (with bills on purchases listed alongside).
//
// Customers themselves are the shared api/Customer (the same list every
// company type uses; IamPermissionMap's *.customers resolves to
// livestock.customers on a Livestock farm).
//
// PERMISSIONS (IamPermissionMap): livestock/sales -> livestock.sales,
// livestock/customer-payments -> livestock.customer-payments,
// livestock/customer-balances -> livestock.customer-balances,
// livestock/expenses -> livestock.expenses. Reversals are POSTs to .../reversal.

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
    [Route("api/Livestock/sales")]
    [RequireCompanyType("Livestock")]
    public class LivestockSaleController : LivestockControllerBase
    {
        public LivestockSaleController(ILivestockDb db) : base(db) { }

        [HttpGet]
        public Task<IActionResult> List([FromQuery] string farmId, [FromQuery] int? customerId, [FromQuery] string? status,
                                        [FromQuery] DateTime? from, [FromQuery] DateTime? to, [FromQuery] int? groupId)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestocksale_list", Text("p_farmid", farmId),
                Jsonb("p_filter", LsJson.Filter(new { customerId, status, groupId,
                    from = from?.ToString("yyyy-MM-dd"), to = to?.ToString("yyyy-MM-dd") })))));

        /// <summary>What can be sold now: groups, tagged animals, stock with stock.</summary>
        [HttpGet("options")]
        public Task<IActionResult> Options([FromQuery] string farmId)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestocksale_options", Text("p_farmid", farmId))));

        [HttpGet("{id:int}")]
        public Task<IActionResult> Get(int id, [FromQuery] string farmId)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestocksale_get", Text("p_farmid", farmId), Int("p_id", id))));

        /// <summary>Body: { farmId, customerId, date, reference, dueDate, notes, overrideWithdrawal, lines: [...], amountReceived, accountId }.</summary>
        [HttpPost]
        public Task<IActionResult> Create([FromBody] JsonElement body)
            => Write(FarmOf(body), async by => Ok(new
            {
                saleId = await Db.IntAsync("splivestocksale_post", Text("p_farmid", FarmOf(body)), Jsonb("p_s", body.GetRawText()), Text("p_by", by)),
            }));

        [HttpPost("{id:int}/reversal")]
        public Task<IActionResult> Reverse(int id, [FromBody] JsonElement body)
            => Write(FarmOf(body), async by =>
            {
                await Db.ExecAsync("splivestocksale_reverse", Text("p_farmid", FarmOf(body)), Int("p_id", id),
                    Text("p_reason", Str(body, "reason")), Text("p_by", by));
                return NoContent();
            });
    }

    [Authorize]
    [ApiController]
    [Route("api/Livestock/customer-payments")]
    [RequireCompanyType("Livestock")]
    public class LivestockCustomerPaymentController : LivestockControllerBase
    {
        public LivestockCustomerPaymentController(ILivestockDb db) : base(db) { }

        [HttpGet]
        public Task<IActionResult> List([FromQuery] string farmId, [FromQuery] int? customerId)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockcustomerpayment_list", Text("p_farmid", farmId),
                Int("p_customerid", customerId))));

        /// <summary>Body: { farmId, customerId, date, amount, accountId, reference, notes, saleId? }.</summary>
        [HttpPost]
        public Task<IActionResult> Receive([FromBody] JsonElement body)
            => Write(FarmOf(body), async by => Ok(new
            {
                paymentId = await Db.IntAsync("splivestockcustomerpayment_post", Text("p_farmid", FarmOf(body)),
                    Jsonb("p_pay", body.GetRawText()), Text("p_by", by)),
            }));

        [HttpPost("{id:int}/reversal")]
        public Task<IActionResult> Reverse(int id, [FromBody] JsonElement body)
            => Write(FarmOf(body), async by =>
            {
                await Db.ExecAsync("splivestockcustomerpayment_reverse", Text("p_farmid", FarmOf(body)), Int("p_paymentid", id),
                    Text("p_reason", Str(body, "reason")), Text("p_by", by));
                return NoContent();
            });
    }

    [Authorize]
    [ApiController]
    [Route("api/Livestock/customer-balances")]
    [RequireCompanyType("Livestock")]
    public class LivestockCustomerBalanceController : LivestockControllerBase
    {
        public LivestockCustomerBalanceController(ILivestockDb db) : base(db) { }

        [HttpGet]
        public Task<IActionResult> List([FromQuery] string farmId)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockcustomer_balances", Text("p_farmid", farmId))));

        [HttpGet("{customerId:int}")]
        public Task<IActionResult> Statement(int customerId, [FromQuery] string farmId)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockcustomer_statement", Text("p_farmid", farmId),
                Int("p_customerid", customerId))));
    }

    [Authorize]
    [ApiController]
    [Route("api/Livestock/expenses")]
    [RequireCompanyType("Livestock")]
    public class LivestockExpenseController : LivestockControllerBase
    {
        public LivestockExpenseController(ILivestockDb db) : base(db) { }

        [HttpGet]
        public Task<IActionResult> List([FromQuery] string farmId, [FromQuery] DateTime? from, [FromQuery] DateTime? to,
                                        [FromQuery] string? category, [FromQuery] int? groupId)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockexpense_list", Text("p_farmid", farmId),
                Jsonb("p_filter", LsJson.Filter(new { category, groupId,
                    from = from?.ToString("yyyy-MM-dd"), to = to?.ToString("yyyy-MM-dd") })))));

        /// <summary>Body: { farmId, date, category, description, amount, groupId, accountId, paidTo, reference }.</summary>
        [HttpPost]
        public Task<IActionResult> Create([FromBody] JsonElement body)
            => Write(FarmOf(body), async by => Ok(new
            {
                expenseId = await Db.IntAsync("splivestockexpense_post", Text("p_farmid", FarmOf(body)), Jsonb("p_e", body.GetRawText()), Text("p_by", by)),
            }));

        [HttpPost("{id:int}/reversal")]
        public Task<IActionResult> Reverse(int id, [FromBody] JsonElement body)
            => Write(FarmOf(body), async by =>
            {
                await Db.ExecAsync("splivestockexpense_reverse", Text("p_farmid", FarmOf(body)), Int("p_id", id),
                    Text("p_reason", Str(body, "reason")), Text("p_by", by));
                return NoContent();
            });
    }
}
