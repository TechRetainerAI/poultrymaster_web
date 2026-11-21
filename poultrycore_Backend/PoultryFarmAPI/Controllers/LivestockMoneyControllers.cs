// Livestock endpoints from migration 463: transfers, reconciliation, staff and
// payroll, staff advances, owner money, outside loans, assets, profit & loss,
// cash flow.
//
// PERMISSIONS (IamPermissionMap): livestock/cash-transfers, livestock/cash-reconciliation,
// livestock/staff, livestock/payroll, livestock/staff-loans, livestock/owner-money,
// livestock/loans, livestock/assets -> their own keys; livestock/reports ->
// livestock.reports (profit & loss, cash flow). Reversals are POSTs to .../reversal.

using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Filters;
using static PoultryFarmAPIWeb.Business.LivestockDb;

namespace PoultryFarmAPIWeb.Controllers
{
    /// <summary>A POST that saves a JSON body through one function and returns its id.</summary>
    public abstract class LivestockPostingController : LivestockControllerBase
    {
        protected LivestockPostingController(ILivestockDb db) : base(db) { }

        protected Task<IActionResult> Post(JsonElement body, string fn, string arg, string idName)
            => Write(FarmOf(body), async by => Ok(new Dictionary<string, int>
            {
                [idName] = await Db.IntAsync(fn, Text("p_farmid", FarmOf(body)), Jsonb(arg, body.GetRawText()), Text("p_by", by)),
            }));

        protected Task<IActionResult> Reverse(JsonElement body, string fn, int id, params LsArg[] extra)
            => Write(FarmOf(body), async by =>
            {
                var args = new List<LsArg> { Text("p_farmid", FarmOf(body)) };
                args.AddRange(extra);
                args.Add(Int("p_id", id));
                args.Add(Text("p_reason", Str(body, "reason")));
                args.Add(Text("p_by", by));
                await Db.ExecAsync(fn, args.ToArray());
                return NoContent();
            });
    }

    [Authorize]
    [ApiController]
    [Route("api/Livestock/cash-transfers")]
    [RequireCompanyType("Livestock")]
    public class LivestockTransferController : LivestockPostingController
    {
        public LivestockTransferController(ILivestockDb db) : base(db) { }

        [HttpGet]
        public Task<IActionResult> List([FromQuery] string farmId)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestocktransfer_list", Text("p_farmid", farmId))));

        /// <summary>Body: { farmId, date, fromAccountId, toAccountId, amount, fee, notes }.</summary>
        [HttpPost]
        public Task<IActionResult> Create([FromBody] JsonElement body) => Post(body, "splivestocktransfer_post", "p_t", "transferId");

        [HttpPost("{id:int}/reversal")]
        public Task<IActionResult> Rev(int id, [FromBody] JsonElement body) => Reverse(body, "splivestocktransfer_reverse", id);
    }

    [Authorize]
    [ApiController]
    [Route("api/Livestock/cash-reconciliation")]
    [RequireCompanyType("Livestock")]
    public class LivestockReconciliationController : LivestockControllerBase
    {
        public LivestockReconciliationController(ILivestockDb db) : base(db) { }

        [HttpGet]
        public Task<IActionResult> List([FromQuery] string farmId, [FromQuery] int? accountId)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockreconcile_list", Text("p_farmid", farmId), Int("p_accountid", accountId))));

        /// <summary>Body: { farmId, accountId, date, counted, notes }.</summary>
        [HttpPost]
        public Task<IActionResult> Create([FromBody] JsonElement body)
            => Write(FarmOf(body), async by => JsonText(await Db.JsonAsync("splivestockreconcile_post", Text("p_farmid", FarmOf(body)),
                Int("p_accountid", IntOf(body, "accountId")), Date("p_date", DateOf(body, "date")),
                LsJson.Num("p_counted", LsJson.Dec(body, "counted")), Text("p_notes", Str(body, "notes")), Text("p_by", by))));
    }

    [Authorize]
    [ApiController]
    [Route("api/Livestock/staff")]
    [RequireCompanyType("Livestock")]
    public class LivestockStaffController : LivestockControllerBase
    {
        public LivestockStaffController(ILivestockDb db) : base(db) { }

        [HttpGet]
        public Task<IActionResult> List([FromQuery] string farmId, [FromQuery] bool includeInactive = false)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockstaff_list", Text("p_farmid", farmId), Bool("p_includeinactive", includeInactive))));

        [HttpPost]
        public Task<IActionResult> Create([FromBody] JsonElement body) => Save(null, body);

        [HttpPut("{id:int}")]
        public Task<IActionResult> Update(int id, [FromBody] JsonElement body) => Save(id, body);

        private Task<IActionResult> Save(int? id, JsonElement body)
            => Write(FarmOf(body), async by => Ok(new
            {
                staffId = await Db.IntAsync("splivestockstaff_save", Text("p_farmid", FarmOf(body)),
                    Jsonb("p_s", LivestockPenController.WithId(body, "staffId", id)), Text("p_by", by)),
            }));
    }

    [Authorize]
    [ApiController]
    [Route("api/Livestock/payroll")]
    [RequireCompanyType("Livestock")]
    public class LivestockPayrollController : LivestockPostingController
    {
        public LivestockPayrollController(ILivestockDb db) : base(db) { }

        [HttpGet]
        public Task<IActionResult> List([FromQuery] string farmId)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockpayrun_list", Text("p_farmid", farmId))));

        /// <summary>Body: { farmId, periodStart, periodEnd, payDate, accountId, notes, lines: [...] }.</summary>
        [HttpPost]
        public Task<IActionResult> Create([FromBody] JsonElement body) => Post(body, "splivestockpayrun_post", "p_r", "runId");

        [HttpPost("{id:int}/reversal")]
        public Task<IActionResult> Rev(int id, [FromBody] JsonElement body) => Reverse(body, "splivestockpayrun_reverse", id);
    }

    [Authorize]
    [ApiController]
    [Route("api/Livestock/staff-loans")]
    [RequireCompanyType("Livestock")]
    public class LivestockStaffLoanController : LivestockPostingController
    {
        public LivestockStaffLoanController(ILivestockDb db) : base(db) { }

        [HttpGet]
        public Task<IActionResult> List([FromQuery] string farmId, [FromQuery] int? staffId)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockstaffloan_list", Text("p_farmid", farmId), Int("p_staffid", staffId))));

        /// <summary>Body: { farmId, staffId, date, amount, accountId, reason }.</summary>
        [HttpPost]
        public Task<IActionResult> Lend([FromBody] JsonElement body) => Post(body, "splivestockstaffloan_post", "p_l", "loanId");

        /// <summary>Body: { farmId, staffId, date, amount, accountId }.</summary>
        [HttpPost("repayments")]
        public Task<IActionResult> Repay([FromBody] JsonElement body) => Post(body, "splivestockstaffloan_repay", "p_r", "repaymentId");

        /// <summary>kind: Loan | Repayment. Body: { farmId, reason }.</summary>
        [HttpPost("{kind}/{id:int}/reversal")]
        public Task<IActionResult> Rev(string kind, int id, [FromBody] JsonElement body)
            => Reverse(body, "splivestockstaffloan_reverse", id, Text("p_kind", kind));
    }

    [Authorize]
    [ApiController]
    [Route("api/Livestock/owner-money")]
    [RequireCompanyType("Livestock")]
    public class LivestockOwnerMoneyController : LivestockPostingController
    {
        public LivestockOwnerMoneyController(ILivestockDb db) : base(db) { }

        [HttpGet]
        public Task<IActionResult> List([FromQuery] string farmId)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockowner_list", Text("p_farmid", farmId))));

        /// <summary>Body: { farmId, date, direction: In|Out, amount, accountId, notes }.</summary>
        [HttpPost]
        public Task<IActionResult> Create([FromBody] JsonElement body) => Post(body, "splivestockowner_post", "p_o", "entryId");

        [HttpPost("{id:int}/reversal")]
        public Task<IActionResult> Rev(int id, [FromBody] JsonElement body) => Reverse(body, "splivestockowner_reverse", id);
    }

    [Authorize]
    [ApiController]
    [Route("api/Livestock/loans")]
    [RequireCompanyType("Livestock")]
    public class LivestockLoanController : LivestockPostingController
    {
        public LivestockLoanController(ILivestockDb db) : base(db) { }

        [HttpGet]
        public Task<IActionResult> List([FromQuery] string farmId)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockloan_list", Text("p_farmid", farmId))));

        /// <summary>Body: { farmId, lender, date, amount, accountId, interestNote, dueDate, notes }.</summary>
        [HttpPost]
        public Task<IActionResult> Borrow([FromBody] JsonElement body) => Post(body, "splivestockloan_post", "p_l", "loanId");

        /// <summary>Body: { farmId, loanId, date, principal, interest, accountId, notes }.</summary>
        [HttpPost("repayments")]
        public Task<IActionResult> Repay([FromBody] JsonElement body) => Post(body, "splivestockloan_repay", "p_r", "repaymentId");

        /// <summary>kind: Loan | Repayment.</summary>
        [HttpPost("{kind}/{id:int}/reversal")]
        public Task<IActionResult> Rev(string kind, int id, [FromBody] JsonElement body)
            => Reverse(body, "splivestockloan_reverse", id, Text("p_kind", kind));
    }

    [Authorize]
    [ApiController]
    [Route("api/Livestock/assets")]
    [RequireCompanyType("Livestock")]
    public class LivestockAssetController : LivestockPostingController
    {
        public LivestockAssetController(ILivestockDb db) : base(db) { }

        [HttpGet]
        public Task<IActionResult> List([FromQuery] string farmId)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestockasset_list", Text("p_farmid", farmId))));

        /// <summary>Body: { farmId, name, category, acquiredDate, cost, salvageValue, usefulMonths, accountId, notes }.</summary>
        [HttpPost]
        public Task<IActionResult> Create([FromBody] JsonElement body) => Post(body, "splivestockasset_post", "p_a", "assetId");

        /// <summary>Sold or scrapped. Body: { farmId, date, amount, accountId }.</summary>
        [HttpPut("{id:int}/disposal")]
        public Task<IActionResult> Dispose(int id, [FromBody] JsonElement body)
            => Write(FarmOf(body), async by => JsonText(await Db.JsonAsync("splivestockasset_dispose", Text("p_farmid", FarmOf(body)), Int("p_id", id),
                Date("p_date", DateOf(body, "date")), LsJson.Num("p_amount", LsJson.Dec(body, "amount")), Int("p_accountid", IntOf(body, "accountId")),
                Text("p_by", by))));

        [HttpPost("{id:int}/reversal")]
        public Task<IActionResult> Rev(int id, [FromBody] JsonElement body) => Reverse(body, "splivestockasset_reverse", id);
    }

    [Authorize]
    [ApiController]
    [Route("api/Livestock/reports")]
    [RequireCompanyType("Livestock")]
    public class LivestockMoneyReportController : LivestockControllerBase
    {
        public LivestockMoneyReportController(ILivestockDb db) : base(db) { }

        [HttpGet("profit-loss")]
        public Task<IActionResult> ProfitLoss([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to, [FromQuery] int? groupId)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestock_profitloss", Text("p_farmid", farmId),
                Date("p_from", from), Date("p_to", to), Int("p_groupid", groupId))));

        [HttpGet("profit-by-group")]
        public Task<IActionResult> ProfitByGroup([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestock_profitbygroup", Text("p_farmid", farmId),
                Date("p_from", from), Date("p_to", to))));

        [HttpGet("cash-flow")]
        public Task<IActionResult> CashFlow([FromQuery] string farmId, [FromQuery] DateTime from, [FromQuery] DateTime to)
            => Read(farmId, async () => JsonText(await Db.JsonAsync("splivestock_cashflow", Text("p_farmid", farmId),
                Date("p_from", from), Date("p_to", to))));
    }
}
