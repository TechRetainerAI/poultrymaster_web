using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // The Generic company's money-out side (migration 249): recurring expenses,
    // staff and contractor payments, and owner contributions and draws.
    //
    // Every action opens with GenericFarmGuard.EnsureAsync, so a company of
    // another type gets a 409 that says so rather than a confusing SQL error.
    //
    // AuditLogActionFilter is global, so every write below is audited without
    // code here -- but its farmId cascade reads the query string or the body,
    // NOT the {farmId} route segment, which is why each request body carries
    // FarmId and each action stamps it from the route.

    // =========================================================================
    // Recurring expenses.
    // =========================================================================
    [ApiController]
    [Route("api/generic-company/{farmId}/recurring-expenses")]
    public class GenericRecurringExpensesController : ControllerBase
    {
        private readonly IGenericMoneyOutService _svc;
        private readonly IGenericCompanyService _companies;

        public GenericRecurringExpensesController(IGenericMoneyOutService svc, IGenericCompanyService companies)
        {
            _svc = svc;
            _companies = companies;
        }

        [HttpGet]
        public async Task<ActionResult<IEnumerable<GenericRecurringExpenseRow>>> GetAll(
            string farmId, [FromQuery] string? status)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _svc.GetRecurring(farmId, status));
        }

        [HttpPost]
        public async Task<ActionResult> Create(string farmId, [FromBody] CreateRecurringExpenseRequest r)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            r.FarmId = farmId;
            var id = await _svc.CreateRecurring(r);
            return Ok(new { genericRecurringExpenseId = id });
        }

        /// <summary>
        /// Pause, resume, cancel or expire. Cancelling needs a reason; the SP
        /// rejects a blank one rather than this layer guessing.
        /// </summary>
        [HttpPost("{id:int}/status")]
        public async Task<IActionResult> SetStatus(
            string farmId, int id, [FromBody] SetRecurringExpenseStatusRequest r)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            r.FarmId = farmId;
            await _svc.SetRecurringStatus(id, r);
            return NoContent();
        }

        /// <summary>
        /// What generating now would raise. Writes nothing, and shares its
        /// selection with generate, so the two cannot disagree.
        /// </summary>
        [HttpGet("preview")]
        public async Task<ActionResult<IEnumerable<RecurringExpensePreviewRow>>> Preview(
            string farmId, [FromQuery] DateTime? asOf)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _svc.PreviewRecurring(farmId, asOf));
        }

        /// <summary>
        /// Raises one expense per unbilled period, catching up anything behind.
        /// Running it twice raises nothing twice.
        /// </summary>
        [HttpPost("generate")]
        public async Task<ActionResult> Generate(string farmId, [FromBody] GenerateRecurringRequest r)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            r.FarmId = farmId;
            var generated = await _svc.GenerateRecurring(r);
            return Ok(new { generated });
        }
    }

    // =========================================================================
    // Staff and contractor payments.
    // =========================================================================
    [ApiController]
    [Route("api/generic-company/{farmId}/staff-payments")]
    public class GenericStaffPaymentsController : ControllerBase
    {
        private readonly IGenericMoneyOutService _svc;
        private readonly IGenericCompanyService _companies;

        public GenericStaffPaymentsController(IGenericMoneyOutService svc, IGenericCompanyService companies)
        {
            _svc = svc;
            _companies = companies;
        }

        [HttpGet]
        public async Task<ActionResult<IEnumerable<GenericStaffPaymentRow>>> GetAll(
            string farmId, [FromQuery] int? staffId,
            [FromQuery] DateTime? from, [FromQuery] DateTime? to)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _svc.GetStaffPayments(farmId, staffId, from, to));
        }

        /// <summary>
        /// Pays one person now. The full payroll run is still there for paying a
        /// whole team for a period; this is the case a run is too much machinery
        /// for. Both post an expense and move cash.
        /// </summary>
        [HttpPost]
        public async Task<ActionResult> Record(string farmId, [FromBody] RecordStaffPaymentRequest r)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            r.FarmId = farmId;
            var paymentId = await _svc.RecordStaffPayment(r);
            return Ok(new { paymentId });
        }

        [HttpPost("{paymentId:int}/reverse")]
        public async Task<IActionResult> Reverse(
            string farmId, int paymentId, [FromBody] ReverseMoneyOutRequest r)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            r.FarmId = farmId;
            await _svc.ReverseStaffPayment(farmId, paymentId, r.Reason, r.ReversedBy);
            return NoContent();
        }
    }

    // =========================================================================
    // Owner contributions and draws.
    // =========================================================================
    /// <summary>
    /// Money the owner puts in or takes out. Deliberately its own endpoint tree
    /// rather than a category on income or expenses: a contribution is not
    /// revenue and a draw is not an operating cost, so neither may reach the
    /// P&amp;L. Both move cash, and that is all they do.
    /// </summary>
    [ApiController]
    [Route("api/generic-company/{farmId}/owner-entries")]
    public class GenericOwnerEntriesController : ControllerBase
    {
        private readonly IGenericMoneyOutService _svc;
        private readonly IGenericCompanyService _companies;

        public GenericOwnerEntriesController(IGenericMoneyOutService svc, IGenericCompanyService companies)
        {
            _svc = svc;
            _companies = companies;
        }

        [HttpGet]
        public async Task<ActionResult<IEnumerable<GenericOwnerEntryRow>>> GetAll(
            string farmId, [FromQuery] string? entryType,
            [FromQuery] DateTime? from, [FromQuery] DateTime? to)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;
            return Ok(await _svc.GetOwnerEntries(farmId, entryType, from, to));
        }

        [HttpPost]
        public async Task<ActionResult> Record(string farmId, [FromBody] RecordOwnerEntryRequest r)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            r.FarmId = farmId;
            if (r.CashAccountId is null or 0)
                return BadRequest("A cash account is required — owner money always moves cash.");

            var entryId = await _svc.RecordOwnerEntry(r);
            return Ok(new { entryId });
        }

        [HttpPost("{entryId:int}/reverse")]
        public async Task<IActionResult> Reverse(
            string farmId, int entryId, [FromBody] ReverseMoneyOutRequest r)
        {
            var guard = await GenericFarmGuard.EnsureAsync(_companies, farmId, this);
            if (guard is not null) return guard;

            r.FarmId = farmId;
            await _svc.ReverseOwnerEntry(farmId, entryId, r.Reason, r.ReversedBy);
            return NoContent();
        }
    }
}
