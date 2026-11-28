// Generic Pharmacy (migration 511): medicines, pack sizes, batches and expiry, batch
// write-offs, batch details on purchases, prescriptions and the pharmacy report.
// Used by Generic companies whose industry template is "Pharmacy"; the web only shows
// the pages to those companies. Settings and medicine setup are owner/admin writes
// (SetupAdminOnly), like the rest of Setup; batches, write-offs and prescriptions are
// daily work and open to staff who can open the page.

using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Filters;

namespace PoultryFarmAPIWeb.Controllers
{
    public class GenericPharmacySettingsRequest
    {
        public string? FarmId { get; set; }
        public string ShopType { get; set; } = "Pharmacy";
        public bool RequirePrescriptionClassA { get; set; } = true;
        public int ExpiryWarningDays { get; set; } = 90;
    }

    public class GenericProductBatchRequest
    {
        public string? FarmId { get; set; }
        public int GenericProductId { get; set; }
        public string? BatchNumber { get; set; }
        public DateTime? ExpiryDate { get; set; }
        public decimal Quantity { get; set; }
        public decimal? UnitCost { get; set; }
        public DateTime? ReceivedDate { get; set; }
        public string? Notes { get; set; }
    }

    public class GenericProductBatchWriteOffRequest
    {
        public string? FarmId { get; set; }
        public decimal Quantity { get; set; }
        public string? Reason { get; set; }
    }

    [ApiController]
    [Route("api/generic-company/{farmId}/pharmacy")]
    [RequireCompanyType("Generic")]
    public class GenericPharmacyController : ControllerBase
    {
        private readonly IGenericPharmacyService _svc;
        private readonly IGenericCompanyService _companies;

        public GenericPharmacyController(IGenericPharmacyService svc, IGenericCompanyService companies)
        {
            _svc = svc;
            _companies = companies;
        }

        private string? CallerId() =>
            User?.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;

        private ContentResult Json(string json) => Content(json, "application/json");

        private Task<ActionResult?> Guard(string farmId) => GenericFarmGuard.EnsureAsync(_companies, farmId, this);

        // ---- Settings -------------------------------------------------------
        [HttpGet("settings")]
        public async Task<ActionResult> GetSettings(string farmId)
            => await Guard(farmId) ?? Json(await _svc.GetSettingsAsync(farmId));

        [HttpPut("settings")]
        [SetupAdminOnly]
        public async Task<ActionResult> SaveSettings(string farmId, [FromBody] GenericPharmacySettingsRequest r)
        {
            var g = await Guard(farmId); if (g is not null) return g;
            await _svc.SaveSettingsAsync(farmId, r.ShopType, r.RequirePrescriptionClassA, r.ExpiryWarningDays, CallerId());
            return NoContent();
        }

        // ---- Medicines (product + details + packs) --------------------------
        [HttpGet("medicines")]
        public async Task<ActionResult> GetMedicines(string farmId)
            => await Guard(farmId) ?? Json(await _svc.GetMedicinesAsync(farmId));

        [HttpPut("medicines/{productId:int}")]
        [SetupAdminOnly]
        public async Task<ActionResult> SaveMedicine(string farmId, int productId, [FromBody] JsonElement body)
        {
            var g = await Guard(farmId); if (g is not null) return g;
            await _svc.SaveMedicineAsync(farmId, productId, body, CallerId());
            return NoContent();
        }

        // ---- Batches --------------------------------------------------------
        [HttpGet("batches")]
        public async Task<ActionResult> GetBatches(string farmId, [FromQuery] int? productId)
            => await Guard(farmId) ?? Json(await _svc.GetBatchesAsync(farmId, productId));

        [HttpPost("batches")]
        public async Task<ActionResult> AddBatch(string farmId, [FromBody] GenericProductBatchRequest r)
        {
            var g = await Guard(farmId); if (g is not null) return g;
            if (r.GenericProductId <= 0) return BadRequest("Choose the medicine.");
            var id = await _svc.AddBatchAsync(farmId, r.GenericProductId, r.BatchNumber, r.ExpiryDate, r.Quantity,
                                              r.UnitCost, r.ReceivedDate, r.Notes, CallerId());
            return Ok(new { genericProductBatchId = id });
        }

        [HttpPut("batches/{id:int}")]
        public async Task<ActionResult> UpdateBatch(string farmId, int id, [FromBody] GenericProductBatchRequest r)
        {
            var g = await Guard(farmId); if (g is not null) return g;
            await _svc.UpdateBatchAsync(farmId, id, r.BatchNumber, r.ExpiryDate, r.Notes);
            return NoContent();
        }

        [HttpDelete("batches/{id:int}")]
        public async Task<ActionResult> DeleteBatch(string farmId, int id)
        {
            var g = await Guard(farmId); if (g is not null) return g;
            await _svc.DeleteBatchAsync(farmId, id);
            return NoContent();
        }

        [HttpPost("batches/{id:int}/write-off")]
        public async Task<ActionResult> WriteOff(string farmId, int id, [FromBody] GenericProductBatchWriteOffRequest r)
        {
            var g = await Guard(farmId); if (g is not null) return g;
            var adj = await _svc.WriteOffBatchAsync(farmId, id, r.Quantity, r.Reason, CallerId());
            return Ok(new { genericStockAdjustmentId = adj });
        }

        // ---- Batch details on a purchase -------------------------------------
        [HttpGet("purchases/{purchaseId:int}/batches")]
        public async Task<ActionResult> GetPurchaseBatches(string farmId, int purchaseId)
            => await Guard(farmId) ?? Json(await _svc.GetPurchaseBatchesAsync(farmId, purchaseId));

        /// <summary>Body: { "lines": [ { genericProductId, batchNumber, expiryDate }, ... ] } in line order.</summary>
        [HttpPut("purchases/{purchaseId:int}/batches")]
        public async Task<ActionResult> SetPurchaseBatches(string farmId, int purchaseId, [FromBody] JsonElement body)
        {
            var g = await Guard(farmId); if (g is not null) return g;
            if (!body.TryGetProperty("lines", out var lines) || lines.ValueKind != JsonValueKind.Array)
                return BadRequest("lines is required.");
            await _svc.SetPurchaseBatchesAsync(farmId, purchaseId, lines);
            return NoContent();
        }

        // ---- Prescriptions --------------------------------------------------
        [HttpGet("prescriptions")]
        public async Task<ActionResult> GetPrescriptions(string farmId, [FromQuery] DateTime? from, [FromQuery] DateTime? to)
            => await Guard(farmId) ?? Json(await _svc.GetPrescriptionsAsync(farmId, from, to));

        [HttpPost("prescriptions")]
        public async Task<ActionResult> CreatePrescription(string farmId, [FromBody] JsonElement body)
        {
            var g = await Guard(farmId); if (g is not null) return g;
            var id = await _svc.CreatePrescriptionAsync(farmId, body, CallerId());
            return Ok(new { genericPrescriptionId = id });
        }

        // ---- Report ---------------------------------------------------------
        [HttpGet("report")]
        public async Task<ActionResult> GetReport(string farmId, [FromQuery] DateTime? from, [FromQuery] DateTime? to,
                                                  [FromQuery] int expiryDays = 90)
        {
            var g = await Guard(farmId); if (g is not null) return g;
            var z = (to ?? DateTime.Today).Date;
            var a = (from ?? z.AddDays(-30)).Date;
            return Json(await _svc.GetReportAsync(farmId, a, z, expiryDays));
        }
    }
}
