// Projects & Contracts (migrations 482-486). One gateway for every project
// function, shaped like LivestockDb: the functions return jsonb already in
// camelCase for the web app, refusals come back as PostgresException P0001 with
// a plain-English message. Function names are fixed strings in the controller;
// every value is a bound parameter.

using Npgsql;
using NpgsqlTypes;

namespace PoultryFarmAPIWeb.Business
{
    public readonly record struct PrjArg(string Name, object? Value, NpgsqlDbType Type);

    public interface IGenericProjectDb
    {
        Task<string> JsonAsync(string function, params PrjArg[] args);
        Task<int> IntAsync(string function, params PrjArg[] args);
        Task ExecAsync(string function, params PrjArg[] args);
    }

    public class GenericProjectDb : IGenericProjectDb
    {
        private readonly string _cs;
        public GenericProjectDb(string cs) => _cs = cs;

        public static PrjArg Text(string name, string? v) => new(name, v, NpgsqlDbType.Text);
        public static PrjArg Int(string name, int? v) => new(name, v, NpgsqlDbType.Integer);
        public static PrjArg Num(string name, decimal? v) => new(name, v, NpgsqlDbType.Numeric);
        public static PrjArg Bool(string name, bool? v) => new(name, v, NpgsqlDbType.Boolean);
        public static PrjArg Date(string name, DateTime? v) => new(name, v?.Date, NpgsqlDbType.Date);
        public static PrjArg Jsonb(string name, string? json) => new(name, json, NpgsqlDbType.Jsonb);
        public static PrjArg Ints(string name, int[]? v) => new(name, v, NpgsqlDbType.Array | NpgsqlDbType.Integer);

        private static NpgsqlCommand Build(NpgsqlConnection c, string function, PrjArg[] args)
        {
            var named = string.Join(", ", args.Select((a, i) => $"{a.Name} => @a{i}"));
            var cmd = new NpgsqlCommand($"SELECT public.{function}({named})", c);
            for (var i = 0; i < args.Length; i++)
                cmd.Parameters.Add(new NpgsqlParameter($"a{i}", args[i].Type) { Value = args[i].Value ?? DBNull.Value });
            return cmd;
        }

        public async Task<string> JsonAsync(string function, params PrjArg[] args)
        {
            await using var c = new NpgsqlConnection(_cs);
            await c.OpenAsync();
            await using var cmd = Build(c, function, args);
            var result = await cmd.ExecuteScalarAsync();
            return result is null or DBNull ? "null" : result.ToString()!;
        }

        public async Task<int> IntAsync(string function, params PrjArg[] args)
        {
            await using var c = new NpgsqlConnection(_cs);
            await c.OpenAsync();
            await using var cmd = Build(c, function, args);
            var result = await cmd.ExecuteScalarAsync();
            return result is null or DBNull ? 0 : Convert.ToInt32(result);
        }

        public async Task ExecAsync(string function, params PrjArg[] args)
        {
            await using var c = new NpgsqlConnection(_cs);
            await c.OpenAsync();
            await using var cmd = Build(c, function, args);
            await cmd.ExecuteNonQueryAsync();
        }
    }

    /// <summary>
    /// The "project" query value used by report filters: "" / "all" = whole
    /// company, "general" = not on any project, "12" or "12,15" = those projects.
    /// Returns (null, null) for anything else.
    /// </summary>
    public static class GenericProjectScope
    {
        public static (string? Scope, int[]? Ids) Parse(string? value)
        {
            if (string.IsNullOrWhiteSpace(value) || value.Equals("all", StringComparison.OrdinalIgnoreCase))
                return ("all", null);
            if (value.Equals("general", StringComparison.OrdinalIgnoreCase))
                return ("general", null);
            var parts = value.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            var ids = new List<int>();
            foreach (var p in parts)
            {
                if (!int.TryParse(p, out var id) || id <= 0) return (null, null);
                ids.Add(id);
            }
            return ids.Count == 0 ? (null, null) : ("projects", ids.Distinct().ToArray());
        }
    }
}
