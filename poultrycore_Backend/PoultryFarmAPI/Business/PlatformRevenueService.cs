// PROMPT 6: SaaS revenue intelligence over the AUTHORITATIVE billing system.
// No second source of truth: per-organization amounts come from the SAME
// evaluation path the customer app bills with (PlatformBillingService
// .GetSummaryAsync → EvaluateCompanyAsync), invoices/payments/discounts/credits
// are read directly from their tables, and the only new storage is the monthly
// MRR snapshot used for New/Expansion/Contraction/Churn movement.
//
// MRR RULES (documented, tested):
//  * Gross MRR  = recurring subscription subtotal, normalized to monthly
//                 (annual cycle = annual subtotal / 12).
//  * Net MRR    = gross minus discounts, PRE-tax. Credits are payment
//                 instruments — never discounts, never MRR.
//  * One-time fees do not exist in this billing system; nothing non-recurring
//    is counted.
//  * Paying = account status Active/PastDue/GracePeriod. Trial, Suspended and
//    cancelled accounts contribute 0 MRR (trials shown separately as
//    "potential", clearly not revenue).
//  * Amounts are NEVER summed across currencies and no FX rate is invented.

using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public static class RevenueMath
    {
        public static readonly string[] PayingStatuses = { "Active", "PastDue", "GracePeriod" };

        public static bool IsPaying(string? status) => PayingStatuses.Contains(status ?? "");

        /// <summary>Normalizes a billing-cycle subtotal/discount to monthly terms.</summary>
        public static (decimal Gross, decimal Net) NormalizeToMonthly(
            decimal cycleSubtotal, decimal cycleDiscount, string billingCycle)
        {
            var divisor = string.Equals(billingCycle, "annual", StringComparison.OrdinalIgnoreCase) ? 12m : 1m;
            var gross = Math.Round(cycleSubtotal / divisor, 2);
            var net = Math.Round(Math.Max(0, cycleSubtotal - cycleDiscount) / divisor, 2);
            return (gross, net);
        }

        /// <summary>Month-over-month movement for one organization (same currency).</summary>
        public static (decimal New, decimal Expansion, decimal Contraction, decimal Churned)
            ClassifyMovement(decimal previousNet, decimal currentNet)
        {
            if (previousNet <= 0 && currentNet > 0) return (currentNet, 0, 0, 0);
            if (previousNet > 0 && currentNet <= 0) return (0, 0, 0, previousNet);
            if (currentNet > previousNet) return (0, currentNet - previousNet, 0, 0);
            if (currentNet < previousNet) return (0, 0, previousNet - currentNet, 0);
            return (0, 0, 0, 0);
        }
    }

    public interface IPlatformRevenueService
    {
        Task<RevenueDashboardDto> GetDashboardAsync();
    }

    public class PlatformRevenueService : IPlatformRevenueService
    {
        private readonly string _cs;
        private readonly IPlatformBillingService _billing;
        private readonly IPlatformActivityService _activity;
        private readonly PlatformHealthOptions _health;
        private readonly ILogger<PlatformRevenueService>? _log;

        public PlatformRevenueService(string connectionString, IPlatformBillingService billing,
            IPlatformActivityService activity, PlatformHealthOptions? healthOptions = null,
            ILogger<PlatformRevenueService>? log = null)
        {
            _cs = connectionString;
            _billing = billing;
            _activity = activity;
            _health = healthOptions ?? new PlatformHealthOptions();
            _log = log;
        }

        private sealed record AccountRow(long Id, string Owner, string Currency, string Market, string Status,
            string Cycle, DateTime? TrialStart, DateTime? TrialEnd, DateTime? PeriodEnd, bool CancelAtPeriodEnd,
            string? Provider, string? ExternalCustomerId, string? PendingMarket);

        public async Task<RevenueDashboardDto> GetDashboardAsync()
        {
            var dto = new RevenueDashboardDto();
            var orgsDir = (await _activity.GetOrganizationSummariesAsync())
                .ToDictionary(o => o.OrganizationId);

            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();

            // 1. All billing accounts (only owners that HAVE accounts are evaluated —
            //    revenue analytics must never create accounts as a side effect).
            var accounts = new List<AccountRow>();
            await using (var cmd = new NpgsqlCommand(@"
                SELECT id, owneruserid, currencycode, billingmarketcode, status, billingcycle,
                       trialstartutc, trialendutc, currentperiodend, cancelatperiodend,
                       provider, externalcustomerid, pendingmarketcode
                FROM organizationbillingaccounts", conn))
            {
                await using var r = await cmd.ExecuteReaderAsync();
                while (await r.ReadAsync())
                    accounts.Add(new AccountRow(
                        r.GetInt64(0), r.GetString(1), r.GetString(2), r.GetString(3),
                        r.IsDBNull(4) ? "Trial" : r.GetString(4),
                        r.IsDBNull(5) ? "monthly" : r.GetString(5),
                        r.IsDBNull(6) ? null : r.GetDateTime(6),
                        r.IsDBNull(7) ? null : r.GetDateTime(7),
                        r.IsDBNull(8) ? null : r.GetDateTime(8),
                        !r.IsDBNull(9) && r.GetBoolean(9),
                        r.IsDBNull(10) ? null : r.GetString(10),
                        r.IsDBNull(11) ? null : r.GetString(11),
                        r.IsDBNull(12) ? null : r.GetString(12)));
            }

            // 2. Evaluate each account with the authoritative billing engine.
            var orgRows = new List<OrgRevenueRowDto>();
            var verticalAgg = new Dictionary<(string Family, string? Template, string Currency), (decimal Mrr, int Companies)>();
            var renewAmounts = new Dictionary<string, decimal>();   // owner -> expected cycle charge
            foreach (var a in accounts)
            {
                BillingSummaryModel summary;
                try { summary = await _billing.GetSummaryAsync(a.Owner); }
                catch (Exception ex)
                {
                    _log?.LogWarning(ex, "Billing evaluation failed for org {Org}", a.Owner);
                    continue;
                }

                var preview = summary.Preview;
                var (gross, net) = RevenueMath.NormalizeToMonthly(
                    preview?.Subtotal ?? 0, preview?.DiscountAmount ?? 0, a.Cycle);
                renewAmounts[a.Owner] = preview?.Total ?? 0;

                var billable = summary.Companies
                    .Where(c => c.PricingStatus is "Resolved" or "CustomPrice" or "Grandfathered")
                    .ToList();

                orgsDir.TryGetValue(a.Owner, out var dir);
                var paying = RevenueMath.IsPaying(a.Status);
                var row = new OrgRevenueRowDto
                {
                    OrganizationId = a.Owner,
                    OrganizationName = dir?.OrganizationName,
                    CurrencyCode = a.Currency,
                    MarketCode = a.Market,
                    AccountStatus = a.Status,
                    BillingCycle = a.Cycle,
                    GrossMrr = gross,
                    NetMrr = net,
                    PayingCompanies = billable.Count,
                    Health = dir?.Health,
                    LastMeaningfulActivityAtUtc = dir?.LastMeaningfulActivityAtUtc,
                    ActivityTrendPercent = dir?.Trend.PercentChange,
                    NextRenewalUtc = a.PeriodEnd,
                };

                // Revenue at risk: paying MRR where the customer is disengaging or
                // payment is already troubled. Internal prioritization, not a churn claim.
                if (paying && net > 0)
                {
                    if (dir?.Health is "At Risk" or "Inactive")
                        row.RiskReasons.Add($"Health: {dir.Health}");
                    if (dir?.Trend.Status == nameof(PlatformTrendStatus.Declining) && dir.Trend.PercentChange is double pc)
                        row.RiskReasons.Add($"Activity decline {Math.Abs(pc):0}%");
                    if (a.Status is "PastDue" or "GracePeriod")
                        row.RiskReasons.Add($"Payment state: {a.Status}");
                    if (a.CancelAtPeriodEnd)
                        row.RiskReasons.Add("Cancellation scheduled at period end");
                    if (row.RiskReasons.Count > 0 &&
                        (dir?.Health is "At Risk" or "Inactive" || a.Status is "PastDue" or "GracePeriod" || a.CancelAtPeriodEnd))
                        row.RevenueAtRisk = net;
                }
                orgRows.Add(row);

                // 3. Snapshot this month's evaluation (history for MRR movement).
                await using (var snap = new NpgsqlCommand(
                    "SELECT platform_mrr_snapshot(@O, @C, @G, @N, @P, @S, @Cy)", conn))
                {
                    snap.Parameters.AddWithValue("@O", a.Owner);
                    snap.Parameters.AddWithValue("@C", a.Currency);
                    snap.Parameters.AddWithValue("@G", paying ? gross : 0m);
                    snap.Parameters.AddWithValue("@N", paying ? net : 0m);
                    snap.Parameters.AddWithValue("@P", paying ? billable.Count : 0);
                    snap.Parameters.AddWithValue("@S", a.Status);
                    snap.Parameters.AddWithValue("@Cy", a.Cycle);
                    await snap.ExecuteNonQueryAsync();
                }

                // Vertical split: distribute net MRR over billable companies in
                // proportion to their evaluated monthly price.
                if (paying && net > 0)
                {
                    var monthlySum = billable.Sum(c => c.MonthlyAmount ?? 0);
                    foreach (var c in billable)
                    {
                        var share = monthlySum <= 0 ? 0 : Math.Round(net * ((c.MonthlyAmount ?? 0) / monthlySum), 2);
                        var template = c.CompanyFamily == "Generic" ? c.BusinessType : null;
                        var key = (c.CompanyFamily, template, a.Currency);
                        var cur = verticalAgg.TryGetValue(key, out var v) ? v : (0m, 0);
                        verticalAgg[key] = (cur.Item1 + share, cur.Item2 + 1);
                    }
                }

                // Billing exceptions straight from the evaluation.
                foreach (var c in summary.Companies.Where(c =>
                    c.PricingStatus is "PricingNotConfigured" or "ScaleSetupRequired"))
                    dto.Exceptions.Add(new BillingExceptionRowDto
                    {
                        Kind = c.PricingStatus,
                        OrganizationId = a.Owner,
                        OrganizationName = dir?.OrganizationName,
                        CompanyId = c.FarmId,
                        CompanyName = c.CompanyName,
                        Detail = c.PricingStatus == "PricingNotConfigured"
                            ? $"No price configured for {c.BillingProfileCode}/{c.TierCode ?? "?"} in {a.Market}"
                            : "Company scale (metric value) not set — tier cannot be resolved",
                    });
                if (paying && (a.Provider is null || a.ExternalCustomerId is null))
                    dto.Exceptions.Add(new BillingExceptionRowDto
                    {
                        Kind = "MissingProviderLink",
                        OrganizationId = a.Owner,
                        OrganizationName = dir?.OrganizationName,
                        Detail = "Paying account has no payment-provider customer/subscription linked",
                    });
                if (a.PendingMarket != null)
                    dto.Exceptions.Add(new BillingExceptionRowDto
                    {
                        Kind = "MarketChangePending",
                        OrganizationId = a.Owner,
                        OrganizationName = dir?.OrganizationName,
                        Detail = $"Billing market change to {a.PendingMarket} awaiting its effective date",
                    });
            }
            dto.Organizations = orgRows.OrderByDescending(x => x.NetMrr).ToList();
            dto.RevenueAtRisk = orgRows.Where(x => x.RevenueAtRisk > 0)
                .OrderByDescending(x => x.RevenueAtRisk).ToList();

            // 4. Keep the attention queue's RevenueAtRisk current (high-value prioritization).
            foreach (var row in orgRows)
            {
                await using var upd = new NpgsqlCommand(@"
                    UPDATE customerattentionitems
                       SET revenueatrisk = @V
                     WHERE organizationid = @O AND status IN ('Open','Assigned','Contacted')", conn);
                upd.Parameters.AddWithValue("@O", row.OrganizationId);
                upd.Parameters.AddWithValue("@V", RevenueMath.IsPaying(row.AccountStatus) ? row.NetMrr : 0m);
                await upd.ExecuteNonQueryAsync();
            }

            // 5. Movement vs last month's snapshots.
            var prevNet = new Dictionary<string, (decimal Net, string Currency)>();
            await using (var cmd = new NpgsqlCommand(@"
                SELECT organizationid, netmrr, currencycode FROM revenuemrrsnapshots
                WHERE snapshotmonth = (date_trunc('month', now() AT TIME ZONE 'UTC') - interval '1 month')::date", conn))
            {
                await using var r = await cmd.ExecuteReaderAsync();
                while (await r.ReadAsync())
                    prevNet[r.GetString(0)] = (r.GetDecimal(1), r.GetString(2));
            }

            // 6. Per-currency blocks.
            var blocks = new Dictionary<string, RevenueCurrencyBlockDto>();
            RevenueCurrencyBlockDto Block(string currency, string market)
            {
                if (!blocks.TryGetValue(currency, out var b))
                    blocks[currency] = b = new RevenueCurrencyBlockDto { CurrencyCode = currency, MarketCode = market };
                return b;
            }
            foreach (var row in orgRows)
            {
                var b = Block(row.CurrencyCode, row.MarketCode);
                var paying = RevenueMath.IsPaying(row.AccountStatus);
                if (paying)
                {
                    b.Mrr += row.NetMrr;
                    b.GrossMrr += row.GrossMrr;
                    if (row.NetMrr > 0 || row.PayingCompanies > 0) b.PayingOrganizations++;
                    b.PayingCompanies += row.PayingCompanies;
                }
                else if (row.AccountStatus == "Trial")
                {
                    b.TrialPotentialMrr += row.NetMrr;
                }
                var prev = prevNet.TryGetValue(row.OrganizationId, out var p) && p.Currency == row.CurrencyCode ? p.Net : 0m;
                var (nw, exp, con, churn) = RevenueMath.ClassifyMovement(prev, paying ? row.NetMrr : 0m);
                b.NewMrr += nw; b.ExpansionMrr += exp; b.ContractionMrr += con; b.ChurnedMrr += churn;
            }
            foreach (var b in blocks.Values)
            {
                b.Arr = Math.Round(b.Mrr * 12, 2);
                b.Arpo = b.PayingOrganizations == 0 ? null : Math.Round(b.Mrr / b.PayingOrganizations, 2);
                b.Arpc = b.PayingCompanies == 0 ? null : Math.Round(b.Mrr / b.PayingCompanies, 2);
            }

            // 7. Invoice/payment aggregates per currency (authoritative tables).
            await FillMoneyAggregatesAsync(conn, blocks, dto);

            dto.ByCurrency = blocks.Values.OrderByDescending(b => b.Mrr).ToList();

            // 8. Vertical table.
            dto.ByVertical = verticalAgg.Select(kv => new VerticalRevenueRowDto
            {
                CompanyFamily = kv.Key.Family,
                BusinessTemplate = kv.Key.Template,
                CurrencyCode = kv.Key.Currency,
                Mrr = kv.Value.Mrr,
                Companies = kv.Value.Companies,
                AveragePrice = kv.Value.Companies == 0 ? null : Math.Round(kv.Value.Mrr / kv.Value.Companies, 2),
                ShareOfCurrencyMrr = blocks.TryGetValue(kv.Key.Currency, out var b) && b.Mrr > 0
                    ? Math.Round((double)(kv.Value.Mrr / b.Mrr * 100), 1) : 0,
            }).OrderByDescending(v => v.Mrr).ToList();

            // 9. Trial intelligence.
            dto.Trials = await BuildTrialIntelligenceAsync(conn, accounts, orgRows, orgsDir);

            // 10. Renewals (paying accounts, next 30 days).
            dto.Renewals30d = orgRows
                .Where(r => RevenueMath.IsPaying(r.AccountStatus) && r.NextRenewalUtc is DateTime d
                            && d > DateTime.UtcNow && d <= DateTime.UtcNow.AddDays(30))
                .Select(r => new RenewalRowDto
                {
                    OrganizationId = r.OrganizationId,
                    OrganizationName = r.OrganizationName,
                    RenewalAtUtc = r.NextRenewalUtc!.Value,
                    BillingCycle = r.BillingCycle,
                    Amount = renewAmounts.TryGetValue(r.OrganizationId, out var amt) ? amt : 0m,
                    CurrencyCode = r.CurrencyCode,
                    Health = r.Health,
                    PaymentState = r.AccountStatus,
                })
                .OrderBy(r => r.RenewalAtUtc).ToList();

            // 11. Discounts + credits intelligence.
            dto.Discounts = await BuildDiscountIntelligenceAsync(conn, orgsDir, orgRows);
            dto.Credits = await BuildCreditIntelligenceAsync(conn);

            // 12. Past-due invoice exceptions (drill-down rows).
            await using (var cmd = new NpgsqlCommand(@"
                SELECT a.owneruserid, i.invoicenumber, i.currencycode, i.balance, i.duedate
                FROM platforminvoices i
                JOIN organizationbillingaccounts a ON a.id = i.accountid
                WHERE i.balance > 0 AND i.duedate < current_date AND i.status NOT IN ('Paid','Void')
                ORDER BY i.duedate", conn))
            {
                await using var r = await cmd.ExecuteReaderAsync();
                while (await r.ReadAsync())
                {
                    var owner = r.GetString(0);
                    orgsDir.TryGetValue(owner, out var dir);
                    dto.Exceptions.Add(new BillingExceptionRowDto
                    {
                        Kind = "PastDueInvoice",
                        OrganizationId = owner,
                        OrganizationName = dir?.OrganizationName,
                        Detail = $"{r.GetString(1)}: {r.GetString(2)} {r.GetDecimal(3):N2} overdue since {r.GetDateTime(4):yyyy-MM-dd}",
                    });
                }
            }

            return dto;
        }

        private static async Task FillMoneyAggregatesAsync(NpgsqlConnection conn,
            Dictionary<string, RevenueCurrencyBlockDto> blocks, RevenueDashboardDto dto)
        {
            // Past due balances.
            await using (var cmd = new NpgsqlCommand(@"
                SELECT i.currencycode, coalesce(sum(i.balance), 0)
                FROM platforminvoices i
                WHERE i.balance > 0 AND i.duedate < current_date AND i.status NOT IN ('Paid','Void')
                GROUP BY i.currencycode", conn))
            {
                await using var r = await cmd.ExecuteReaderAsync();
                while (await r.ReadAsync())
                    if (blocks.TryGetValue(r.GetString(0), out var b))
                        b.PastDueAmount = r.GetDecimal(1);
            }
            // Failed payments, 30 days.
            await using (var cmd = new NpgsqlCommand(@"
                SELECT currencycode, count(*), coalesce(sum(amount), 0)
                FROM platformpayments
                WHERE status = 'Failed' AND coalesce(paymentdateutc, createdatutc) > now() - interval '30 days'
                GROUP BY currencycode", conn))
            {
                await using var r = await cmd.ExecuteReaderAsync();
                while (await r.ReadAsync())
                    if (blocks.TryGetValue(r.GetString(0), out var b))
                    { b.FailedPaymentsCount30d = Convert.ToInt32(r.GetValue(1)); b.FailedPaymentsAmount30d = r.GetDecimal(2); }
            }
            // Discounts granted this month (invoice truth).
            await using (var cmd = new NpgsqlCommand(@"
                SELECT currencycode, coalesce(sum(discountamount), 0)
                FROM platforminvoices
                WHERE issuedate >= date_trunc('month', now())::date
                GROUP BY currencycode", conn))
            {
                await using var r = await cmd.ExecuteReaderAsync();
                while (await r.ReadAsync())
                    if (blocks.TryGetValue(r.GetString(0), out var b))
                        b.DiscountsGrantedThisMonth = r.GetDecimal(1);
            }
            // Outstanding credit per currency.
            await using (var cmd = new NpgsqlCommand(@"
                SELECT c.currencycode,
                       coalesce(sum(c.amount), 0)
                       - coalesce((SELECT sum(ap.amount) FROM platformcreditapplications ap
                                    JOIN platformaccountcredits c2 ON c2.id = ap.creditid
                                   WHERE c2.currencycode = c.currencycode AND c2.revokedatutc IS NULL), 0)
                FROM platformaccountcredits c
                WHERE c.revokedatutc IS NULL
                GROUP BY c.currencycode", conn))
            {
                await using var r = await cmd.ExecuteReaderAsync();
                while (await r.ReadAsync())
                    if (blocks.TryGetValue(r.GetString(0), out var b))
                        b.CreditsIssuedOutstanding = Math.Max(0, r.GetDecimal(1));
            }
            // Recovered payments: succeeded after the invoice's due date, 30 days.
            await using (var cmd = new NpgsqlCommand(@"
                SELECT p.currencycode, coalesce(sum(p.amount), 0)
                FROM platformpayments p
                JOIN platforminvoices i ON i.id = p.invoiceid
                WHERE p.status = 'Succeeded'
                  AND coalesce(p.paymentdateutc, p.createdatutc) > now() - interval '30 days'
                  AND coalesce(p.paymentdateutc, p.createdatutc)::date > i.duedate
                GROUP BY p.currencycode", conn))
            {
                await using var r = await cmd.ExecuteReaderAsync();
                while (await r.ReadAsync())
                    dto.RecoveredPayments30d.Add(new MoneyByCurrencyDto
                    { CurrencyCode = r.GetString(0), Amount = r.GetDecimal(1) });
            }
        }

        private async Task<TrialIntelligenceDto> BuildTrialIntelligenceAsync(NpgsqlConnection conn,
            List<AccountRow> accounts, List<OrgRevenueRowDto> orgRows,
            Dictionary<string, OrganizationActivitySummaryDto> orgsDir)
        {
            var t = new TrialIntelligenceDto();
            var now = DateTime.UtcNow;
            var trials = accounts.Where(a => a.Status == "Trial").ToList();
            t.OrganizationsInTrial = trials.Count;
            t.TrialEnding7d = trials.Count(a => a.TrialEnd is DateTime e && e > now && e <= now.AddDays(7));
            t.TrialEnding30d = trials.Count(a => a.TrialEnd is DateTime e && e > now && e <= now.AddDays(30));

            // Conversion = first successful payment (the authoritative "became paying" moment).
            var firstPayments = new Dictionary<string, DateTime>();
            await using (var cmd = new NpgsqlCommand(@"
                SELECT a.owneruserid, min(coalesce(p.paymentdateutc, p.createdatutc))
                FROM platformpayments p
                JOIN organizationbillingaccounts a ON a.id = p.accountid
                WHERE p.status = 'Succeeded'
                GROUP BY a.owneruserid", conn))
            {
                await using var r = await cmd.ExecuteReaderAsync();
                while (await r.ReadAsync())
                    firstPayments[r.GetString(0)] = r.GetDateTime(1);
            }
            var monthStart = new DateTime(now.Year, now.Month, 1, 0, 0, 0, DateTimeKind.Utc);
            t.ConvertedThisMonth = firstPayments.Values.Count(d => d >= monthStart);
            var withTrial = accounts.Where(a => a.TrialStart != null).ToList();
            if (withTrial.Count > 0)
            {
                var converted = withTrial.Where(a => firstPayments.ContainsKey(a.Owner)).ToList();
                t.TrialToPaidConversionRate = Math.Round(100.0 * converted.Count / withTrial.Count, 1);
                if (converted.Count > 0)
                    t.AverageDaysToConversion = Math.Round(converted.Average(a =>
                        (firstPayments[a.Owner] - a.TrialStart!.Value).TotalDays), 1);
            }

            var rowByOrg = orgRows.ToDictionary(r => r.OrganizationId);
            foreach (var a in trials)
            {
                if (!rowByOrg.TryGetValue(a.Owner, out var row)) continue;
                orgsDir.TryGetValue(a.Owner, out var dir);
                var engaged = (dir?.MeaningfulActivityCount30d ?? 0) >= _health.HighEngagementMin30d;
                var endingSoon = a.TrialEnd is DateTime e && e > now && e <= now.AddDays(_health.TrialEndingSoonDays);
                if (engaged && !firstPayments.ContainsKey(a.Owner))
                    t.HighEngagementTrialsNotPaid.Add(row);
                else if (!engaged && endingSoon)
                    t.LowEngagementTrialsEndingSoon.Add(row);
            }
            return t;
        }

        private static async Task<DiscountIntelligenceDto> BuildDiscountIntelligenceAsync(
            NpgsqlConnection conn, Dictionary<string, OrganizationActivitySummaryDto> orgsDir,
            List<OrgRevenueRowDto> orgRows)
        {
            var d = new DiscountIntelligenceDto();

            async Task<List<MoneyByCurrencyDto>> SumsAsync(string where)
            {
                var list = new List<MoneyByCurrencyDto>();
                await using var cmd = new NpgsqlCommand($@"
                    SELECT currencycode, coalesce(sum(discountamount), 0)
                    FROM platforminvoices WHERE {where} GROUP BY currencycode", conn);
                await using var r = await cmd.ExecuteReaderAsync();
                while (await r.ReadAsync())
                    list.Add(new MoneyByCurrencyDto { CurrencyCode = r.GetString(0), Amount = r.GetDecimal(1) });
                return list;
            }
            d.GrantedThisMonth = await SumsAsync("issuedate >= date_trunc('month', now())::date");
            d.GrantedLast90d = await SumsAsync("issuedate >= (current_date - 90)");

            await using (var cmd = new NpgsqlCommand(@"
                SELECT a.owneruserid, dd.name, dd.discounttype, dd.value, dd.enddate, dd.promotionid,
                       (SELECT i.discountpercent FROM platforminvoices i
                         WHERE i.accountid = a.id ORDER BY i.issuedate DESC LIMIT 1)
                FROM platformdiscounts dd
                JOIN organizationbillingaccounts a ON a.id = dd.accountid
                WHERE dd.active AND dd.revokedatutc IS NULL
                  AND (dd.enddate IS NULL OR dd.enddate >= current_date)", conn))
            {
                await using var r = await cmd.ExecuteReaderAsync();
                while (await r.ReadAsync())
                {
                    var owner = r.GetString(0);
                    orgsDir.TryGetValue(owner, out var dir);
                    var row = new AccountDiscountRowDto
                    {
                        OrganizationId = owner,
                        OrganizationName = dir?.OrganizationName,
                        Name = r.GetString(1),
                        DiscountType = r.GetString(2),
                        Value = r.GetDecimal(3),
                        EndDate = r.IsDBNull(4) ? null : r.GetDateTime(4),
                        LastInvoicePercent = r.IsDBNull(6) ? null : r.GetDecimal(6),
                    };
                    if (r.IsDBNull(5)) d.ActiveCustomerSpecificDiscounts++; else d.ActivePromotionalDiscounts++;
                    d.LargestDiscountAccounts.Add(row);
                    if (row.EndDate is DateTime e && e <= DateTime.UtcNow.AddDays(30))
                        d.ExpiringDiscounts.Add(row);
                }
            }
            d.LargestDiscountAccounts = d.LargestDiscountAccounts
                .OrderByDescending(x => x.LastInvoicePercent ?? x.Value).Take(10).ToList();
            // Automatic multi-company discount: orgs with >1 billable company get the
            // built-in rule — count from the evaluated rows (gross > net implies discounting).
            d.ActiveAutomaticMultiCompany = orgRows.Count(o => o.PayingCompanies > 1 && o.GrossMrr > o.NetMrr);
            return d;
        }

        private static async Task<CreditIntelligenceDto> BuildCreditIntelligenceAsync(NpgsqlConnection conn)
        {
            var c = new CreditIntelligenceDto();
            await using (var cmd = new NpgsqlCommand(@"
                SELECT currencycode, coalesce(sum(amount), 0) FROM platformaccountcredits
                WHERE revokedatutc IS NULL GROUP BY currencycode", conn))
            {
                await using var r = await cmd.ExecuteReaderAsync();
                while (await r.ReadAsync())
                    c.Issued.Add(new MoneyByCurrencyDto { CurrencyCode = r.GetString(0), Amount = r.GetDecimal(1) });
            }
            await using (var cmd = new NpgsqlCommand(@"
                SELECT cr.currencycode, coalesce(sum(ap.amount), 0)
                FROM platformcreditapplications ap
                JOIN platformaccountcredits cr ON cr.id = ap.creditid
                GROUP BY cr.currencycode", conn))
            {
                await using var r = await cmd.ExecuteReaderAsync();
                while (await r.ReadAsync())
                    c.Consumed.Add(new MoneyByCurrencyDto { CurrencyCode = r.GetString(0), Amount = r.GetDecimal(1) });
            }
            foreach (var issued in c.Issued)
            {
                var used = c.Consumed.FirstOrDefault(x => x.CurrencyCode == issued.CurrencyCode)?.Amount ?? 0;
                c.Outstanding.Add(new MoneyByCurrencyDto
                { CurrencyCode = issued.CurrencyCode, Amount = Math.Max(0, issued.Amount - used) });
            }
            await using (var cmd = new NpgsqlCommand(@"
                SELECT coalesce(nullif(reason, ''), '(unspecified)'), currencycode,
                       coalesce(sum(amount), 0), count(*)
                FROM platformaccountcredits WHERE revokedatutc IS NULL
                GROUP BY 1, 2 ORDER BY 3 DESC", conn))
            {
                await using var r = await cmd.ExecuteReaderAsync();
                while (await r.ReadAsync())
                    c.ByReason.Add(new CreditReasonRowDto
                    {
                        Reason = r.GetString(0),
                        CurrencyCode = r.GetString(1),
                        Amount = r.GetDecimal(2),
                        Count = Convert.ToInt32(r.GetValue(3)),
                    });
            }
            return c;
        }
    }
}
