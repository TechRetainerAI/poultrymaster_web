// Restaurant supplier side (migration 329).
//
//   /api/Restaurant/supplier-balances ...  \
//   /api/Restaurant/supplier-payments ...   } the SAME contract PoultryBalancesController
//   /api/Restaurant/suppliers/{id}/statement/  answers, so components/balances works unchanged
//   /api/Restaurant/purchases              purchases that carry a cost, and cost recognition
//   /api/Restaurant/deferred-inventory-costs  the read-only Deferred inventory cost page
//
// Same conventions as RestaurantAssetsController: every action checks the
// caller's JWT company against farmId, the acting user comes from the token
// (a createdBy / reversedBy sent in a body is ignored), and business-rule
// refusals from the database come back as 400 with the database's own sentence
// (RestaurantBusinessRuleFilter).

using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Filters;
using PoultryFarmAPIWeb.Helpers;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Authorize]
    [RestaurantBusinessRuleFilter]
    [Route("api/Restaurant")]
    public class RestaurantBalancesController : ControllerBase
    {
        private readonly IRestaurantSupplierService _svc;
        public RestaurantBalancesController(IRestaurantSupplierService svc) => _svc = svc;

        private string Me => HotelAuthHelper.GetUserName(User);
        private IActionResult? Deny(string? farmId) =>
            string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : HotelAuthHelper.VerifyFarmOwnership(User, farmId);

        [HttpGet("supplier-balances")]
        public async Task<IActionResult> Balances([FromQuery] string farmId, [FromQuery] DateTime? from, [FromQuery] DateTime? to,
            [FromQuery] int? supplierId, [FromQuery] string? status, [FromQuery] decimal? minBalance, [FromQuery] string? search)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.BalancesAsync(farmId, from, to, supplierId, status, minBalance, search)); }

        [HttpGet("supplier-balances/summary")]
        public async Task<IActionResult> Summary([FromQuery] string farmId)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.SummaryAsync(farmId)); }

        [HttpGet("supplier-balances/{supplierId:int}/open-purchases")]
        public async Task<IActionResult> OpenPurchases(int supplierId, [FromQuery] string farmId, [FromQuery] DateTime? from,
            [FromQuery] DateTime? to, [FromQuery] string? status)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.OpenDocumentsAsync(farmId, supplierId, from, to, status)); }

        /// <summary>One cash-out from the chosen account; allocations must add up to the amount.</summary>
        [HttpPost("supplier-payments")]
        public async Task<IActionResult> Record([FromBody] RecordPaymentRequest r)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var d = Deny(r.FarmId); if (d != null) return d;
            if (r.Allocations.Count == 0) return BadRequest(new { message = "Select at least one purchase to apply this payment to." });
            var id = await _svc.RecordPaymentAsync(r, Me);
            return Ok(new { paymentId = id });
        }

        /// <summary>Append-only: the cash comes back through a new ledger row dated today. A reason is required.</summary>
        [HttpPost("supplier-payments/{paymentId:int}/reverse")]
        public async Task<IActionResult> Reverse(int paymentId, [FromBody] ReversePaymentRequest r)
        {
            var d = Deny(r.FarmId); if (d != null) return d;
            return Ok(new { reversedAllocations = await _svc.ReversePaymentAsync(r.FarmId, paymentId, r.Reason, Me) });
        }

        [HttpGet("supplier-payments")]
        public async Task<IActionResult> History([FromQuery] string farmId, [FromQuery] int? supplierId, [FromQuery] string? documentType,
            [FromQuery] int? documentId, [FromQuery] DateTime? from, [FromQuery] DateTime? to)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.HistoryAsync(farmId, supplierId, documentType, documentId, from, to)); }

        [HttpGet("supplier-payments/{paymentId:int}")]
        public async Task<IActionResult> Get(int paymentId, [FromQuery] string farmId)
        {
            var d = Deny(farmId); if (d != null) return d;
            var header = (await _svc.HistoryAsync(farmId, null, null, null, null, null))
                .FirstOrDefault(p => p.PaymentId == paymentId.ToString());
            if (header == null) return NotFound(new { message = "Payment not found." });
            return Ok(new { payment = header, allocations = await _svc.AllocationsAsync(farmId, paymentId) });
        }

        [HttpGet("suppliers/{supplierId:int}/statement")]
        public async Task<IActionResult> Statement(int supplierId, [FromQuery] string farmId, [FromQuery] DateTime? from, [FromQuery] DateTime? to)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.StatementAsync(farmId, supplierId, from, to)); }

        /// <summary>The payment state of each expense (supplier, paid, balance). Read next to the expense list.</summary>
        [HttpGet("expenses/payments")]
        public async Task<IActionResult> ExpensePayments([FromQuery] string farmId, [FromQuery] DateTime? from, [FromQuery] DateTime? to)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.ExpensePaymentsAsync(farmId, from, to)); }

        /// <summary>Updates a supplier (Setup > Finance > Suppliers).</summary>
        [HttpPut("setup/suppliers/{id:int}")]
        public async Task<IActionResult> UpdateSupplier(int id, [FromBody] RestaurantSupplierUpdateRequest req)
        {
            var d = Deny(req.FarmId); if (d != null) return d;
            if (string.IsNullOrWhiteSpace(req.Name)) return BadRequest(new { message = "Supplier name is required." });
            await _svc.UpdateSupplierAsync(id, req);
            return Ok();
        }
    }

    [ApiController]
    [Authorize]
    [RestaurantBusinessRuleFilter]
    [Route("api/Restaurant/purchases")]
    public class RestaurantPurchasesController : ControllerBase
    {
        private readonly IRestaurantSupplierService _svc;
        public RestaurantPurchasesController(IRestaurantSupplierService svc) => _svc = svc;

        private string Me => HotelAuthHelper.GetUserName(User);
        private IActionResult? Deny(string? farmId) => HotelAuthHelper.VerifyFarmOwnership(User, farmId);

        [HttpGet]
        public async Task<IActionResult> List([FromQuery] string farmId, [FromQuery] DateTime? from, [FromQuery] DateTime? to,
            [FromQuery] int? supplierId, [FromQuery] int? ingredientId, [FromQuery] int? purchaseId)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.ListPurchasesAsync(farmId, from, to, supplierId, ingredientId, purchaseId)); }

        /// <summary>Adds the stock as a FIFO lot, moves only the amount paid now, leaves the rest owed.</summary>
        [HttpPost]
        public async Task<IActionResult> Create([FromQuery] string farmId, [FromBody] RestaurantPurchaseCreateRequest req)
        { var d = Deny(farmId); if (d != null) return d; return Ok(new { purchaseId = await _svc.CreatePurchaseAsync(farmId, req, Me) }); }

        /// <summary>Refused once any of its stock is used or a supplier payment was applied to it.</summary>
        [HttpPost("{id:int}/reverse")]
        public async Task<IActionResult> Reverse(int id, [FromQuery] string farmId, [FromBody] RestaurantPurchaseReverseRequest req)
        { var d = Deny(farmId); if (d != null) return d; await _svc.ReversePurchaseAsync(farmId, id, req.Reason, Me); return Ok(); }

        /// <summary>Expense when purchased (default) or when consumed, per ingredient category.</summary>
        [HttpGet("cost-recognition")]
        public async Task<IActionResult> CostModes([FromQuery] string farmId)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.CostModesAsync(farmId)); }

        [HttpPut("cost-recognition")]
        public async Task<IActionResult> SetCostMode([FromQuery] string farmId, [FromBody] RestaurantCostModeRequest req)
        { var d = Deny(farmId); if (d != null) return d; await _svc.SetCostModeAsync(farmId, req, Me); return Ok(); }
    }

    [ApiController]
    [Authorize]
    [RestaurantBusinessRuleFilter]
    [Route("api/Restaurant/deferred-inventory-costs")]
    public class RestaurantDeferredInventoryCostController : ControllerBase
    {
        private readonly IRestaurantSupplierService _svc;
        public RestaurantDeferredInventoryCostController(IRestaurantSupplierService svc) => _svc = svc;

        private IActionResult? Deny(string? farmId) => HotelAuthHelper.VerifyFarmOwnership(User, farmId);

        /// <summary>Read-only. The cards and the table come from the same rows.</summary>
        [HttpGet]
        public async Task<IActionResult> Get([FromQuery] string farmId, [FromQuery] string? scope, [FromQuery] int? itemId,
            [FromQuery] int? supplierId, [FromQuery] string? category, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate,
            [FromQuery] string? search)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.DeferredAsync(farmId, scope, itemId, supplierId, category, fromDate, toDate, search)); }

        [HttpGet("{purchaseId:int}/history")]
        public async Task<IActionResult> History(int purchaseId, [FromQuery] string farmId)
        { var d = Deny(farmId); if (d != null) return d; return Ok(await _svc.DeferredHistoryAsync(farmId, purchaseId)); }
    }
}
