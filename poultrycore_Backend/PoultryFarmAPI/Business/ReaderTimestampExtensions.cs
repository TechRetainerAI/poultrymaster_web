// A tolerant read for a row's creation timestamp.
//
// Migration 301 added `createdat` to eight list readers so the frontend can show
// a time beside the date on every table. The services below read it through this
// helper rather than `reader.GetDateTime(reader.GetOrdinal("CreatedAt"))`,
// because GetOrdinal THROWS when the column is absent.
//
// That matters during a rollout: the API and the database are deployed
// separately, so there is a window where new code runs against a database that
// has not had 301 applied yet. A throw there would take out the whole page --
// egg production, flocks, houses, inventory -- to avoid showing a time. Missing
// the time is the right failure; the table renders with the date alone, exactly
// as it did before.

using Npgsql;

namespace PoultryFarmAPIWeb.Business
{
    public static class ReaderTimestampExtensions
    {
        /// <summary>
        /// The named timestamp column, or null when the column is absent or NULL.
        /// Never throws for a missing column.
        /// </summary>
        public static DateTime? OptionalDateTime(this NpgsqlDataReader r, string column)
        {
            for (int i = 0; i < r.FieldCount; i++)
            {
                if (!string.Equals(r.GetName(i), column, StringComparison.OrdinalIgnoreCase))
                    continue;
                return r.IsDBNull(i) ? null : r.GetDateTime(i);
            }
            return null;
        }
    }
}
