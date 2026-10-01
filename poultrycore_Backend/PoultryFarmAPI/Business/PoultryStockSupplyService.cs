// Days of supply (migration 337): how long each raw material will last at the
// rate it has actually been used. Every rule -- what counts as consumption, the
// window, the thresholds, the states -- lives in sppoultrystocksupply and is
// covered by the migration's self-test. This file sends parameters and maps rows.

using Npgsql;

namespace PoultryFarmAPIWeb.Business
{
    public class StockSupplyRow
    {
        public int PoultryRawMaterialItemId { get; set; }
        public string ItemName { get; set; } = string.Empty;
        public string? Category { get; set; }
        /// <summary>Unit stock and usage are measured in (kg, litre...).</summary>
        public string? UnitOfMeasure { get; set; }
        public string? PurchaseUnitOfMeasure { get; set; }
        /// <summary>Production units per purchase unit on the latest lot (e.g. 50 kg per bag).</summary>
        public decimal? UnitsPerPurchaseUnit { get; set; }
        public decimal CurrentQuantity { get; set; }
        public decimal? MinimumStockAlert { get; set; }
        public bool BelowReorder { get; set; }
        public DateTime BusinessDate { get; set; }
        public DateTime WindowFrom { get; set; }
        public DateTime WindowTo { get; set; }
        public int LookbackDays { get; set; }
        /// <summary>Days actually averaged over (fewer than LookbackDays for a new product).</summary>
        public int WindowDays { get; set; }
        public decimal ConsumedQty { get; set; }
        public int UsageDays { get; set; }
        public decimal? AvgDailyUsage { get; set; }
        public decimal? DaysOfSupply { get; set; }
        /// <summary>An estimate: company today + whole days of supply.</summary>
        public DateTime? EstimatedStockout { get; set; }
        /// <summary>Negative | OutOfStock | Critical | Warning | Healthy | InsufficientHistory | NoRecentUsage</summary>
        public string Status { get; set; } = "NoRecentUsage";
        public int SeverityRank { get; set; }
        public decimal CriticalDays { get; set; }
        public decimal WarningDays { get; set; }
        /// <summary>Birds x the saved feed rate (335); null when no rate is saved.</summary>
        public decimal? ExpectedDailyUsage { get; set; }
    }

    public class StockSupplySettings
    {
        public string FarmId { get; set; } = string.Empty;
        public int LookbackDays { get; set; } = 7;
        public decimal CriticalDays { get; set; } = 3;
        public decimal WarningDays { get; set; } = 7;
        public int MinHistoryDays { get; set; } = 3;
        public bool IsCustomised { get; set; }
    }

    public interface IPoultryStockSupplyService
    {
        Task<IReadOnlyList<StockSupplyRow>> GetAsync(string farmId, int? lookbackDays);
        Task<StockSupplySettings> GetSettingsAsync(string farmId);
        Task SetSettingsAsync(StockSupplySettings s, string? updatedBy);
    }

    public class PoultryStockSupplyService : IPoultryStockSupplyService
    {
        private readonly string _cs;
        public PoultryStockSupplyService(string cs) => _cs = cs;

        public async Task<IReadOnlyList<StockSupplyRow>> GetAsync(string farmId, int? lookbackDays)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultrystocksupply(p_farmid => @FarmId::text, p_lookbackdays => @Days::int)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Days", lookbackDays.HasValue ? lookbackDays.Value : DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<StockSupplyRow>();
            while (await r.ReadAsync())
            {
                list.Add(new StockSupplyRow
                {
                    PoultryRawMaterialItemId = r.GetInt32(r.GetOrdinal("poultryrawmaterialitemid")),
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
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrystocksupplysettings_get(p_farmid => @FarmId::text)", c);
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
                "SELECT sppoultrystocksupplysettings_set(p_farmid => @FarmId::text, p_lookbackdays => @Look::int, "
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
