// Platform billing administration (spec Part 27): the configuration surface
// that lets pricing change WITHOUT a deployment — markets, price book
// entries, discount rules, settings, per-company billing state, credit notes,
// and a manual trigger for the daily maintenance pass.
//
// Every endpoint is gated on SystemAdmin / PlatformOwner (27.1). Company
// owners cannot reach any of this: tier rules and price books are the
// platform's, not the customer's.
//
// Pricing edits never mutate history (27.2): changing a price CLOSES the
// current entry (effectiveto = yesterday) and INSERTS a new effective-dated
// one, so every historical invoice keeps pointing at the entry that priced it.

using Microsoft.AspNetCore.Mvc;
using Npgsql;
using PoultryFarmAPIWeb.Business;

namespace PoultryFarmAPIWeb.Controllers
{
    [ApiController]
    [Route("api/PlatformBillingAdmin")]
    public class PlatformBillingAdminController : ControllerBase
    {
        private readonly IPlatformBillingService _svc;
        private readonly string _cs;

        public PlatformBillingAdminController(IPlatformBillingService svc, IConfiguration cfg)
        {
            _svc = svc;
            _cs = cfg.GetConnectionString("PoultryConn")
                  ?? cfg["ConnectionStrings:PoultryConn"] ?? "";
        }

        private async Task<bool> Denied(string userId) =>
            string.IsNullOrWhiteSpace(userId) || !await _svc.IsPlatformAdminAsync(userId);

        /// <summary>Everything an admin needs on one read: markets, tiers, profiles, rules, prices, discounts, settings.</summary>
        [HttpGet("config")]
        public async Task<IActionResult> Config([FromQuery] string userId)
        {
            if (await Denied(userId)) return StatusCode(403, "Platform administrators only.");
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();

            async Task<List<Dictionary<string, object?>>> Rows(string sql)
            {
                var list = new List<Dictionary<string, object?>>();
                using var cmd = new NpgsqlCommand(sql, conn);
                using var r = await cmd.ExecuteReaderAsync();
                while (await r.ReadAsync())
                {
                    var row = new Dictionary<string, object?>();
                    for (var i = 0; i < r.FieldCount; i++)
                        row[r.GetName(i)] = r.IsDBNull(i) ? null : r.GetValue(i);
                    list.Add(row);
                }
                return list;
            }

            return Ok(new
            {
                markets = await Rows("SELECT code, name, currencycode, provider, active FROM billingmarkets ORDER BY code"),
                tiers = await Rows("SELECT code, name, rank, active FROM platformtiers ORDER BY rank"),
                profiles = await Rows("SELECT code, name, metrictype, active FROM billingprofiles ORDER BY code"),
                tierRules = await Rows(@"SELECT id, profilecode, tiercode, minvalue, maxvalue, effectivefrom, effectiveto, active
                                           FROM billingtierrules ORDER BY profilecode, minvalue"),
                priceEntries = await Rows(@"SELECT e.id, b.marketcode, b.code AS pricebook, e.tiercode, e.profilecode,
                                                   e.currencycode, e.monthlyprice, e.annualprice, e.effectivefrom, e.effectiveto, e.active
                                              FROM pricebookentries e JOIN pricebooks b ON b.id = e.pricebookid
                                             ORDER BY b.marketcode, e.tiercode"),
                discounts = await Rows("SELECT id, mincompanies, percent, active FROM multicompanydiscountrules ORDER BY mincompanies"),
                settings = await Rows("SELECT key, value, description FROM platformbillingsettings ORDER BY key"),
                templateProfiles = await Rows("SELECT templatecode, defaultbillingprofile FROM businesstemplatebillingprofiles ORDER BY templatecode"),
                entitlements = await Rows("SELECT tiercode, capability, enabled, limitvalue FROM planentitlements ORDER BY tiercode, capability"),
            });
        }

        [HttpPut("setting")]
        public async Task<IActionResult> PutSetting([FromBody] AdminSettingBody req)
        {
            if (await Denied(req?.UserId ?? "")) return StatusCode(403, "Platform administrators only.");
            if (string.IsNullOrWhiteSpace(req!.Key)) return BadRequest("key is required.");
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            string? old = null;
            using (var q = new NpgsqlCommand("SELECT value FROM platformbillingsettings WHERE key=@K", conn))
            {
                q.Parameters.AddWithValue("@K", req.Key);
                old = await q.ExecuteScalarAsync() as string;
            }
            using (var up = new NpgsqlCommand(@"
                INSERT INTO platformbillingsettings (key, value) VALUES (@K, @V)
                ON CONFLICT (key) DO UPDATE SET value = @V, updatedatutc = now() AT TIME ZONE 'utc'", conn))
            {
                up.Parameters.AddWithValue("@K", req.Key);
                up.Parameters.AddWithValue("@V", req.Value ?? "");
                await up.ExecuteNonQueryAsync();
            }
            await PlatformBillingService.LogEventAsync(conn, null, null, "SettingChanged", $"{req.Key}={old}", $"{req.Key}={req.Value}", req.UserId, null);
            return Ok(new { ok = true });
        }

        /// <summary>Effective-dated price change: closes today's entry, inserts the new one (27.2/11.1).</summary>
        [HttpPost("price")]
        public async Task<IActionResult> PostPrice([FromBody] AdminPriceBody req)
        {
            if (await Denied(req?.UserId ?? "")) return StatusCode(403, "Platform administrators only.");
            if (string.IsNullOrWhiteSpace(req!.MarketCode) || string.IsNullOrWhiteSpace(req.TierCode))
                return BadRequest("marketCode and tierCode are required.");
            if (req.MonthlyPrice <= 0) return BadRequest("monthlyPrice must be positive.");

            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            using var tx = await conn.BeginTransactionAsync();

            long? bookId = null;
            using (var q = new NpgsqlCommand(@"
                SELECT id FROM pricebooks WHERE marketcode = @M AND active
                   AND CURRENT_DATE >= effectivefrom AND (effectiveto IS NULL OR CURRENT_DATE <= effectiveto)
                 ORDER BY effectivefrom DESC LIMIT 1", conn, (NpgsqlTransaction)tx))
            {
                q.Parameters.AddWithValue("@M", req.MarketCode.ToUpperInvariant());
                bookId = await q.ExecuteScalarAsync() as long?;
            }
            if (bookId is null)
            {
                using var ins = new NpgsqlCommand(@"
                    INSERT INTO pricebooks (code, marketcode, name, effectivefrom)
                    SELECT @C, @M, @N, CURRENT_DATE FROM billingmarkets WHERE code = @M
                    RETURNING id", conn, (NpgsqlTransaction)tx);
                ins.Parameters.AddWithValue("@C", $"{req.MarketCode.ToUpperInvariant()}-{DateTime.UtcNow:yyyy}");
                ins.Parameters.AddWithValue("@M", req.MarketCode.ToUpperInvariant());
                ins.Parameters.AddWithValue("@N", $"{req.MarketCode.ToUpperInvariant()} {DateTime.UtcNow:yyyy}");
                bookId = await ins.ExecuteScalarAsync() as long?;
                if (bookId is null) { await tx.RollbackAsync(); return BadRequest($"Unknown market {req.MarketCode}."); }
            }

            using (var close = new NpgsqlCommand(@"
                UPDATE pricebookentries SET effectiveto = CURRENT_DATE - 1
                 WHERE pricebookid = @B AND tiercode = @T
                   AND (profilecode = @P OR (profilecode IS NULL AND @P IS NULL))
                   AND active AND (effectiveto IS NULL OR effectiveto >= CURRENT_DATE)", conn, (NpgsqlTransaction)tx))
            {
                close.Parameters.AddWithValue("@B", bookId.Value);
                close.Parameters.AddWithValue("@T", req.TierCode);
                close.Parameters.AddWithValue("@P", (object?)req.ProfileCode ?? DBNull.Value);
                await close.ExecuteNonQueryAsync();
            }
            using (var ins = new NpgsqlCommand(@"
                INSERT INTO pricebookentries
                       (pricebookid, tiercode, profilecode, currencycode, monthlyprice, annualprice, effectivefrom)
                SELECT @B, @T, @P, m.currencycode, @MP, @AP, CURRENT_DATE
                  FROM pricebooks b JOIN billingmarkets m ON m.code = b.marketcode WHERE b.id = @B", conn, (NpgsqlTransaction)tx))
            {
                ins.Parameters.AddWithValue("@B", bookId.Value);
                ins.Parameters.AddWithValue("@T", req.TierCode);
                ins.Parameters.AddWithValue("@P", (object?)req.ProfileCode ?? DBNull.Value);
                ins.Parameters.AddWithValue("@MP", req.MonthlyPrice);
                ins.Parameters.AddWithValue("@AP", (object?)req.AnnualPrice ?? DBNull.Value);
                await ins.ExecuteNonQueryAsync();
            }
            await PlatformBillingService.LogEventAsync(conn, null, null, "PriceConfigured", null,
                $"{req.MarketCode}/{req.TierCode}/{req.ProfileCode ?? "*"} = {req.MonthlyPrice}", req.UserId, null, (NpgsqlTransaction)tx);
            await tx.CommitAsync();
            return Ok(new { ok = true });
        }

        /// <summary>Replace the discount ladder as a versioned set (8: rules live in data).</summary>
        [HttpPut("discounts")]
        public async Task<IActionResult> PutDiscounts([FromBody] AdminDiscountsBody req)
        {
            if (await Denied(req?.UserId ?? "")) return StatusCode(403, "Platform administrators only.");
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            using var tx = await conn.BeginTransactionAsync();
            using (var off = new NpgsqlCommand(
                "UPDATE multicompanydiscountrules SET active = FALSE, effectiveto = CURRENT_DATE - 1 WHERE active", conn, (NpgsqlTransaction)tx))
                await off.ExecuteNonQueryAsync();
            foreach (var rule in req!.Rules ?? new())
            {
                using var ins = new NpgsqlCommand(@"
                    INSERT INTO multicompanydiscountrules (mincompanies, percent, active, effectivefrom)
                    VALUES (@N, @P, TRUE, CURRENT_DATE)", conn, (NpgsqlTransaction)tx);
                ins.Parameters.AddWithValue("@N", rule.MinCompanies);
                ins.Parameters.AddWithValue("@P", rule.Percent);
                await ins.ExecuteNonQueryAsync();
            }
            await PlatformBillingService.LogEventAsync(conn, null, null, "DiscountRulesChanged", null,
                string.Join(", ", (req.Rules ?? new()).Select(x => $"{x.MinCompanies}+:{x.Percent}%")), req.UserId, null, (NpgsqlTransaction)tx);
            await tx.CommitAsync();
            return Ok(new { ok = true });
        }

        /// <summary>The admin lever on one company: participation, manual scale, custom/grandfathered price, profile override (9.2/6.2/11.2).</summary>
        [HttpPut("company-state")]
        public async Task<IActionResult> PutCompanyState([FromBody] AdminCompanyStateBody req)
        {
            if (await Denied(req?.UserId ?? "")) return StatusCode(403, "Platform administrators only.");
            if (string.IsNullOrWhiteSpace(req!.FarmId)) return BadRequest("farmId is required.");
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            using var upd = new NpgsqlCommand(@"
                UPDATE companybillingstates SET
                    participationstatus = COALESCE(@PS, participationstatus),
                    manualscalevalue = COALESCE(@MS, manualscalevalue),
                    custommonthlyprice = CASE WHEN @ClearCustom THEN NULL ELSE COALESCE(@CP, custommonthlyprice) END,
                    grandfatheredmonthlyprice = CASE WHEN @ClearGf THEN NULL ELSE COALESCE(@GP, grandfatheredmonthlyprice) END,
                    billingprofilecode = COALESCE(@BP, billingprofilecode),
                    operatingcountrycode = COALESCE(@OC, operatingcountrycode),
                    evaluationtrialenduntilutc = COALESCE(@EV, evaluationtrialenduntilutc),
                    exemptreason = COALESCE(@ER, exemptreason),
                    archivedatutc = CASE WHEN @PS = 'Archived' THEN now() AT TIME ZONE 'utc' ELSE archivedatutc END,
                    updatedatutc = now() AT TIME ZONE 'utc'
                 WHERE farmid = @F", conn);
            upd.Parameters.AddWithValue("@F", req.FarmId);
            upd.Parameters.AddWithValue("@PS", (object?)req.ParticipationStatus ?? DBNull.Value);
            upd.Parameters.AddWithValue("@MS", (object?)req.ManualScaleValue ?? DBNull.Value);
            upd.Parameters.AddWithValue("@CP", (object?)req.CustomMonthlyPrice ?? DBNull.Value);
            upd.Parameters.AddWithValue("@GP", (object?)req.GrandfatheredMonthlyPrice ?? DBNull.Value);
            upd.Parameters.AddWithValue("@ClearCustom", req.ClearCustomPrice);
            upd.Parameters.AddWithValue("@ClearGf", req.ClearGrandfatheredPrice);
            upd.Parameters.AddWithValue("@BP", (object?)req.BillingProfileCode ?? DBNull.Value);
            upd.Parameters.AddWithValue("@OC", (object?)req.OperatingCountryCode ?? DBNull.Value);
            upd.Parameters.AddWithValue("@EV", (object?)req.EvaluationUntilUtc ?? DBNull.Value);
            upd.Parameters.AddWithValue("@ER", (object?)req.ExemptReason ?? DBNull.Value);
            var n = await upd.ExecuteNonQueryAsync();
            if (n == 0) return NotFound("Company has no billing state yet — open its organization's billing once first.");
            await PlatformBillingService.LogEventAsync(conn, null, req.FarmId, "CompanyBillingStateChanged", null,
                System.Text.Json.JsonSerializer.Serialize(req), req.UserId, null);
            return Ok(new { ok = true });
        }

        [HttpPut("template-profile")]
        public async Task<IActionResult> PutTemplateProfile([FromBody] AdminTemplateProfileBody req)
        {
            if (await Denied(req?.UserId ?? "")) return StatusCode(403, "Platform administrators only.");
            if (string.IsNullOrWhiteSpace(req!.TemplateCode) || string.IsNullOrWhiteSpace(req.DefaultBillingProfile))
                return BadRequest("templateCode and defaultBillingProfile are required.");
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            using var up = new NpgsqlCommand(@"
                INSERT INTO businesstemplatebillingprofiles (templatecode, defaultbillingprofile)
                VALUES (@T, @P)
                ON CONFLICT (templatecode) DO UPDATE SET defaultbillingprofile = @P, updatedatutc = now() AT TIME ZONE 'utc'", conn);
            up.Parameters.AddWithValue("@T", req.TemplateCode);
            up.Parameters.AddWithValue("@P", req.DefaultBillingProfile);
            await up.ExecuteNonQueryAsync();
            await PlatformBillingService.LogEventAsync(conn, null, null, "TemplateProfileChanged", null,
                $"{req.TemplateCode} -> {req.DefaultBillingProfile}", req.UserId, null);
            return Ok(new { ok = true });
        }

        /// <summary>Credit note (spec 35): a new record that reduces an invoice's balance — history stays intact.</summary>
        [HttpPost("credit-note")]
        public async Task<IActionResult> PostCreditNote([FromBody] AdminCreditNoteBody req)
        {
            if (await Denied(req?.UserId ?? "")) return StatusCode(403, "Platform administrators only.");
            if (string.IsNullOrWhiteSpace(req!.InvoiceNumber) || req.Amount <= 0 || string.IsNullOrWhiteSpace(req.Reason))
                return BadRequest("invoiceNumber, a positive amount and a reason are required.");

            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            using var tx = await conn.BeginTransactionAsync();

            long invoiceId; long accountId; decimal balance; string currency;
            using (var q = new NpgsqlCommand(@"
                SELECT id, accountid, balance, currencycode FROM platforminvoices
                 WHERE invoicenumber = @N FOR UPDATE", conn, (NpgsqlTransaction)tx))
            {
                q.Parameters.AddWithValue("@N", req.InvoiceNumber);
                using var r = await q.ExecuteReaderAsync();
                if (!await r.ReadAsync()) return NotFound($"No invoice {req.InvoiceNumber}.");
                invoiceId = r.GetInt64(0); accountId = r.GetInt64(1);
                balance = r.GetDecimal(2); currency = r.GetString(3);
            }
            var amount = PlatformBillingRules.Money(Math.Min(req.Amount, balance));
            if (amount <= 0) return BadRequest("Invoice has no balance to credit.");

            using (var ins = new NpgsqlCommand(@"
                INSERT INTO platformcreditnotes (accountid, invoiceid, amount, currencycode, reason, createdby)
                VALUES (@A, @I, @Amt, @C, @R, @U)", conn, (NpgsqlTransaction)tx))
            {
                ins.Parameters.AddWithValue("@A", accountId);
                ins.Parameters.AddWithValue("@I", invoiceId);
                ins.Parameters.AddWithValue("@Amt", amount);
                ins.Parameters.AddWithValue("@C", currency);
                ins.Parameters.AddWithValue("@R", req.Reason);
                ins.Parameters.AddWithValue("@U", req.UserId);
                await ins.ExecuteNonQueryAsync();
            }
            using (var upd = new NpgsqlCommand(@"
                UPDATE platforminvoices
                   SET balance = GREATEST(0, balance - @Amt),
                       status = CASE WHEN balance - @Amt <= 0 THEN 'Paid' ELSE status END
                 WHERE id = @I", conn, (NpgsqlTransaction)tx))
            {
                upd.Parameters.AddWithValue("@Amt", amount);
                upd.Parameters.AddWithValue("@I", invoiceId);
                await upd.ExecuteNonQueryAsync();
            }
            await PlatformBillingService.LogEventAsync(conn, accountId, null, "CreditNoteApplied", null,
                $"{req.InvoiceNumber} {currency} {amount}: {req.Reason}", req.UserId, null, (NpgsqlTransaction)tx);
            await tx.CommitAsync();
            return Ok(new { ok = true, credited = amount, currency });
        }

        /// <summary>Run the daily maintenance pass on demand — the same code the worker runs.</summary>
        [HttpPost("run-maintenance")]
        public async Task<IActionResult> RunMaintenance([FromBody] AdminSettingBody req)
        {
            if (await Denied(req?.UserId ?? "")) return StatusCode(403, "Platform administrators only.");
            return Ok(new { report = await _svc.RunDailyMaintenanceAsync(req!.UserId) });
        }
    }

    public class AdminSettingBody { public string UserId { get; set; } = ""; public string Key { get; set; } = ""; public string? Value { get; set; } }
    public class AdminPriceBody
    {
        public string UserId { get; set; } = "";
        public string MarketCode { get; set; } = "";
        public string TierCode { get; set; } = "";
        public string? ProfileCode { get; set; }
        public decimal MonthlyPrice { get; set; }
        public decimal? AnnualPrice { get; set; }
    }
    public class AdminDiscountsBody
    {
        public string UserId { get; set; } = "";
        public List<AdminDiscountRule>? Rules { get; set; }
    }
    public class AdminDiscountRule { public int MinCompanies { get; set; } public decimal Percent { get; set; } }
    public class AdminCompanyStateBody
    {
        public string UserId { get; set; } = "";
        public string FarmId { get; set; } = "";
        public string? ParticipationStatus { get; set; }
        public decimal? ManualScaleValue { get; set; }
        public decimal? CustomMonthlyPrice { get; set; }
        public decimal? GrandfatheredMonthlyPrice { get; set; }
        public bool ClearCustomPrice { get; set; }
        public bool ClearGrandfatheredPrice { get; set; }
        public string? BillingProfileCode { get; set; }
        public string? OperatingCountryCode { get; set; }
        public DateTime? EvaluationUntilUtc { get; set; }
        public string? ExemptReason { get; set; }
    }
    public class AdminTemplateProfileBody
    {
        public string UserId { get; set; } = "";
        public string TemplateCode { get; set; } = "";
        public string DefaultBillingProfile { get; set; } = "";
    }
    public class AdminCreditNoteBody
    {
        public string UserId { get; set; } = "";
        public string InvoiceNumber { get; set; } = "";
        public decimal Amount { get; set; }
        public string Reason { get; set; } = "";
    }
}
