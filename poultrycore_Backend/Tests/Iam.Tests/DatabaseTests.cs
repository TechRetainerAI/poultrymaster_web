using Npgsql;
using Xunit;

namespace Iam.Tests;

/// <summary>
/// Page-access rules that only the database can prove: owner vs staff,
/// explicit deny beating a role, suspension, multi-company isolation,
/// revocation on the next request, audit rows, and who may manage whom.
///
/// <para>
/// Each test opens a transaction, applies migrations 506 + 507 inside it,
/// seeds two organisations, runs, and ROLLS BACK — so it can point at a real
/// development database without changing a row. Skipped unless
/// <c>IAM_ITEST_CONN</c> is set.
/// </para>
/// </summary>
public class DatabaseTests
{
    private static readonly string? Conn = Environment.GetEnvironmentVariable("IAM_ITEST_CONN");

    private static string MigrationsDir()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null && !Directory.Exists(Path.Combine(dir.FullName, "PoultryFarmAPI", "Migrations")))
            dir = dir.Parent;
        // Built outside the repo (artifacts path): fall back to the source tree.
        return dir is not null
            ? Path.Combine(dir.FullName, "PoultryFarmAPI", "Migrations")
            : Environment.GetEnvironmentVariable("IAM_MIGRATIONS_DIR")
              ?? throw new InvalidOperationException("Set IAM_MIGRATIONS_DIR to PoultryFarmAPI/Migrations.");
    }

    private static string Body(string pattern)
    {
        var file = Directory.GetFiles(MigrationsDir(), pattern).Single();
        var sql = File.ReadAllText(file);
        // The test owns the transaction.
        return string.Join('\n', sql.Split('\n').Where(l => l.Trim() is not ("BEGIN;" or "COMMIT;")));
    }

    private const string O = "itest-owner-o", S = "itest-staff-s", T = "itest-staff-t", X = "itest-owner-x";
    private const string A = "itest-farm-a", B = "itest-farm-b", C = "itest-farm-c";

    private static async Task Exec(NpgsqlConnection c, string sql)
    {
        await using var cmd = new NpgsqlCommand(sql, c) { CommandTimeout = 300 };
        await cmd.ExecuteNonQueryAsync();
    }

    private static async Task<T?> Scalar<T>(NpgsqlConnection c, string sql)
    {
        await using var cmd = new NpgsqlCommand(sql, c);
        var r = await cmd.ExecuteScalarAsync();
        return r is null or DBNull ? default : (T)Convert.ChangeType(r, typeof(T));
    }

    private static async Task<HashSet<string>> Effective(NpgsqlConnection c, string user, string farm)
    {
        var keys = new HashSet<string>();
        await using var cmd = new NpgsqlCommand($"SELECT permissionkey FROM spiam_geteffectivepermissions('{user}', '{farm}')", c);
        await using var r = await cmd.ExecuteReaderAsync();
        while (await r.ReadAsync()) keys.Add(r.GetString(0));
        return keys;
    }

    /// <summary>A refusal aborts a Postgres transaction; contain it so the test can carry on.</summary>
    private static async Task<PostgresException> Refused(NpgsqlConnection c, Func<Task> action)
    {
        await Exec(c, "SAVEPOINT expect_refusal");
        var ex = await Assert.ThrowsAsync<PostgresException>(action);
        await Exec(c, "ROLLBACK TO SAVEPOINT expect_refusal");
        return ex;
    }

    private static Task SetAccess(NpgsqlConnection c, string caller, string user, string farm, params string[] keys) =>
        Exec(c, $"SELECT * FROM spiam_pageaccess_set('{caller}', '{user}', '{farm}', '{string.Join(',', keys)}', 'itest')");

    /// <summary>506, seed, 507 (so the legacy rebuild sees the seeded staff), test, roll back.</summary>
    private static async Task InMigratedDb(Func<NpgsqlConnection, Task> test, string staffFlags = "{\"canEnterSales\":true}")
    {
        await using var c = new NpgsqlConnection(Conn);
        await c.OpenAsync();
        await using var tx = await c.BeginTransactionAsync();
        try
        {
            await Exec(c, Body("506_*_PageAccessCatalog.postgres.sql"));
            await Exec(c, $@"
                INSERT INTO aspnetusers (id, username, normalizedusername, firstname, lastname, isstaff, isadmin, farmid, featurepermissions,
                                         emailconfirmed, phonenumberconfirmed, twofactorenabled, lockoutenabled, accessfailedcount)
                VALUES ('{O}', 'itest_o', 'ITEST_O', 'Owner', 'O', FALSE, FALSE, '{A}', NULL, TRUE, FALSE, FALSE, FALSE, 0),
                       ('{X}', 'itest_x', 'ITEST_X', 'Owner', 'X', FALSE, FALSE, '{C}', NULL, TRUE, FALSE, FALSE, FALSE, 0),
                       ('{S}', 'itest_s', 'ITEST_S', 'Staff', 'S', TRUE,  FALSE, '{A}', '{staffFlags}', TRUE, FALSE, FALSE, FALSE, 0),
                       ('{T}', 'itest_t', 'ITEST_T', 'Staff', 'T', TRUE,  FALSE, '{A}', NULL, TRUE, FALSE, FALSE, FALSE, 0);
                INSERT INTO farms (id, name, email, type, owneruserid) VALUES
                       ('{A}', 'ITest Poultry A', 'a@itest', 'Poultry', '{O}'),
                       ('{B}', 'ITest Water B',   'b@itest', 'Water',   '{O}'),
                       ('{C}', 'ITest Poultry C', 'c@itest', 'Poultry', '{X}');
                INSERT INTO userfarms (userid, farmid, role) VALUES
                       ('{O}', '{A}', 'Admin'), ('{O}', '{B}', 'Admin'), ('{X}', '{C}', 'Admin'),
                       ('{S}', '{A}', 'Staff'), ('{S}', '{B}', 'Staff'), ('{T}', '{A}', 'Staff');");
            await Exec(c, Body("507_*_PageAccessMembership.postgres.sql"));
            await test(c);
        }
        finally
        {
            await tx.RollbackAsync();
        }
    }

    [SkippableFact]
    public async Task OwnerHasEverythingAndCannotBeRestricted()
    {
        Skip.If(string.IsNullOrWhiteSpace(Conn), "IAM_ITEST_CONN not set");
        await InMigratedDb(async c =>
        {
            var all = await Scalar<long>(c, "SELECT count(*) FROM iampermissions");
            Assert.Equal(all, (await Effective(c, O, A)).Count);
            var ex = await Refused(c, () => SetAccess(c, S, O, A, "poultry.sales.view"));
            Assert.Contains("owner", ex.MessageText, StringComparison.OrdinalIgnoreCase);
        });
    }

    /// <summary>The demonstration: P&amp;L, Supplier Balances and Cash Account off; Sales and Expenses kept (tests 3, 4, 5).</summary>
    [SkippableFact]
    public async Task OwnerRestrictsProfitLossSupplierBalancesAndCash()
    {
        Skip.If(string.IsNullOrWhiteSpace(Conn), "IAM_ITEST_CONN not set");
        await InMigratedDb(async c =>
        {
            await SetAccess(c, O, S, A, "poultry.sales.view", "poultry.sales.create", "poultry.expenses.view", "poultry.expenses.create");
            var e = await Effective(c, S, A);
            Assert.Contains("poultry.sales.view", e);
            Assert.Contains("poultry.expenses.view", e);
            Assert.DoesNotContain("poultry.profit-loss.view", e);
            Assert.DoesNotContain("poultry.supplier-balances.view", e);
            Assert.DoesNotContain("poultry.cash.view", e);
            Assert.DoesNotContain("poultry.payroll.view", e);
            Assert.DoesNotContain("poultry.owner-money.view", e);
        });
    }

    [SkippableFact]
    public async Task CreateIsNotApprove()
    {
        Skip.If(string.IsNullOrWhiteSpace(Conn), "IAM_ITEST_CONN not set");
        await InMigratedDb(async c =>
        {
            await SetAccess(c, O, S, A, "poultry.sales.view", "poultry.sales.create");
            var e = await Effective(c, S, A);
            Assert.Contains("poultry.sales.create", e);
            Assert.DoesNotContain("poultry.sales.approve", e);
            Assert.DoesNotContain("poultry.sales.reverse", e);

            await SetAccess(c, O, S, A, "poultry.sales.view");
            Assert.DoesNotContain("poultry.sales.create", await Effective(c, S, A)); // view-only (test 18)
        });
    }

    [SkippableFact]
    public async Task EachCompanyHasItsOwnPermissions()
    {
        Skip.If(string.IsNullOrWhiteSpace(Conn), "IAM_ITEST_CONN not set");
        await InMigratedDb(async c =>
        {
            await SetAccess(c, O, S, A, "poultry.sales.view", "poultry.expenses.view");
            await SetAccess(c, O, S, B, "water.sales.view", "water.profit-loss.view");
            var a = await Effective(c, S, A);
            var b = await Effective(c, S, B);
            Assert.Contains("poultry.expenses.view", a);
            Assert.DoesNotContain("poultry.profit-loss.view", a);
            Assert.Contains("water.profit-loss.view", b);
            Assert.DoesNotContain("water.expenses.view", b);
            Assert.DoesNotContain(a, k => k.StartsWith("water."));
            Assert.Empty(await Effective(c, S, C)); // another organisation's company
        });
    }

    [SkippableFact]
    public async Task RevocationAppliesOnTheNextRequest()
    {
        Skip.If(string.IsNullOrWhiteSpace(Conn), "IAM_ITEST_CONN not set");
        await InMigratedDb(async c =>
        {
            await SetAccess(c, O, S, A, "poultry.sales.view", "poultry.cash-flow.view");
            Assert.Contains("poultry.cash-flow.view", await Effective(c, S, A));
            await SetAccess(c, O, S, A, "poultry.sales.view");
            Assert.DoesNotContain("poultry.cash-flow.view", await Effective(c, S, A));
        });
    }

    /// <summary>An explicit untick beats a role, including Organization Admin (tests 15, 16).</summary>
    [SkippableFact]
    public async Task ExplicitUntickBeatsAdminRole()
    {
        Skip.If(string.IsNullOrWhiteSpace(Conn), "IAM_ITEST_CONN not set");
        await InMigratedDb(async c =>
        {
            await Exec(c, $"UPDATE aspnetusers SET isadmin = TRUE WHERE id = '{S}'"); // the admin switch (trigger adds the role)
            Assert.Contains("poultry.profit-loss.view", await Effective(c, S, A));

            var everythingButPl = (await Effective(c, S, A)).Where(k => k != "poultry.profit-loss.view").ToArray();
            await SetAccess(c, O, S, A, everythingButPl);
            Assert.DoesNotContain("poultry.profit-loss.view", await Effective(c, S, A));
            Assert.Equal(1, await Scalar<long>(c,
                $"SELECT count(*) FROM iamuserpermissions WHERE userid = '{S}' AND farmid = '{A}' AND permissionkey = 'poultry.profit-loss.view' AND effect = 'Deny'"));

            await Exec(c, $"UPDATE aspnetusers SET isadmin = FALSE WHERE id = '{S}'");
            Assert.Equal(0, await Scalar<long>(c,
                $"SELECT count(*) FROM iamuserroles ur JOIN iamroles r USING (roleid) WHERE ur.userid = '{S}' AND r.rolekey = 'sys-org-admin'"));
        });
    }

    [SkippableFact]
    public async Task SuspensionRemovesAccessWhateverIsTicked()
    {
        Skip.If(string.IsNullOrWhiteSpace(Conn), "IAM_ITEST_CONN not set");
        await InMigratedDb(async c =>
        {
            await SetAccess(c, O, S, A, "poultry.sales.view");
            await Exec(c, $"SELECT * FROM spiam_membership_setstatus('{O}', '{S}', '{A}', 'suspended', 'itest')");
            Assert.Empty(await Effective(c, S, A));
            Assert.NotEmpty(await Effective(c, S, B)); // still active at the other company

            await Exec(c, $"UPDATE aspnetusers SET refreshtoken = 'rt' WHERE id = '{S}'");
            await Exec(c, $"SELECT * FROM spiam_membership_setstatus('{O}', '{S}', '{B}', 'terminated', 'itest')");
            Assert.True(await Scalar<bool>(c, $"SELECT tokensvalidfrom IS NOT NULL FROM iamusersecurity WHERE userid = '{S}'"));
            Assert.Null(await Scalar<string>(c, $"SELECT refreshtoken FROM aspnetusers WHERE id = '{S}'"));
        });
    }

    [SkippableFact]
    public async Task ChangesAreRecordedInPlainWords()
    {
        Skip.If(string.IsNullOrWhiteSpace(Conn), "IAM_ITEST_CONN not set");
        await InMigratedDb(async c =>
        {
            await SetAccess(c, O, S, A, "poultry.sales.view", "poultry.profit-loss.view");
            await SetAccess(c, O, S, A, "poultry.sales.view");
            var detail = await Scalar<string>(c,
                $"SELECT detail FROM iamaccessaudit WHERE entity = 'PageAccess' AND subjectid = '{S}' AND actorid = '{O}' AND operation = 'Revoke' ORDER BY id DESC LIMIT 1");
            Assert.Equal("Profit & Loss: Enabled → Disabled (itest)", detail);
        });
    }

    [SkippableFact]
    public async Task NobodyGrantsAccessTheyDoNotHave()
    {
        Skip.If(string.IsNullOrWhiteSpace(Conn), "IAM_ITEST_CONN not set");
        await InMigratedDb(async c =>
        {
            // S may manage access but holds no payroll; T starts without payroll too
            // (the old menu showed Poultry Payroll to everyone, so take it away first).
            await SetAccess(c, O, S, A, "office.employees.view", "office.employee-access.view", "office.employee-access.edit", "poultry.sales.view");
            await SetAccess(c, O, T, A, "poultry.flocks.view");
            var ex = await Refused(c, () => SetAccess(c, S, T, A, "poultry.payroll.view"));
            Assert.Equal("42501", ex.SqlState);
            await SetAccess(c, S, T, A, "poultry.sales.view"); // within their own access: fine
            Assert.Contains("poultry.sales.view", await Effective(c, T, A));
            // ...and nobody edits their own access.
            await Refused(c, () => SetAccess(c, S, S, A, "poultry.sales.view"));
        });
    }

    [SkippableFact]
    public async Task EmployeeManagementStaysInsideTheOrganisation()
    {
        Skip.If(string.IsNullOrWhiteSpace(Conn), "IAM_ITEST_CONN not set");
        await InMigratedDb(async c =>
        {
            Assert.True(await Scalar<bool>(c, $"SELECT fniam_maymanageemployee('{O}', '{S}')"));
            Assert.False(await Scalar<bool>(c, $"SELECT fniam_maymanageemployee('{X}', '{S}')"));
            Assert.False(await Scalar<bool>(c, $"SELECT fniam_maymanageemployee('{S}', '{O}')"));
            Assert.False(await Scalar<bool>(c, $"SELECT fniam_maymanageemployee('{S}', '{T}')"));
        });
    }

    /// <summary>Test 12: existing staff keep what they could open, and nothing sensitive they could not.</summary>
    [SkippableFact]
    public async Task ExistingStaffKeepTheirAccess()
    {
        Skip.If(string.IsNullOrWhiteSpace(Conn), "IAM_ITEST_CONN not set");
        await InMigratedDb(async c =>
        {
            var e = await Effective(c, S, A); // seeded with {"canEnterSales": true}
            Assert.Contains("poultry.sales.view", e);              // the flag they had
            Assert.Contains("poultry.production-records.view", e); // ungated in the old menu
            Assert.DoesNotContain("poultry.cash.view", e);         // needed View Cash Ledger
            Assert.DoesNotContain("poultry.profit-loss.view", e);  // needed Financial/Reports
            Assert.DoesNotContain("office.access.view", e);        // admin-only
        });
    }
}
