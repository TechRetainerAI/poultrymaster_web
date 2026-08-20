using System.Collections.Concurrent;
using System.Linq;
using Npgsql;

namespace PoultryFarmAPIWeb.Business
{
    // Builds the PostgreSQL invocation text for a converted stored procedure at
    // runtime, for the handful of call sites that assemble their parameter list
    // dynamically (conditional adds, or a helper that takes the procedure name
    // as a string).
    //
    //   "spWaterX_SetStatus" + (@FarmId, @Status)
    //     -> "SELECT * FROM spwaterx_setstatus(p_farmid => @FarmId::text, p_status => @Status::text)"
    //
    // The casts are not cosmetic. Without them Npgsql infers the PostgreSQL type
    // from the .NET value — DateTime becomes timestamp, and a null string becomes
    // "unknown" — so a function declaring (text, text, date, date) is not found
    // and the call fails with 42883 "function ... does not exist". The real
    // argument types are read from pg_proc once per procedure and cached.
    internal static class PgCallText
    {
        private static readonly ConcurrentDictionary<string, Dictionary<string, string>> Cache = new();

        private static readonly Dictionary<string, string> CastFor = new(StringComparer.OrdinalIgnoreCase)
        {
            ["text"] = "::text",
            ["character varying"] = "::text",
            ["integer"] = "::int",
            ["bigint"] = "::bigint",
            ["smallint"] = "::smallint",
            ["numeric"] = "::numeric",
            ["boolean"] = "::boolean",
            ["timestamp without time zone"] = "::timestamp",
            ["timestamp with time zone"] = "::timestamptz",
            ["date"] = "::date",
            ["time without time zone"] = "::time",
            ["uuid"] = "::uuid",
            ["double precision"] = "::float8",
            ["real"] = "::real",
            ["jsonb"] = "::jsonb",
            ["json"] = "::json",
            ["bytea"] = "::bytea",
        };

        // Requires an OPEN connection on the command — the signature is read from
        // the catalog on first use of each procedure.
        public static async Task<string> ForAsync(string procName, NpgsqlCommand cmd)
        {
            var fn = procName.ToLowerInvariant();
            if (!Cache.TryGetValue(fn, out var argTypes))
            {
                argTypes = await LoadSignatureAsync(fn, cmd.Connection!);
                Cache[fn] = argTypes;
            }

            var args = cmd.Parameters
                .Cast<NpgsqlParameter>()
                .Select(p =>
                {
                    var bare = p.ParameterName.TrimStart('@');
                    var arg = "p_" + bare.ToLowerInvariant();
                    var cast = argTypes.TryGetValue(arg, out var t) && CastFor.TryGetValue(t, out var c) ? c : "";
                    return $"{arg} => @{bare}{cast}";
                });

            return $"SELECT * FROM {fn}({string.Join(", ", args)})";
        }

        private static async Task<Dictionary<string, string>> LoadSignatureAsync(string fn, NpgsqlConnection conn)
        {
            var map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            await using var cmd = new NpgsqlCommand(
                @"SELECT a.name, a.typeoid::bigint
                  FROM pg_proc p
                  JOIN pg_namespace n ON n.oid = p.pronamespace
                  CROSS JOIN LATERAL unnest(
                      COALESCE(p.proargnames, ARRAY[]::text[]),
                      COALESCE(p.proallargtypes, p.proargtypes::oid[])
                  ) WITH ORDINALITY AS a(name, typeoid, ord)
                  WHERE n.nspname = 'public' AND p.proname = @fn", conn);
            cmd.Parameters.AddWithValue("@fn", fn);

            // resolve type oids to names in the same pass
            await using var reader = await cmd.ExecuteReaderAsync();
            var raw = new List<(string Name, uint Oid)>();
            while (await reader.ReadAsync())
            {
                if (reader.IsDBNull(0)) continue;
                raw.Add((reader.GetString(0), (uint)reader.GetInt64(1)));
            }
            await reader.CloseAsync();

            if (raw.Count == 0) return map;

            await using var typeCmd = new NpgsqlCommand(
                "SELECT oid::bigint, format_type(oid, NULL) FROM pg_type WHERE oid = ANY(@oids)", conn);
            typeCmd.Parameters.AddWithValue("@oids", raw.Select(r => (long)r.Oid).Distinct().ToArray());
            var names = new Dictionary<long, string>();
            await using (var tr = await typeCmd.ExecuteReaderAsync())
            {
                while (await tr.ReadAsync()) names[tr.GetInt64(0)] = tr.GetString(1);
            }

            foreach (var (name, oid) in raw)
            {
                if (names.TryGetValue((long)oid, out var tn))
                    map[name] = tn;
            }
            return map;
        }
    }
}
