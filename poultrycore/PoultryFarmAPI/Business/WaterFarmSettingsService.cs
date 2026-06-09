// Migration 068 — currency + display settings on the Farms row. The Farms
// table is shared with the Login API but only the Login API mutates
// Name/Type/OwnerUserId. We treat the currency columns as Farm-API-owned
// because the rest of the Water app is what reads them.

using Microsoft.Data.SqlClient;
using System.Data;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IWaterFarmSettingsService
    {
        Task<WaterFarmSettingsModel?> GetAsync(string farmId);
        Task<WaterFarmSettingsModel?> UpdateCurrencyAsync(
            string farmId, string currencyCode, string currencySymbol, bool showCurrencySymbol);
    }

    public class WaterFarmSettingsService : IWaterFarmSettingsService
    {
        private readonly string _cs;
        public WaterFarmSettingsService(string cs) => _cs = cs;

        public async Task<WaterFarmSettingsModel?> GetAsync(string farmId)
        {
            // Read through spCompany_GetCurrency rather than a direct SELECT on
            // dbo.Farms: the Farm API login only has EXECUTE on dbo SPs (Farms is
            // owned by the Login API), and a raw inline SELECT is not covered by
            // ownership chaining — it 500s with "SELECT permission denied on Farms"
            // wherever the login lacks a direct grant (see migration 089).
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spCompany_GetCurrency", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await ReadSettingsAsync(r);
        }

        public async Task<WaterFarmSettingsModel?> UpdateCurrencyAsync(
            string farmId, string currencyCode, string currencySymbol, bool showCurrencySymbol)
        {
            // The SP both updates and returns the row, so we read its result set
            // here instead of a second round-trip through GetAsync — avoiding the
            // inline Farms SELECT entirely.
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spCompany_UpdateCurrency", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@CurrencyCode",       currencyCode);
            cmd.Parameters.AddWithValue("@CurrencySymbol",     currencySymbol);
            cmd.Parameters.AddWithValue("@ShowCurrencySymbol", showCurrencySymbol);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await ReadSettingsAsync(r);
        }

        private static async Task<WaterFarmSettingsModel?> ReadSettingsAsync(SqlDataReader r)
        {
            if (!await r.ReadAsync()) return null;
            return new WaterFarmSettingsModel
            {
                FarmId             = r.GetString(0),
                Name               = r.IsDBNull(1) ? "" : r.GetString(1),
                CurrencyCode       = r.GetString(2),
                CurrencySymbol     = r.GetString(3),
                ShowCurrencySymbol = r.GetBoolean(4),
            };
        }
    }
}
