// Water Owner Money and Loan controllers (migrations 258 and 259).
//
// The water twins of the owner-money and loan controllers in
// PoultryCashControllers.cs, route for route. Water's cash accounts and cash
// transfers already live in WaterFinanceControllers.cs; these two features are
// new to the water rail, so they get their own file rather than growing that
// one by another four hundred lines.
//
// Flat per-resource [Route] with FarmId on the query string, matching the
// convention the frontend already expects.

using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    // ====================================================================
    // Owner money (migration 258)
    // ====================================================================
    // Contributions and draws. Neither is trading, so nothing here creates a
    // sale, an expense, a customer payment or a supplier payment -- the SP
    // writes the record and exactly one cash row.
    [ApiController]
    [Route("api/Water/owner-money")]
    public class WaterOwnerMoneyController : ControllerBase
    {
        private readonly IWaterOwnerMoneyService _svc;
        public WaterOwnerMoneyController(IWaterOwnerMoneyService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<WaterOwnerMoneyModel>>> GetAll(
            [FromQuery] string farmId, [FromQuery] string? type,
            [FromQuery] DateTime? from, [FromQuery] DateTime? to, [FromQuery] string? status)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetAllAsync(farmId, type, from, to, status));

        [HttpGet("summary")]
        public async Task<ActionResult<WaterOwnerMoneySummary>> Summary(
            [FromQuery] string farmId, [FromQuery] DateTime? from, [FromQuery] DateTime? to)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetSummaryAsync(farmId, from, to));

        /// <summary>
        /// Records a contribution or a draw. One endpoint rather than two: the
        /// two differ by a single field, and splitting them would mean two
        /// copies of the same validation.
        /// </summary>
        [HttpPost]
        public async Task<ActionResult<int>> Record([FromBody] WaterOwnerMoneyRecordRequest r)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(r.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.RecordAsync(r);
            return Ok(new { WaterOwnerMoneyId = id });
        }

        [HttpPost("{id:int}/reverse")]
        public async Task<IActionResult> Reverse(
            int id, [FromQuery] string farmId, [FromQuery] string? reversedBy,
            [FromBody] WaterOwnerMoneyReverseRequest body)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.ReverseAsync(id, farmId, body.Reason, reversedBy);
            return NoContent();
        }
    }

    // ====================================================================
    // Loans and repayments (migration 259)
    // ====================================================================
    // Repaying principal is not an expense, a repayment moves cash exactly
    // once for its total, and a lender is never a supplier. All three are
    // enforced in the SPs; nothing here can route around them.
    [ApiController]
    [Route("api/Water/loans")]
    public class WaterLoanController : ControllerBase
    {
        private readonly IWaterLoanService _svc;
        public WaterLoanController(IWaterLoanService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<WaterLoanModel>>> GetAll(
            [FromQuery] string farmId, [FromQuery] string? status)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetAllAsync(farmId, status));

        [HttpGet("summary")]
        public async Task<ActionResult<WaterLoanSummary>> Summary([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetSummaryAsync(farmId));

        [HttpGet("{id:int}")]
        public async Task<ActionResult<WaterLoanModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            var m = await _svc.GetByIdAsync(id, farmId);
            return m is null ? NotFound() : Ok(m);
        }

        [HttpPost]
        public async Task<ActionResult<int>> Create([FromBody] WaterLoanCreateRequest r)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(r.FarmId)) return BadRequest("Company ID is required.");
            var id = await _svc.CreateAsync(r);
            return Ok(new { WaterLoanId = id });
        }

        /// <summary>
        /// Edits the descriptive fields only. Principal, amount received and the
        /// running totals are consequences of postings, and a form that could
        /// rewrite them is how a loan stops matching its own payments.
        /// </summary>
        [HttpPut("{id:int}")]
        public async Task<IActionResult> Update(
            int id, [FromQuery] string farmId, [FromQuery] string? updatedBy,
            [FromBody] WaterLoanUpdateRequest r)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.UpdateAsync(id, farmId, r, updatedBy);
            return NoContent();
        }

        [HttpPost("{id:int}/cancel")]
        public async Task<IActionResult> Cancel(
            int id, [FromQuery] string farmId, [FromQuery] string? cancelledBy,
            [FromBody] WaterLoanReasonRequest body)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.CancelAsync(id, farmId, body.Reason, cancelledBy);
            return NoContent();
        }

        [HttpGet("{id:int}/repayments")]
        public async Task<ActionResult<IEnumerable<WaterLoanPaymentModel>>> Repayments(
            int id, [FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetPaymentsAsync(farmId, id, null, null));

        [HttpPost("{id:int}/record-repayment")]
        public async Task<ActionResult<int>> RecordRepayment(
            int id, [FromBody] WaterLoanPaymentRequest r)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(r.FarmId)) return BadRequest("Company ID is required.");
            r.WaterLoanId = id;
            var paymentId = await _svc.RecordPaymentAsync(r);
            return Ok(new { WaterLoanPaymentId = paymentId });
        }
    }

    [ApiController]
    [Route("api/Water/loan-payments")]
    public class WaterLoanPaymentController : ControllerBase
    {
        private readonly IWaterLoanService _svc;
        public WaterLoanPaymentController(IWaterLoanService svc) => _svc = svc;

        [HttpGet]
        public async Task<ActionResult<IEnumerable<WaterLoanPaymentModel>>> GetAll(
            [FromQuery] string farmId, [FromQuery] int? loanId,
            [FromQuery] DateTime? from, [FromQuery] DateTime? to)
            => string.IsNullOrWhiteSpace(farmId)
                ? BadRequest("Company ID is required.")
                : Ok(await _svc.GetPaymentsAsync(farmId, loanId, from, to));

        [HttpPost("{paymentId:int}/reverse")]
        public async Task<IActionResult> Reverse(
            int paymentId, [FromQuery] string farmId, [FromQuery] string? reversedBy,
            [FromBody] WaterLoanReasonRequest body)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            await _svc.ReversePaymentAsync(paymentId, farmId, body.Reason, reversedBy);
            return NoContent();
        }
    }}
