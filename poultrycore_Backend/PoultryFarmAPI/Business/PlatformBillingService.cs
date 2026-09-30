// Platform billing engine (migration 329).
//
// The pipeline (spec Part 28): account → market/currency → eligible companies
// → per-company profile → metric → tier → price → evaluation snapshot → lines
// → multi-company discount → tax → one consolidated Organization invoice →
// provider checkout → settlement. Every step reads configuration (never
// source-code prices) and writes an auditable record.
//
// Deliberate Phase A boundaries:
//   * Enforcement is governed by platformbillingsettings.enforcementenabled,
//     seeded FALSE — no customer loses access because this code shipped.
//   * Only POULTRY_BIRDS has an authoritative metric (the migration-204
//     birds-left formula, wrapped in spplatformbilling_activebirds). Every
//     other profile reads companybillingstates.manualscalevalue (0 when
//     unset) and qualifies through configuration, so Hotel/Restaurant/Water/
//     Generic bill without invented counts (spec 4.2–4.5).
//   * Legacy Login-API Paystack checkout is untouched; this engine settles
//     only its own invoices, so the two cannot double-charge.

using Npgsql;
using PoultryFarmAPIWeb.Models;
using System.Data;

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
    }

    public class PlatformBillingService : IPlatformBillingService
    {
        private readonly string _cs;
        private readonly string _paystackSecret;
        private readonly IHttpClientFactory _httpFactory;

        public PlatformBillingService(string connectionString, string paystackSecretKey, IHttpClientFactory httpFactory)
        {
            _cs = connectionString;
            _paystackSecret = paystackSecretKey;
            _httpFactory = httpFactory;
        }

        // ------------------------------------------------------------------
        // Configuration
        // ------------------------------------------------------------------

        private sealed record Config(
            Dictionary<string, (string Name, string Currency, string Provider, bool Active)> Markets,
            Dictionary<string, (string Name, int Rank)> Tiers,
            Dictionary<string, (string Name, string MetricType)> Profiles,
            List<TierRule> TierRules,
            List<PriceEntry> GhEntriesByMarket, // entries of the active book for one market (loaded per account)
            List<DiscountRule> Discounts,
            Dictionary<string, string> Settings);

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

        /// <summary>
        /// Load the caller's billing account, creating it on first sight from
        /// their Business Office declaration (spec 3.3/3.4: declared market,
        /// never IP). Existing owners get the promised 150-day trial measured
        /// from their signup date — never reset by this migration (spec 10.2).
        /// </summary>
        private async Task<BillingAccountModel> EnsureAccountAsync(NpgsqlConnection conn, string userId)
        {
            var acct = await ReadAccountAsync(conn, userId);
            if (acct != null) return acct;

            // Business Office declaration + signup date from the identity row.
            string? officeCountry = null, officeCurrency = null, orgCode = null, email = null, name = null;
            DateTime created = DateTime.UtcNow;
            using (var u = new NpgsqlCommand(@"
                SELECT businessofficecountry, businessofficecurrency, organizationcode, email,
                       COALESCE(NULLIF(TRIM(CONCAT(firstname,' ',lastname)), ''), username), createddate
                  FROM aspnetusers WHERE id = @Id", conn))
            {
                u.Parameters.AddWithValue("@Id", userId);
                using var r = await u.ExecuteReaderAsync();
                if (await r.ReadAsync())
                {
                    officeCountry = r.IsDBNull(0) ? null : r.GetString(0);
                    officeCurrency = r.IsDBNull(1) ? null : r.GetString(1);
                    orgCode = r.IsDBNull(2) ? null : r.GetString(2);
                    email = r.IsDBNull(3) ? null : r.GetString(3);
                    name = r.IsDBNull(4) ? null : r.GetString(4);
                    created = r.IsDBNull(5) ? DateTime.UtcNow : r.GetDateTime(5);
                }
            }

            // Declared country → market. Only Ghana is active today; anything
            // else still gets an account (GH is the only configured market)
            // and can request a market change through the controlled flow.
            var market = "GH";
            var c = (officeCountry ?? "").Trim().ToUpperInvariant();
            if (c is "NG" or "NIGERIA") market = "NG";
            else if (c is "US" or "USA" or "UNITED STATES") market = "US";
            using (var m = new NpgsqlCommand("SELECT active, currencycode FROM billingmarkets WHERE code = @C", conn))
            {
                m.Parameters.AddWithValue("@C", market);
                using var r = await m.ExecuteReaderAsync();
                if (!await r.ReadAsync() || !r.GetBoolean(0)) market = "GH";
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
            return (await ReadAccountAsync(conn, userId))!;
        }

        private static async Task<BillingAccountModel?> ReadAccountAsync(NpgsqlConnection conn, string userId)
        {
            using var cmd = new NpgsqlCommand(@"
                SELECT id, owneruserid, orgcode, billingmarketcode, currencycode, billingemail,
                       billingcontactname, status, billingcycle, trialstartutc, trialendutc,
                       verificationstatus, currentperiodstart, currentperiodend, cancelatperiodend, provider
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
            };
            if (a.TrialEndUtc.HasValue)
                a.TrialDaysLeft = Math.Max(0, (int)Math.Ceiling((a.TrialEndUtc.Value - DateTime.UtcNow).TotalDays));
            return a;
        }

        // ------------------------------------------------------------------
        // Companies + evaluation
        // ------------------------------------------------------------------

        private sealed record CompanyRow(string FarmId, string Name, string Family, string? Template);

        /// <summary>
        /// The organization's companies: farms this user reaches through
        /// userfarms as Owner. Server-side ownership is the query itself —
        /// a farmid the caller does not own simply never appears (spec 31).
        /// </summary>
        private static async Task<List<CompanyRow>> LoadCompaniesAsync(NpgsqlConnection conn, string userId)
        {
            var list = new List<CompanyRow>();
            using var cmd = new NpgsqlCommand(@"
                SELECT f.farmid, f.name, f.type, g.genericbusinesstemplate
                  FROM userfarms uf
                  JOIN farms f ON f.farmid = uf.farmid
                  LEFT JOIN genericcompanyprofiles g ON g.farmid = f.farmid
                 WHERE uf.userid = @U AND LOWER(COALESCE(uf.role,'')) = 'owner'
                 ORDER BY f.name", conn);
            cmd.Parameters.AddWithValue("@U", userId);
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Add(new CompanyRow(r.GetString(0), r.GetString(1),
                    r.IsDBNull(2) ? "Poultry" : r.GetString(2),
                    r.IsDBNull(3) ? null : r.GetString(3)));
            return list;
        }

        private sealed record CompanyState(string? ProfileOverride, string Participation,
            decimal? ManualScale, decimal? CustomPrice, decimal? GrandfatheredPrice);

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
                       custommonthlyprice, grandfatheredmonthlyprice
                  FROM companybillingstates WHERE farmid = @F", conn);
            cmd.Parameters.AddWithValue("@F", farmId);
            using var r = await cmd.ExecuteReaderAsync();
            await r.ReadAsync();
            return new CompanyState(
                r.IsDBNull(0) ? null : r.GetString(0),
                r.GetString(1),
                r.IsDBNull(2) ? null : r.GetDecimal(2),
                r.IsDBNull(3) ? null : r.GetDecimal(3),
                r.IsDBNull(4) ? null : r.GetDecimal(4));
        }

        /// <summary>The authoritative metric for a profile — never a fork of a domain formula.</summary>
        private static async Task<decimal> MetricValueAsync(NpgsqlConnection conn, string metricType, string farmId, CompanyState state)
        {
            if (string.Equals(metricType, "ActiveBirdCount", StringComparison.OrdinalIgnoreCase))
            {
                using var cmd = new NpgsqlCommand("SELECT spplatformbilling_activebirds(@F)", conn);
                cmd.Parameters.AddWithValue("@F", farmId);
                var v = await cmd.ExecuteScalarAsync();
                return v is decimal d ? d : Convert.ToDecimal(v ?? 0);
            }
            // ManualScale (and any not-yet-authoritative metric): the configured value, 0 when unset.
            return state.ManualScale ?? 0m;
        }

        private async Task<CompanyBillingRowModel> EvaluateCompanyAsync(
            NpgsqlConnection conn, Config cfg, BillingAccountModel acct, CompanyRow company,
            string reason, DateTime periodStart, DateTime periodEnd, NpgsqlTransaction? tx = null)
        {
            var state = await EnsureCompanyStateAsync(conn, acct.Id, company.FarmId);
            var profileCode = PlatformBillingRules.ResolveProfileCode(company.Family, state.ProfileOverride);
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
                // Archived / Exempt / Suspended companies contribute no line (spec 9.1/9.2).
                row.PricingStatus = "Exempt";
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
                var entry = PlatformBillingRules.ResolvePrice(cfg.GhEntriesByMarket, row.TierCode, profileCode);
                if (entry != null)
                {
                    entryId = entry.Id;
                    row.MonthlyAmount = PlatformBillingRules.Money(entry.MonthlyPrice);
                    row.PricingStatus = "Resolved";
                }
                else
                {
                    row.PricingStatus = "PricingNotConfigured"; // never zero, never a guess (spec 39)
                }
            }
            else
            {
                row.PricingStatus = "PricingNotConfigured";
            }

            // The snapshot that answers "why was this charged" months later (spec 5.1).
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

        private static (DateTime Start, DateTime End) CurrentPeriod()
        {
            var today = DateTime.UtcNow.Date;
            var start = new DateTime(today.Year, today.Month, 1);
            return (start, start.AddMonths(1).AddDays(-1));
        }

        // ------------------------------------------------------------------
        // Summary / preview
        // ------------------------------------------------------------------

        public async Task<BillingSummaryModel> GetSummaryAsync(string userId)
        {
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            var acct = await EnsureAccountAsync(conn, userId);
            var cfg = await LoadConfigAsync(conn, acct.MarketCode);
            var (ps, pe) = CurrentPeriod();

            var companies = new List<CompanyBillingRowModel>();
            foreach (var c in await LoadCompaniesAsync(conn, userId))
                companies.Add(await EvaluateCompanyAsync(conn, cfg, acct, c, "Preview", ps, pe));

            var billable = companies.Where(x => x.PricingStatus is "Resolved" or "CustomPrice" or "Grandfathered").ToList();
            var discount = PlatformBillingRules.PickDiscount(cfg.Discounts, billable.Count);
            var taxRate = cfg.Settings.TryGetValue("taxratepercent", out var tr) && decimal.TryParse(tr, out var trd) ? trd : 0m;
            var (sub, disc, tax, total) = PlatformBillingRules.Totals(
                billable.Select(x => x.MonthlyAmount ?? 0m), discount?.Percent ?? 0m, taxRate);

            return new BillingSummaryModel
            {
                Account = acct,
                Companies = companies,
                EnforcementEnabled = cfg.Settings.TryGetValue("enforcementenabled", out var en)
                                     && string.Equals(en, "true", StringComparison.OrdinalIgnoreCase),
                Preview = new BillPreviewModel
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
                },
            };
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

            // "Next tier at N" — the smallest rule bound above the current value.
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

        /// <summary>
        /// The current period's invoice, created transactionally on first
        /// need. UNIQUE(accountid, periodstart) is the deterministic period
        /// identity (spec 33): a concurrent second call re-reads the same
        /// invoice instead of creating another.
        /// </summary>
        private async Task<(long Id, string Number, decimal Balance, string Status)> EnsureCurrentInvoiceAsync(
            NpgsqlConnection conn, BillingAccountModel acct, Config cfg)
        {
            var (ps, pe) = CurrentPeriod();

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
                companies.Add(await EvaluateCompanyAsync(conn, cfg, acct, c, "InvoiceGeneration", ps, pe, (NpgsqlTransaction)tx));

            var billable = companies.Where(x => x.PricingStatus is "Resolved" or "CustomPrice" or "Grandfathered").ToList();
            if (companies.Any(x => x.PricingStatus == "PricingNotConfigured"))
                throw new InvalidOperationException(
                    "Pricing for one of your business types is being finalized. Please contact VisibilityCore support.");
            if (billable.Count == 0)
                throw new InvalidOperationException("There are no billable companies on this account yet.");

            var discount = PlatformBillingRules.PickDiscount(cfg.Discounts, billable.Count);
            var taxRate = cfg.Settings.TryGetValue("taxratepercent", out var trs) && decimal.TryParse(trs, out var trd) ? trd : 0m;
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
                    // Lost the race: someone else created this period's invoice.
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
            return (invoiceId, number, total, "Open");
        }

        // ------------------------------------------------------------------
        // Checkout + settlement (Paystack behind the provider seam)
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
            if (!string.Equals(market.Provider, "paystack", StringComparison.OrdinalIgnoreCase))
                return new StartCheckoutResponse { Success = false, Message = "No payment provider is configured for this market yet." };
            if (string.IsNullOrWhiteSpace(_paystackSecret))
                return new StartCheckoutResponse { Success = false, Message = "Paystack is not configured on this service (PAYSTACK_SECRET_KEY)." };

            (long Id, string Number, decimal Balance, string Status) invoice;
            try { invoice = await EnsureCurrentInvoiceAsync(conn, acct, cfg); }
            catch (InvalidOperationException ex)
            { return new StartCheckoutResponse { Success = false, Message = ex.Message }; }

            if (invoice.Balance <= 0m || invoice.Status == "Paid")
                return new StartCheckoutResponse { Success = false, Message = "This period's invoice is already settled." };

            // Server-computed amount + our reference; the browser never chooses a price (spec 31.1).
            var reference = $"{invoice.Number}-{Guid.NewGuid():N}"[..40];
            var http = _httpFactory.CreateClient();
            http.DefaultRequestHeaders.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", _paystackSecret);
            var payload = System.Text.Json.JsonSerializer.Serialize(new
            {
                email = acct.BillingEmail ?? "billing@visibilitycore.com",
                amount = PlatformBillingRules.ToMinorUnits(invoice.Balance, acct.CurrencyCode),
                currency = acct.CurrencyCode.ToUpperInvariant(),
                reference,
                callback_url = req.SuccessUrl,
                metadata = new { invoiceNumber = invoice.Number, accountId = acct.Id, cancelUrl = req.FailureUrl },
            });
            using var content = new StringContent(payload, System.Text.Encoding.UTF8, "application/json");
            var resp = await http.PostAsync("https://api.paystack.co/transaction/initialize", content);
            var text = await resp.Content.ReadAsStringAsync();
            if (!resp.IsSuccessStatusCode)
                return new StartCheckoutResponse { Success = false, Message = $"Paystack initialize failed: {text}" };

            using var doc = System.Text.Json.JsonDocument.Parse(text);
            var data = doc.RootElement.GetProperty("data");
            var url = data.TryGetProperty("authorization_url", out var au) ? au.GetString() : null;
            if (string.IsNullOrWhiteSpace(url))
                return new StartCheckoutResponse { Success = false, Message = "Paystack did not return a checkout URL." };

            using (var upd = new NpgsqlCommand(
                "UPDATE platforminvoices SET externalreference = @R WHERE id = @I", conn))
            {
                upd.Parameters.AddWithValue("@R", reference);
                upd.Parameters.AddWithValue("@I", invoice.Id);
                await upd.ExecuteNonQueryAsync();
            }
            await LogEventAsync(conn, acct.Id, null, "CheckoutInitiated", null, reference, req.UserId, null);

            return new StartCheckoutResponse
            {
                Success = true,
                CheckoutUrl = url,
                Reference = reference,
                InvoiceNumber = invoice.Number,
                Amount = invoice.Balance,
                CurrencyCode = acct.CurrencyCode,
            };
        }

        /// <summary>
        /// Authoritative confirmation by provider verify — the return URL
        /// alone never settles anything (spec 13.4). Shares the idempotent
        /// settlement path with the webhook, so browser-return and webhook
        /// racing each other still posts exactly once.
        /// </summary>
        public async Task<(bool Ok, string Message)> VerifyAndSettleAsync(string userId, string reference)
        {
            if (string.IsNullOrWhiteSpace(_paystackSecret))
                return (false, "Paystack is not configured on this service.");
            var http = _httpFactory.CreateClient();
            http.DefaultRequestHeaders.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", _paystackSecret);
            var resp = await http.GetAsync($"https://api.paystack.co/transaction/verify/{Uri.EscapeDataString(reference)}");
            var text = await resp.Content.ReadAsStringAsync();
            if (!resp.IsSuccessStatusCode) return (false, $"Paystack verify failed: {text}");

            using var doc = System.Text.Json.JsonDocument.Parse(text);
            var data = doc.RootElement.GetProperty("data");
            var status = data.TryGetProperty("status", out var st) ? st.GetString() : null;
            if (!string.Equals(status, "success", StringComparison.OrdinalIgnoreCase))
                return (false, $"Payment is not successful yet (status: {status}).");

            return await SettleAsync(
                externalPaymentId: data.TryGetProperty("id", out var pid) ? pid.GetRawText() : null,
                reference: reference,
                amountMinor: data.TryGetProperty("amount", out var am) ? am.GetInt64() : 0,
                currency: data.TryGetProperty("currency", out var cu) ? cu.GetString() ?? "" : "",
                paidAtUtc: data.TryGetProperty("paid_at", out var pa) && pa.ValueKind == System.Text.Json.JsonValueKind.String
                           && DateTime.TryParse(pa.GetString(), null, System.Globalization.DateTimeStyles.AdjustToUniversal, out var dt)
                           ? dt : DateTime.UtcNow,
                methodSummary: data.TryGetProperty("channel", out var ch) ? ch.GetString() : null);
        }

        /// <summary>
        /// One settlement per provider payment, no matter how many webhook
        /// deliveries or verify calls carry it: the UNIQUE index on
        /// (provider, externalreference) turns duplicates into no-ops
        /// inside the same transaction that applies the money (spec 13.3).
        /// </summary>
        private async Task<(bool Ok, string Message)> SettleAsync(
            string? externalPaymentId, string reference, long amountMinor, string currency,
            DateTime paidAtUtc, string? methodSummary)
        {
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            using var tx = await conn.BeginTransactionAsync();

            long invoiceId; long accountId; decimal balance; string number; string curr;
            using (var q = new NpgsqlCommand(@"
                SELECT id, accountid, balance, invoicenumber, currencycode
                  FROM platforminvoices WHERE externalreference = @R FOR UPDATE", conn, (NpgsqlTransaction)tx))
            {
                q.Parameters.AddWithValue("@R", reference);
                using var r = await q.ExecuteReaderAsync();
                if (!await r.ReadAsync()) return (false, $"No invoice matches reference {reference}.");
                invoiceId = r.GetInt64(0); accountId = r.GetInt64(1);
                balance = r.GetDecimal(2); number = r.GetString(3); curr = r.GetString(4);
            }

            var amount = PlatformBillingRules.Money(amountMinor / 100m);
            if (!string.Equals(curr, currency, StringComparison.OrdinalIgnoreCase))
                return (false, $"Payment currency {currency} does not match invoice currency {curr}.");

            long paymentId;
            using (var ins = new NpgsqlCommand(@"
                INSERT INTO platformpayments
                       (accountid, invoiceid, provider, externalpaymentid, externalreference,
                        amount, currencycode, status, paymentdateutc, methodsummary)
                VALUES (@A, @I, 'paystack', @EP, @R, @Amt, @C, 'Succeeded', @Paid, @M)
                ON CONFLICT (provider, externalreference) WHERE externalreference IS NOT NULL DO NOTHING
                RETURNING id", conn, (NpgsqlTransaction)tx))
            {
                ins.Parameters.AddWithValue("@A", accountId);
                ins.Parameters.AddWithValue("@I", invoiceId);
                ins.Parameters.AddWithValue("@EP", (object?)externalPaymentId ?? DBNull.Value);
                ins.Parameters.AddWithValue("@R", reference);
                ins.Parameters.AddWithValue("@Amt", amount);
                ins.Parameters.AddWithValue("@C", curr);
                ins.Parameters.AddWithValue("@Paid", paidAtUtc);
                ins.Parameters.AddWithValue("@M", (object?)methodSummary ?? DBNull.Value);
                var idObj = await ins.ExecuteScalarAsync();
                if (idObj is null)
                {
                    await tx.RollbackAsync();
                    return (true, "Payment already recorded."); // duplicate delivery — business posting happened once
                }
                paymentId = (long)idObj;
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
                   SET status = 'Active', provider = 'paystack',
                       currentperiodstart = (SELECT periodstart FROM platforminvoices WHERE id = @I),
                       currentperiodend   = (SELECT periodend   FROM platforminvoices WHERE id = @I),
                       updatedatutc = now() AT TIME ZONE 'utc'
                 WHERE id = @A", conn, (NpgsqlTransaction)tx))
            {
                updAcct.Parameters.AddWithValue("@I", invoiceId);
                updAcct.Parameters.AddWithValue("@A", accountId);
                await updAcct.ExecuteNonQueryAsync();
            }

            await LogEventAsync(conn, accountId, null, "PaymentSucceeded", null,
                $"{number} {curr} {amount}", "system", reference, (NpgsqlTransaction)tx);
            await tx.CommitAsync();
            return (true, $"Payment of {curr} {amount} applied to {number}.");
        }

        // ------------------------------------------------------------------
        // Webhook
        // ------------------------------------------------------------------

        public async Task<(bool Ok, string Message)> ProcessPaystackWebhookAsync(string payload, string signatureHeader)
        {
            // Authenticity first (spec 13.2): HMAC-SHA512 of the raw body with the secret key.
            if (string.IsNullOrWhiteSpace(_paystackSecret)) return (false, "Provider not configured.");
            var computed = Convert.ToHexString(
                new System.Security.Cryptography.HMACSHA512(System.Text.Encoding.UTF8.GetBytes(_paystackSecret))
                    .ComputeHash(System.Text.Encoding.UTF8.GetBytes(payload))).ToLowerInvariant();
            if (!string.Equals(computed, signatureHeader?.Trim(), StringComparison.OrdinalIgnoreCase))
                return (false, "Invalid signature.");

            var hash = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(
                System.Text.Encoding.UTF8.GetBytes(payload))).ToLowerInvariant();

            string eventType = "unknown"; string? reference = null; string? extId = null;
            long amountMinor = 0; string currency = ""; string? channel = null; DateTime paidAt = DateTime.UtcNow;
            try
            {
                using var doc = System.Text.Json.JsonDocument.Parse(payload);
                eventType = doc.RootElement.TryGetProperty("event", out var ev) ? ev.GetString() ?? "unknown" : "unknown";
                if (doc.RootElement.TryGetProperty("data", out var data))
                {
                    reference = data.TryGetProperty("reference", out var rf) ? rf.GetString() : null;
                    extId = data.TryGetProperty("id", out var idp) ? idp.GetRawText() : null;
                    amountMinor = data.TryGetProperty("amount", out var am) ? am.GetInt64() : 0;
                    currency = data.TryGetProperty("currency", out var cu) ? cu.GetString() ?? "" : "";
                    channel = data.TryGetProperty("channel", out var chp) ? chp.GetString() : null;
                    if (data.TryGetProperty("paid_at", out var pa) && pa.ValueKind == System.Text.Json.JsonValueKind.String)
                        DateTime.TryParse(pa.GetString(), null, System.Globalization.DateTimeStyles.AdjustToUniversal, out paidAt);
                }
            }
            catch { /* recorded below as unparseable; never 500 back at the provider */ }

            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();

            // The event store is the delivery-level dedupe (spec 13.1): the
            // same payload landing twice is recorded once and processed once.
            using (var ins = new NpgsqlCommand(@"
                INSERT INTO billingwebhookevents (provider, externaleventid, eventtype, payloadhash)
                VALUES ('paystack', @E, @T, @H)
                ON CONFLICT (provider, payloadhash) DO NOTHING RETURNING id", conn))
            {
                ins.Parameters.AddWithValue("@E", (object?)extId ?? DBNull.Value);
                ins.Parameters.AddWithValue("@T", eventType);
                ins.Parameters.AddWithValue("@H", hash);
                if (await ins.ExecuteScalarAsync() is null)
                    return (true, "Duplicate delivery ignored.");
            }

            string resultMsg; string resultStatus;
            if (eventType == "charge.success" && !string.IsNullOrWhiteSpace(reference))
            {
                var (ok, msg) = await SettleAsync(extId, reference!, amountMinor, currency, paidAt, channel);
                resultMsg = msg; resultStatus = ok ? "Processed" : "Failed";
            }
            else
            {
                resultMsg = $"Event {eventType} acknowledged."; resultStatus = "Ignored";
            }

            using (var upd = new NpgsqlCommand(@"
                UPDATE billingwebhookevents
                   SET processedatutc = now() AT TIME ZONE 'utc', processingstatus = @S, error = @Err
                 WHERE provider='paystack' AND payloadhash = @H", conn))
            {
                upd.Parameters.AddWithValue("@S", resultStatus);
                upd.Parameters.AddWithValue("@Err", resultStatus == "Failed" ? resultMsg : (object)DBNull.Value);
                upd.Parameters.AddWithValue("@H", hash);
                await upd.ExecuteNonQueryAsync();
            }
            return (true, resultMsg);
        }

        // ------------------------------------------------------------------
        // Payments list + audit
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

        private static async Task LogEventAsync(NpgsqlConnection conn, long? accountId, string? farmId,
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
