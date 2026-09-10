// Water financial settings (migration 274): when inventory costs reach the P&L.
//
// Two independent choices -- packaging and treatment -- and a forward-dated
// activation. Everything that decides what a setting MEANS lives in the SPs;
// this file sends parameters and maps rows.
//
// The read never writes. A company that has never opened the page has no row,
// and reads back as today's behaviour with IsConfigured = false, so merely
// looking at the settings does not create rows for every company in the
// database.
//
// WHERE THIS HAS MORE SURFACE THAN THE POULTRY TWIN
// -------------------------------------------------
// 261 folded the item override into sppoultryrawmaterialitem_update and the
// resolved columns into _getall, because it had those Postgres bodies to copy
// from. Water's are not in the repo, so 274 left them alone and added two small
// functions instead. That means this service carries two extra members the
// poultry one does not need:
//
//   GetItemsAsync        the resolved view, read separately from the item list
//   SetItemOverrideAsync writes one item's override without touching _update
//
// When the live item bodies become available and 274's section 9 is folded in,
// both can be retired and the frontend can read the override off the item list.

using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IWaterFinancialSettingsService
    {
        Task<WaterFinancialSettingsModel> GetAsync(string farmId);

        /// <summary>
        /// Writes both methods. The returned model carries the PREVIOUS values
        /// so the caller can audit the change from one round trip.
        /// </summary>
        Task<WaterFinancialSettingsModel> UpsertAsync(WaterFinancialSettingsUpdateRequest r);

        /// <summary>Every item and how its cost is treated, resolved server-side.</summary>
        Task<List<WaterItemCostRecognitionModel>> GetItemsAsync(string farmId);

        /// <summary>
        /// Sets or clears one item's override. Returns the item's resolution
        /// afterwards, so the caller does not have to re-read the list to show
        /// what changed.
        /// </summary>
        Task<WaterItemCostRecognitionModel?> SetItemOverrideAsync(
            int itemId, WaterItemCostRecognitionUpdateRequest r);
    }

    public class WaterFinancialSettingsService : IWaterFinancialSettingsService
    {
        private readonly string _cs;
        public WaterFinancialSettingsService(string cs) => _cs = cs;

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

        private static WaterFinancialSettingsModel Map(NpgsqlDataReader r) => new()
        {
            FarmId = r.GetString(r.GetOrdinal("FarmId")),
            PackagingCostRecognitionMethod = r.GetString(r.GetOrdinal("PackagingCostRecognitionMethod")),
            TreatmentCostRecognitionMethod = r.GetString(r.GetOrdinal("TreatmentCostRecognitionMethod")),
            EffectiveFromDate = DateN(r, "EffectiveFromDate"),
            IsConfigured = r.GetBoolean(r.GetOrdinal("IsConfigured")),
            DeferralAvailable = r.GetBoolean(r.GetOrdinal("DeferralAvailable")),
            CreatedBy = Str(r, "CreatedBy"),
            CreatedAt = DateN(r, "CreatedAt"),
            UpdatedBy = Str(r, "UpdatedBy"),
            UpdatedAt = DateN(r, "UpdatedAt"),
            // Only the upsert returns these two.
            PreviousPackagingMethod = Has(r, "PreviousPackagingMethod") ? Str(r, "PreviousPackagingMethod") : null,
            PreviousTreatmentMethod = Has(r, "PreviousTreatmentMethod") ? Str(r, "PreviousTreatmentMethod") : null,
        };

        public async Task<WaterFinancialSettingsModel> GetAsync(string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spwaterfinancialsettings_get(p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            // The SP always returns exactly one row, defaults included, so an
            // empty reader would mean something is wrong rather than "no settings".
            return await r.ReadAsync()
                ? Map(r)
                : new WaterFinancialSettingsModel { FarmId = farmId };
        }

        public async Task<WaterFinancialSettingsModel> UpsertAsync(WaterFinancialSettingsUpdateRequest q)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spwaterfinancialsettings_upsert("
                + "p_farmid => @FarmId::text,"
                + "p_packagingmethod => @Packaging::text,"
                + "p_treatmentmethod => @Treatment::text,"
                + "p_effectivefromdate => @EffectiveFrom::date,"
                + "p_updatedby => @UpdatedBy::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", q.FarmId);
            cmd.Parameters.AddWithValue("@Packaging", q.PackagingCostRecognitionMethod);
            cmd.Parameters.AddWithValue("@Treatment", q.TreatmentCostRecognitionMethod);
            cmd.Parameters.AddWithValue("@EffectiveFrom",
                q.EffectiveFromDate.HasValue ? q.EffectiveFromDate.Value.Date : (object)DBNull.Value);
            cmd.Parameters.AddWithValue("@UpdatedBy", (object?)q.UpdatedBy ?? DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync()
                ? Map(r)
                : new WaterFinancialSettingsModel { FarmId = q.FarmId };
        }

        private static WaterItemCostRecognitionModel MapItem(NpgsqlDataReader r) => new()
        {
            WaterRawMaterialItemId = r.GetInt32(r.GetOrdinal("WaterRawMaterialItemId")),
            ItemName = Str(r, "ItemName"),
            Category = Str(r, "Category"),
            IsActive = !r.IsDBNull(r.GetOrdinal("IsActive")) && r.GetBoolean(r.GetOrdinal("IsActive")),
            CostRecognitionOverride = Str(r, "CostRecognitionOverride"),
            EffectiveCostRecognitionMethod =
                Str(r, "EffectiveCostRecognitionMethod") ?? CostRecognitionMethod.ExpenseWhenPurchased,
            CostRecognitionSource = Str(r, "CostRecognitionSource") ?? Models.CostRecognitionSource.FarmDefault,
            CostRecognitionCategoryGroup =
                Str(r, "CostRecognitionCategoryGroup") ?? WaterCostRecognitionGroup.Unconfigured,
            // Only the list read returns this; the setter's result does not.
            FarmDefaultMethod = Has(r, "FarmDefaultMethod") ? Str(r, "FarmDefaultMethod") : null,
        };

        public async Task<List<WaterItemCostRecognitionModel>> GetItemsAsync(string farmId)
        {
            var list = new List<WaterItemCostRecognitionModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spwatercostrecognition_items(p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(MapItem(r));
            return list;
        }

        public async Task<WaterItemCostRecognitionModel?> SetItemOverrideAsync(
            int itemId, WaterItemCostRecognitionUpdateRequest q)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spwaterrawmaterialitem_setcostrecognition("
                + "p_waterrawmaterialitemid => @ItemId::integer,"
                + "p_farmid => @FarmId::text,"
                + "p_costrecognitionoverride => @Override::text,"
                + "p_updatedby => @UpdatedBy::text)", c);
            cmd.Parameters.AddWithValue("@ItemId", itemId);
            cmd.Parameters.AddWithValue("@FarmId", q.FarmId);
            // Null and "USE_DEFAULT" both mean "no override"; the SP accepts
            // either, and normalising here as well keeps the two agreeing.
            cmd.Parameters.AddWithValue("@Override",
                (object?)CostRecognitionMethod.NormaliseOverride(q.CostRecognitionOverride) ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@UpdatedBy", (object?)q.UpdatedBy ?? DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? MapItem(r) : null;
        }
    }
}
