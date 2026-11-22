// Livestock (migration 458+). One gateway for every livestock function.
//
// The livestock functions return jsonb already shaped for the web app
// (camelCase keys), so there is no model class per screen and no row mapping:
// the JSON goes from the database to the browser as it is. Business rules live
// in the functions; refusals come back as PostgresException P0001 with a
// plain-English message, which LivestockControllerBase turns into a 400.
//
// Function names are fixed strings in the controllers, never from a request,
// and every value is a bound parameter.

using Npgsql;
using NpgsqlTypes;

namespace PoultryFarmAPIWeb.Business
{
    /// <summary>A named argument for a livestock function: p_name => value::type.</summary>
    public readonly record struct LsArg(string Name, object? Value, NpgsqlDbType Type);

    public interface ILivestockDb
    {
        /// <summary>Calls a function returning jsonb; returns the JSON text.</summary>
        Task<string> JsonAsync(string function, params LsArg[] args);
        /// <summary>Calls a function returning an integer id.</summary>
        Task<int> IntAsync(string function, params LsArg[] args);
        /// <summary>Calls a function returning void.</summary>
        Task ExecAsync(string function, params LsArg[] args);
    }

    public class LivestockDb : ILivestockDb
    {
        private readonly string _cs;
        public LivestockDb(string cs) => _cs = cs;

        public static LsArg Text(string name, string? v) => new(name, v, NpgsqlDbType.Text);
        public static LsArg Int(string name, int? v) => new(name, v, NpgsqlDbType.Integer);
        public static LsArg Date(string name, DateTime? v) => new(name, v?.Date, NpgsqlDbType.Date);
        public static LsArg Bool(string name, bool? v) => new(name, v, NpgsqlDbType.Boolean);
        public static LsArg Jsonb(string name, string? json) => new(name, json, NpgsqlDbType.Jsonb);
        public static LsArg TextArray(string name, string[]? v) => new(name, v, NpgsqlDbType.Array | NpgsqlDbType.Text);

        private static NpgsqlCommand Build(NpgsqlConnection c, string function, LsArg[] args)
        {
            var named = string.Join(", ", args.Select((a, i) => $"{a.Name} => @a{i}"));
            var cmd = new NpgsqlCommand($"SELECT public.{function}({named})", c);
            for (var i = 0; i < args.Length; i++)
                cmd.Parameters.Add(new NpgsqlParameter($"a{i}", args[i].Type) { Value = args[i].Value ?? DBNull.Value });
            return cmd;
        }

        public async Task<string> JsonAsync(string function, params LsArg[] args)
        {
            await using var c = new NpgsqlConnection(_cs);
            await c.OpenAsync();
            await using var cmd = Build(c, function, args);
            var result = await cmd.ExecuteScalarAsync();
            return result is null or DBNull ? "null" : result.ToString()!;
        }

        public async Task<int> IntAsync(string function, params LsArg[] args)
        {
            await using var c = new NpgsqlConnection(_cs);
            await c.OpenAsync();
            await using var cmd = Build(c, function, args);
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task ExecAsync(string function, params LsArg[] args)
        {
            await using var c = new NpgsqlConnection(_cs);
            await c.OpenAsync();
            await using var cmd = Build(c, function, args);
            await cmd.ExecuteNonQueryAsync();
        }
    }
}
