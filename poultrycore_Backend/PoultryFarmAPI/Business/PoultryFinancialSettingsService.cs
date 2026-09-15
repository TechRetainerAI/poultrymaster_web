// Poultry financial settings (migration 261): when inventory costs reach the P&L.
//
// Two independent choices -- feed and medication -- and a forward-dated
// activation. Everything that decides what a setting MEANS lives in the SPs;
// this file sends parameters and maps rows.
//
// The read never writes. A farm that has never opened the page has no row, and
// reads back as today's behaviour with IsConfigured = false, so merely looking
// at the settings does not create rows for every company in the database.

using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IPoultryFinancialSettingsService
    {
        Task<PoultryFinancialSettingsModel> GetAsync(string farmId);

        /// <summary>
        /// Writes both methods. The returned model carries the PREVIOUS values
        /// so the caller can audit the change from one round trip.
        /// </summary>
        Task<PoultryFinancialSettingsModel> UpsertAsync(PoultryFinancialSettingsUpdateRequest r);
    }

    public class PoultryFinancialSettingsService : IPoultryFinancialSettingsService
    {
        private readonly string _cs;
        public PoultryFinancialSettingsService(string cs) => _cs = cs;

        private static string? Str(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? null : r.GetString(i);
        }

        private static DateTime? DateN(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? null : r.GetDateTime(i);
        }

        private static bool Has(NpgsqlDataReader r, string name)
        {
            for (int i = 0; i < r.FieldCount; i++)
                if (string.Equals(r.GetName(i), name, StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }

        private static PoultryFinancialSettingsModel Map(NpgsqlDataReader r) => new()
        {
            FarmId = r.GetString(r.GetOrdinal("FarmId")),
            FeedCostRecognitionMethod = r.GetString(r.GetOrdinal("FeedCostRecognitionMethod")),
            MedicationCostRecognitionMethod = r.GetString(r.GetOrdinal("MedicationCostRecognitionMethod")),
            EffectiveFromDate = DateN(r, "EffectiveFromDate"),
            IsConfigured = r.GetBoolean(r.GetOrdinal("IsConfigured")),
            CreatedBy = Str(r, "CreatedBy"),
            CreatedAt = DateN(r, "CreatedAt"),
            UpdatedBy = Str(r, "UpdatedBy"),
            UpdatedAt = DateN(r, "UpdatedAt"),
            // Only the upsert returns these two.
            PreviousFeedMethod = Has(r, "PreviousFeedMethod") ? Str(r, "PreviousFeedMethod") : null,
            PreviousMedicationMethod = Has(r, "PreviousMedicationMethod") ? Str(r, "PreviousMedicationMethod") : null,
        };

        public async Task<PoultryFinancialSettingsModel> GetAsync(string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryfinancialsettings_get(p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            // The SP always returns exactly one row, defaults included, so an
            // empty reader would mean something is wrong rather than "no settings".
            return await r.ReadAsync()
                ? Map(r)
                : new PoultryFinancialSettingsModel { FarmId = farmId };
        }

        public async Task<PoultryFinancialSettingsModel> UpsertAsync(PoultryFinancialSettingsUpdateRequest q)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryfinancialsettings_upsert("
                + "p_farmid => @FarmId::text,"
                + "p_feedmethod => @Feed::text,"
                + "p_medicationmethod => @Medication::text,"
                + "p_effectivefromdate => @EffectiveFrom::date,"
                + "p_updatedby => @UpdatedBy::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", q.FarmId);
            cmd.Parameters.AddWithValue("@Feed", q.FeedCostRecognitionMethod);
            cmd.Parameters.AddWithValue("@Medication", q.MedicationCostRecognitionMethod);
            cmd.Parameters.AddWithValue("@EffectiveFrom",
                q.EffectiveFromDate.HasValue ? q.EffectiveFromDate.Value.Date : (object)DBNull.Value);
            cmd.Parameters.AddWithValue("@UpdatedBy", (object?)q.UpdatedBy ?? DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync()
                ? Map(r)
                : new PoultryFinancialSettingsModel { FarmId = q.FarmId };
        }
    }
}
