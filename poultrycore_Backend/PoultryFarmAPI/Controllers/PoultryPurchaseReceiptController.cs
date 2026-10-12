using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using Npgsql;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    /// <summary>
    /// Receive Purchase (migration 345): one supplier invoice -- stock, payable
    /// and any payment made on the spot -- in one step.
    ///
    /// <para>
    /// Permissions come from IamPermissionMap's "poultry/purchase-receipts"
    /// entry, so they switch on with Iam:Enforced like every other route:
    /// </para>
    /// <list type="bullet">
    /// <item>GET                    → poultry.purchase-receipts.view</item>
    /// <item>POST                   → poultry.purchase-receipts.create</item>
    /// <item>POST {id}/reverse      → poultry.purchase-receipts.approve
    ///   ("reverse" is one of ResolveAction's approve segments)</item>
    /// </list>
    /// <para>
    /// A receipt that pays the supplier is ALSO a supplier payment, and the route
    /// map can only name one key. So once IAM enforces, paying on receipt also
    /// needs poultry.supplier-payments.create -- otherwise this screen would be a
    /// way round the Supplier Payments permission. In shadow mode it is a no-op,
    /// exactly like PoultryFarmSetupController's extra checks.
    /// </para>
    /// <para>farmId travels in the query string on every route, because that is
    /// where the IAM filter reads the company from.</para>
    /// </summary>
    [ApiController]
    [Route("api/Poultry/purchase-receipts")]
    public class PoultryPurchaseReceiptController : ControllerBase
    {
        private readonly IPoultryPurchaseReceiptService _svc;
        private readonly IIamService _iam;
        private readonly IConfiguration _config;

        public PoultryPurchaseReceiptController(IPoultryPurchaseReceiptService svc, IIamService iam, IConfiguration config)
        {
            _svc = svc;
            _iam = iam;
            _config = config;
        }

        // GET api/Poultry/purchase-receipts?farmId=&fromDate=&toDate=&status=
        [HttpGet]
        public async Task<ActionResult<IEnumerable<PoultryPurchaseReceiptModel>>> GetAll(
            [FromQuery] string farmId, [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate, [FromQuery] string? status)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest(new { message = "Company ID is required." });
            return Ok(await _svc.GetAllAsync(farmId, fromDate, toDate, status));
        }

        // GET api/Poultry/purchase-receipts/{id}?farmId=
        [HttpGet("{id:int}")]
        public async Task<ActionResult<PoultryPurchaseReceiptModel>> GetById(int id, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest(new { message = "Company ID is required." });
            var receipt = await _svc.GetByIdAsync(id, farmId);
            return receipt is null ? NotFound(new { message = "Purchase receipt not found for this company." }) : Ok(receipt);
        }

        // POST api/Poultry/purchase-receipts?farmId=
        [HttpPost]
        public async Task<ActionResult<PoultryPurchaseReceiptModel>> Receive([FromBody] PoultryPurchaseReceiptRequest req)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest(new { message = "Company ID is required." });
            if (req.Lines is null || req.Lines.Count == 0) return BadRequest(new { message = "Add at least one item to the receipt." });

            var callerId = User?.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (req.AmountPaid > 0 && _config.GetValue("Iam:Enforced", false))
            {
                if (!await _iam.HasPermissionAsync(callerId ?? req.CreatedBy ?? string.Empty, req.FarmId, "poultry.supplier-payments.create"))
                    return StatusCode(403, new { message = "Paying on receipt records a supplier payment, which you do not have permission to do. Receive it on credit instead." });
            }
            // The person on the token, not whatever the body claims.
            req.CreatedBy = callerId ?? req.CreatedBy;

            try
            {
                var id = await _svc.ReceiveAsync(req);
                var receipt = await _svc.GetByIdAsync(id, req.FarmId);
                return CreatedAtAction(nameof(GetById), new { id, farmId = req.FarmId }, receipt);
            }
            catch (PostgresException ex) when (ex.SqlState == PostgresErrorCodes.RaiseException)
            {
                return BadRequest(new { message = ex.MessageText });
            }
            catch (PostgresException ex) when (ex.SqlState == PostgresErrorCodes.UniqueViolation)
            {
                // Two people receiving the same invoice at the same moment: the
                // function's own check missed it, the partial unique index did not.
                return Conflict(new { message = "This supplier invoice has just been received by someone else. Refresh the list before receiving it again." });
            }
        }

        // POST api/Poultry/purchase-receipts/{id}/reverse?farmId=
        [HttpPost("{id:int}/reverse")]
        public async Task<IActionResult> Reverse(int id, [FromBody] PoultryPurchaseReceiptReverseRequest req)
        {
            if (req is null || string.IsNullOrWhiteSpace(req.FarmId)) return BadRequest(new { message = "Company ID is required." });
            if (string.IsNullOrWhiteSpace(req.Reason)) return BadRequest(new { message = "Give a reason for reversing this receipt." });
            req.ReversedBy = User?.FindFirst(ClaimTypes.NameIdentifier)?.Value ?? req.ReversedBy;

            try
            {
                var lines = await _svc.ReverseAsync(id, req);
                return Ok(new { linesReversed = lines, receipt = await _svc.GetByIdAsync(id, req.FarmId) });
            }
            catch (PostgresException ex) when (ex.SqlState == PostgresErrorCodes.RaiseException)
            {
                return BadRequest(new { message = ex.MessageText });
            }
        }
    }
}
