// ADMIN APP endpoints (ADMIN APP spec 2026-10-05): organizations inspector,
// special discounts & promotions, account credits, tier rules, pricing
// presentation, coverage dashboards, enterprise contracts and granular
// permissions — plus the anonymous public-pricing read the customer app's
// plan cards consume.
//
// Permission model (spec 29): SystemAdmin/PlatformOwner implicitly hold every
// permission; other staff need explicit grants. Reads need BillingAdmin.View;
// each write names its own permission. Guardrails (spec 30) live in the
// service, with the threshold in platformbillingsettings.

using Microsoft.AspNetCore.Mvc;
using Npgsql;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/PlatformBillingAdmin")]
    public class PlatformBillingAdminAppController : ControllerBase
    {
        private readonly IPlatformBillingAdminService _admin;
        public PlatformBillingAdminAppController(IPlatformBillingAdminService admin) => _admin = admin;

        private async Task<IActionResult?> Gate(string userId, string permission)
        {
            if (string.IsNullOrWhiteSpace(userId) || !await _admin.HasPermissionAsync(userId, permission))
                return StatusCode(403, $"This action needs the {permission} permission.");
            return null;
        }

        [HttpGet("my-permissions")]
        public async Task<IActionResult> MyPermissions([FromQuery] string userId) =>
            Ok(await _admin.MyPermissionsAsync(userId ?? ""));

        [HttpPost("permission")]
        public async Task<IActionResult> GrantPermission([FromBody] PermissionBody b)
        {
            // Only the implicit superadmins can hand out permissions.
            if (await Gate(b.UserId, "BillingAdmin.SuperAdminOnly") is { } denied) return denied;
            var r = await _admin.GrantPermissionAsync(b.TargetUserId, b.Permission, b.UserId);
            return r.Ok ? Ok(new { ok = true, message = r.Message }) : BadRequest(new { ok = false, message = r.Message });
        }

        [HttpDelete("permission")]
        public async Task<IActionResult> RevokePermission([FromQuery] string userId, [FromQuery] string targetUserId, [FromQuery] string permission)
        {
            if (await Gate(userId, "BillingAdmin.SuperAdminOnly") is { } denied) return denied;
            var r = await _admin.RevokePermissionAsync(targetUserId, permission, userId);
            return Ok(new { ok = r.Ok, message = r.Message });
        }

        // ---------------- Organizations (spec 31/32) ----------------

        [HttpGet("organizations")]
        public async Task<IActionResult> Organizations([FromQuery] string userId, [FromQuery] string? search)
        {
            if (await Gate(userId, "BillingAdmin.View") is { } denied) return denied;
            return Ok(await _admin.AdminListOrganizationsAsync(search));
        }

        [HttpGet("organization")]
        public async Task<IActionResult> Organization([FromQuery] string userId, [FromQuery] string ownerUserId)
        {
            if (await Gate(userId, "BillingAdmin.View") is { } denied) return denied;
            var m = await _admin.AdminInspectAsync(ownerUserId);
            return m is null ? NotFound("No billing account for that organization.") : Ok(m);
        }

        // ---------------- Discounts (spec 21-25, 30) ----------------

        [HttpPost("discount")]
        public async Task<IActionResult> AssignDiscount([FromBody] AdminDiscountBody b)
        {
            if (await Gate(b.UserId, "BillingAdmin.AssignDiscount") is { } denied) return denied;
            var r = await _admin.AdminAssignDiscountAsync(b, b.UserId);
            return r.Ok ? Ok(new { ok = true, message = r.Message, id = r.Id })
                        : BadRequest(new { ok = false, message = r.Message });
        }

        [HttpDelete("discount/{id:long}")]
        public async Task<IActionResult> RevokeDiscount(long id, [FromQuery] string userId, [FromQuery] string? reason)
        {
            if (await Gate(userId, "BillingAdmin.AssignDiscount") is { } denied) return denied;
            var r = await _admin.AdminRevokeDiscountAsync(id, userId, reason);
            return r.Ok ? Ok(new { ok = true, message = r.Message }) : BadRequest(new { ok = false, message = r.Message });
        }

        /// <summary>Backend-generated before/after preview (spec 23); persists nothing.</summary>
        [HttpPost("discount-preview")]
        public async Task<IActionResult> DiscountPreview([FromBody] AdminDiscountBody b)
        {
            if (await Gate(b.UserId, "BillingAdmin.View") is { } denied) return denied;
            var m = await _admin.AdminDiscountPreviewAsync(b);
            return m is null ? NotFound("No billing account for that organization.") : Ok(m);
        }

        // ---------------- Promotions (spec 20) ----------------

        [HttpGet("promotions")]
        public async Task<IActionResult> Promotions([FromQuery] string userId)
        {
            if (await Gate(userId, "BillingAdmin.View") is { } denied) return denied;
            return Ok(await _admin.AdminListPromotionsAsync());
        }

        [HttpPost("promotion")]
        public async Task<IActionResult> CreatePromotion([FromBody] AdminPromotionBody b)
        {
            if (await Gate(b.UserId, "BillingAdmin.ManageDiscountRules") is { } denied) return denied;
            var r = await _admin.AdminCreatePromotionAsync(b, b.UserId);
            return r.Ok ? Ok(new { ok = true, message = r.Message, id = r.Id })
                        : BadRequest(new { ok = false, message = r.Message });
        }

        [HttpPost("promotion-assign")]
        public async Task<IActionResult> AssignPromotion([FromBody] PromotionAssignBody b)
        {
            if (await Gate(b.UserId, "BillingAdmin.AssignDiscount") is { } denied) return denied;
            var r = await _admin.AdminAssignPromotionAsync(b.Code, b.OwnerUserId, b.UserId);
            return r.Ok ? Ok(new { ok = true, message = r.Message }) : BadRequest(new { ok = false, message = r.Message });
        }

        // ---------------- Credits (spec 26/27) ----------------

        [HttpPost("credit")]
        public async Task<IActionResult> IssueCredit([FromBody] AdminCreditBody b)
        {
            if (await Gate(b.UserId, "BillingAdmin.IssueCredit") is { } denied) return denied;
            var r = await _admin.AdminIssueCreditAsync(b, b.UserId);
            return r.Ok ? Ok(new { ok = true, message = r.Message, id = r.Id })
                        : BadRequest(new { ok = false, message = r.Message });
        }

        [HttpDelete("credit/{id:long}")]
        public async Task<IActionResult> RevokeCredit(long id, [FromQuery] string userId, [FromQuery] string? reason)
        {
            if (await Gate(userId, "BillingAdmin.IssueCredit") is { } denied) return denied;
            var r = await _admin.AdminRevokeCreditAsync(id, userId, reason);
            return r.Ok ? Ok(new { ok = true, message = r.Message }) : BadRequest(new { ok = false, message = r.Message });
        }

        // ---------------- Tier rules (spec 4/5/6/39) ----------------

        [HttpGet("tier-rules")]
        public async Task<IActionResult> TierRules([FromQuery] string userId, [FromQuery] string? profileCode)
        {
            if (await Gate(userId, "BillingAdmin.View") is { } denied) return denied;
            return Ok(await _admin.AdminGetTierRulesAsync(profileCode));
        }

        [HttpPut("tier-rules")]
        public async Task<IActionResult> PutTierRules([FromBody] AdminTierRulesBody b)
        {
            if (await Gate(b.UserId, "BillingAdmin.ManageTierRules") is { } denied) return denied;
            var (ok, problems) = await _admin.AdminPutTierRulesAsync(b, b.UserId);
            return ok ? Ok(new { ok = true })
                      : BadRequest(new { ok = false, problems });
        }

        // ---------------- Presentation (spec 11-16) ----------------

        [HttpGet("presentations")]
        public async Task<IActionResult> Presentations([FromQuery] string userId)
        {
            if (await Gate(userId, "BillingAdmin.View") is { } denied) return denied;
            return Ok(await _admin.AdminListPresentationsAsync());
        }

        [HttpPut("presentation")]
        public async Task<IActionResult> PutPresentation([FromBody] AdminPresentationBody b)
        {
            if (await Gate(b.UserId, "BillingAdmin.ManagePresentations") is { } denied) return denied;
            var r = await _admin.AdminUpsertPresentationAsync(b, b.UserId);
            return r.Ok ? Ok(new { ok = true, message = r.Message }) : BadRequest(new { ok = false, message = r.Message });
        }

        // ---------------- Dashboards + audit (spec 34/35/36, 2.10) ----------------

        [HttpGet("coverage")]
        public async Task<IActionResult> Coverage([FromQuery] string userId)
        {
            if (await Gate(userId, "BillingAdmin.View") is { } denied) return denied;
            return Ok(await _admin.AdminCoverageAsync());
        }

        [HttpGet("events")]
        public async Task<IActionResult> Events([FromQuery] string userId, [FromQuery] int limit = 100)
        {
            if (await Gate(userId, "BillingAdmin.View") is { } denied) return denied;
            return Ok(await _admin.AdminListEventsAsync(limit));
        }

        // ---------------- Enterprise contracts (spec 33/37) ----------------

        [HttpPost("enterprise-contract")]
        public async Task<IActionResult> EnterpriseContract([FromBody] AdminContractBody b)
        {
            if (await Gate(b.UserId, "BillingAdmin.ManageEnterprisePricing") is { } denied) return denied;
            var r = await _admin.AdminCreateEnterpriseContractAsync(b, b.UserId);
            return r.Ok ? Ok(new { ok = true, message = r.Message, id = r.Id })
                        : BadRequest(new { ok = false, message = r.Message });
        }
    }

    public class PermissionBody
    {
        public string UserId { get; set; } = string.Empty;
        public string TargetUserId { get; set; } = string.Empty;
        public string Permission { get; set; } = string.Empty;
    }
    public class PromotionAssignBody
    {
        public string UserId { get; set; } = string.Empty;
        public string OwnerUserId { get; set; } = string.Empty;
        public string Code { get; set; } = string.Empty;
    }

    /// <summary>
    /// Anonymous, cache-friendly plan-card data for the customer app and the
    /// public pricing page (spec 11-16): presentation copy + current prices,
    /// template fallback applied server-side. Read-only; amounts come from the
    /// price book, never from the caller.
    /// </summary>
    [ApiController]
    [Route("api/PlatformBilling")]
    public class PlatformBillingPublicController : ControllerBase
    {
        private readonly IPlatformBillingAdminService _admin;
        public PlatformBillingPublicController(IPlatformBillingAdminService admin) => _admin = admin;

        [HttpGet("public-pricing")]
        public async Task<IActionResult> PublicPricing([FromQuery] string market = "GH",
            [FromQuery] string profile = "POULTRY_BIRDS", [FromQuery] string? template = null)
        {
            var m = await _admin.GetPublicPricingAsync(market, profile, template);
            return m is null ? NotFound("No presentation is configured for that profile.") : Ok(m);
        }
    }

    /// <summary>
    /// Water production lines — the OPERATIONAL data water billing reads
    /// (admin-app spec 5/7). The water company manages its own lines here;
    /// billing admin never edits a company's line count.
    /// </summary>
    [ApiController]
    [Route("api/WaterProductionLines")]
    public class WaterProductionLinesController : ControllerBase
    {
        private readonly string _cs;
        public WaterProductionLinesController(IConfiguration cfg) =>
            _cs = cfg.GetConnectionString("PoultryConn") ?? cfg["ConnectionStrings:PoultryConn"] ?? "";

        [HttpGet]
        public async Task<IActionResult> List([FromQuery] string farmId)
        {
            if (string.IsNullOrWhiteSpace(farmId)) return BadRequest("farmId is required.");
            var list = new List<object>();
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            using var q = new NpgsqlCommand(@"
                SELECT id, name, isactive, notes, createdat FROM waterproductionlines
                 WHERE farmid = @F ORDER BY id", conn);
            q.Parameters.AddWithValue("@F", farmId);
            using var r = await q.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Add(new
                {
                    id = r.GetInt64(0),
                    name = r.GetString(1),
                    isActive = r.GetBoolean(2),
                    notes = r.IsDBNull(3) ? null : r.GetString(3),
                    createdAt = r.GetDateTime(4),
                });
            return Ok(list);
        }

        public class LineBody
        {
            public string FarmId { get; set; } = string.Empty;
            public string Name { get; set; } = string.Empty;
            public string? Notes { get; set; }
            public string? UserId { get; set; }
        }

        [HttpPost]
        public async Task<IActionResult> Create([FromBody] LineBody b)
        {
            if (string.IsNullOrWhiteSpace(b.FarmId) || string.IsNullOrWhiteSpace(b.Name))
                return BadRequest("farmId and name are required.");
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            using var ins = new NpgsqlCommand(@"
                INSERT INTO waterproductionlines (farmid, name, notes, createdby)
                VALUES (@F, @N, @No, @By) RETURNING id", conn);
            ins.Parameters.AddWithValue("@F", b.FarmId);
            ins.Parameters.AddWithValue("@N", b.Name.Trim());
            ins.Parameters.AddWithValue("@No", (object?)b.Notes ?? DBNull.Value);
            ins.Parameters.AddWithValue("@By", (object?)b.UserId ?? DBNull.Value);
            var id = (long)(await ins.ExecuteScalarAsync())!;
            return Ok(new { ok = true, id });
        }

        public class LineUpdateBody : LineBody { public bool IsActive { get; set; } = true; }

        [HttpPut("{id:long}")]
        public async Task<IActionResult> Update(long id, [FromBody] LineUpdateBody b)
        {
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            using var up = new NpgsqlCommand(@"
                UPDATE waterproductionlines
                   SET name = COALESCE(NULLIF(@N, ''), name), isactive = @A,
                       notes = @No, updatedat = now() AT TIME ZONE 'utc'
                 WHERE id = @I AND farmid = @F", conn);
            up.Parameters.AddWithValue("@I", id);
            up.Parameters.AddWithValue("@F", b.FarmId);
            up.Parameters.AddWithValue("@N", b.Name ?? "");
            up.Parameters.AddWithValue("@A", b.IsActive);
            up.Parameters.AddWithValue("@No", (object?)b.Notes ?? DBNull.Value);
            var n = await up.ExecuteNonQueryAsync();
            return n > 0 ? Ok(new { ok = true }) : NotFound();
        }
    }
}
