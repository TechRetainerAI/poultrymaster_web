using Npgsql;

// Water days of supply (migration 464). Same rows and settings as Poultry (337) --
// StockSupplyRow / StockSupplySettings are shared, so the JSON (and the web page
// helpers) are identical; the item id travels in PoultryRawMaterialItemId.
namespace PoultryFarmAPIWeb.Business
{
    public interface IWaterStockSupplyService
    {
        Task<IReadOnlyList<StockSupplyRow>> GetAsync(string farmId, int? lookbackDays);
        Task<StockSupplySettings> GetSettingsAsync(string farmId);
        Task SetSettingsAsync(StockSupplySettings s, string? updatedBy);
    }

    public class WaterStockSupplyService : IWaterStockSupplyService
    {
        private readonly string _cs;
        public WaterStockSupplyService(string cs) => _cs = cs;

        public async Task<IReadOnlyList<StockSupplyRow>> GetAsync(string farmId, int? lookbackDays)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spwaterstocksupply(p_farmid => @FarmId::text, p_lookbackdays => @Days::int)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Days", lookbackDays.HasValue ? lookbackDays.Value : DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<StockSupplyRow>();
            while (await r.ReadAsync())
            {
                list.Add(new StockSupplyRow
                {
                    PoultryRawMaterialItemId = r.GetInt32(r.GetOrdinal("waterrawmaterialitemid")),
                    ItemName = Str(r, "itemname") ?? string.Empty,
                    Category = Str(r, "category"),
                    UnitOfMeasure = Str(r, "unitofmeasure"),
                    PurchaseUnitOfMeasure = Str(r, "purchaseunitofmeasure"),
                    UnitsPerPurchaseUnit = Dec(r, "unitsperpurchaseunit"),
                    CurrentQuantity = Dec(r, "currentquantity") ?? 0,
                    MinimumStockAlert = Dec(r, "minimumstockalert"),
                    BelowReorder = r.GetBoolean(r.GetOrdinal("belowreorder")),
                    BusinessDate = r.GetDateTime(r.GetOrdinal("businessdate")),
                    WindowFrom = r.GetDateTime(r.GetOrdinal("windowfrom")),
                    WindowTo = r.GetDateTime(r.GetOrdinal("windowto")),
                    LookbackDays = r.GetInt32(r.GetOrdinal("lookbackdays")),
                    WindowDays = r.GetInt32(r.GetOrdinal("windowdays")),
                    ConsumedQty = Dec(r, "consumedqty") ?? 0,
                    UsageDays = r.GetInt32(r.GetOrdinal("usagedays")),
                    AvgDailyUsage = Dec(r, "avgdailyusage"),
                    DaysOfSupply = Dec(r, "daysofsupply"),
                    EstimatedStockout = r.IsDBNull(r.GetOrdinal("estimatedstockout")) ? null : r.GetDateTime(r.GetOrdinal("estimatedstockout")),
                    Status = Str(r, "status") ?? "NoRecentUsage",
                    SeverityRank = r.GetInt32(r.GetOrdinal("severityrank")),
                    CriticalDays = Dec(r, "criticaldays") ?? 3,
                    WarningDays = Dec(r, "warningdays") ?? 7,
                    ExpectedDailyUsage = Dec(r, "expecteddailyusage"),
                });
            }
            return list;
        }

        public async Task<StockSupplySettings> GetSettingsAsync(string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwaterstocksupplysettings_get(p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            if (!await r.ReadAsync()) return new StockSupplySettings { FarmId = farmId };
            return new StockSupplySettings
            {
                FarmId = farmId,
                LookbackDays = r.GetInt32(r.GetOrdinal("lookbackdays")),
                CriticalDays = r.GetDecimal(r.GetOrdinal("criticaldays")),
                WarningDays = r.GetDecimal(r.GetOrdinal("warningdays")),
                MinHistoryDays = r.GetInt32(r.GetOrdinal("minhistorydays")),
                IsCustomised = r.GetBoolean(r.GetOrdinal("iscustomised")),
            };
        }

        public async Task SetSettingsAsync(StockSupplySettings s, string? updatedBy)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT spwaterstocksupplysettings_set(p_farmid => @FarmId::text, p_lookbackdays => @Look::int, "
                + "p_criticaldays => @Crit::numeric, p_warningdays => @Warn::numeric, p_minhistorydays => @Min::int, "
                + "p_updatedby => @By::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", s.FarmId);
            cmd.Parameters.AddWithValue("@Look", s.LookbackDays);
            cmd.Parameters.AddWithValue("@Crit", s.CriticalDays);
            cmd.Parameters.AddWithValue("@Warn", s.WarningDays);
            cmd.Parameters.AddWithValue("@Min", s.MinHistoryDays);
            cmd.Parameters.AddWithValue("@By", (object?)updatedBy ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static string? Str(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? null : r.GetValue(i).ToString();
        }

        private static decimal? Dec(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? null : Convert.ToDecimal(r.GetValue(i));
        }
    }
}
