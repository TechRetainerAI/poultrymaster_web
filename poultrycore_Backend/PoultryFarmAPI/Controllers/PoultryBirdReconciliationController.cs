using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Filters;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    /// <summary>
    /// Batch Bird Reconciliation (migration 413): where every bird a batch bought
    /// went, the postings that explain birds never placed in a flock, flock-to-
    /// flock transfers, and the diagnostic / repair of mis-linked bird movements.
    /// Company membership of every batch, flock, customer and debt is checked by
    /// the database functions; the user comes from the token, never the body.
    /// </summary>
    [ApiController]
    [Route("api/Poultry/bird-reconciliation")]
    [RequireCompanyType("Poultry")]
    public class PoultryBirdReconciliationController : ControllerBase
    {
        private readonly IBirdReconciliationService _svc;
        public PoultryBirdReconciliationController(IBirdReconciliationService svc) => _svc = svc;

        private string? CurrentUser => User?.FindFirst(ClaimTypes.NameIdentifier)?.Value;

        [HttpGet("batches")]
        public async Task<ActionResult<IEnumerable<BatchBirdReconciliationRow>>> GetSummary([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.GetSummaryAsync(farmId));

        [HttpGet("batches/{batchId:int}")]
        public async Task<IActionResult> GetDetail(int batchId, [FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("Company ID is required.");
            return Content(await _svc.GetDetailAsync(farmId, batchId), "application/json");
        }

        [HttpPost("batches/{batchId:int}/reconcile")]
        public async Task<IActionResult> Reconcile(int batchId, [FromBody] BatchReconciliationRequest m)
        {
            if (m is null || string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest(new { message = "Company ID is required." });
            m.BatchId = batchId;
            m.CreatedBy = CurrentUser ?? m.CreatedBy;
            try { return Content(await _svc.PostAsync(m), "application/json"); }
            catch (Npgsql.PostgresException ex) when (ex.SqlState == "P0001") { return BadRequest(new { message = ex.MessageText }); }
            catch (Npgsql.PostgresException ex) when (ex.SqlState == "23505")
            {
                return Conflict(new { message = "That debt or request has already been recorded against a historical sale." });
            }
        }

        [HttpPost("reconciliations/{reconciliationId:int}/reverse")]
        [SetupAdminOnly]
        public async Task<IActionResult> Reverse(int reconciliationId, [FromBody] BatchReconciliationReverseRequest m)
        {
            if (m is null || string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest(new { message = "Company ID is required." });
            if (string.IsNullOrWhiteSpace(m.Reason)) return BadRequest(new { message = "Say why this reconciliation is being reversed." });
            m.ReversedBy = CurrentUser ?? m.ReversedBy;
            try { return Content(await _svc.ReverseAsync(reconciliationId, m), "application/json"); }
            catch (Npgsql.PostgresException ex) when (ex.SqlState == "P0001") { return BadRequest(new { message = ex.MessageText }); }
        }

        [HttpPost("transfers")]
        public async Task<IActionResult> Transfer([FromBody] BirdTransferRequest m)
        {
            if (m is null || string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest(new { message = "Company ID is required." });
            m.CreatedBy = CurrentUser ?? m.CreatedBy;
            try { return Content(await _svc.TransferAsync(m), "application/json"); }
            catch (Npgsql.PostgresException ex) when (ex.SqlState == "P0001") { return BadRequest(new { message = ex.MessageText }); }
        }

        // ---- Repair of bird movements written before 413 -------------------

        [HttpGet("repair/diagnose")]
        [SetupAdminOnly]
        public async Task<ActionResult<IEnumerable<BirdRepairDiagnosticRow>>> Diagnose([FromQuery] string farmId)
            => string.IsNullOrWhiteSpace(farmId) ? BadRequest("Company ID is required.") : Ok(await _svc.DiagnoseAsync(farmId));

        /// <summary>DryRun defaults to TRUE: nothing is written unless the caller says so.</summary>
        [HttpPost("repair/apply")]
        [SetupAdminOnly]
        public async Task<ActionResult<IEnumerable<BirdRepairAppliedRow>>> Repair([FromBody] BirdRepairApplyRequest m)
        {
            if (m is null || string.IsNullOrWhiteSpace(m.FarmId)) return BadRequest(new { message = "Company ID is required." });
            m.RepairedBy = CurrentUser ?? m.RepairedBy;
            try { return Ok(await _svc.RepairAsync(m)); }
            catch (Npgsql.PostgresException ex) when (ex.SqlState == "P0001") { return BadRequest(new { message = ex.MessageText }); }
        }
    }
}
