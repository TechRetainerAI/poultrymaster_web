// Applies one .sql migration file to the Farm API's PostgreSQL database.
//
// WHY THIS EXISTS
// psql is not installed on this machine, and the migrations are plain .sql files
// that have to be run by hand. This reads ConnectionStrings:PoultryConn from the
// SAME user-secrets store the Farm API uses (matching UserSecretsId in the csproj),
// so there is nothing extra to configure and no copy of the credential anywhere.
//
// USAGE
//   cd poultrycore_Backend/Tools/RunMigration
//   dotnet run -- ../../PoultryFarmAPI/Migrations/287_RestaurantCustomMenuItemNames.postgres.sql
//
//   Add --dry-run to connect, report the server/database and exit without executing.
//
// The whole file runs inside ONE transaction: if any statement fails, nothing is
// committed, so a partially-applied migration cannot be left behind.

using Microsoft.Extensions.Configuration;
using Npgsql;

var dryRun = args.Contains("--dry-run");
var path = args.FirstOrDefault(a => !a.StartsWith("--"));

if (string.IsNullOrWhiteSpace(path))
{
    Console.Error.WriteLine("Usage: dotnet run -- <path-to.sql> [--dry-run]");
    return 2;
}
if (!File.Exists(path))
{
    Console.Error.WriteLine($"ERROR: file not found: {Path.GetFullPath(path)}");
    return 2;
}

var config = new ConfigurationBuilder()
    .AddUserSecrets(typeof(Program).Assembly, optional: true)
    .AddEnvironmentVariables()
    .Build();

var cs = config["ConnectionStrings:PoultryConn"];
if (string.IsNullOrWhiteSpace(cs))
{
    Console.Error.WriteLine(
        "ERROR: no connection string.\n" +
        "Expected ConnectionStrings:PoultryConn in the Farm API user-secrets store\n" +
        "(UserSecretsId 908e46c5-3db3-4cbd-83ae-341a968cf7b3), or the environment\n" +
        "variable ConnectionStrings__PoultryConn.");
    return 2;
}

// Report where we are pointed WITHOUT ever printing the password.
var b = new NpgsqlConnectionStringBuilder(cs);
Console.WriteLine($"Server   : {b.Host}:{b.Port}");
Console.WriteLine($"Database : {b.Database}");
Console.WriteLine($"User     : {b.Username}");
Console.WriteLine($"File     : {Path.GetFileName(path)}");
Console.WriteLine();

var sql = File.ReadAllText(path);

await using var conn = new NpgsqlConnection(cs);
try
{
    await conn.OpenAsync();
}
catch (Exception ex)
{
    Console.Error.WriteLine($"ERROR: could not connect — {ex.Message}");
    return 1;
}

if (dryRun)
{
    Console.WriteLine("Dry run: connected successfully. Nothing was executed.");
    return 0;
}

// --query: run the file as a SELECT and print the rows instead of executing DDL.
if (args.Contains("--query"))
{
    await using var q = new NpgsqlCommand(sql, conn);
    await using var rdr = await q.ExecuteReaderAsync();
    while (await rdr.ReadAsync())
    {
        var cells = new List<string>();
        for (int i = 0; i < rdr.FieldCount; i++)
            cells.Add(rdr.IsDBNull(i) ? "NULL" : rdr.GetValue(i).ToString() ?? "");
        Console.WriteLine(string.Join("  |  ", cells));
    }
    return 0;
}

await using var tx = await conn.BeginTransactionAsync();
try
{
    await using var cmd = new NpgsqlCommand(sql, conn, tx);
    cmd.CommandTimeout = 300;
    await cmd.ExecuteNonQueryAsync();
    await tx.CommitAsync();
    Console.WriteLine("SUCCESS: migration applied and committed.");
    return 0;
}
catch (PostgresException ex)
{
    await tx.RollbackAsync();
    Console.Error.WriteLine($"FAILED (rolled back — nothing was applied)");
    Console.Error.WriteLine($"  SQLSTATE {ex.SqlState}: {ex.MessageText}");
    if (!string.IsNullOrEmpty(ex.Detail)) Console.Error.WriteLine($"  Detail: {ex.Detail}");
    if (!string.IsNullOrEmpty(ex.Hint)) Console.Error.WriteLine($"  Hint:   {ex.Hint}");
    if (ex.Position > 0) Console.Error.WriteLine($"  Position: {ex.Position}");
    return 1;
}
catch (Exception ex)
{
    await tx.RollbackAsync();
    Console.Error.WriteLine($"FAILED (rolled back — nothing was applied): {ex.Message}");
    return 1;
}
