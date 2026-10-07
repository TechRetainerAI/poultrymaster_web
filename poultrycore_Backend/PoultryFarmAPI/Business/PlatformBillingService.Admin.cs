// Platform billing — ADMIN APP surface (ADMIN APP spec, 2026-10-05).
// Same class (partial) so the admin console and the customer engine share one
// config loader, one evaluation path and ONE discount/credit pipeline: the
// admin app decides WHAT VisibilityCore charges, this backend computes it.

using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.Extensions.Logging;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IPlatformBillingAdminService
    {
        Task<bool> HasPermissionAsync(string userId, string permission);
        Task<List<string>> MyPermissionsAsync(string userId);
        Task<(bool Ok, string Message)> GrantPermissionAsync(string targetUserId, string permission, string actorId);
        Task<(bool Ok, string Message)> RevokePermissionAsync(string targetUserId, string permission, string actorId);

        Task<List<AdminOrgListItemModel>> AdminListOrganizationsAsync(string? search);
        Task<AdminOrgInspectorModel?> AdminInspectAsync(string ownerUserId);

        Task<(bool Ok, string Message, long Id)> AdminAssignDiscountAsync(AdminDiscountBody body, string actorId);
        Task<(bool Ok, string Message)> AdminRevokeDiscountAsync(long discountId, string actorId, string? reason);
        Task<AdminDiscountPreviewModel?> AdminDiscountPreviewAsync(AdminDiscountBody proposed);

        Task<List<AdminPromotionModel>> AdminListPromotionsAsync();
        Task<(bool Ok, string Message, long Id)> AdminCreatePromotionAsync(AdminPromotionBody body, string actorId);
        Task<(bool Ok, string Message)> AdminAssignPromotionAsync(string code, string ownerUserId, string actorId);

        Task<(bool Ok, string Message, long Id)> AdminIssueCreditAsync(AdminCreditBody body, string actorId);
        Task<(bool Ok, string Message)> AdminRevokeCreditAsync(long creditId, string actorId, string? reason);

        Task<List<AdminTierRuleModel>> AdminGetTierRulesAsync(string? profileCode);
        Task<(bool Ok, List<string> Problems)> AdminPutTierRulesAsync(AdminTierRulesBody body, string actorId);

        Task<List<AdminPresentationModel>> AdminListPresentationsAsync();
        Task<(bool Ok, string Message)> AdminUpsertPresentationAsync(AdminPresentationBody body, string actorId);

        Task<AdminCoverageModel> AdminCoverageAsync();
        Task<List<AdminEventModel>> AdminListEventsAsync(int limit);
        Task<(bool Ok, string Message, long Id)> AdminCreateEnterpriseContractAsync(AdminContractBody body, string actorId);

        /// <summary>Customer-facing plan cards: presentation + current prices, template fallback included.</summary>
        Task<PublicPricingModel?> GetPublicPricingAsync(string marketCode, string profileCode, string? templateCode);
        /// <summary>The pricing-context selector's options (customer-app spec 3), from presentation config.</summary>
        Task<List<PricingContextModel>> GetPricingContextsAsync();
    }

    public partial class PlatformBillingService : IPlatformBillingAdminService
    {
        // ------------------------------------------------------------------
        // Permissions (spec 29/30). SystemAdmin / PlatformOwner keep implicit
        // full access; anyone else needs an explicit grant per permission.
        // ------------------------------------------------------------------
        public async Task<bool> HasPermissionAsync(string userId, string permission)
        {
            if (string.IsNullOrWhiteSpace(userId)) return false;
            if (await IsPlatformAdminAsync(userId)) return true;
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            using var q = new NpgsqlCommand(
                "SELECT 1 FROM platformadminpermissions WHERE userid = @U AND permission = @P", conn);
            q.Parameters.AddWithValue("@U", userId);
            q.Parameters.AddWithValue("@P", permission);
            return await q.ExecuteScalarAsync() is not null;
        }

        public async Task<List<string>> MyPermissionsAsync(string userId)
        {
            if (await IsPlatformAdminAsync(userId))
                return new List<string> { "BillingAdmin.*" };
            var list = new List<string>();
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            using var q = new NpgsqlCommand(
                "SELECT permission FROM platformadminpermissions WHERE userid = @U ORDER BY permission", conn);
            q.Parameters.AddWithValue("@U", userId);
            using var r = await q.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(r.GetString(0));
            return list;
        }

        public async Task<(bool Ok, string Message)> GrantPermissionAsync(string targetUserId, string permission, string actorId)
        {
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            using var cmd = new NpgsqlCommand(@"
                INSERT INTO platformadminpermissions (userid, permission, grantedby)
                VALUES (@U, @P, @By) ON CONFLICT (userid, permission) DO NOTHING", conn);
            cmd.Parameters.AddWithValue("@U", targetUserId);
            cmd.Parameters.AddWithValue("@P", permission);
            cmd.Parameters.AddWithValue("@By", actorId);
            await cmd.ExecuteNonQueryAsync();
            await LogEventAsync(conn, null, null, "PermissionGranted", null, $"{targetUserId}:{permission}", actorId, null);
            return (true, "Granted.");
        }

        public async Task<(bool Ok, string Message)> RevokePermissionAsync(string targetUserId, string permission, string actorId)
        {
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            using var cmd = new NpgsqlCommand(
                "DELETE FROM platformadminpermissions WHERE userid = @U AND permission = @P", conn);
            cmd.Parameters.AddWithValue("@U", targetUserId);
            cmd.Parameters.AddWithValue("@P", permission);
            await cmd.ExecuteNonQueryAsync();
            await LogEventAsync(conn, null, null, "PermissionRevoked", $"{targetUserId}:{permission}", null, actorId, null);
            return (true, "Revoked.");
        }

        // ------------------------------------------------------------------
        // Organizations (spec 2.8/31)
        // ------------------------------------------------------------------
        public async Task<List<AdminOrgListItemModel>> AdminListOrganizationsAsync(string? search)
        {
            var list = new List<AdminOrgListItemModel>();
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            using var q = new NpgsqlCommand(@"
                SELECT a.id, a.owneruserid, u.email,
                       COALESCE(NULLIF(TRIM(CONCAT(u.firstname,' ',u.lastname)), ''), u.username),
                       a.orgcode, a.billingmarketcode, a.currencycode, a.status, a.billingcycle,
                       (SELECT COUNT(*) FROM userfarms uf WHERE uf.userid = a.owneruserid)
                  FROM organizationbillingaccounts a
                  LEFT JOIN aspnetusers u ON u.id = a.owneruserid
                 WHERE @S = '' OR u.email ILIKE '%' || @S || '%' OR a.orgcode ILIKE '%' || @S || '%'
                    OR CONCAT(u.firstname,' ',u.lastname) ILIKE '%' || @S || '%'
                 ORDER BY a.id DESC LIMIT 100", conn);
            q.Parameters.AddWithValue("@S", search ?? "");
            using var r = await q.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Add(new AdminOrgListItemModel
                {
                    AccountId = r.GetInt64(0),
                    OwnerUserId = r.GetString(1),
                    OwnerEmail = r.IsDBNull(2) ? null : r.GetString(2),
                    OwnerName = r.IsDBNull(3) ? null : r.GetString(3),
                    OrgCode = r.IsDBNull(4) ? null : r.GetString(4),
                    MarketCode = r.GetString(5),
                    CurrencyCode = r.GetString(6),
                    Status = r.GetString(7),
                    BillingCycle = r.GetString(8),
                    CompanyCount = r.GetInt32(9),
                });
            return list;
        }

        public async Task<AdminOrgInspectorModel?> AdminInspectAsync(string ownerUserId)
        {
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            var acct = await ReadAccountAsync(conn, ownerUserId);
            if (acct is null) return null;   // never auto-provision from the inspector
            var cfg = await LoadConfigAsync(conn, acct.MarketCode);
            var (ps, pe) = CurrentPeriod(acct.BillingCycle);

            var model = new AdminOrgInspectorModel { Account = acct };
            using (var u = new NpgsqlCommand(@"
                SELECT email, COALESCE(NULLIF(TRIM(CONCAT(firstname,' ',lastname)), ''), username)
                  FROM aspnetusers WHERE id = @U", conn))
            {
                u.Parameters.AddWithValue("@U", ownerUserId);
                using var r = await u.ExecuteReaderAsync();
                if (await r.ReadAsync())
                {
                    model.OwnerEmail = r.IsDBNull(0) ? null : r.GetString(0);
                    model.OwnerName = r.IsDBNull(1) ? null : r.GetString(1);
                }
            }

            var rows = new List<CompanyBillingRowModel>();
            foreach (var c in await LoadCompaniesAsync(conn, ownerUserId))
                rows.Add(await EvaluateCompanyAsync(conn, cfg, acct, c, "AdminInspect", ps, pe, persistEvaluation: false));

            foreach (var row in rows)
            {
                decimal? custom = null, grandfathered = null;
                using (var st = new NpgsqlCommand(@"
                    SELECT customprice, grandfatheredprice FROM companybillingstates WHERE farmid = @F", conn))
                {
                    st.Parameters.AddWithValue("@F", row.FarmId);
                    using var r = await st.ExecuteReaderAsync();
                    if (await r.ReadAsync())
                    {
                        custom = r.IsDBNull(0) ? null : r.GetDecimal(0);
                        grandfathered = r.IsDBNull(1) ? null : r.GetDecimal(1);
                    }
                }
                decimal? annual = null;
                if (row.TierCode is not null)
                    annual = PlatformBillingRules.ResolvePrice(cfg.Entries, row.TierCode, row.BillingProfileCode)?.AnnualPrice;
                model.Companies.Add(new AdminCompanyModel
                {
                    FarmId = row.FarmId,
                    CompanyName = row.CompanyName,
                    CompanyFamily = row.CompanyFamily,
                    BusinessType = row.BusinessType,
                    BillingProfileCode = row.BillingProfileCode,
                    BillingProfileName = row.BillingProfileName,
                    MetricType = row.MetricType,
                    MetricValue = row.MetricValue,
                    MetricSource = string.Equals(row.MetricType, "ManualScale", StringComparison.OrdinalIgnoreCase)
                        ? "Configured scale" : "Operational data (read-only)",
                    TierCode = row.TierCode,
                    TierName = row.TierName,
                    MonthlyAmount = row.MonthlyAmount,
                    AnnualPrice = annual,
                    CustomPrice = custom,
                    GrandfatheredPrice = grandfathered,
                    ParticipationStatus = row.ParticipationStatus,
                    PricingStatus = row.PricingStatus,
                });
            }

            model.Preview = await BuildPreviewAsync(conn, cfg, acct, rows, ps, pe);
            model.Discounts = await ListDiscountsAsync(conn, acct.Id);
            model.Credits = await ListCreditsAsync(conn, acct.Id);
            model.Invoices = await GetInvoicesAsync(ownerUserId);
            model.Payments = await GetPaymentsAsync(ownerUserId);
            return model;
        }

        private static async Task<List<AdminDiscountModel>> ListDiscountsAsync(NpgsqlConnection conn, long accountId)
        {
            var list = new List<AdminDiscountModel>();
            using var q = new NpgsqlCommand(@"
                SELECT d.id, d.name, d.discounttype, d.value, d.scope, d.farmid, d.profilecode,
                       d.startdate, d.enddate, d.durationperiods, d.stackable, d.priority, d.reason,
                       d.internalnotes, d.createdby, d.createdatutc, d.approvedby, d.revokedby, d.revokedatutc, d.active,
                       (SELECT COUNT(*) FROM platformdiscountapplications a WHERE a.discountid = d.id)
                  FROM platformdiscounts d WHERE d.accountid = @A ORDER BY d.id DESC", conn);
            q.Parameters.AddWithValue("@A", accountId);
            using var r = await q.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                var applied = r.GetInt32(20);
                var duration = r.IsDBNull(9) ? (int?)null : r.GetInt32(9);
                list.Add(new AdminDiscountModel
                {
                    Id = r.GetInt64(0),
                    Name = r.GetString(1),
                    DiscountType = r.GetString(2),
                    Value = r.GetDecimal(3),
                    Scope = r.GetString(4),
                    FarmId = r.IsDBNull(5) ? null : r.GetString(5),
                    ProfileCode = r.IsDBNull(6) ? null : r.GetString(6),
                    StartDate = r.GetDateTime(7),
                    EndDate = r.IsDBNull(8) ? null : r.GetDateTime(8),
                    DurationPeriods = duration,
                    AppliedCount = applied,
                    RemainingPeriods = duration.HasValue ? Math.Max(0, duration.Value - applied) : null,
                    Stackable = r.GetBoolean(10),
                    Priority = r.GetInt32(11),
                    Reason = r.GetString(12),
                    InternalNotes = r.IsDBNull(13) ? null : r.GetString(13),
                    CreatedBy = r.IsDBNull(14) ? null : r.GetString(14),
                    CreatedAtUtc = r.GetDateTime(15),
                    ApprovedBy = r.IsDBNull(16) ? null : r.GetString(16),
                    RevokedBy = r.IsDBNull(17) ? null : r.GetString(17),
                    RevokedAtUtc = r.IsDBNull(18) ? null : r.GetDateTime(18),
                    Active = r.GetBoolean(19),
                });
            }
            return list;
        }

        private static async Task<List<AdminCreditModel>> ListCreditsAsync(NpgsqlConnection conn, long accountId)
        {
            var list = new List<AdminCreditModel>();
            using (var q = new NpgsqlCommand(@"
                SELECT c.id, c.amount, c.currencycode, COALESCE(u.used, 0), c.reason, c.reference,
                       c.expiresatutc, c.issuedby, c.issuedatutc, c.revokedby
                  FROM platformaccountcredits c
                  LEFT JOIN (SELECT creditid, SUM(amount) AS used FROM platformcreditapplications GROUP BY creditid) u
                    ON u.creditid = c.id
                 WHERE c.accountid = @A ORDER BY c.id DESC", conn))
            {
                q.Parameters.AddWithValue("@A", accountId);
                using var r = await q.ExecuteReaderAsync();
                while (await r.ReadAsync())
                    list.Add(new AdminCreditModel
                    {
                        Id = r.GetInt64(0),
                        Amount = r.GetDecimal(1),
                        CurrencyCode = r.GetString(2),
                        Used = r.GetDecimal(3),
                        Remaining = r.GetDecimal(1) - r.GetDecimal(3),
                        Reason = r.GetString(4),
                        Reference = r.IsDBNull(5) ? null : r.GetString(5),
                        ExpiresAtUtc = r.IsDBNull(6) ? null : r.GetDateTime(6),
                        IssuedBy = r.IsDBNull(7) ? null : r.GetString(7),
                        IssuedAtUtc = r.GetDateTime(8),
                        RevokedBy = r.IsDBNull(9) ? null : r.GetString(9),
                    });
            }
            foreach (var c in list)
            {
                using var q = new NpgsqlCommand(@"
                    SELECT i.invoicenumber FROM platformcreditapplications a
                      JOIN platforminvoices i ON i.id = a.invoiceid
                     WHERE a.creditid = @C ORDER BY a.id", conn);
                q.Parameters.AddWithValue("@C", c.Id);
                using var r = await q.ExecuteReaderAsync();
                while (await r.ReadAsync()) c.AppliedInvoices.Add(r.GetString(0));
            }
            return list;
        }

        // ------------------------------------------------------------------
        // Special discounts (spec 21/22/28/30)
        // ------------------------------------------------------------------
        private async Task<long?> AccountIdForOwnerAsync(NpgsqlConnection conn, string ownerUserId)
        {
            using var q = new NpgsqlCommand(
                "SELECT id FROM organizationbillingaccounts WHERE owneruserid = @U", conn);
            q.Parameters.AddWithValue("@U", ownerUserId);
            return await q.ExecuteScalarAsync() is long id ? id : null;
        }

        public async Task<(bool Ok, string Message, long Id)> AdminAssignDiscountAsync(AdminDiscountBody b, string actorId)
        {
            if (string.IsNullOrWhiteSpace(b.Reason))
                return (false, "A reason is required for every manual discount (spec 21/28).", 0);
            if (b.Value <= 0) return (false, "The discount value must be positive.", 0);
            if (string.Equals(b.Scope, "Company", StringComparison.OrdinalIgnoreCase) && string.IsNullOrWhiteSpace(b.FarmId))
                return (false, "A company-scoped discount needs the company (farmId).", 0);
            if (string.Equals(b.Scope, "Profile", StringComparison.OrdinalIgnoreCase) && string.IsNullOrWhiteSpace(b.ProfileCode))
                return (false, "A profile-scoped discount needs the billing profile code.", 0);

            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();

            // Approval guardrail (spec 30): the threshold is configuration.
            decimal threshold = 10m;
            using (var s = new NpgsqlCommand(
                "SELECT value FROM platformbillingsettings WHERE key = 'discountapprovalthresholdpercent'", conn))
                if (await s.ExecuteScalarAsync() is string tv && decimal.TryParse(tv, out var t)) threshold = t;
            var isLarge = string.Equals(b.DiscountType, "Percentage", StringComparison.OrdinalIgnoreCase)
                ? b.Value > threshold
                : true;   // every fixed-amount credit-like discount counts as large
            if (isLarge && !await HasPermissionAsync(actorId, "BillingAdmin.ApproveLargeDiscount"))
                return (false, $"Discounts above {threshold}% (or fixed amounts) need the ApproveLargeDiscount permission.", 0);

            var accountId = await AccountIdForOwnerAsync(conn, b.OwnerUserId);
            if (accountId is null) return (false, "No billing account exists for that organization.", 0);

            long id;
            using (var ins = new NpgsqlCommand(@"
                INSERT INTO platformdiscounts
                       (accountid, name, discounttype, value, scope, farmid, profilecode, startdate, enddate,
                        durationperiods, stackable, priority, reason, internalnotes, createdby, approvedby)
                VALUES (@A, @N, @T, @V, @S, @F, @P, @SD, @ED, @DP, @St, @Pr, @R, @IN, @By, @Ap)
                RETURNING id", conn))
            {
                ins.Parameters.AddWithValue("@A", accountId.Value);
                ins.Parameters.AddWithValue("@N", b.Name.Trim());
                ins.Parameters.AddWithValue("@T", b.DiscountType);
                ins.Parameters.AddWithValue("@V", b.Value);
                ins.Parameters.AddWithValue("@S", b.Scope);
                ins.Parameters.AddWithValue("@F", (object?)b.FarmId ?? DBNull.Value);
                ins.Parameters.AddWithValue("@P", (object?)b.ProfileCode ?? DBNull.Value);
                ins.Parameters.AddWithValue("@SD", b.StartDate?.Date ?? DateTime.UtcNow.Date);
                ins.Parameters.AddWithValue("@ED", (object?)b.EndDate?.Date ?? DBNull.Value);
                ins.Parameters.AddWithValue("@DP", (object?)b.DurationPeriods ?? DBNull.Value);
                ins.Parameters.AddWithValue("@St", b.Stackable);
                ins.Parameters.AddWithValue("@Pr", b.Priority);
                ins.Parameters.AddWithValue("@R", b.Reason.Trim());
                ins.Parameters.AddWithValue("@IN", (object?)b.InternalNotes ?? DBNull.Value);
                ins.Parameters.AddWithValue("@By", actorId);
                ins.Parameters.AddWithValue("@Ap", isLarge ? actorId : (object)DBNull.Value);
                id = (long)(await ins.ExecuteScalarAsync())!;
            }
            await LogEventAsync(conn, accountId, b.FarmId, "DiscountAssigned", null,
                $"{b.Name}: {b.DiscountType} {b.Value} ({b.Scope})", actorId, b.Reason);
            _log.LogInformation("Discount {Id} '{Name}' assigned to account {Account} by {Actor}", id, b.Name, accountId, actorId);
            return (true, "Discount assigned.", id);
        }

        public async Task<(bool Ok, string Message)> AdminRevokeDiscountAsync(long discountId, string actorId, string? reason)
        {
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            using var cmd = new NpgsqlCommand(@"
                UPDATE platformdiscounts
                   SET active = FALSE, revokedby = @By, revokedatutc = now() AT TIME ZONE 'utc'
                 WHERE id = @I AND revokedatutc IS NULL
                RETURNING accountid, name", conn);
            cmd.Parameters.AddWithValue("@I", discountId);
            cmd.Parameters.AddWithValue("@By", actorId);
            using var r = await cmd.ExecuteReaderAsync();
            if (!await r.ReadAsync()) return (false, "Discount not found or already revoked.");
            var acct = r.GetInt64(0); var name = r.GetString(1);
            r.Close();
            await LogEventAsync(conn, acct, null, "DiscountRevoked", name, null, actorId, reason);
            return (true, "Discount revoked. Already-issued invoices are untouched.");
        }

        public async Task<AdminDiscountPreviewModel?> AdminDiscountPreviewAsync(AdminDiscountBody proposed)
        {
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            var acct = await ReadAccountAsync(conn, proposed.OwnerUserId);
            if (acct is null) return null;
            var cfg = await LoadConfigAsync(conn, acct.MarketCode);
            var (ps, pe) = CurrentPeriod(acct.BillingCycle);
            var rows = new List<CompanyBillingRowModel>();
            foreach (var c in await LoadCompaniesAsync(conn, proposed.OwnerUserId))
                rows.Add(await EvaluateCompanyAsync(conn, cfg, acct, c, "AdminDiscountPreview", ps, pe, persistEvaluation: false));
            var billable = rows.Where(x => x.PricingStatus is "Resolved" or "CustomPrice" or "Grandfathered").ToList();

            var current = await BuildPreviewAsync(conn, cfg, acct, rows, ps, pe);
            var with = await ComputeChargesAsync(conn, acct, cfg, billable, null,
                (proposed.Name, proposed.DiscountType, proposed.Value, proposed.Scope,
                 proposed.FarmId, proposed.ProfileCode, proposed.Stackable, proposed.Priority));
            var creditsAvailable = current.CreditsAvailable;
            var estCredit = Math.Min(creditsAvailable, with.Total);
            var withModel = new BillPreviewModel
            {
                Subtotal = with.Subtotal,
                EligibleCompanyCount = billable.Count,
                DiscountPercent = with.AutoPercent,
                DiscountAmount = with.DiscountTotal,
                TaxRate = with.TaxRate,
                TaxAmount = with.TaxAmount,
                Total = with.Total,
                CurrencyCode = acct.CurrencyCode,
                HasUnpricedCompanies = rows.Any(x => x.PricingStatus == "PricingNotConfigured"),
                PeriodStart = ps,
                PeriodEnd = pe,
                DiscountBreakdown = with.Breakdown.Select(x => new DiscountLineModel { Id = x.Id, Name = x.Name, Amount = x.Amount }).ToList(),
                CreditsAvailable = creditsAvailable,
                EstimatedCreditApplied = estCredit,
                EstimatedAmountDue = with.Total - estCredit,
            };
            return new AdminDiscountPreviewModel { Current = current, WithProposed = withModel };
        }

        // ------------------------------------------------------------------
        // Promotions (spec 20)
        // ------------------------------------------------------------------
        public async Task<List<AdminPromotionModel>> AdminListPromotionsAsync()
        {
            var list = new List<AdminPromotionModel>();
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            using var q = new NpgsqlCommand(@"
                SELECT id, code, name, discounttype, value, durationperiods, marketcode, newcustomersonly,
                       startdate, enddate, maxredemptions, redemptions, stackable, active
                  FROM platformpromotions ORDER BY id DESC", conn);
            using var r = await q.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Add(new AdminPromotionModel
                {
                    Id = r.GetInt64(0), Code = r.GetString(1), Name = r.GetString(2),
                    DiscountType = r.GetString(3), Value = r.GetDecimal(4), DurationPeriods = r.GetInt32(5),
                    MarketCode = r.IsDBNull(6) ? null : r.GetString(6), NewCustomersOnly = r.GetBoolean(7),
                    StartDate = r.GetDateTime(8), EndDate = r.IsDBNull(9) ? null : r.GetDateTime(9),
                    MaxRedemptions = r.IsDBNull(10) ? null : r.GetInt32(10), Redemptions = r.GetInt32(11),
                    Stackable = r.GetBoolean(12), Active = r.GetBoolean(13),
                });
            return list;
        }

        public async Task<(bool Ok, string Message, long Id)> AdminCreatePromotionAsync(AdminPromotionBody b, string actorId)
        {
            if (string.IsNullOrWhiteSpace(b.Code) || string.IsNullOrWhiteSpace(b.Name))
                return (false, "Code and name are required.", 0);
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            try
            {
                using var ins = new NpgsqlCommand(@"
                    INSERT INTO platformpromotions
                           (code, name, discounttype, value, durationperiods, marketcode, newcustomersonly,
                            startdate, enddate, maxredemptions, stackable, createdby)
                    VALUES (@C, @N, @T, @V, @D, @M, @New, @SD, @ED, @Max, @St, @By)
                    RETURNING id", conn);
                ins.Parameters.AddWithValue("@C", b.Code.Trim().ToUpperInvariant());
                ins.Parameters.AddWithValue("@N", b.Name.Trim());
                ins.Parameters.AddWithValue("@T", b.DiscountType);
                ins.Parameters.AddWithValue("@V", b.Value);
                ins.Parameters.AddWithValue("@D", b.DurationPeriods);
                ins.Parameters.AddWithValue("@M", (object?)b.MarketCode ?? DBNull.Value);
                ins.Parameters.AddWithValue("@New", b.NewCustomersOnly);
                ins.Parameters.AddWithValue("@SD", b.StartDate?.Date ?? DateTime.UtcNow.Date);
                ins.Parameters.AddWithValue("@ED", (object?)b.EndDate?.Date ?? DBNull.Value);
                ins.Parameters.AddWithValue("@Max", (object?)b.MaxRedemptions ?? DBNull.Value);
                ins.Parameters.AddWithValue("@St", b.Stackable);
                ins.Parameters.AddWithValue("@By", actorId);
                var id = (long)(await ins.ExecuteScalarAsync())!;
                await LogEventAsync(conn, null, null, "PromotionCreated", null, b.Code, actorId, b.Name);
                return (true, "Promotion created.", id);
            }
            catch (PostgresException ex) when (ex.SqlState == "23505")
            {
                return (false, $"A promotion with code {b.Code} already exists.", 0);
            }
        }

        public async Task<(bool Ok, string Message)> AdminAssignPromotionAsync(string code, string ownerUserId, string actorId)
        {
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            var accountId = await AccountIdForOwnerAsync(conn, ownerUserId);
            if (accountId is null) return (false, "No billing account exists for that organization.");

            long promoId; string name, type; decimal value; int duration; bool stackable;
            using (var q = new NpgsqlCommand(@"
                SELECT id, name, discounttype, value, durationperiods, stackable
                  FROM platformpromotions
                 WHERE code = @C AND active
                   AND startdate <= CURRENT_DATE AND (enddate IS NULL OR enddate >= CURRENT_DATE)
                   AND (maxredemptions IS NULL OR redemptions < maxredemptions)", conn))
            {
                q.Parameters.AddWithValue("@C", code.Trim().ToUpperInvariant());
                using var r = await q.ExecuteReaderAsync();
                if (!await r.ReadAsync())
                    return (false, "That promotion is not available (inactive, out of window, or fully redeemed).");
                promoId = r.GetInt64(0); name = r.GetString(1); type = r.GetString(2);
                value = r.GetDecimal(3); duration = r.GetInt32(4); stackable = r.GetBoolean(5);
            }

            using var tx = await conn.BeginTransactionAsync();
            long discountId;
            try
            {
                using (var ins = new NpgsqlCommand(@"
                    INSERT INTO platformdiscounts
                           (accountid, name, discounttype, value, scope, durationperiods, stackable, priority,
                            reason, promotionid, createdby)
                    VALUES (@A, @N, @T, @V, 'Organization', @D, @St, 50, @R, @P, @By)
                    RETURNING id", conn, (NpgsqlTransaction)tx))
                {
                    ins.Parameters.AddWithValue("@A", accountId.Value);
                    ins.Parameters.AddWithValue("@N", $"{name} ({code.ToUpperInvariant()})");
                    ins.Parameters.AddWithValue("@T", type);
                    ins.Parameters.AddWithValue("@V", value);
                    ins.Parameters.AddWithValue("@D", duration);
                    ins.Parameters.AddWithValue("@St", stackable);
                    ins.Parameters.AddWithValue("@R", $"Promotion {code.ToUpperInvariant()}");
                    ins.Parameters.AddWithValue("@P", promoId);
                    ins.Parameters.AddWithValue("@By", actorId);
                    discountId = (long)(await ins.ExecuteScalarAsync())!;
                }
                using (var red = new NpgsqlCommand(@"
                    INSERT INTO platformpromotionredemptions (promotionid, accountid, discountid, redeemedby)
                    VALUES (@P, @A, @D, @By)", conn, (NpgsqlTransaction)tx))
                {
                    red.Parameters.AddWithValue("@P", promoId);
                    red.Parameters.AddWithValue("@A", accountId.Value);
                    red.Parameters.AddWithValue("@D", discountId);
                    red.Parameters.AddWithValue("@By", actorId);
                    await red.ExecuteNonQueryAsync();
                }
                using (var upd = new NpgsqlCommand(
                    "UPDATE platformpromotions SET redemptions = redemptions + 1 WHERE id = @P", conn, (NpgsqlTransaction)tx))
                {
                    upd.Parameters.AddWithValue("@P", promoId);
                    await upd.ExecuteNonQueryAsync();
                }
                await LogEventAsync(conn, accountId, null, "PromotionAssigned", null, code.ToUpperInvariant(), actorId, name, (NpgsqlTransaction)tx);
                await tx.CommitAsync();
            }
            catch (PostgresException ex) when (ex.SqlState == "23505")
            {
                await tx.RollbackAsync();
                return (false, "This organization has already redeemed that promotion.");
            }
            return (true, $"Promotion {code.ToUpperInvariant()} assigned for {duration} billing period(s).");
        }

        // ------------------------------------------------------------------
        // Credits (spec 26/27)
        // ------------------------------------------------------------------
        public async Task<(bool Ok, string Message, long Id)> AdminIssueCreditAsync(AdminCreditBody b, string actorId)
        {
            if (b.Amount <= 0) return (false, "The credit amount must be positive.", 0);
            if (string.IsNullOrWhiteSpace(b.Reason))
                return (false, "A reason is required for every credit (spec 26).", 0);
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            var acct = await ReadAccountAsync(conn, b.OwnerUserId);
            if (acct is null) return (false, "No billing account exists for that organization.", 0);

            long id;
            using (var ins = new NpgsqlCommand(@"
                INSERT INTO platformaccountcredits
                       (accountid, amount, currencycode, reason, internalnotes, reference, expiresatutc, issuedby)
                VALUES (@A, @Amt, @C, @R, @N, @Ref, @Exp, @By)
                RETURNING id", conn))
            {
                ins.Parameters.AddWithValue("@A", acct.Id);
                ins.Parameters.AddWithValue("@Amt", b.Amount);
                // The account's billing currency, always (spec 26) — never caller-supplied.
                ins.Parameters.AddWithValue("@C", acct.CurrencyCode);
                ins.Parameters.AddWithValue("@R", b.Reason.Trim());
                ins.Parameters.AddWithValue("@N", (object?)b.InternalNotes ?? DBNull.Value);
                ins.Parameters.AddWithValue("@Ref", (object?)b.Reference ?? DBNull.Value);
                ins.Parameters.AddWithValue("@Exp", (object?)b.ExpiresAtUtc ?? DBNull.Value);
                ins.Parameters.AddWithValue("@By", actorId);
                id = (long)(await ins.ExecuteScalarAsync())!;
            }
            await LogEventAsync(conn, acct.Id, null, "CreditIssued", null,
                $"{b.Amount:0.00} {acct.CurrencyCode}", actorId, b.Reason);
            _log.LogInformation("Credit {Id} of {Amount} {Currency} issued to account {Account} by {Actor}",
                id, b.Amount, acct.CurrencyCode, acct.Id, actorId);
            return (true, $"Credit of {acct.CurrencyCode} {b.Amount:N2} issued.", id);
        }

        public async Task<(bool Ok, string Message)> AdminRevokeCreditAsync(long creditId, string actorId, string? reason)
        {
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            using var cmd = new NpgsqlCommand(@"
                UPDATE platformaccountcredits c
                   SET revokedby = @By, revokedatutc = now() AT TIME ZONE 'utc'
                 WHERE c.id = @I AND c.revokedatutc IS NULL
                   AND NOT EXISTS (SELECT 1 FROM platformcreditapplications a WHERE a.creditid = c.id)
                RETURNING c.accountid", conn);
            cmd.Parameters.AddWithValue("@I", creditId);
            cmd.Parameters.AddWithValue("@By", actorId);
            var acct = await cmd.ExecuteScalarAsync();
            if (acct is null)
                return (false, "Credit not found, already revoked, or already partially used — used credits are never deleted (spec 27).");
            await LogEventAsync(conn, (long)acct, null, "CreditRevoked", creditId.ToString(), null, actorId, reason);
            return (true, "Credit revoked.");
        }

        // ------------------------------------------------------------------
        // Tier rules (spec 4/5/6/39)
        // ------------------------------------------------------------------
        public async Task<List<AdminTierRuleModel>> AdminGetTierRulesAsync(string? profileCode)
        {
            var list = new List<AdminTierRuleModel>();
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            using var q = new NpgsqlCommand(@"
                SELECT id, profilecode, tiercode, minvalue, maxvalue, effectivefrom, effectiveto, active
                  FROM billingtierrules
                 WHERE @P = '' OR profilecode = @P
                 ORDER BY profilecode, active DESC, minvalue", conn);
            q.Parameters.AddWithValue("@P", profileCode ?? "");
            using var r = await q.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Add(new AdminTierRuleModel
                {
                    Id = r.GetInt64(0), ProfileCode = r.GetString(1), TierCode = r.GetString(2),
                    MinValue = r.GetDecimal(3), MaxValue = r.IsDBNull(4) ? null : r.GetDecimal(4),
                    EffectiveFrom = r.GetDateTime(5), EffectiveTo = r.IsDBNull(6) ? null : r.GetDateTime(6),
                    Active = r.GetBoolean(7),
                });
            return list;
        }

        public async Task<(bool Ok, List<string> Problems)> AdminPutTierRulesAsync(AdminTierRulesBody b, string actorId)
        {
            var problems = PlatformBillingRules.ValidateTierRules(
                b.Rules.Select(x => (x.TierCode, x.MinValue, x.MaxValue)));
            if (problems.Count > 0) return (false, problems);
            if (b.Rules.Count == 0) return (false, new List<string> { "At least one rule is required." });

            var from = (b.EffectiveFrom ?? DateTime.UtcNow).Date;
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            using var tx = await conn.BeginTransactionAsync();

            string oldSummary;
            using (var oldQ = new NpgsqlCommand(@"
                SELECT string_agg(tiercode || ' ' || minvalue || '-' || COALESCE(maxvalue::text, 'inf'), ', ' ORDER BY minvalue)
                  FROM billingtierrules WHERE profilecode = @P AND active", conn, (NpgsqlTransaction)tx))
            {
                oldQ.Parameters.AddWithValue("@P", b.ProfileCode);
                oldSummary = await oldQ.ExecuteScalarAsync() as string ?? "(none)";
            }

            // Effective-dated change (spec 39): close the current rules, never
            // delete them — historical invoices already carry their snapshots.
            using (var close = new NpgsqlCommand(@"
                UPDATE billingtierrules SET active = FALSE, effectiveto = @D
                 WHERE profilecode = @P AND active", conn, (NpgsqlTransaction)tx))
            {
                close.Parameters.AddWithValue("@P", b.ProfileCode);
                close.Parameters.AddWithValue("@D", from.AddDays(-1));
                await close.ExecuteNonQueryAsync();
            }
            foreach (var rule in b.Rules)
            {
                using var ins = new NpgsqlCommand(@"
                    INSERT INTO billingtierrules (profilecode, tiercode, minvalue, maxvalue, effectivefrom, active)
                    VALUES (@P, @T, @Min, @Max, @D, TRUE)", conn, (NpgsqlTransaction)tx);
                ins.Parameters.AddWithValue("@P", b.ProfileCode);
                ins.Parameters.AddWithValue("@T", rule.TierCode);
                ins.Parameters.AddWithValue("@Min", rule.MinValue);
                ins.Parameters.AddWithValue("@Max", (object?)rule.MaxValue ?? DBNull.Value);
                ins.Parameters.AddWithValue("@D", from);
                await ins.ExecuteNonQueryAsync();
            }
            var newSummary = string.Join(", ", b.Rules.OrderBy(x => x.MinValue)
                .Select(x => $"{x.TierCode} {x.MinValue}-{(x.MaxValue?.ToString() ?? "inf")}"));
            await LogEventAsync(conn, null, null, "TierRulesChanged", oldSummary,
                $"{b.ProfileCode}: {newSummary} (from {from:yyyy-MM-dd})", actorId, null, (NpgsqlTransaction)tx);
            await tx.CommitAsync();
            _log.LogInformation("Tier rules for {Profile} changed by {Actor}: {New}", b.ProfileCode, actorId, newSummary);
            return (true, new List<string>());
        }

        // ------------------------------------------------------------------
        // Pricing presentation (spec 11-16)
        // ------------------------------------------------------------------
        public async Task<List<AdminPresentationModel>> AdminListPresentationsAsync()
        {
            var list = new List<AdminPresentationModel>();
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            using (var q = new NpgsqlCommand(@"
                SELECT id, billingprofilecode, businesstemplatecode, displayname, shortdescription,
                       metricdisplayname, metricsingular, metricplural, sortorder, active
                  FROM pricingpresentationprofiles ORDER BY sortorder, id", conn))
            using (var r = await q.ExecuteReaderAsync())
                while (await r.ReadAsync())
                    list.Add(new AdminPresentationModel
                    {
                        Id = r.GetInt64(0), BillingProfileCode = r.GetString(1),
                        BusinessTemplateCode = r.IsDBNull(2) ? null : r.GetString(2),
                        DisplayName = r.GetString(3),
                        ShortDescription = r.IsDBNull(4) ? null : r.GetString(4),
                        MetricDisplayName = r.IsDBNull(5) ? null : r.GetString(5),
                        MetricSingular = r.IsDBNull(6) ? null : r.GetString(6),
                        MetricPlural = r.IsDBNull(7) ? null : r.GetString(7),
                        SortOrder = r.GetInt32(8), Active = r.GetBoolean(9),
                    });
            foreach (var pres in list)
            {
                using var q = new NpgsqlCommand(@"
                    SELECT tiercode, headline, description, featurebullets, badgetext, ismostpopular, ctatext, displayorder
                      FROM tierpresentations WHERE presentationid = @P ORDER BY displayorder", conn);
                q.Parameters.AddWithValue("@P", pres.Id);
                using var r = await q.ExecuteReaderAsync();
                while (await r.ReadAsync())
                    pres.Tiers.Add(new AdminTierPresentationModel
                    {
                        TierCode = r.GetString(0),
                        Headline = r.IsDBNull(1) ? null : r.GetString(1),
                        Description = r.IsDBNull(2) ? null : r.GetString(2),
                        FeatureBullets = r.IsDBNull(3) ? null : r.GetString(3),
                        BadgeText = r.IsDBNull(4) ? null : r.GetString(4),
                        IsMostPopular = r.GetBoolean(5),
                        CtaText = r.IsDBNull(6) ? null : r.GetString(6),
                        DisplayOrder = r.GetInt32(7),
                    });
            }
            return list;
        }

        public async Task<(bool Ok, string Message)> AdminUpsertPresentationAsync(AdminPresentationBody b, string actorId)
        {
            if (string.IsNullOrWhiteSpace(b.DisplayName)) return (false, "Display name is required.");
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            using var tx = await conn.BeginTransactionAsync();
            long id;
            using (var up = new NpgsqlCommand(@"
                INSERT INTO pricingpresentationprofiles
                       (billingprofilecode, businesstemplatecode, displayname, shortdescription,
                        metricdisplayname, metricsingular, metricplural, sortorder, active, updatedby,
                        updatedatutc)
                VALUES (@P, @T, @D, @S, @M, @MS, @MP, @O, @A, @By, now() AT TIME ZONE 'utc')
                ON CONFLICT (billingprofilecode, COALESCE(businesstemplatecode, ''))
                DO UPDATE SET displayname = EXCLUDED.displayname, shortdescription = EXCLUDED.shortdescription,
                              metricdisplayname = EXCLUDED.metricdisplayname, metricsingular = EXCLUDED.metricsingular,
                              metricplural = EXCLUDED.metricplural, sortorder = EXCLUDED.sortorder,
                              active = EXCLUDED.active, updatedby = EXCLUDED.updatedby,
                              updatedatutc = now() AT TIME ZONE 'utc'
                RETURNING id", conn, (NpgsqlTransaction)tx))
            {
                up.Parameters.AddWithValue("@P", b.BillingProfileCode);
                up.Parameters.AddWithValue("@T", (object?)b.BusinessTemplateCode ?? DBNull.Value);
                up.Parameters.AddWithValue("@D", b.DisplayName.Trim());
                up.Parameters.AddWithValue("@S", (object?)b.ShortDescription ?? DBNull.Value);
                up.Parameters.AddWithValue("@M", (object?)b.MetricDisplayName ?? DBNull.Value);
                up.Parameters.AddWithValue("@MS", (object?)b.MetricSingular ?? DBNull.Value);
                up.Parameters.AddWithValue("@MP", (object?)b.MetricPlural ?? DBNull.Value);
                up.Parameters.AddWithValue("@O", b.SortOrder);
                up.Parameters.AddWithValue("@A", b.Active);
                up.Parameters.AddWithValue("@By", actorId);
                id = (long)(await up.ExecuteScalarAsync())!;
            }
            using (var del = new NpgsqlCommand(
                "DELETE FROM tierpresentations WHERE presentationid = @P", conn, (NpgsqlTransaction)tx))
            {
                del.Parameters.AddWithValue("@P", id);
                await del.ExecuteNonQueryAsync();
            }
            foreach (var t in b.Tiers)
            {
                using var ins = new NpgsqlCommand(@"
                    INSERT INTO tierpresentations
                           (presentationid, tiercode, headline, description, featurebullets, badgetext,
                            ismostpopular, ctatext, displayorder)
                    VALUES (@P, @T, @H, @D, @F, @B, @Pop, @C, @O)", conn, (NpgsqlTransaction)tx);
                ins.Parameters.AddWithValue("@P", id);
                ins.Parameters.AddWithValue("@T", t.TierCode);
                ins.Parameters.AddWithValue("@H", (object?)t.Headline ?? DBNull.Value);
                ins.Parameters.AddWithValue("@D", (object?)t.Description ?? DBNull.Value);
                ins.Parameters.AddWithValue("@F", (object?)t.FeatureBullets ?? DBNull.Value);
                ins.Parameters.AddWithValue("@B", (object?)t.BadgeText ?? DBNull.Value);
                ins.Parameters.AddWithValue("@Pop", t.IsMostPopular);
                ins.Parameters.AddWithValue("@C", (object?)t.CtaText ?? DBNull.Value);
                ins.Parameters.AddWithValue("@O", t.DisplayOrder);
                await ins.ExecuteNonQueryAsync();
            }
            await LogEventAsync(conn, null, null, "PresentationChanged", null,
                $"{b.BillingProfileCode}/{b.BusinessTemplateCode ?? "default"}", actorId, null, (NpgsqlTransaction)tx);
            await tx.CommitAsync();
            return (true, "Presentation saved. Customer pricing cards update immediately; no deploy needed.");
        }

        // ------------------------------------------------------------------
        // Coverage dashboards (spec 34/35/36)
        // ------------------------------------------------------------------
        public async Task<AdminCoverageModel> AdminCoverageAsync()
        {
            var model = new AdminCoverageModel();
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();

            using (var q = new NpgsqlCommand(@"
                SELECT m.code, p.code, t.code,
                       bool_or(e.monthlyprice IS NOT NULL),
                       bool_or(e.annualprice IS NOT NULL)
                  FROM billingmarkets m
                 CROSS JOIN billingprofiles p
                  JOIN (SELECT DISTINCT profilecode, tiercode FROM billingtierrules WHERE active) r
                    ON r.profilecode = p.code
                  JOIN platformtiers t ON t.code = r.tiercode
                  LEFT JOIN pricebooks b ON b.marketcode = m.code AND b.active
                       AND CURRENT_DATE >= b.effectivefrom AND (b.effectiveto IS NULL OR CURRENT_DATE <= b.effectiveto)
                  LEFT JOIN pricebookentries e ON e.pricebookid = b.id AND e.active
                       AND e.tiercode = t.code AND (e.profilecode = p.code OR e.profilecode IS NULL)
                       AND CURRENT_DATE >= e.effectivefrom AND (e.effectiveto IS NULL OR CURRENT_DATE <= e.effectiveto)
                 WHERE p.active
                 GROUP BY m.code, p.code, t.code
                 ORDER BY m.code, p.code, t.code", conn))
            using (var r = await q.ExecuteReaderAsync())
                while (await r.ReadAsync())
                    model.PriceCoverage.Add(new AdminPriceCoverageRow
                    {
                        MarketCode = r.GetString(0),
                        ProfileCode = r.GetString(1),
                        TierCode = r.GetString(2),
                        HasMonthly = !r.IsDBNull(3) && r.GetBoolean(3),
                        HasAnnual = !r.IsDBNull(4) && r.GetBoolean(4),
                    });

            foreach (var g in model.PriceCoverage.GroupBy(x => (x.MarketCode, x.ProfileCode)))
            {
                var noMonthly = g.Where(x => !x.HasMonthly).Select(x => x.TierCode).ToList();
                var noAnnual = g.Where(x => !x.HasAnnual).Select(x => x.TierCode).ToList();
                if (noMonthly.Count > 0)
                    model.PricingWarnings.Add($"{g.Key.ProfileCode} / {g.Key.MarketCode}: monthly price missing for {string.Join(", ", noMonthly)}");
                else if (noAnnual.Count > 0)
                    model.PricingWarnings.Add($"{g.Key.ProfileCode} / {g.Key.MarketCode}: annual price missing for {string.Join(", ", noAnnual)}");
            }

            // Presentation completeness (spec 36): every active profile, plus
            // every Generic template in actual use, with fallback noted.
            using (var q = new NpgsqlCommand(@"
                SELECT p.code,
                       EXISTS (SELECT 1 FROM pricingpresentationprofiles pp
                                WHERE pp.billingprofilecode = p.code AND pp.businesstemplatecode IS NULL AND pp.active)
                  FROM billingprofiles p WHERE p.active ORDER BY p.code", conn))
            using (var r = await q.ExecuteReaderAsync())
                while (await r.ReadAsync())
                    model.PresentationStatus.Add($"{r.GetString(0)} presentation {(r.GetBoolean(1) ? "OK" : "MISSING")}");
            using (var q = new NpgsqlCommand(@"
                SELECT DISTINCT g.genericbusinesstemplate,
                       EXISTS (SELECT 1 FROM pricingpresentationprofiles pp
                                WHERE pp.businesstemplatecode = g.genericbusinesstemplate AND pp.active)
                  FROM genericcompanyprofiles g
                 WHERE g.genericbusinesstemplate IS NOT NULL AND g.genericbusinesstemplate <> ''
                 ORDER BY 1", conn))
            using (var r = await q.ExecuteReaderAsync())
                while (await r.ReadAsync())
                    model.PresentationStatus.Add($"Template {r.GetString(0)}: {(r.GetBoolean(1) ? "override OK" : "using Generic fallback")}");
            return model;
        }

        public async Task<List<AdminEventModel>> AdminListEventsAsync(int limit)
        {
            var list = new List<AdminEventModel>();
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            using var q = new NpgsqlCommand(@"
                SELECT id, createdatutc, eventtype, accountid, farmid, oldvalue, newvalue, actoruserid, reference
                  FROM billingevents ORDER BY id DESC LIMIT @L", conn);
            q.Parameters.AddWithValue("@L", Math.Clamp(limit, 1, 500));
            using var r = await q.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Add(new AdminEventModel
                {
                    Id = r.GetInt64(0), AtUtc = r.GetDateTime(1), EventType = r.GetString(2),
                    AccountId = r.IsDBNull(3) ? null : r.GetInt64(3),
                    FarmId = r.IsDBNull(4) ? null : r.GetString(4),
                    OldValue = r.IsDBNull(5) ? null : r.GetString(5),
                    NewValue = r.IsDBNull(6) ? null : r.GetString(6),
                    Actor = r.IsDBNull(7) ? null : r.GetString(7),
                    Notes = r.IsDBNull(8) ? null : r.GetString(8),
                });
            return list;
        }

        // ------------------------------------------------------------------
        // Enterprise contracts (spec 33/37)
        // ------------------------------------------------------------------
        public async Task<(bool Ok, string Message, long Id)> AdminCreateEnterpriseContractAsync(AdminContractBody b, string actorId)
        {
            if (string.IsNullOrWhiteSpace(b.Name)) return (false, "A contract name is required.", 0);
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            var acct = await ReadAccountAsync(conn, b.OwnerUserId);
            if (acct is null) return (false, "No billing account exists for that organization.", 0);

            using var tx = await conn.BeginTransactionAsync();
            long id;
            using (var ins = new NpgsqlCommand(@"
                INSERT INTO enterprisecontracts
                       (accountid, name, contractreference, billingfrequency, effectivefrom, effectiveto,
                        notes, createdby, approvedby)
                VALUES (@A, @N, @Ref, @F, @From, @To, @Notes, @By, @By)
                RETURNING id", conn, (NpgsqlTransaction)tx))
            {
                ins.Parameters.AddWithValue("@A", acct.Id);
                ins.Parameters.AddWithValue("@N", b.Name.Trim());
                ins.Parameters.AddWithValue("@Ref", (object?)b.ContractReference ?? DBNull.Value);
                ins.Parameters.AddWithValue("@F", b.BillingFrequency);
                ins.Parameters.AddWithValue("@From", b.EffectiveFrom?.Date ?? DateTime.UtcNow.Date);
                ins.Parameters.AddWithValue("@To", (object?)b.EffectiveTo?.Date ?? DBNull.Value);
                ins.Parameters.AddWithValue("@Notes", (object?)b.Notes ?? DBNull.Value);
                ins.Parameters.AddWithValue("@By", actorId);
                id = (long)(await ins.ExecuteScalarAsync())!;
            }
            // The contract's numbers land on the companies as custom prices +
            // EnterpriseContract participation — a proper price, never a
            // disguised giant discount (spec 37).
            foreach (var c in b.Companies)
            {
                using var up = new NpgsqlCommand(@"
                    INSERT INTO companybillingstates (farmid, accountid, customprice, participationstatus)
                    VALUES (@F, @A, @P, 'EnterpriseContract')
                    ON CONFLICT (farmid) DO UPDATE
                       SET customprice = EXCLUDED.customprice, participationstatus = 'EnterpriseContract'",
                    conn, (NpgsqlTransaction)tx);
                up.Parameters.AddWithValue("@F", c.FarmId);
                up.Parameters.AddWithValue("@A", acct.Id);
                up.Parameters.AddWithValue("@P", (object?)c.CustomMonthlyPrice ?? DBNull.Value);
                await up.ExecuteNonQueryAsync();
            }
            await LogEventAsync(conn, acct.Id, null, "EnterpriseContractCreated", null,
                $"{b.Name} ({b.Companies.Count} companies)", actorId, b.ContractReference, (NpgsqlTransaction)tx);
            await tx.CommitAsync();
            return (true, "Enterprise contract recorded and company prices fixed.", id);
        }

        public async Task<List<PricingContextModel>> GetPricingContextsAsync()
        {
            var list = new List<PricingContextModel>();
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            using var q = new NpgsqlCommand(@"
                SELECT billingprofilecode, businesstemplatecode, displayname, sortorder
                  FROM pricingpresentationprofiles WHERE active ORDER BY sortorder, id", conn);
            using var r = await q.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Add(new PricingContextModel
                {
                    BillingProfileCode = r.GetString(0),
                    BusinessTemplateCode = r.IsDBNull(1) ? null : r.GetString(1),
                    DisplayName = r.GetString(2),
                    SortOrder = r.GetInt32(3),
                });
            return list;
        }

        // ------------------------------------------------------------------
        // Customer-facing plan cards (spec 11-16): presentation + prices.
        // ------------------------------------------------------------------
        public async Task<PublicPricingModel?> GetPublicPricingAsync(string marketCode, string profileCode, string? templateCode)
        {
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            var cfg = await LoadConfigAsync(conn, marketCode);
            if (!cfg.Markets.TryGetValue(marketCode, out var market)) return null;

            async Task<(long Id, PublicPricingModel M)?> ReadPresentationAsync(string? template)
            {
                using var q = new NpgsqlCommand(@"
                    SELECT id, displayname, shortdescription, metricdisplayname, metricsingular, metricplural
                      FROM pricingpresentationprofiles
                     WHERE billingprofilecode = @P AND COALESCE(businesstemplatecode, '') = @T AND active", conn);
                q.Parameters.AddWithValue("@P", profileCode);
                q.Parameters.AddWithValue("@T", template ?? "");
                using var r = await q.ExecuteReaderAsync();
                if (!await r.ReadAsync()) return null;
                return (r.GetInt64(0), new PublicPricingModel
                {
                    MarketCode = marketCode,
                    CurrencyCode = market.Currency,
                    BillingProfileCode = profileCode,
                    BusinessTemplateCode = templateCode,
                    DisplayName = r.GetString(1),
                    ShortDescription = r.IsDBNull(2) ? null : r.GetString(2),
                    MetricDisplayName = r.IsDBNull(3) ? null : r.GetString(3),
                    MetricSingular = r.IsDBNull(4) ? null : r.GetString(4),
                    MetricPlural = r.IsDBNull(5) ? null : r.GetString(5),
                });
            }

            var found = !string.IsNullOrWhiteSpace(templateCode) ? await ReadPresentationAsync(templateCode) : null;
            var usedFallback = found is null && !string.IsNullOrWhiteSpace(templateCode);
            found ??= await ReadPresentationAsync(null);   // spec 16: profile default, never a broken page
            if (found is null) return null;
            var (presId, model) = found.Value;
            model.UsedFallback = usedFallback;

            var tierPres = new Dictionary<string, AdminTierPresentationModel>(StringComparer.OrdinalIgnoreCase);
            using (var q = new NpgsqlCommand(@"
                SELECT tiercode, headline, featurebullets, badgetext, ismostpopular, ctatext, displayorder
                  FROM tierpresentations WHERE presentationid = @P ORDER BY displayorder", conn))
            {
                q.Parameters.AddWithValue("@P", presId);
                using var r = await q.ExecuteReaderAsync();
                while (await r.ReadAsync())
                    tierPres[r.GetString(0)] = new AdminTierPresentationModel
                    {
                        TierCode = r.GetString(0),
                        Headline = r.IsDBNull(1) ? null : r.GetString(1),
                        FeatureBullets = r.IsDBNull(2) ? null : r.GetString(2),
                        BadgeText = r.IsDBNull(3) ? null : r.GetString(3),
                        IsMostPopular = r.GetBoolean(4),
                        CtaText = r.IsDBNull(5) ? null : r.GetString(5),
                        DisplayOrder = r.GetInt32(6),
                    };
            }

            foreach (var tier in cfg.Tiers.OrderBy(t => t.Value.Rank))
            {
                var entry = PlatformBillingRules.ResolvePrice(cfg.Entries, tier.Key, profileCode);
                var rule = cfg.TierRules.FirstOrDefault(x =>
                    string.Equals(x.ProfileCode, profileCode, StringComparison.OrdinalIgnoreCase)
                    && string.Equals(x.TierCode, tier.Key, StringComparison.OrdinalIgnoreCase));
                tierPres.TryGetValue(tier.Key, out var pres);
                // Show a card when EITHER the tier has presentation copy or a
                // price/rule exists; enterprise typically has copy but no price.
                if (pres is null && entry is null && rule is null) continue;
                model.Plans.Add(new PublicPlanCardModel
                {
                    TierCode = tier.Key,
                    TierName = tier.Value.Name,
                    Headline = pres?.Headline,
                    FeatureBullets = (pres?.FeatureBullets ?? "")
                        .Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).ToList(),
                    BadgeText = pres?.BadgeText,
                    IsMostPopular = pres?.IsMostPopular ?? false,
                    CtaText = pres?.CtaText,
                    MonthlyPrice = entry?.MonthlyPrice,
                    AnnualPrice = entry?.AnnualPrice,
                    MinValue = rule?.MinValue,
                    MaxValue = rule?.MaxValue,
                });
            }
            return model;
        }
    }
}
