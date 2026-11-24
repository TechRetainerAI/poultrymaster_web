// Projects & Contracts (migrations 482-486): saving a transaction together with
// its project split.
//
// The existing Generic services keep calling their own functions unchanged.
// When the request carries a "projects" value, the call is wrapped so the save
// and the project split run as ONE SQL statement -- one implicit transaction --
// and either both happen or neither does:
//
//   SELECT spgenericproject_attach(@PrjFarm, 'Sale', x.id, @PrjJson, @PrjBy)
//   FROM (SELECT spgenericsale_insert(...) AS id) x
//
// A request without "projects" runs exactly the SQL it ran before.

using System.Text.Json;
using Npgsql;
using NpgsqlTypes;

namespace PoultryFarmAPIWeb.Business
{
    public static class GenericProjectAttach
    {
        /// <summary>True when the request asked for a project split.</summary>
        public static bool Has(JsonElement? projects) =>
            projects.HasValue && projects.Value.ValueKind is JsonValueKind.Object;

        /// <summary>
        /// Wrap a function returning the new document's id.
        /// <paramref name="call"/> is the bare call, e.g. "spgenericsale_insert(p_farmid => @FarmId::text, ...)".
        /// </summary>
        public static string WrapInsert(string call, string documentType) =>
            $"SELECT spgenericproject_attach(@PrjFarm::text, '{documentType}', x.id, @PrjJson::jsonb, @PrjBy::text) " +
            $"FROM (SELECT {call} AS id) x";

        /// <summary>
        /// Wrap a void update of a known document. Runs the update first, then
        /// re-attaches (also carries line projects over when an edit re-created
        /// the lines and no new split was sent).
        /// </summary>
        public static string WrapUpdate(string call, string documentType) =>
            $"WITH u AS (SELECT {call}) " +
            $"SELECT spgenericproject_attach(@PrjFarm::text, '{documentType}', @PrjDocId::int, @PrjJson::jsonb, @PrjBy::text) FROM u";

        /// <summary>Strip a leading "SELECT * FROM " / "SELECT " so a command text becomes a bare call.</summary>
        public static string Bare(string commandText)
        {
            var t = commandText.Trim();
            foreach (var prefix in new[] { "SELECT * FROM ", "SELECT " })
                if (t.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) return t[prefix.Length..].Trim();
            return t;
        }

        public static void AddParams(NpgsqlCommand cmd, string farmId, JsonElement? projects, string? by, int? documentId = null)
        {
            cmd.Parameters.Add(new NpgsqlParameter("@PrjFarm", NpgsqlDbType.Text) { Value = farmId });
            cmd.Parameters.Add(new NpgsqlParameter("@PrjJson", NpgsqlDbType.Jsonb)
            {
                Value = Has(projects) ? projects!.Value.GetRawText() : DBNull.Value,
            });
            cmd.Parameters.Add(new NpgsqlParameter("@PrjBy", NpgsqlDbType.Text) { Value = (object?)by ?? DBNull.Value });
            if (documentId.HasValue)
                cmd.Parameters.Add(new NpgsqlParameter("@PrjDocId", NpgsqlDbType.Integer) { Value = documentId.Value });
        }
    }
}
