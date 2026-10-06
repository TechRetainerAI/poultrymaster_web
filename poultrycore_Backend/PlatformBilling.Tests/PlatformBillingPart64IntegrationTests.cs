// Spec Parts 64 + 65 — the required billing-engine test, end to end against a
// REAL PostgreSQL database:
//
//   Evans Group (GH/GHS) with three companies —
//     Prof Owusu Poultry   POULTRY_BIRDS          6,365 birds
//     Evans Academy        Generic/School → GENERIC_STANDARD
//     Evans Restaurant     RESTAURANT_LOCATIONS
//   → one consolidated invoice (three lines + multi-company discount),
//     three persisted evaluation snapshots, ONE provider payment.
//   Part 65: raise today's bird count afterwards — the settled invoice must
//     still show the metric used THEN. History is immutable.
//
// The test creates its own throwaway database (billing_itest_*), applies the
// real 329/330 migrations onto minimal stubs of the platform tables the
// engine touches, runs the real PlatformBillingService with a fake payment
// provider, and drops the database afterwards. Fixture prices for the
// generic/restaurant profiles exist only inside the throwaway database —
// live commercial configuration is never touched.
//
// Set BILLING_ITEST_CONN to a maintenance connection string (a role allowed
// CREATE DATABASE). Without it the test reports itself skipped and passes,
// so the fast rules-only suite keeps working anywhere.

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.Extensions.Logging.Abstractions;
using Npgsql;
using PoultryFarmAPIWeb.Business;
using PoultryFarmAPIWeb.Models;
using Xunit;
using Xunit.Abstractions;

namespace PlatformBilling.Tests
{
    public class PlatformBillingPart64IntegrationTests
    {
        private readonly ITestOutputHelper _out;
        public PlatformBillingPart64IntegrationTests(ITestOutputHelper output) => _out = output;

        private sealed class FakeProvider : IPlatformPaymentProvider
        {
            public string Name => "Paystack";
            public bool IsConfigured => true;
            public long LastAmountMinor { get; private set; }
            public string? LastReference { get; private set; }

            public Task<ProviderCheckout> CreateCheckoutAsync(string email, long amountMinor, string currency,
                string reference, string successUrl, string cancelUrl, string invoiceNumber, long accountId)
            {
                LastAmountMinor = amountMinor;
                LastReference = reference;
                return Task.FromResult(new ProviderCheckout(true, "https://fake.checkout/" + reference, null));
            }

            public Task<ProviderCharge> VerifyAsync(string reference) =>
                Task.FromResult(new ProviderCharge(true, "FAKE-" + reference, reference, LastAmountMinor,
                    "GHS", DateTime.UtcNow, "card ending 0000", null));

            public ProviderWebhookEvent ParseWebhook(string payload, string signatureHeader) =>
                throw new NotSupportedException("not used in this test");
        }

        private static string? MigrationsDir()
        {
            // bin/Debug/net8.0 → repo's PoultryFarmAPI/Migrations
            var d = AppContext.BaseDirectory;
            for (var i = 0; i < 8 && d != null; i++, d = Path.GetDirectoryName(d))
            {
                var probe = Path.Combine(d!, "PoultryFarmAPI", "Migrations");
                if (Directory.Exists(probe)) return probe;
            }
            return null;
        }

        private static string StripPsqlMeta(string sql) =>
            string.Join("\n", sql.Replace("\r\n", "\n").Split('\n').Where(l => !l.TrimStart().StartsWith("\\")));

        private static async Task Exec(NpgsqlConnection c, string sql)
        {
            using var cmd = new NpgsqlCommand(sql, c) { CommandTimeout = 300 };
            await cmd.ExecuteNonQueryAsync();
        }

        private static async Task<object?> Scalar(NpgsqlConnection c, string sql)
        {
            using var cmd = new NpgsqlCommand(sql, c) { CommandTimeout = 300 };
            return await cmd.ExecuteScalarAsync();
        }

        [Fact]
        public async Task Part64_ThreeCompanies_OneInvoice_OnePayment_And_Part65_HistoryImmutable()
        {
            var maint = Environment.GetEnvironmentVariable("BILLING_ITEST_CONN");
            if (string.IsNullOrWhiteSpace(maint))
            {
                _out.WriteLine("SKIPPED: set BILLING_ITEST_CONN to run the Part 64/65 integration test.");
                return;
            }

            var dbName = "billing_itest_" + Guid.NewGuid().ToString("N").Substring(0, 10);
            var maintBuilder = new NpgsqlConnectionStringBuilder(maint);

            using (var mc = new NpgsqlConnection(maintBuilder.ConnectionString))
            {
                await mc.OpenAsync();
                await Exec(mc, $"CREATE DATABASE {dbName}");
            }

            var testBuilder = new NpgsqlConnectionStringBuilder(maint) { Database = dbName };
            var cs = testBuilder.ConnectionString;
            try
            {
                const string owner = "itest-owner-evans";
                const string farmPoultry = "itest-farm-poultry";
                const string farmSchool = "itest-farm-school";
                const string farmRest = "itest-farm-restaurant";

                using (var c = new NpgsqlConnection(cs))
                {
                    await c.OpenAsync();

                    // Minimal stubs of the platform tables/SP the engine reads.
                    await Exec(c, @"
                        CREATE TABLE aspnetusers (
                            id varchar(450) PRIMARY KEY, businessofficecountry varchar(100),
                            organizationcode varchar(50), email varchar(256),
                            firstname varchar(100), lastname varchar(100), username varchar(256));
                        CREATE TABLE aspnetroles (id varchar(450) PRIMARY KEY, name varchar(256));
                        CREATE TABLE aspnetuserroles (userid varchar(450), roleid varchar(450));
                        CREATE TABLE farms (
                            farmid varchar(450) PRIMARY KEY, name varchar(200) NOT NULL,
                            email varchar(256), type varchar(50), createdat timestamp, isdeleted boolean DEFAULT false);
                        CREATE TABLE userfarms (userid varchar(450), farmid varchar(450), role varchar(50), createdat timestamp DEFAULT now());
                        CREATE TABLE genericcompanyprofiles (
                            genericcompanyprofileid serial PRIMARY KEY, farmid varchar(450), genericbusinesstemplate text);
                        CREATE TABLE flock (
                            farmid text, flockid int, quantity numeric, active boolean DEFAULT true,
                            hasarrived boolean DEFAULT true, isdeleted boolean DEFAULT false);
                        CREATE TABLE productionrecords (farmid text, flockid int, noofbirdsleft numeric, date timestamp);
                        CREATE FUNCTION spcompany_getbyuserid(p_userid text)
                        RETURNS TABLE(farmid varchar, name varchar, type varchar, role varchar)
                        LANGUAGE sql STABLE AS $$
                            SELECT f.farmid, f.name, f.type, uf.role
                              FROM farms f JOIN userfarms uf ON uf.farmid = f.farmid
                             WHERE uf.userid = p_userid AND COALESCE(f.isdeleted, false) = false
                        $$;");

                    // The REAL billing migrations.
                    var mig = MigrationsDir();
                    Assert.False(mig is null, "PoultryFarmAPI/Migrations not found relative to test binary");
                    await Exec(c, StripPsqlMeta(File.ReadAllText(Path.Combine(mig!, "329_PlatformBillingCore.postgres.sql"))));
                    await Exec(c, StripPsqlMeta(File.ReadAllText(Path.Combine(mig!, "330_PlatformBillingPhaseB.postgres.sql"))));
                    await Exec(c, StripPsqlMeta(File.ReadAllText(Path.Combine(mig!, "341_PlatformBillingAdminApp.postgres.sql"))));

                    // Fixture commercial config FOR THIS THROWAWAY DB ONLY:
                    // generic + restaurant starter prices, School template mapping,
                    // and the seeded (inactive) multi-company discount switched on.
                    await Exec(c, @"
                        INSERT INTO billingtierrules (profilecode, tiercode, minvalue, maxvalue, active)
                        SELECT 'GENERIC_STANDARD', 'starter', 0, NULL, true
                         WHERE NOT EXISTS (SELECT 1 FROM billingtierrules WHERE profilecode = 'GENERIC_STANDARD');
                        INSERT INTO billingtierrules (profilecode, tiercode, minvalue, maxvalue, active)
                        SELECT 'RESTAURANT_LOCATIONS', 'starter', 0, NULL, true
                         WHERE NOT EXISTS (SELECT 1 FROM billingtierrules WHERE profilecode = 'RESTAURANT_LOCATIONS');
                        INSERT INTO pricebookentries (pricebookid, tiercode, profilecode, currencycode, monthlyprice, active)
                        SELECT pb.id, 'starter', 'GENERIC_STANDARD', 'GHS', 200, true FROM pricebooks pb WHERE pb.code = 'GH-2026';
                        INSERT INTO pricebookentries (pricebookid, tiercode, profilecode, currencycode, monthlyprice, active)
                        SELECT pb.id, 'starter', 'RESTAURANT_LOCATIONS', 'GHS', 300, true FROM pricebooks pb WHERE pb.code = 'GH-2026';
                        INSERT INTO businesstemplatebillingprofiles (templatecode, defaultbillingprofile)
                        VALUES ('School', 'GENERIC_STANDARD')
                        ON CONFLICT (templatecode) DO UPDATE SET defaultbillingprofile = EXCLUDED.defaultbillingprofile;
                        UPDATE multicompanydiscountrules SET active = true;");

                    // Evans Group: owner + three companies; poultry flock = 6,365 birds.
                    await Exec(c, $@"
                        INSERT INTO aspnetusers (id, businessofficecountry, organizationcode, email, firstname, lastname, username)
                        VALUES ('{owner}', 'Ghana', 'EVANS', 'evans@example.test', 'Evans', 'Group', 'evansgroup');
                        INSERT INTO farms (farmid, name, email, type, createdat) VALUES
                        ('{farmPoultry}', 'Prof Owusu Poultry', 'p@example.test', 'Poultry',    now() - interval '200 days'),
                        ('{farmSchool}',  'Evans Academy',      's@example.test', 'Generic',    now() - interval '150 days'),
                        ('{farmRest}',    'Evans Restaurant',   'r@example.test', 'Restaurant', now() - interval '100 days');
                        INSERT INTO userfarms (userid, farmid, role) VALUES
                        ('{owner}', '{farmPoultry}', 'Admin'), ('{owner}', '{farmSchool}', 'Admin'), ('{owner}', '{farmRest}', 'Admin');
                        INSERT INTO genericcompanyprofiles (farmid, genericbusinesstemplate) VALUES ('{farmSchool}', 'School');
                        INSERT INTO flock (farmid, flockid, quantity) VALUES ('{farmPoultry}', 1, 6365);");
                }

                var provider = new FakeProvider();
                var svc = new PlatformBillingService(cs, provider, NullLogger<PlatformBillingService>.Instance);

                // Bootstrap the account + company states, then give the two
                // manual-scale companies their scale (1 unit each → starter).
                var summary = await svc.GetSummaryAsync(owner);
                Assert.Equal("GH", summary.Account.MarketCode);
                Assert.Equal("GHS", summary.Account.CurrencyCode);
                using (var c = new NpgsqlConnection(cs))
                {
                    await c.OpenAsync();
                    await Exec(c, $"UPDATE companybillingstates SET manualscalevalue = 1 WHERE farmid IN ('{farmSchool}', '{farmRest}')");
                }

                summary = await svc.GetSummaryAsync(owner);
                Assert.Equal(3, summary.Companies.Count);
                Assert.False(summary.Preview.HasUnpricedCompanies);
                var poultryRow = summary.Companies.Single(x => x.FarmId == farmPoultry);
                Assert.Equal(6365m, poultryRow.MetricValue);          // Part 64 metric
                Assert.Equal(1500m, poultryRow.MonthlyAmount);        // >5,000 birds → GHS 1,500

                // Subtotal 1500 + 200 + 300 = 2000; 3 companies → seeded 10% discount.
                Assert.Equal(2000m, summary.Preview.Subtotal);
                Assert.Equal(3, summary.Preview.EligibleCompanyCount);
                Assert.Equal(10m, summary.Preview.DiscountPercent);
                Assert.Equal(1800m, summary.Preview.Total);

                // ONE consolidated checkout → ONE provider payment settles it.
                var checkout = await svc.StartCheckoutAsync(new StartCheckoutRequest
                {
                    UserId = owner,
                    SuccessUrl = "https://test/success",
                    FailureUrl = "https://test/cancel",
                });
                Assert.True(checkout.Success, checkout.Message);
                Assert.Equal(1800m, checkout.Amount);
                Assert.Equal(180000, provider.LastAmountMinor);       // GHS → pesewas

                var settle = await svc.VerifyAndSettleAsync(owner, checkout.Reference!);
                Assert.True(settle.Ok, settle.Message);

                var invoices = await svc.GetInvoicesAsync(owner);
                var inv = Assert.Single(invoices);                    // ONE organization invoice
                Assert.Equal(3, inv.Lines.Count);                     // one line per company
                Assert.Equal(1800m, inv.TotalAmount);
                Assert.Equal(0m, inv.Balance);
                Assert.Equal("Paid", inv.Status, ignoreCase: true);

                var payments = await svc.GetPaymentsAsync(owner);
                Assert.Single(payments);                              // ONE payment

                using (var c = new NpgsqlConnection(cs))
                {
                    await c.OpenAsync();
                    // Evaluation snapshots persisted for all three companies.
                    var snaps = Convert.ToInt32(await Scalar(c,
                        "SELECT COUNT(DISTINCT farmid) FROM companybillingevaluations WHERE evaluationreason = 'InvoiceGeneration'"));
                    Assert.Equal(3, snaps);

                    // ---- Part 65: months later the flock shrinks to 4,200 ----
                    await Exec(c, $"INSERT INTO productionrecords (farmid, flockid, noofbirdsleft, date) VALUES ('{farmPoultry}', 1, 4200, now())");
                }

                var today = await svc.GetSummaryAsync(owner);
                Assert.Equal(4200m, today.Companies.Single(x => x.FarmId == farmPoultry).MetricValue);

                // The settled invoice still shows the metric used THEN — never recalculated.
                var invAgain = (await svc.GetInvoicesAsync(owner)).Single();
                var poultryLine = invAgain.Lines.Single(l => l.FarmId == farmPoultry);
                Assert.Equal(6365m, poultryLine.MetricValue);
                Assert.Equal(1500m, poultryLine.LineAmount);
                Assert.Equal(1800m, invAgain.TotalAmount);
                _out.WriteLine($"Part 64/65 passed against throwaway db {dbName}.");
            }
            finally
            {
                try
                {
                    using var mc = new NpgsqlConnection(maintBuilder.ConnectionString);
                    await mc.OpenAsync();
                    await Exec(mc, $@"
                        SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '{dbName}' AND pid <> pg_backend_pid();");
                    await Exec(mc, $"DROP DATABASE IF EXISTS {dbName}");
                }
                catch (Exception ex) { _out.WriteLine($"cleanup: {ex.Message}"); }
            }
        }
    }
}
