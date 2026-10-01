// Platform billing engine (migrations 329 + 330).
//
// The pipeline (spec Part 28): account → market/currency → eligible companies
// → per-company profile → metric → tier → price → evaluation snapshot → lines
// → multi-company discount → tax → one consolidated Organization invoice →
// provider checkout → settlement. Every step reads configuration (never
// source-code prices) and writes an auditable record.
//
// Provider access goes through IPlatformPaymentProvider (Part 12): this file
// never mentions a Paystack URL. Enforcement stays behind
// platformbillingsettings.enforcementenabled — status transitions here are
// bookkeeping until that switch is deliberately turned on.

using Microsoft.Extensions.Logging;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IPlatformBillingService
    {
        Task<BillingSummaryModel> GetSummaryAsync(string userId);
        Task<List<PlatformInvoiceModel>> GetInvoicesAsync(string userId);
        Task<List<PlatformPaymentModel>> GetPaymentsAsync(string userId);
        Task<PricingExplainModel?> ExplainAsync(string userId, string farmId);
        Task<StartCheckoutResponse> StartCheckoutAsync(StartCheckoutRequest req);
        Task<(bool Ok, string Message)> VerifyAndSettleAsync(string userId, string reference);
        Task<(bool Ok, string Message)> ProcessPaystackWebhookAsync(string payload, string signatureHeader);

        // Phase B
        Task<(bool Ok, string Message)> RequestMarketChangeAsync(string userId, string marketCode, string? reason);
        Task<(bool Ok, string Message)> CancelMarketChangeAsync(string userId);
        Task<MarketChangePreviewModel?> PreviewMarketAsync(string userId, string marketCode);
        Task<(bool Ok, string Message)> SetBillingCycleAsync(string userId, string cycle);
        Task<(bool Ok, string Message)> CancelAtPeriodEndAsync(string userId, string? reason);
        Task<(bool Ok, string Message)> ReactivateAsync(string userId);
        Task<PlanUsageModel?> GetPlanUsageAsync(string userId, string farmId);
        Task<List<EntitlementModel>> GetEntitlementsAsync(string userId, string farmId);
        Task<string> RunDailyMaintenanceAsync(string actor);
        Task<bool> IsPlatformAdminAsync(string userId);
    }

    public class PlatformBillingService : IPlatformBillingService
    {
        private readonly string _cs;
        private readonly IPlatformPaymentProvider _provider;
        private readonly ILogger<PlatformBillingService> _log;

        public PlatformBillingService(string connectionString, IPlatformPaymentProvider provider,
            ILogger<PlatformBillingService> log)
        {
            _cs = connectionString;
            _provider = provider;
            _log = log;
        }

        // ------------------------------------------------------------------
        // Configuration
        // ------------------------------------------------------------------

        internal sealed record Config(
            Dictionary<string, (string Name, string Currency, string Provider, bool Active)> Markets,
            Dictionary<string, (string Name, int Rank)> Tiers,
            Dictionary<string, (string Name, string MetricType)> Profiles,
            List<TierRule> TierRules,
            List<PriceEntry> Entries,
            List<DiscountRule> Discounts,
            Dictionary<string, string> Settings)
        {
            public int IntSetting(string key, int fallback) =>
                Settings.TryGetValue(key, out var v) && int.TryParse(v, out var n) ? n : fallback;
            public decimal DecSetting(string key, decimal fallback) =>
                Settings.TryGetValue(key, out var v) && decimal.TryParse(v, out var n) ? n : fallback;
            public bool BoolSetting(string key) =>
                Settings.TryGetValue(key, out var v) && string.Equals(v, "true", StringComparison.OrdinalIgnoreCase);
        }

        private async Task<Config> LoadConfigAsync(NpgsqlConnection conn, string marketCode)
        {
            var markets = new Dictionary<string, (string, string, string, bool)>(StringComparer.OrdinalIgnoreCase);
            var tiers = new Dictionary<string, (string, int)>(StringComparer.OrdinalIgnoreCase);
            var profiles = new Dictionary<string, (string, string)>(StringComparer.OrdinalIgnoreCase);
            var rules = new List<TierRule>();
            var entries = new List<PriceEntry>();
            var discounts = new List<DiscountRule>();
            var settings = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

            using (var cmd = new NpgsqlCommand(@"
                SELECT code, name, currencycode, provider, active FROM billingmarkets;
                SELECT code, name, rank FROM platformtiers WHERE active;
                SELECT code, name, metrictype FROM billingprofiles WHERE active;
                SELECT profilecode, tiercode, minvalue, maxvalue FROM billingtierrules
                 WHERE active AND CURRENT_DATE >= effectivefrom AND (effectiveto IS NULL OR CURRENT_DATE <= effectiveto);
                SELECT e.id, e.tiercode, e.profilecode, e.currencycode, e.monthlyprice, e.annualprice, e.taxinclusive
                  FROM pricebookentries e JOIN pricebooks b ON b.id = e.pricebookid
                 WHERE b.marketcode = @Market AND b.active AND e.active
                   AND CURRENT_DATE >= b.effectivefrom AND (b.effectiveto IS NULL OR CURRENT_DATE <= b.effectiveto)
                   AND CURRENT_DATE >= e.effectivefrom AND (e.effectiveto IS NULL OR CURRENT_DATE <= e.effectiveto);
                SELECT mincompanies, percent FROM multicompanydiscountrules
                 WHERE active AND CURRENT_DATE >= effectivefrom AND (effectiveto IS NULL OR CURRENT_DATE <= effectiveto);
                SELECT key, value FROM platformbillingsettings;", conn))
            {
                cmd.Parameters.AddWithValue("@Market", marketCode);
                using var r = await cmd.ExecuteReaderAsync();
                while (await r.ReadAsync())
                    markets[r.GetString(0)] = (r.GetString(1), r.GetString(2), r.GetString(3), r.GetBoolean(4));
                await r.NextResultAsync();
                while (await r.ReadAsync()) tiers[r.GetString(0)] = (r.GetString(1), r.GetInt32(2));
                await r.NextResultAsync();
                while (await r.ReadAsync()) profiles[r.GetString(0)] = (r.GetString(1), r.GetString(2));
                await r.NextResultAsync();
                while (await r.ReadAsync())
                    rules.Add(new TierRule(r.GetString(0), r.GetString(1), r.GetDecimal(2),
                        r.IsDBNull(3) ? null : r.GetDecimal(3)));
                await r.NextResultAsync();
                while (await r.ReadAsync())
                    entries.Add(new PriceEntry(r.GetInt64(0), r.GetString(1),
                        r.IsDBNull(2) ? null : r.GetString(2), r.GetString(3), r.GetDecimal(4),
                        r.IsDBNull(5) ? null : r.GetDecimal(5), r.GetBoolean(6)));
                await r.NextResultAsync();
                while (await r.ReadAsync()) discounts.Add(new DiscountRule(r.GetInt32(0), r.GetDecimal(1)));
                await r.NextResultAsync();
                while (await r.ReadAsync()) settings[r.GetString(0)] = r.GetString(1);
            }
            return new Config(markets, tiers, profiles, rules, entries, discounts, settings);
        }

        // ------------------------------------------------------------------
        // Account
        // ------------------------------------------------------------------

        private async Task<BillingAccountModel> EnsureAccountAsync(NpgsqlConnection conn, string userId)
        {
            var acct = await ReadAccountAsync(conn, userId);
            if (acct != null) return acct;

            string? officeCountry = null, orgCode = null, email = null, name = null;
            using (var u = new NpgsqlCommand(@"
                SELECT businessofficecountry, organizationcode, email,
                       COALESCE(NULLIF(TRIM(CONCAT(firstname,' ',lastname)), ''), username)
                  FROM aspnetusers WHERE id = @Id", conn))
            {
                u.Parameters.AddWithValue("@Id", userId);
                using var r = await u.ExecuteReaderAsync();
                if (await r.ReadAsync())
                {
                    officeCountry = r.IsDBNull(0) ? null : r.GetString(0);
                    orgCode = r.IsDBNull(1) ? null : r.GetString(1);
                    email = r.IsDBNull(2) ? null : r.GetString(2);
                    name = r.IsDBNull(3) ? null : r.GetString(3);
                }
            }

            // aspnetusers carries no creation date, so the trial anchors to the
            // oldest company this owner has — an EXISTING customer's trial is
            // measured from when they actually started, not from the day this
            // feature shipped (spec 10.2).
            var created = DateTime.UtcNow;
            using (var fc = new NpgsqlCommand(@"
                SELECT MIN(f.createdat) FROM userfarms uf JOIN farms f ON f.farmid = uf.farmid
                 WHERE uf.userid = @U", conn))
            {
                fc.Parameters.AddWithValue("@U", userId);
                if (await fc.ExecuteScalarAsync() is DateTime firstFarm) created = firstFarm;
            }

            // Declared country → market; only an ACTIVE market is assignable,
            // never geolocation (spec 3.4).
            var market = "GH";
            var c = (officeCountry ?? "").Trim().ToUpperInvariant();
            if (c is "NG" or "NIGERIA") market = "NG";
            else if (c is "US" or "USA" or "UNITED STATES") market = "US";
            using (var m = new NpgsqlCommand("SELECT active FROM billingmarkets WHERE code = @C", conn))
            {
                m.Parameters.AddWithValue("@C", market);
                if (await m.ExecuteScalarAsync() is not true) market = "GH";
            }

            var trialDays = 150;
            using (var s = new NpgsqlCommand("SELECT value FROM platformbillingsettings WHERE key='trialdays'", conn))
                if (await s.ExecuteScalarAsync() is string tv && int.TryParse(tv, out var td)) trialDays = td;

            using (var ins = new NpgsqlCommand(@"
                INSERT INTO organizationbillingaccounts
                       (owneruserid, orgcode, billingmarketcode, currencycode, billingemail,
                        billingcontactname, verificationstatus, verificationmethod,
                        trialstartutc, trialendutc, status)
                SELECT @U, @Org, @M, m.currencycode, @Email, @Name, 'AutoVerified', 'SelfDeclared',
                       @TrialStart, @TrialEnd, 'Trial'
                  FROM billingmarkets m WHERE m.code = @M
                ON CONFLICT (owneruserid) DO NOTHING", conn))
            {
                ins.Parameters.AddWithValue("@U", userId);
                ins.Parameters.AddWithValue("@Org", (object?)orgCode ?? DBNull.Value);
                ins.Parameters.AddWithValue("@M", market);
                ins.Parameters.AddWithValue("@Email", (object?)email ?? DBNull.Value);
                ins.Parameters.AddWithValue("@Name", (object?)name ?? DBNull.Value);
                ins.Parameters.AddWithValue("@TrialStart", created);
                ins.Parameters.AddWithValue("@TrialEnd", created.AddDays(trialDays));
                await ins.ExecuteNonQueryAsync();
            }
            await LogEventAsync(conn, null, null, "AccountCreated", null, market, userId, "auto-provisioned from Business Office");
            _log.LogInformation("Billing account auto-provisioned for {UserId} in market {Market}", userId, market);
            return (await ReadAccountAsync(conn, userId))!;
        }

        private static async Task<BillingAccountModel?> ReadAccountAsync(NpgsqlConnection conn, string userId)
        {
            using var cmd = new NpgsqlCommand(@"
                SELECT id, owneruserid, orgcode, billingmarketcode, currencycode, billingemail,
                       billingcontactname, status, billingcycle, trialstartutc, trialendutc,
                       verificationstatus, currentperiodstart, currentperiodend, cancelatperiodend, provider,
                       pendingmarketcode, pendingmarketeffective
                  FROM organizationbillingaccounts WHERE owneruserid = @U", conn);
            cmd.Parameters.AddWithValue("@U", userId);
            using var r = await cmd.ExecuteReaderAsync();
            if (!await r.ReadAsync()) return null;
            var a = new BillingAccountModel
            {
                Id = r.GetInt64(0),
                OwnerUserId = r.GetString(1),
                OrgCode = r.IsDBNull(2) ? null : r.GetString(2),
                MarketCode = r.GetString(3),
                CurrencyCode = r.GetString(4),
                BillingEmail = r.IsDBNull(5) ? null : r.GetString(5),
                BillingContactName = r.IsDBNull(6) ? null : r.GetString(6),
                Status = r.GetString(7),
                BillingCycle = r.GetString(8),
                TrialStartUtc = r.IsDBNull(9) ? null : r.GetDateTime(9),
                TrialEndUtc = r.IsDBNull(10) ? null : r.GetDateTime(10),
                VerificationStatus = r.GetString(11),
                CurrentPeriodStart = r.IsDBNull(12) ? null : r.GetDateTime(12),
                CurrentPeriodEnd = r.IsDBNull(13) ? null : r.GetDateTime(13),
                CancelAtPeriodEnd = r.GetBoolean(14),
                Provider = r.IsDBNull(15) ? null : r.GetString(15),
                PendingMarketCode = r.IsDBNull(16) ? null : r.GetString(16),
                PendingMarketEffective = r.IsDBNull(17) ? null : r.GetDateTime(17),
            };
            if (a.TrialEndUtc.HasValue)
                a.TrialDaysLeft = Math.Max(0, (int)Math.Ceiling((a.TrialEndUtc.Value - DateTime.UtcNow).TotalDays));
            return a;
        }

        // ------------------------------------------------------------------
        // Companies + evaluation
        // ------------------------------------------------------------------

        private sealed record CompanyRow(string FarmId, string Name, string Family, string? Template, string? TemplateDefaultProfile);

        /// <summary>
        /// The organization's companies — the platform's own
        /// spcompany_getbyuserid (the list the Companies screen shows),
        /// restricted to Admin: the owner role in this platform's Admin|Staff
        /// vocabulary. Ownership is the query itself (spec 31). The template's
        /// configured default profile rides along for the 4.6 resolution chain.
        /// </summary>
        private static async Task<List<CompanyRow>> LoadCompaniesAsync(NpgsqlConnection conn, string userId)
        {
            var list = new List<CompanyRow>();
            using var cmd = new NpgsqlCommand(@"
                SELECT c.farmid, c.name, c.type, g.genericbusinesstemplate, tp.defaultbillingprofile
                  FROM spcompany_getbyuserid(p_userid => @U::text) c
                  LEFT JOIN genericcompanyprofiles g ON g.farmid = c.farmid
                  LEFT JOIN businesstemplatebillingprofiles tp ON tp.templatecode = g.genericbusinesstemplate
                 WHERE LOWER(COALESCE(c.role, 'admin')) = 'admin'
                 ORDER BY c.name", conn);
            cmd.Parameters.AddWithValue("@U", userId);
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Add(new CompanyRow(r.GetString(0), r.GetString(1),
                    r.IsDBNull(2) ? "Poultry" : r.GetString(2),
                    r.IsDBNull(3) ? null : r.GetString(3),
                    r.IsDBNull(4) ? null : r.GetString(4)));
            return list;
        }

        private sealed record CompanyState(string? ProfileOverride, string Participation,
            decimal? ManualScale, decimal? CustomPrice, decimal? GrandfatheredPrice, DateTime? EvaluationUntilUtc);

        private static async Task<CompanyState> EnsureCompanyStateAsync(NpgsqlConnection conn, long accountId, string farmId)
        {
            using (var ins = new NpgsqlCommand(@"
                INSERT INTO companybillingstates (farmid, accountid)
                VALUES (@F, @A) ON CONFLICT (farmid) DO NOTHING", conn))
            {
                ins.Parameters.AddWithValue("@F", farmId);
                ins.Parameters.AddWithValue("@A", accountId);
                await ins.ExecuteNonQueryAsync();
            }
            using var cmd = new NpgsqlCommand(@"
                SELECT billingprofilecode, participationstatus, manualscalevalue,
                       custommonthlyprice, grandfatheredmonthlyprice, evaluationtrialenduntilutc
                  FROM companybillingstates WHERE farmid = @F", conn);
            cmd.Parameters.AddWithValue("@F", farmId);
            using var r = await cmd.ExecuteReaderAsync();
            await r.ReadAsync();
            return new CompanyState(
                r.IsDBNull(0) ? null : r.GetString(0),
                r.GetString(1),
                r.IsDBNull(2) ? null : r.GetDecimal(2),
                r.IsDBNull(3) ? null : r.GetDecimal(3),
                r.IsDBNull(4) ? null : r.GetDecimal(4),
                r.IsDBNull(5) ? null : r.GetDateTime(5));
        }

        private static async Task<decimal> MetricValueAsync(NpgsqlConnection conn, string metricType, string farmId, CompanyState state)
        {
            if (string.Equals(metricType, "ActiveBirdCount", StringComparison.OrdinalIgnoreCase))
            {
                using var cmd = new NpgsqlCommand("SELECT spplatformbilling_activebirds(@F)", conn);
                cmd.Parameters.AddWithValue("@F", farmId);
                var v = await cmd.ExecuteScalarAsync();
                return v is decimal d ? d : Convert.ToDecimal(v ?? 0);
            }
            return state.ManualScale ?? 0m;
        }

        private async Task<CompanyBillingRowModel> EvaluateCompanyAsync(
            NpgsqlConnection conn, Config cfg, BillingAccountModel acct, CompanyRow company,
            string reason, DateTime periodStart, DateTime periodEnd,
            bool persistEvaluation = true, NpgsqlTransaction? tx = null)
        {
            var state = await EnsureCompanyStateAsync(conn, acct.Id, company.FarmId);
            // Resolution chain (4.6): company override > template default > family map.
            var profileCode = PlatformBillingRules.ResolveProfileCode(
                company.Family, state.ProfileOverride ?? company.TemplateDefaultProfile);
            var (profileName, metricType) = cfg.Profiles.TryGetValue(profileCode, out var p)
                ? p : (profileCode, "ManualScale");

            var row = new CompanyBillingRowModel
            {
                FarmId = company.FarmId,
                CompanyName = company.Name,
                CompanyFamily = company.Family,
                BusinessType = string.IsNullOrWhiteSpace(company.Template) ? company.Family : company.Template!,
                BillingProfileCode = profileCode,
                BillingProfileName = profileName,
                MetricType = metricType,
                CurrencyCode = acct.CurrencyCode,
                ParticipationStatus = state.Participation,
            };

            if (!string.Equals(state.Participation, "Active", StringComparison.OrdinalIgnoreCase)
                && !string.Equals(state.Participation, "EnterpriseContract", StringComparison.OrdinalIgnoreCase))
            {
                row.PricingStatus = "Exempt";   // Archived / Exempt / Suspended contribute no line (9.1/9.2)
                return row;
            }

            // A company still inside its own evaluation window (10.3) is shown
            // but not billed, and does NOT block the rest of the invoice.
            if (state.EvaluationUntilUtc.HasValue && state.EvaluationUntilUtc.Value > DateTime.UtcNow)
            {
                row.PricingStatus = "Evaluation";
                row.EvaluationUntilUtc = state.EvaluationUntilUtc;
                row.MetricValue = await MetricValueAsync(conn, metricType, company.FarmId, state);
                return row;
            }

            row.MetricValue = await MetricValueAsync(conn, metricType, company.FarmId, state);
            row.TierCode = PlatformBillingRules.QualifyTier(cfg.TierRules, profileCode, row.MetricValue);
            row.TierName = row.TierCode != null && cfg.Tiers.TryGetValue(row.TierCode, out var t) ? t.Name : row.TierCode;

            long? entryId = null;
            if (state.CustomPrice.HasValue)
            {
                row.MonthlyAmount = PlatformBillingRules.Money(state.CustomPrice.Value);
                row.PricingStatus = "CustomPrice";
            }
            else if (state.GrandfatheredPrice.HasValue)
            {
                row.MonthlyAmount = PlatformBillingRules.Money(state.GrandfatheredPrice.Value);
                row.PricingStatus = "Grandfathered";
            }
            else if (row.TierCode != null)
            {
                var entry = PlatformBillingRules.ResolvePrice(cfg.Entries, row.TierCode, profileCode);
                var cyclePrice = entry is null ? null : PlatformBillingRules.CyclePrice(entry, acct.BillingCycle);
                if (entry != null && cyclePrice.HasValue)
                {
                    entryId = entry.Id;
                    row.MonthlyAmount = PlatformBillingRules.Money(cyclePrice.Value);
                    row.PricingStatus = "Resolved";
                }
                else
                {
                    row.PricingStatus = "PricingNotConfigured";  // never zero, never a guess (39)
                }
            }
            else
            {
                row.PricingStatus = "PricingNotConfigured";
            }

            if (!persistEvaluation) return row;

            using var ins = new NpgsqlCommand(@"
                INSERT INTO companybillingevaluations
                       (accountid, farmid, billingprofilecode, metrictype, metricvalue, tiercode,
                        marketcode, currencycode, pricebookentryid, monthlyamount, pricingstatus,
                        evaluationreason, billingperiodstart, billingperiodend)
                VALUES (@A, @F, @P, @MT, @MV, @T, @MK, @C, @E, @Amt, @PS, @R, @S, @En)
                RETURNING id", conn, tx);
            ins.Parameters.AddWithValue("@A", acct.Id);
            ins.Parameters.AddWithValue("@F", company.FarmId);
            ins.Parameters.AddWithValue("@P", profileCode);
            ins.Parameters.AddWithValue("@MT", metricType);
            ins.Parameters.AddWithValue("@MV", row.MetricValue);
            ins.Parameters.AddWithValue("@T", (object?)row.TierCode ?? DBNull.Value);
            ins.Parameters.AddWithValue("@MK", acct.MarketCode);
            ins.Parameters.AddWithValue("@C", acct.CurrencyCode);
            ins.Parameters.AddWithValue("@E", (object?)entryId ?? DBNull.Value);
            ins.Parameters.AddWithValue("@Amt", (object?)row.MonthlyAmount ?? DBNull.Value);
            ins.Parameters.AddWithValue("@PS", row.PricingStatus);
            ins.Parameters.AddWithValue("@R", reason);
            ins.Parameters.AddWithValue("@S", periodStart.Date);
            ins.Parameters.AddWithValue("@En", periodEnd.Date);
            row.EvaluationId = (long)(await ins.ExecuteScalarAsync())!;
            return row;
        }

        /// <summary>Monthly = calendar month; annual = twelve months from the month start (11.3).</summary>
        private static (DateTime Start, DateTime End) CurrentPeriod(string billingCycle)
        {
            var today = DateTime.UtcNow.Date;
            var start = new DateTime(today.Year, today.Month, 1);
            return string.Equals(billingCycle, "annual", StringComparison.OrdinalIgnoreCase)
                ? (start, start.AddYears(1).AddDays(-1))
                : (start, start.AddMonths(1).AddDays(-1));
        }

        // ------------------------------------------------------------------
        // Summary / preview / pending changes
        // ------------------------------------------------------------------

        public async Task<BillingSummaryModel> GetSummaryAsync(string userId)
        {
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            var acct = await EnsureAccountAsync(conn, userId);
            var cfg = await LoadConfigAsync(conn, acct.MarketCode);
            var (ps, pe) = CurrentPeriod(acct.BillingCycle);

            var companies = new List<CompanyBillingRowModel>();
            foreach (var c in await LoadCompaniesAsync(conn, userId))
                companies.Add(await EvaluateCompanyAsync(conn, cfg, acct, c, "Preview", ps, pe));

            var summary = new BillingSummaryModel
            {
                Account = acct,
                Companies = companies,
                EnforcementEnabled = cfg.BoolSetting("enforcementenabled"),
                Preview = BuildPreview(cfg, acct, companies, ps, pe),
                PendingTierChanges = await PendingTierChangesAsync(conn, cfg, acct, companies, ps),
            };
            return summary;
        }

        private static BillPreviewModel BuildPreview(Config cfg, BillingAccountModel acct,
            List<CompanyBillingRowModel> companies, DateTime ps, DateTime pe)
        {
            var billable = companies.Where(x => x.PricingStatus is "Resolved" or "CustomPrice" or "Grandfathered").ToList();
            var discount = PlatformBillingRules.PickDiscount(cfg.Discounts, billable.Count);
            var taxRate = cfg.DecSetting("taxratepercent", 0m);
            var (sub, disc, tax, total) = PlatformBillingRules.Totals(
                billable.Select(x => x.MonthlyAmount ?? 0m), discount?.Percent ?? 0m, taxRate);
            return new BillPreviewModel
            {
                Subtotal = sub,
                EligibleCompanyCount = billable.Count,
                DiscountPercent = discount?.Percent ?? 0m,
                DiscountAmount = disc,
                TaxRate = taxRate,
                TaxAmount = tax,
                Total = total,
                CurrencyCode = acct.CurrencyCode,
                HasUnpricedCompanies = companies.Any(x => x.PricingStatus == "PricingNotConfigured"),
                PeriodStart = ps,
                PeriodEnd = pe,
            };
        }

        /// <summary>
        /// "Your operation now qualifies for Growth…" (spec 5.3/30): a change
        /// is pending when the tier evaluated NOW differs from the tier this
        /// company was last INVOICED at. Recorded once per period as a
        /// TierChangeScheduled event so support can see when the customer was
        /// told.
        /// </summary>
        private async Task<List<PendingTierChangeModel>> PendingTierChangesAsync(
            NpgsqlConnection conn, Config cfg, BillingAccountModel acct,
            List<CompanyBillingRowModel> companies, DateTime periodStart)
        {
            var changes = new List<PendingTierChangeModel>();
            foreach (var c in companies.Where(x => x.TierCode != null && x.PricingStatus == "Resolved"))
            {
                string? invoicedTier = null;
                using (var q = new NpgsqlCommand(@"
                    SELECT tiercode FROM companybillingevaluations
                     WHERE farmid = @F AND evaluationreason = 'InvoiceGeneration' AND tiercode IS NOT NULL
                     ORDER BY evaluatedatutc DESC LIMIT 1", conn))
                {
                    q.Parameters.AddWithValue("@F", c.FarmId);
                    invoicedTier = await q.ExecuteScalarAsync() as string;
                }
                if (invoicedTier is null || string.Equals(invoicedTier, c.TierCode, StringComparison.OrdinalIgnoreCase))
                    continue;

                var effective = CurrentPeriod(acct.BillingCycle).Start >= periodStart
                    ? periodStart : CurrentPeriod(acct.BillingCycle).Start;
                changes.Add(new PendingTierChangeModel
                {
                    FarmId = c.FarmId,
                    CompanyName = c.CompanyName,
                    FromTierName = cfg.Tiers.TryGetValue(invoicedTier, out var ft) ? ft.Name : invoicedTier,
                    ToTierName = c.TierName ?? c.TierCode!,
                    EffectiveDate = effective,
                });

                var reference = $"{c.FarmId}:{periodStart:yyyyMM}";
                using var exists = new NpgsqlCommand(@"
                    SELECT 1 FROM billingevents
                     WHERE eventtype = 'TierChangeScheduled' AND reference = @R LIMIT 1", conn);
                exists.Parameters.AddWithValue("@R", reference);
                if (await exists.ExecuteScalarAsync() is null)
                    await LogEventAsync(conn, acct.Id, c.FarmId, "TierChangeScheduled",
                        invoicedTier, c.TierCode, "system", reference);
            }
            return changes;
        }

        public async Task<PricingExplainModel?> ExplainAsync(string userId, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            var acct = await EnsureAccountAsync(conn, userId);
            var cfg = await LoadConfigAsync(conn, acct.MarketCode);

            using var cmd = new NpgsqlCommand(@"
                SELECT e.billingprofilecode, e.metrictype, e.metricvalue, e.tiercode,
                       e.monthlyamount, e.currencycode, e.pricingstatus, e.evaluatedatutc, f.name
                  FROM companybillingevaluations e
                  JOIN farms f ON f.farmid = e.farmid
                 WHERE e.accountid = @A AND e.farmid = @F
                 ORDER BY e.evaluatedatutc DESC LIMIT 1", conn);
            cmd.Parameters.AddWithValue("@A", acct.Id);
            cmd.Parameters.AddWithValue("@F", farmId);
            using var r = await cmd.ExecuteReaderAsync();
            if (!await r.ReadAsync()) return null;

            var profile = r.GetString(0);
            var tierCode = r.IsDBNull(3) ? null : r.GetString(3);
            var model = new PricingExplainModel
            {
                FarmId = farmId,
                CompanyName = r.GetString(8),
                BillingProfileName = cfg.Profiles.TryGetValue(profile, out var p) ? p.Name : profile,
                MetricType = r.GetString(1),
                MetricValue = r.GetDecimal(2),
                TierName = tierCode != null && cfg.Tiers.TryGetValue(tierCode, out var t) ? t.Name : tierCode,
                MonthlyAmount = r.IsDBNull(4) ? null : r.GetDecimal(4),
                CurrencyCode = r.GetString(5),
                PricingStatus = r.GetString(6),
                EvaluatedAtUtc = r.GetDateTime(7),
                MarketName = cfg.Markets.TryGetValue(acct.MarketCode, out var mk) ? mk.Name : acct.MarketCode,
            };

            var next = cfg.TierRules
                .Where(x => x.ProfileCode.Equals(profile, StringComparison.OrdinalIgnoreCase)
                            && x.MinValue > model.MetricValue)
                .OrderBy(x => x.MinValue).FirstOrDefault();
            if (next != null)
            {
                model.NextTierAtValue = next.MinValue;
                model.NextTierName = cfg.Tiers.TryGetValue(next.TierCode, out var nt) ? nt.Name : next.TierCode;
            }
            return model;
        }

        // ------------------------------------------------------------------
        // Invoices
        // ------------------------------------------------------------------

        public async Task<List<PlatformInvoiceModel>> GetInvoicesAsync(string userId)
        {
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            var acct = await EnsureAccountAsync(conn, userId);

            var list = new List<PlatformInvoiceModel>();
            using (var cmd = new NpgsqlCommand(@"
                SELECT id, invoicenumber, currencycode, periodstart, periodend, issuedate, duedate,
                       subtotal, discountamount, taxamount, totalamount, amountpaid, balance, status
                  FROM platforminvoices WHERE accountid = @A ORDER BY periodstart DESC", conn))
            {
                cmd.Parameters.AddWithValue("@A", acct.Id);
                using var r = await cmd.ExecuteReaderAsync();
                while (await r.ReadAsync())
                    list.Add(new PlatformInvoiceModel
                    {
                        Id = r.GetInt64(0),
                        InvoiceNumber = r.GetString(1),
                        CurrencyCode = r.GetString(2),
                        PeriodStart = r.GetDateTime(3),
                        PeriodEnd = r.GetDateTime(4),
                        IssueDate = r.GetDateTime(5),
                        DueDate = r.GetDateTime(6),
                        Subtotal = r.GetDecimal(7),
                        DiscountAmount = r.GetDecimal(8),
                        TaxAmount = r.GetDecimal(9),
                        TotalAmount = r.GetDecimal(10),
                        AmountPaid = r.GetDecimal(11),
                        Balance = r.GetDecimal(12),
                        Status = r.GetString(13),
                    });
            }
            foreach (var inv in list)
            {
                using var lc = new NpgsqlCommand(@"
                    SELECT farmid, description, tiercode, metricvalue, metrictype, unitprice, lineamount
                      FROM platforminvoicelines WHERE invoiceid = @I ORDER BY id", conn);
                lc.Parameters.AddWithValue("@I", inv.Id);
                using var lr = await lc.ExecuteReaderAsync();
                while (await lr.ReadAsync())
                    inv.Lines.Add(new PlatformInvoiceLineModel
                    {
                        FarmId = lr.IsDBNull(0) ? null : lr.GetString(0),
                        Description = lr.GetString(1),
                        TierCode = lr.IsDBNull(2) ? null : lr.GetString(2),
                        MetricValue = lr.IsDBNull(3) ? null : lr.GetDecimal(3),
                        MetricType = lr.IsDBNull(4) ? null : lr.GetString(4),
                        UnitPrice = lr.GetDecimal(5),
                        LineAmount = lr.GetDecimal(6),
                    });
            }
            return list;
        }

        private async Task<(long Id, string Number, decimal Balance, string Status)> EnsureCurrentInvoiceAsync(
            NpgsqlConnection conn, BillingAccountModel acct, Config cfg)
        {
            var (ps, pe) = CurrentPeriod(acct.BillingCycle);

            async Task<(long, string, decimal, string)?> ReadExistingAsync()
            {
                using var q = new NpgsqlCommand(@"
                    SELECT id, invoicenumber, balance, status FROM platforminvoices
                     WHERE accountid = @A AND periodstart = @S", conn);
                q.Parameters.AddWithValue("@A", acct.Id);
                q.Parameters.AddWithValue("@S", ps);
                using var r = await q.ExecuteReaderAsync();
                if (await r.ReadAsync())
                    return (r.GetInt64(0), r.GetString(1), r.GetDecimal(2), r.GetString(3));
                return null;
            }

            if (await ReadExistingAsync() is { } existing) return existing;

            using var tx = await conn.BeginTransactionAsync();

            var companies = new List<CompanyBillingRowModel>();
            foreach (var c in await LoadCompaniesAsync(conn, acct.OwnerUserId))
                companies.Add(await EvaluateCompanyAsync(conn, cfg, acct, c, "InvoiceGeneration", ps, pe,
                    persistEvaluation: true, (NpgsqlTransaction)tx));

            var billable = companies.Where(x => x.PricingStatus is "Resolved" or "CustomPrice" or "Grandfathered").ToList();
            if (companies.Any(x => x.PricingStatus == "PricingNotConfigured"))
                throw new InvalidOperationException(
                    "Pricing for one of your business types is being finalized. Please contact VisibilityCore support.");
            if (billable.Count == 0)
                throw new InvalidOperationException("There are no billable companies on this account yet.");

            var discount = PlatformBillingRules.PickDiscount(cfg.Discounts, billable.Count);
            var taxRate = cfg.DecSetting("taxratepercent", 0m);
            var (sub, disc, tax, total) = PlatformBillingRules.Totals(
                billable.Select(x => x.MonthlyAmount ?? 0m), discount?.Percent ?? 0m, taxRate);
            var number = PlatformBillingRules.InvoiceNumber(acct.Id, ps);

            long invoiceId;
            using (var ins = new NpgsqlCommand(@"
                INSERT INTO platforminvoices
                       (invoicenumber, accountid, marketcode, currencycode, periodstart, periodend,
                        issuedate, duedate, subtotal, discountrulesnapshot, eligiblecompanycount,
                        discountpercent, discountamount, taxrate, taxamount, totalamount, amountpaid, balance, status)
                VALUES (@N, @A, @MK, @C, @S, @E, CURRENT_DATE, CURRENT_DATE + 7, @Sub, @DR, @EC,
                        @DP, @DA, @TR, @TA, @Tot, 0, @Tot, 'Open')
                ON CONFLICT (accountid, periodstart) DO NOTHING
                RETURNING id", conn, (NpgsqlTransaction)tx))
            {
                ins.Parameters.AddWithValue("@N", number);
                ins.Parameters.AddWithValue("@A", acct.Id);
                ins.Parameters.AddWithValue("@MK", acct.MarketCode);
                ins.Parameters.AddWithValue("@C", acct.CurrencyCode);
                ins.Parameters.AddWithValue("@S", ps);
                ins.Parameters.AddWithValue("@E", pe);
                ins.Parameters.AddWithValue("@Sub", sub);
                ins.Parameters.AddWithValue("@DR", discount is null ? DBNull.Value
                    : $"min {discount.MinCompanies} companies -> {discount.Percent}%");
                ins.Parameters.AddWithValue("@EC", billable.Count);
                ins.Parameters.AddWithValue("@DP", discount?.Percent ?? 0m);
                ins.Parameters.AddWithValue("@DA", disc);
                ins.Parameters.AddWithValue("@TR", taxRate);
                ins.Parameters.AddWithValue("@TA", tax);
                ins.Parameters.AddWithValue("@Tot", total);
                var idObj = await ins.ExecuteScalarAsync();
                if (idObj is null)
                {
                    await tx.RollbackAsync();
                    return (await ReadExistingAsync())!.Value;
                }
                invoiceId = (long)idObj;
            }

            foreach (var b in billable)
            {
                using var line = new NpgsqlCommand(@"
                    INSERT INTO platforminvoicelines
                           (invoiceid, farmid, description, billingprofilecode, metrictype,
                            metricvalue, tiercode, quantity, unitprice, lineamount, evaluationid)
                    VALUES (@I, @F, @D, @P, @MT, @MV, @T, 1, @U, @L, @E)", conn, (NpgsqlTransaction)tx);
                line.Parameters.AddWithValue("@I", invoiceId);
                line.Parameters.AddWithValue("@F", b.FarmId);
                line.Parameters.AddWithValue("@D", $"{b.CompanyName} — {b.TierName ?? "Custom"}");
                line.Parameters.AddWithValue("@P", b.BillingProfileCode);
                line.Parameters.AddWithValue("@MT", b.MetricType);
                line.Parameters.AddWithValue("@MV", b.MetricValue);
                line.Parameters.AddWithValue("@T", (object?)b.TierCode ?? DBNull.Value);
                line.Parameters.AddWithValue("@U", b.MonthlyAmount ?? 0m);
                line.Parameters.AddWithValue("@L", b.MonthlyAmount ?? 0m);
                line.Parameters.AddWithValue("@E", (object?)b.EvaluationId ?? DBNull.Value);
                await line.ExecuteNonQueryAsync();
            }

            await LogEventAsync(conn, acct.Id, null, "InvoiceGenerated", null, number, acct.OwnerUserId, null, (NpgsqlTransaction)tx);
            await tx.CommitAsync();
            _log.LogInformation("Invoice {Number} generated for account {AccountId}: {Total} {Currency}",
                number, acct.Id, total, acct.CurrencyCode);
            return (invoiceId, number, total, "Open");
        }

        // ------------------------------------------------------------------
        // Checkout + settlement (through the provider seam)
        // ------------------------------------------------------------------

        public async Task<StartCheckoutResponse> StartCheckoutAsync(StartCheckoutRequest req)
        {
            if (string.IsNullOrWhiteSpace(req.UserId) || string.IsNullOrWhiteSpace(req.SuccessUrl)
                || string.IsNullOrWhiteSpace(req.FailureUrl))
                return new StartCheckoutResponse { Success = false, Message = "userId, successUrl and failureUrl are required." };

            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            var acct = await EnsureAccountAsync(conn, req.UserId);
            var cfg = await LoadConfigAsync(conn, acct.MarketCode);

            if (!cfg.Markets.TryGetValue(acct.MarketCode, out var market) || !market.Active)
                return new StartCheckoutResponse { Success = false, Message = $"Billing market {acct.MarketCode} is not open yet." };
            if (!string.Equals(market.Provider, _provider.Name, StringComparison.OrdinalIgnoreCase))
                return new StartCheckoutResponse { Success = false, Message = "No payment provider is configured for this market yet." };
            if (!_provider.IsConfigured)
                return new StartCheckoutResponse { Success = false, Message = $"{_provider.Name} is not configured on this service (PAYSTACK_SECRET_KEY)." };

            (long Id, string Number, decimal Balance, string Status) invoice;
            try { invoice = await EnsureCurrentInvoiceAsync(conn, acct, cfg); }
            catch (InvalidOperationException ex)
            { return new StartCheckoutResponse { Success = false, Message = ex.Message }; }

            if (invoice.Balance <= 0m || invoice.Status == "Paid")
                return new StartCheckoutResponse { Success = false, Message = "This period's invoice is already settled." };

            var reference = $"{invoice.Number}-{Guid.NewGuid():N}"[..40];
            var checkout = await _provider.CreateCheckoutAsync(
                acct.BillingEmail ?? "billing@visibilitycore.com",
                PlatformBillingRules.ToMinorUnits(invoice.Balance, acct.CurrencyCode),
                acct.CurrencyCode, reference, req.SuccessUrl, req.FailureUrl, invoice.Number, acct.Id);
            if (!checkout.Ok)
                return new StartCheckoutResponse { Success = false, Message = checkout.Message };

            using (var upd = new NpgsqlCommand(
                "UPDATE platforminvoices SET externalreference = @R WHERE id = @I", conn))
            {
                upd.Parameters.AddWithValue("@R", reference);
                upd.Parameters.AddWithValue("@I", invoice.Id);
                await upd.ExecuteNonQueryAsync();
            }
            await LogEventAsync(conn, acct.Id, null, "CheckoutInitiated", null, reference, req.UserId, null);
            _log.LogInformation("Checkout {Reference} started for invoice {Number}", reference, invoice.Number);

            return new StartCheckoutResponse
            {
                Success = true,
                CheckoutUrl = checkout.CheckoutUrl,
                Reference = reference,
                InvoiceNumber = invoice.Number,
                Amount = invoice.Balance,
                CurrencyCode = acct.CurrencyCode,
            };
        }

        public async Task<(bool Ok, string Message)> VerifyAndSettleAsync(string userId, string reference)
        {
            if (!_provider.IsConfigured) return (false, "Payment provider is not configured on this service.");
            var charge = await _provider.VerifyAsync(reference);
            if (!charge.Ok) return (false, charge.Message ?? "Verification failed.");
            return await SettleAsync(charge.ExternalPaymentId, charge.Reference, charge.AmountMinor,
                charge.Currency, charge.PaidAtUtc, charge.MethodSummary);
        }

        private async Task<(bool Ok, string Message)> SettleAsync(
            string? externalPaymentId, string reference, long amountMinor, string currency,
            DateTime paidAtUtc, string? methodSummary)
        {
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            using var tx = await conn.BeginTransactionAsync();

            // References are "<invoicenumber>-<guid>": the fallback match means a
            // payment settles even when a SECOND checkout attempt replaced the
            // invoice's stored reference (Part 60, duplicate checkout).
            var numberFromRef = PlatformBillingRules.InvoiceNumberFromReference(reference);

            long invoiceId; long accountId; string number; string curr;
            using (var q = new NpgsqlCommand(@"
                SELECT id, accountid, invoicenumber, currencycode
                  FROM platforminvoices
                 WHERE externalreference = @R OR invoicenumber = @N
                 ORDER BY (externalreference = @R) DESC
                 LIMIT 1
                 FOR UPDATE", conn, (NpgsqlTransaction)tx))
            {
                q.Parameters.AddWithValue("@R", reference);
                q.Parameters.AddWithValue("@N", numberFromRef);
                using var r = await q.ExecuteReaderAsync();
                if (!await r.ReadAsync()) return (false, $"No invoice matches reference {reference}.");
                invoiceId = r.GetInt64(0); accountId = r.GetInt64(1);
                number = r.GetString(2); curr = r.GetString(3);
            }

            var amount = PlatformBillingRules.Money(amountMinor / 100m);
            if (!string.Equals(curr, currency, StringComparison.OrdinalIgnoreCase))
                return (false, $"Payment currency {currency} does not match invoice currency {curr}.");

            using (var ins = new NpgsqlCommand(@"
                INSERT INTO platformpayments
                       (accountid, invoiceid, provider, externalpaymentid, externalreference,
                        amount, currencycode, status, paymentdateutc, methodsummary)
                VALUES (@A, @I, @Prov, @EP, @R, @Amt, @C, 'Succeeded', @Paid, @M)
                ON CONFLICT (provider, externalreference) WHERE externalreference IS NOT NULL DO NOTHING
                RETURNING id", conn, (NpgsqlTransaction)tx))
            {
                ins.Parameters.AddWithValue("@A", accountId);
                ins.Parameters.AddWithValue("@I", invoiceId);
                ins.Parameters.AddWithValue("@Prov", _provider.Name);
                ins.Parameters.AddWithValue("@EP", (object?)externalPaymentId ?? DBNull.Value);
                ins.Parameters.AddWithValue("@R", reference);
                ins.Parameters.AddWithValue("@Amt", amount);
                ins.Parameters.AddWithValue("@C", curr);
                ins.Parameters.AddWithValue("@Paid", paidAtUtc);
                ins.Parameters.AddWithValue("@M", (object?)methodSummary ?? DBNull.Value);
                if (await ins.ExecuteScalarAsync() is null)
                {
                    await tx.RollbackAsync();
                    return (true, "Payment already recorded.");   // duplicate delivery posts once (13.3)
                }
            }

            using (var updInv = new NpgsqlCommand(@"
                UPDATE platforminvoices
                   SET amountpaid = amountpaid + @Amt,
                       balance = GREATEST(0, balance - @Amt),
                       status = CASE WHEN balance - @Amt <= 0 THEN 'Paid' ELSE status END
                 WHERE id = @I", conn, (NpgsqlTransaction)tx))
            {
                updInv.Parameters.AddWithValue("@Amt", amount);
                updInv.Parameters.AddWithValue("@I", invoiceId);
                await updInv.ExecuteNonQueryAsync();
            }

            using (var updAcct = new NpgsqlCommand(@"
                UPDATE organizationbillingaccounts
                   SET status = 'Active', provider = @Prov,
                       currentperiodstart = (SELECT periodstart FROM platforminvoices WHERE id = @I),
                       currentperiodend   = (SELECT periodend   FROM platforminvoices WHERE id = @I),
                       updatedatutc = now() AT TIME ZONE 'utc'
                 WHERE id = @A", conn, (NpgsqlTransaction)tx))
            {
                updAcct.Parameters.AddWithValue("@Prov", _provider.Name);
                updAcct.Parameters.AddWithValue("@I", invoiceId);
                updAcct.Parameters.AddWithValue("@A", accountId);
                await updAcct.ExecuteNonQueryAsync();
            }

            await LogEventAsync(conn, accountId, null, "PaymentSucceeded", null,
                $"{number} {curr} {amount}", "system", reference, (NpgsqlTransaction)tx);
            await tx.CommitAsync();
            _log.LogInformation("Payment {Reference} of {Amount} {Currency} settled invoice {Number}",
                reference, amount, curr, number);
            return (true, $"Payment of {curr} {amount} applied to {number}.");
        }

        // ------------------------------------------------------------------
        // Webhook
        // ------------------------------------------------------------------

        public async Task<(bool Ok, string Message)> ProcessPaystackWebhookAsync(string payload, string signatureHeader)
        {
            var ev = _provider.ParseWebhook(payload, signatureHeader);
            if (!ev.SignatureValid) return (false, "Invalid signature.");

            var hash = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(
                System.Text.Encoding.UTF8.GetBytes(payload))).ToLowerInvariant();

            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();

            using (var ins = new NpgsqlCommand(@"
                INSERT INTO billingwebhookevents (provider, externaleventid, eventtype, payloadhash)
                VALUES (@P, @E, @T, @H)
                ON CONFLICT (provider, payloadhash) DO NOTHING RETURNING id", conn))
            {
                ins.Parameters.AddWithValue("@P", _provider.Name);
                ins.Parameters.AddWithValue("@E", (object?)ev.ExternalPaymentId ?? DBNull.Value);
                ins.Parameters.AddWithValue("@T", ev.EventType);
                ins.Parameters.AddWithValue("@H", hash);
                if (await ins.ExecuteScalarAsync() is null)
                    return (true, "Duplicate delivery ignored.");
            }

            string resultMsg; string resultStatus;
            if (ev.EventType == "charge.success" && !string.IsNullOrWhiteSpace(ev.Reference))
            {
                var (ok, msg) = await SettleAsync(ev.ExternalPaymentId, ev.Reference!, ev.AmountMinor,
                    ev.Currency, ev.PaidAtUtc, ev.MethodSummary);
                resultMsg = msg; resultStatus = ok ? "Processed" : "Failed";
            }
            else if (ev.EventType == "charge.failed" && !string.IsNullOrWhiteSpace(ev.Reference))
            {
                var (ok, msg) = await RecordFailedPaymentAsync(conn, ev.ExternalPaymentId, ev.Reference!,
                    ev.AmountMinor, ev.Currency, ev.FailureMessage);
                resultMsg = msg; resultStatus = ok ? "Processed" : "Failed";
            }
            else
            {
                resultMsg = $"Event {ev.EventType} acknowledged."; resultStatus = "Ignored";
            }

            using (var upd = new NpgsqlCommand(@"
                UPDATE billingwebhookevents
                   SET processedatutc = now() AT TIME ZONE 'utc', processingstatus = @S, error = @Err
                 WHERE provider = @P AND payloadhash = @H", conn))
            {
                upd.Parameters.AddWithValue("@S", resultStatus);
                upd.Parameters.AddWithValue("@Err", resultStatus == "Failed" ? resultMsg : (object)DBNull.Value);
                upd.Parameters.AddWithValue("@P", _provider.Name);
                upd.Parameters.AddWithValue("@H", hash);
                await upd.ExecuteNonQueryAsync();
            }
            _log.LogInformation("Webhook {EventType} -> {Status}: {Message}", ev.EventType, resultStatus, resultMsg);
            return (true, resultMsg);
        }

        /// <summary>A failed attempt is a first-class record too (spec Part 14), idempotently.</summary>
        private async Task<(bool Ok, string Message)> RecordFailedPaymentAsync(
            NpgsqlConnection conn, string? externalPaymentId, string reference, long amountMinor,
            string currency, string? failureMessage)
        {
            var numberFromRef = PlatformBillingRules.InvoiceNumberFromReference(reference);
            long? accountId = null; long? invoiceId = null;
            using (var q = new NpgsqlCommand(@"
                SELECT id, accountid FROM platforminvoices
                 WHERE externalreference = @R OR invoicenumber = @N
                 ORDER BY (externalreference = @R) DESC LIMIT 1", conn))
            {
                q.Parameters.AddWithValue("@R", reference);
                q.Parameters.AddWithValue("@N", numberFromRef);
                using var r = await q.ExecuteReaderAsync();
                if (await r.ReadAsync()) { invoiceId = r.GetInt64(0); accountId = r.GetInt64(1); }
            }
            if (accountId is null) return (true, $"Failed charge {reference} matches no invoice; recorded as event only.");

            using (var ins = new NpgsqlCommand(@"
                INSERT INTO platformpayments
                       (accountid, invoiceid, provider, externalpaymentid, externalreference,
                        amount, currencycode, status, failuremessage)
                VALUES (@A, @I, @P, @EP, @R, @Amt, @C, 'Failed', @FM)
                ON CONFLICT (provider, externalreference) WHERE externalreference IS NOT NULL DO NOTHING", conn))
            {
                ins.Parameters.AddWithValue("@A", accountId.Value);
                ins.Parameters.AddWithValue("@I", (object?)invoiceId ?? DBNull.Value);
                ins.Parameters.AddWithValue("@P", _provider.Name);
                ins.Parameters.AddWithValue("@EP", (object?)externalPaymentId ?? DBNull.Value);
                ins.Parameters.AddWithValue("@R", reference);
                ins.Parameters.AddWithValue("@Amt", PlatformBillingRules.Money(amountMinor / 100m));
                ins.Parameters.AddWithValue("@C", currency);
                ins.Parameters.AddWithValue("@FM", (object?)failureMessage ?? DBNull.Value);
                await ins.ExecuteNonQueryAsync();
            }
            await LogEventAsync(conn, accountId, null, "PaymentFailed", null, failureMessage, "system", reference);
            return (true, $"Failed charge recorded for {reference}.");
        }

        // ------------------------------------------------------------------
        // Market change (spec 3.7/46) — a controlled request, never a dropdown
        // ------------------------------------------------------------------

        public async Task<(bool Ok, string Message)> RequestMarketChangeAsync(string userId, string marketCode, string? reason)
        {
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            var acct = await EnsureAccountAsync(conn, userId);
            var code = (marketCode ?? "").Trim().ToUpperInvariant();
            if (string.Equals(code, acct.MarketCode, StringComparison.OrdinalIgnoreCase))
                return (false, "That is already your billing market.");

            using (var m = new NpgsqlCommand("SELECT active FROM billingmarkets WHERE code = @C", conn))
            {
                m.Parameters.AddWithValue("@C", code);
                var active = await m.ExecuteScalarAsync();
                if (active is null) return (false, $"Unknown billing market {code}.");
                if (active is not true) return (false, $"Billing market {code} is not open yet.");
            }

            // Effective next cycle: current invoices and the running period are
            // never touched (46 — historical invoices unchanged).
            var effective = CurrentPeriod(acct.BillingCycle).End.AddDays(1);
            using (var upd = new NpgsqlCommand(@"
                UPDATE organizationbillingaccounts
                   SET pendingmarketcode = @C, pendingmarketeffective = @E,
                       updatedatutc = now() AT TIME ZONE 'utc'
                 WHERE id = @A", conn))
            {
                upd.Parameters.AddWithValue("@C", code);
                upd.Parameters.AddWithValue("@E", effective.Date);
                upd.Parameters.AddWithValue("@A", acct.Id);
                await upd.ExecuteNonQueryAsync();
            }
            await LogEventAsync(conn, acct.Id, null, "BillingMarketChangeRequested",
                acct.MarketCode, code, userId, reason ?? "");
            return (true, $"Billing market change to {code} takes effect {effective:d}. Your current period is unchanged.");
        }

        public async Task<(bool Ok, string Message)> CancelMarketChangeAsync(string userId)
        {
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            var acct = await EnsureAccountAsync(conn, userId);
            if (acct.PendingMarketCode is null) return (false, "No market change is pending.");
            using (var upd = new NpgsqlCommand(@"
                UPDATE organizationbillingaccounts
                   SET pendingmarketcode = NULL, pendingmarketeffective = NULL,
                       updatedatutc = now() AT TIME ZONE 'utc'
                 WHERE id = @A", conn))
            {
                upd.Parameters.AddWithValue("@A", acct.Id);
                await upd.ExecuteNonQueryAsync();
            }
            await LogEventAsync(conn, acct.Id, null, "BillingMarketChangeCancelled", acct.PendingMarketCode, acct.MarketCode, userId, null);
            return (true, "Pending market change cancelled.");
        }

        /// <summary>The "show resulting price impact" half of 3.7 — same engine, target market's config, nothing persisted.</summary>
        public async Task<MarketChangePreviewModel?> PreviewMarketAsync(string userId, string marketCode)
        {
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            var acct = await EnsureAccountAsync(conn, userId);
            var code = (marketCode ?? "").Trim().ToUpperInvariant();
            var cfg = await LoadConfigAsync(conn, code);
            if (!cfg.Markets.TryGetValue(code, out var market)) return null;

            var previewAcct = new BillingAccountModel
            {
                Id = acct.Id,
                OwnerUserId = acct.OwnerUserId,
                MarketCode = code,
                CurrencyCode = market.Currency,
                BillingCycle = acct.BillingCycle,
            };
            var (ps, pe) = CurrentPeriod(acct.BillingCycle);
            var companies = new List<CompanyBillingRowModel>();
            foreach (var c in await LoadCompaniesAsync(conn, userId))
                companies.Add(await EvaluateCompanyAsync(conn, cfg, previewAcct, c, "Preview", ps, pe,
                    persistEvaluation: false));

            return new MarketChangePreviewModel
            {
                MarketCode = code,
                MarketName = market.Name,
                CurrencyCode = market.Currency,
                MarketActive = market.Active,
                Companies = companies,
                Preview = BuildPreview(cfg, previewAcct, companies, ps, pe),
            };
        }

        // ------------------------------------------------------------------
        // Cycle, cancellation
        // ------------------------------------------------------------------

        public async Task<(bool Ok, string Message)> SetBillingCycleAsync(string userId, string cycle)
        {
            var c = (cycle ?? "").Trim().ToLowerInvariant();
            if (c is not ("monthly" or "annual")) return (false, "Billing cycle must be monthly or annual.");
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            var acct = await EnsureAccountAsync(conn, userId);
            if (string.Equals(acct.BillingCycle, c, StringComparison.OrdinalIgnoreCase))
                return (false, $"Billing cycle is already {c}.");
            using (var upd = new NpgsqlCommand(@"
                UPDATE organizationbillingaccounts SET billingcycle = @C, updatedatutc = now() AT TIME ZONE 'utc'
                 WHERE id = @A", conn))
            {
                upd.Parameters.AddWithValue("@C", c);
                upd.Parameters.AddWithValue("@A", acct.Id);
                await upd.ExecuteNonQueryAsync();
            }
            await LogEventAsync(conn, acct.Id, null, "BillingCycleChanged", acct.BillingCycle, c, userId, null);
            return (true, $"Billing cycle set to {c}. It applies from your next invoice; the current period is unchanged.");
        }

        public async Task<(bool Ok, string Message)> CancelAtPeriodEndAsync(string userId, string? reason)
        {
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            var acct = await EnsureAccountAsync(conn, userId);
            if (acct.CancelAtPeriodEnd) return (false, "Cancellation is already scheduled.");
            using (var upd = new NpgsqlCommand(@"
                UPDATE organizationbillingaccounts SET cancelatperiodend = TRUE, updatedatutc = now() AT TIME ZONE 'utc'
                 WHERE id = @A", conn))
            {
                upd.Parameters.AddWithValue("@A", acct.Id);
                await upd.ExecuteNonQueryAsync();
            }
            await LogEventAsync(conn, acct.Id, null, "CancellationRequested", null,
                acct.CurrentPeriodEnd?.ToString("yyyy-MM-dd") ?? "period end", userId, reason);
            var paidThrough = acct.CurrentPeriodEnd?.ToString("d") ?? "the end of the current period";
            return (true, $"Your subscription will not renew. You keep full access through {paidThrough}.");
        }

        public async Task<(bool Ok, string Message)> ReactivateAsync(string userId)
        {
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            var acct = await EnsureAccountAsync(conn, userId);
            if (!acct.CancelAtPeriodEnd && acct.Status != "Cancelled")
                return (false, "The subscription is not cancelled.");
            using (var upd = new NpgsqlCommand(@"
                UPDATE organizationbillingaccounts
                   SET cancelatperiodend = FALSE,
                       status = CASE WHEN status = 'Cancelled' THEN 'Active' ELSE status END,
                       updatedatutc = now() AT TIME ZONE 'utc'
                 WHERE id = @A", conn))
            {
                upd.Parameters.AddWithValue("@A", acct.Id);
                await upd.ExecuteNonQueryAsync();
            }
            await LogEventAsync(conn, acct.Id, null, "SubscriptionReactivated", null, null, userId, null);
            return (true, "Welcome back — your subscription will continue.");   // no duplicate subscription (21)
        }

        // ------------------------------------------------------------------
        // Company Plan & Usage (spec 23) + entitlements (17)
        // ------------------------------------------------------------------

        public async Task<PlanUsageModel?> GetPlanUsageAsync(string userId, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();

            // The viewer must be a member of this company; anyone in the farm
            // may SEE the plan, only the Business Office manages it (57).
            using (var member = new NpgsqlCommand(
                "SELECT 1 FROM userfarms WHERE userid = @U AND farmid = @F", conn))
            {
                member.Parameters.AddWithValue("@U", userId);
                member.Parameters.AddWithValue("@F", farmId);
                if (await member.ExecuteScalarAsync() is null) return null;
            }

            using var cmd = new NpgsqlCommand(@"
                SELECT e.billingprofilecode, e.metrictype, e.metricvalue, e.tiercode, e.monthlyamount,
                       e.currencycode, e.pricingstatus, e.evaluatedatutc, f.name,
                       COALESCE(a.billingcontactname, a.orgcode, 'your Business Office')
                  FROM companybillingevaluations e
                  JOIN farms f ON f.farmid = e.farmid
                  JOIN organizationbillingaccounts a ON a.id = e.accountid
                 WHERE e.farmid = @F
                 ORDER BY e.evaluatedatutc DESC LIMIT 1", conn);
            cmd.Parameters.AddWithValue("@F", farmId);
            using var r = await cmd.ExecuteReaderAsync();
            if (!await r.ReadAsync()) return null;

            return new PlanUsageModel
            {
                FarmId = farmId,
                CompanyName = r.GetString(8),
                BillingProfileCode = r.GetString(0),
                MetricType = r.GetString(1),
                MetricValue = r.GetDecimal(2),
                TierCode = r.IsDBNull(3) ? null : r.GetString(3),
                MonthlyAmount = r.IsDBNull(4) ? null : r.GetDecimal(4),
                CurrencyCode = r.GetString(5),
                PricingStatus = r.GetString(6),
                EvaluatedAtUtc = r.GetDateTime(7),
                ManagedBy = r.GetString(9),
            };
        }

        public async Task<List<EntitlementModel>> GetEntitlementsAsync(string userId, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            var list = new List<EntitlementModel>();

            string? tierCode = null;
            using (var q = new NpgsqlCommand(@"
                SELECT e.tiercode FROM companybillingevaluations e
                 WHERE e.farmid = @F AND e.tiercode IS NOT NULL
                 ORDER BY e.evaluatedatutc DESC LIMIT 1", conn))
            {
                q.Parameters.AddWithValue("@F", farmId);
                tierCode = await q.ExecuteScalarAsync() as string;
            }
            if (tierCode is null) return list;   // no tier yet: nothing restricted, nothing listed

            using var cmd = new NpgsqlCommand(@"
                SELECT capability, enabled, limitvalue FROM planentitlements WHERE tiercode = @T", conn);
            cmd.Parameters.AddWithValue("@T", tierCode);
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Add(new EntitlementModel
                {
                    TierCode = tierCode,
                    Capability = r.GetString(0),
                    Enabled = r.GetBoolean(1),
                    Limit = r.IsDBNull(2) ? null : r.GetDecimal(2),
                });
            return list;   // a capability with NO row is unlimited by convention (17)
        }

        // ------------------------------------------------------------------
        // Daily maintenance (spec 20/33) — deterministic, idempotent, lockable
        // ------------------------------------------------------------------

        public async Task<string> RunDailyMaintenanceAsync(string actor)
        {
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();

            // One runner at a time across every instance.
            using (var lk = new NpgsqlCommand("SELECT pg_try_advisory_lock(3290001)", conn))
                if (await lk.ExecuteScalarAsync() is not true)
                    return "Another maintenance run holds the lock; skipped.";

            var report = new List<string>();
            try
            {
                // 1. Apply due market changes at a period boundary (3.7).
                using (var due = new NpgsqlCommand(@"
                    SELECT id, owneruserid, billingmarketcode, pendingmarketcode FROM organizationbillingaccounts
                     WHERE pendingmarketcode IS NOT NULL AND pendingmarketeffective <= CURRENT_DATE", conn))
                using (var r = await due.ExecuteReaderAsync())
                {
                    var rows = new List<(long, string, string, string)>();
                    while (await r.ReadAsync()) rows.Add((r.GetInt64(0), r.GetString(1), r.GetString(2), r.GetString(3)));
                    r.Close();
                    foreach (var (id, owner, oldM, newM) in rows)
                    {
                        using var upd = new NpgsqlCommand(@"
                            UPDATE organizationbillingaccounts a
                               SET billingmarketcode = @N,
                                   currencycode = m.currencycode,
                                   pendingmarketcode = NULL, pendingmarketeffective = NULL,
                                   updatedatutc = now() AT TIME ZONE 'utc'
                              FROM billingmarkets m
                             WHERE a.id = @A AND m.code = @N AND m.active", conn);
                        upd.Parameters.AddWithValue("@N", newM);
                        upd.Parameters.AddWithValue("@A", id);
                        if (await upd.ExecuteNonQueryAsync() > 0)
                        {
                            await LogEventAsync(conn, id, null, "BillingMarketChanged", oldM, newM, actor, "scheduled");
                            report.Add($"market {oldM}->{newM} applied for account {id}");
                        }
                    }
                }

                // 2. Invoice past-due bookkeeping + account status ladder (20).
                using (var upd = new NpgsqlCommand(@"
                    UPDATE platforminvoices SET status = 'PastDue'
                     WHERE status = 'Open' AND duedate < CURRENT_DATE", conn))
                    report.Add($"{await upd.ExecuteNonQueryAsync()} invoices past due");

                var graceDays = 14; var suspendDays = 14;
                using (var s = new NpgsqlCommand(
                    "SELECT key, value FROM platformbillingsettings WHERE key IN ('gracedays','suspenddaysaftergrace')", conn))
                using (var r = await s.ExecuteReaderAsync())
                    while (await r.ReadAsync())
                    {
                        if (r.GetString(0) == "gracedays") int.TryParse(r.GetString(1), out graceDays);
                        else int.TryParse(r.GetString(1), out suspendDays);
                    }

                using (var q = new NpgsqlCommand(@"
                    SELECT a.id, a.status, MIN(i.duedate)
                      FROM organizationbillingaccounts a
                      JOIN platforminvoices i ON i.accountid = a.id AND i.status IN ('Open','PastDue') AND i.balance > 0
                     WHERE a.status IN ('Active','PastDue','GracePeriod','Suspended')
                     GROUP BY a.id, a.status", conn))
                using (var r = await q.ExecuteReaderAsync())
                {
                    var rows = new List<(long, string, DateTime)>();
                    while (await r.ReadAsync()) rows.Add((r.GetInt64(0), r.GetString(1), r.GetDateTime(2)));
                    r.Close();
                    foreach (var (id, current, oldestDue) in rows)
                    {
                        var target = PlatformBillingRules.AccountStatusFor(
                            oldestDue, DateTime.UtcNow.Date, graceDays, suspendDays);
                        if (target == current) continue;
                        using var upd = new NpgsqlCommand(
                            "UPDATE organizationbillingaccounts SET status = @S, updatedatutc = now() AT TIME ZONE 'utc' WHERE id = @A", conn);
                        upd.Parameters.AddWithValue("@S", target);
                        upd.Parameters.AddWithValue("@A", id);
                        await upd.ExecuteNonQueryAsync();
                        await LogEventAsync(conn, id, null, $"Account{target}", current, target, actor, "dunning");
                        report.Add($"account {id}: {current} -> {target}");
                    }
                }

                // 3. Complete scheduled cancellations at period end (21).
                using (var q = new NpgsqlCommand(@"
                    SELECT id, owneruserid FROM organizationbillingaccounts
                     WHERE cancelatperiodend AND currentperiodend IS NOT NULL AND currentperiodend < CURRENT_DATE
                       AND status <> 'Cancelled'", conn))
                using (var r = await q.ExecuteReaderAsync())
                {
                    var rows = new List<(long, string)>();
                    while (await r.ReadAsync()) rows.Add((r.GetInt64(0), r.GetString(1)));
                    r.Close();
                    foreach (var (id, owner) in rows)
                    {
                        using var upd = new NpgsqlCommand(
                            "UPDATE organizationbillingaccounts SET status = 'Cancelled', updatedatutc = now() AT TIME ZONE 'utc' WHERE id = @A", conn);
                        upd.Parameters.AddWithValue("@A", id);
                        await upd.ExecuteNonQueryAsync();
                        await LogEventAsync(conn, id, null, "SubscriptionCancelled", null, null, actor, "period end reached");
                        report.Add($"account {id} cancelled at period end");
                    }
                }

                // 4. Auto-generate the new period's invoice for Active accounts —
                //    only when deliberately enabled (33; ships off).
                var autoInvoice = false;
                using (var s = new NpgsqlCommand(
                    "SELECT value FROM platformbillingsettings WHERE key='autoinvoiceenabled'", conn))
                    autoInvoice = string.Equals(await s.ExecuteScalarAsync() as string, "true", StringComparison.OrdinalIgnoreCase);
                if (autoInvoice)
                {
                    using var q = new NpgsqlCommand(@"
                        SELECT owneruserid FROM organizationbillingaccounts a
                         WHERE a.status = 'Active' AND NOT a.cancelatperiodend
                           AND NOT EXISTS (SELECT 1 FROM platforminvoices i
                                            WHERE i.accountid = a.id AND i.periodstart = date_trunc('month', CURRENT_DATE)::date)", conn);
                    var owners = new List<string>();
                    using (var r = await q.ExecuteReaderAsync())
                        while (await r.ReadAsync()) owners.Add(r.GetString(0));
                    foreach (var owner in owners)
                    {
                        try
                        {
                            var acct = await EnsureAccountAsync(conn, owner);
                            var cfg = await LoadConfigAsync(conn, acct.MarketCode);
                            var inv = await EnsureCurrentInvoiceAsync(conn, acct, cfg);
                            report.Add($"invoice {inv.Number} auto-generated");
                        }
                        catch (InvalidOperationException ex)
                        {
                            // Unpriced companies block generation loudly, not silently (39).
                            _log.LogWarning("Auto-invoice skipped for {Owner}: {Reason}", owner, ex.Message);
                            report.Add($"auto-invoice skipped for account of {owner}: {ex.Message}");
                        }
                    }
                }
            }
            finally
            {
                using var ul = new NpgsqlCommand("SELECT pg_advisory_unlock(3290001)", conn);
                await ul.ExecuteNonQueryAsync();
            }

            var text = report.Count == 0 ? "Nothing to do." : string.Join("; ", report);
            _log.LogInformation("Billing maintenance: {Report}", text);
            return text;
        }

        // ------------------------------------------------------------------
        // Payments list, admin gate, audit
        // ------------------------------------------------------------------

        public async Task<List<PlatformPaymentModel>> GetPaymentsAsync(string userId)
        {
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            var acct = await EnsureAccountAsync(conn, userId);
            var list = new List<PlatformPaymentModel>();
            using var cmd = new NpgsqlCommand(@"
                SELECT p.id, p.provider, p.externalreference, p.amount, p.currencycode,
                       p.status, p.paymentdateutc, i.invoicenumber, p.methodsummary
                  FROM platformpayments p
                  LEFT JOIN platforminvoices i ON i.id = p.invoiceid
                 WHERE p.accountid = @A ORDER BY p.receivedatutc DESC", conn);
            cmd.Parameters.AddWithValue("@A", acct.Id);
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Add(new PlatformPaymentModel
                {
                    Id = r.GetInt64(0),
                    Provider = r.GetString(1),
                    ExternalReference = r.IsDBNull(2) ? null : r.GetString(2),
                    Amount = r.GetDecimal(3),
                    CurrencyCode = r.GetString(4),
                    Status = r.GetString(5),
                    PaymentDateUtc = r.IsDBNull(6) ? null : r.GetDateTime(6),
                    InvoiceNumber = r.IsDBNull(7) ? null : r.GetString(7),
                    MethodSummary = r.IsDBNull(8) ? null : r.GetString(8),
                });
            return list;
        }

        /// <summary>
        /// Platform pricing is edited only by SystemAdmin / PlatformOwner
        /// (spec 27.1) — the same roles DatabaseBootstrap seeds for the
        /// platform's own operators. Company owners never qualify.
        /// </summary>
        public async Task<bool> IsPlatformAdminAsync(string userId)
        {
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            using var cmd = new NpgsqlCommand(@"
                SELECT 1 FROM aspnetuserroles ur
                  JOIN aspnetroles r ON r.id = ur.roleid
                 WHERE ur.userid = @U AND r.name IN ('SystemAdmin','PlatformOwner') LIMIT 1", conn);
            cmd.Parameters.AddWithValue("@U", userId);
            return await cmd.ExecuteScalarAsync() is not null;
        }

        internal static async Task LogEventAsync(NpgsqlConnection conn, long? accountId, string? farmId,
            string eventType, string? oldValue, string? newValue, string? actor, string? reference,
            NpgsqlTransaction? tx = null)
        {
            using var cmd = new NpgsqlCommand(@"
                INSERT INTO billingevents (accountid, farmid, eventtype, oldvalue, newvalue, actoruserid, reference)
                VALUES (@A, @F, @T, @O, @N, @U, @R)", conn, tx);
            cmd.Parameters.AddWithValue("@A", (object?)accountId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@F", (object?)farmId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@T", eventType);
            cmd.Parameters.AddWithValue("@O", (object?)oldValue ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@N", (object?)newValue ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@U", (object?)actor ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@R", (object?)reference ?? DBNull.Value);
            await cmd.ExecuteNonQueryAsync();
        }
    }
}
