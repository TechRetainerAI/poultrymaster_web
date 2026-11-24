using Npgsql;
using NpgsqlTypes;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business;

public partial class GenericReportService
{
    /// <summary>
    /// The Generic P&amp;L entries. Since migration 484 the SQL lives in the
    /// database (fngenericpnl_entries, reached through
    /// spgenericproject_pnlentries) so the company P&amp;L and every project
    /// P&amp;L come from one definition. It was moved unchanged and checked
    /// row-for-row against the previous inline SQL on every Generic company.
    ///
    /// <paramref name="scope"/>: "all" (the whole company, the default and the
    /// only behaviour before 484), "general" (only what is not assigned to any
    /// project) or "projects" (the projects in <paramref name="projectIds"/>).
    /// Use the same cost-of-goods rule throughout: the recorded sale-out cost,
    /// else the item's historical unit cost; never today's cost.
    /// </summary>
    public async Task<List<GenericProfitLossEntry>> GetProfitLossEntriesAsync(
        string farmId, DateOnly from, DateOnly to, CancellationToken cancellationToken)
        => await GetProfitLossEntriesAsync(farmId, from, to, "all", null, cancellationToken);

    public async Task<List<GenericProfitLossEntry>> GetProfitLossEntriesAsync(
        string farmId, DateOnly from, DateOnly to, string scope, int[]? projectIds, CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT section, line, day, ref, coalesce(description, ''), amount
            FROM spgenericproject_pnlentries(@farm, @scope, @projects, @start, @finish)
            WHERE amount <> 0
            ORDER BY day DESC, ref, section, line
            """;
        using var connection = new NpgsqlConnection(_connectionString);
        using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("farm", NpgsqlDbType.Text, farmId);
        command.Parameters.AddWithValue("scope", NpgsqlDbType.Text, scope);
        command.Parameters.Add(new NpgsqlParameter("projects", NpgsqlDbType.Array | NpgsqlDbType.Integer)
        {
            Value = (object?)projectIds ?? DBNull.Value,
        });
        command.Parameters.AddWithValue("start", NpgsqlDbType.Date, from);
        command.Parameters.AddWithValue("finish", NpgsqlDbType.Date, to);

        await connection.OpenAsync(cancellationToken);
        using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var entries = new List<GenericProfitLossEntry>();
        while (await reader.ReadAsync(cancellationToken))
        {
            entries.Add(new GenericProfitLossEntry(reader.GetString(0), reader.GetString(1),
                reader.GetFieldValue<DateOnly>(2), reader.GetString(3), reader.GetString(4), reader.GetDecimal(5)));
        }
        return entries;
    }
}
