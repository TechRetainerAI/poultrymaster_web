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
            using var conn = new SqlConnection(_cs);
            // Farms has both Id (PK) and the legacy FarmId column — the
            // frontend stores the FarmId column in localStorage (see the
            // "misplaced GUID" issue), so resolve by either.
            using var cmd = new SqlCommand(@"
                SELECT TOP 1 ISNULL(FarmId, Id) AS Id, Name,
                       ISNULL(CurrencyCode,   N'GHS') AS CurrencyCode,
                       ISNULL(CurrencySymbol, N'GHC') AS CurrencySymbol,
                       ISNULL(ShowCurrencySymbol, 1)  AS ShowCurrencySymbol
                FROM   dbo.Farms WHERE FarmId = @FarmId OR Id = @FarmId", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
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

        public async Task<WaterFarmSettingsModel?> UpdateCurrencyAsync(
            string farmId, string currencyCode, string currencySymbol, bool showCurrencySymbol)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spCompany_UpdateCurrency", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@CurrencyCode",       currencyCode);
            cmd.Parameters.AddWithValue("@CurrencySymbol",     currencySymbol);
            cmd.Parameters.AddWithValue("@ShowCurrencySymbol", showCurrencySymbol);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
            return await GetAsync(farmId);
        }
    }
}
