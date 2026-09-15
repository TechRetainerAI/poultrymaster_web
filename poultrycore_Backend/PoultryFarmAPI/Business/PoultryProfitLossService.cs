// The structured Poultry Profit & Loss (migration 272).
//
// Reads only, and thin. Every classification decision -- what counts as revenue,
// which line a cost lands on, what is excluded from profit entirely -- lives in
// the SQL functions, so the report, its drilldowns and the exports cannot each
// grow their own idea of what an expense is.
//
// The summary and the line list come back in ONE round trip. A card that
// disagreed with the statement under it, because a bill landed between two
// queries, would be worse than a slower page.

using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IPoultryProfitLossService
    {
        Task<PoultryProfitLossReport> GetAsync(string farmId, DateTime start, DateTime end);
        Task<List<PoultryProfitLossExpenseRow>> GetExpenseDetailAsync(string farmId, DateTime start, DateTime end, string? lineKey);
        Task<List<PoultryProfitLossRevenueRow>> GetRevenueDetailAsync(string farmId, DateTime start, DateTime end, string? lineKey);
        Task<List<PoultryProfitLossInventoryRow>> GetInventoryDetailAsync(string farmId, DateTime start, DateTime end, string lineKey);
        Task<List<PoultryAssetDepreciationModel>> GetDepreciationDetailAsync(string farmId, DateTime start, DateTime end);
        Task<List<PoultryProfitLossFinancingRow>> GetFinancingDetailAsync(string farmId, DateTime start, DateTime end, string? lineKey);
        Task<List<PoultryProfitLossCapitalRow>> GetCapitalDetailAsync(string farmId, DateTime start, DateTime end);
    }

    public class PoultryProfitLossService : IPoultryProfitLossService
    {
        private readonly string _cs;
        public PoultryProfitLossService(string cs) => _cs = cs;

        private static string? StrN(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? null : r.GetString(i); }
        private static string Str(NpgsqlDataReader r, string c) => StrN(r, c) ?? string.Empty;
        private static int Int(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? 0 : r.GetInt32(i); }
        private static int? IntN(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? (int?)null : r.GetInt32(i); }
        private static decimal Dec(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? 0m : r.GetDecimal(i); }
        private static decimal? DecN(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? (decimal?)null : r.GetDecimal(i); }
        private static DateTime Date(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? default : r.GetDateTime(i); }
        private static bool Bool(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return !r.IsDBNull(i) && r.GetBoolean(i); }

        private static void Range(NpgsqlCommand cmd, string farmId, DateTime start, DateTime end)
        {
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Start", start.Date);
            cmd.Parameters.AddWithValue("@End", end.Date);
        }

        public async Task<PoultryProfitLossReport> GetAsync(string farmId, DateTime start, DateTime end)
        {
            var rep = new PoultryProfitLossReport { StartDate = start.Date, EndDate = end.Date };

            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryreport_plsummary(p_farmid => @FarmId::text, " +
                "p_startdate => @Start::date, p_enddate => @End::date); " +
                "SELECT * FROM sppoultryreport_pllines(p_farmid => @FarmId::text, " +
                "p_startdate => @Start::date, p_enddate => @End::date)", conn);
            Range(cmd, farmId, start, end);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();

            if (await r.ReadAsync())
            {
                rep.EggSales = Dec(r, "EggSales");
                rep.BirdSales = Dec(r, "BirdSales");
                rep.ManureSales = Dec(r, "ManureSales");
                rep.FeedSales = Dec(r, "FeedSales");
                rep.OtherRevenue = Dec(r, "OtherRevenue");
                rep.TotalRevenue = Dec(r, "TotalRevenue");

                rep.FeedCost = Dec(r, "FeedCost");
                rep.MedicationCost = Dec(r, "MedicationCost");
                rep.DirectLabour = Dec(r, "DirectLabour");
                rep.ProductionSupplies = Dec(r, "ProductionSupplies");
                rep.FlockCost = Dec(r, "FlockCost");
                rep.OtherDirectCosts = Dec(r, "OtherDirectCosts");
                rep.TotalDirectCosts = Dec(r, "TotalDirectCosts");

                rep.GrossProfit = Dec(r, "GrossProfit");
                rep.GrossMarginPercent = DecN(r, "GrossMarginPercent");

                rep.Payroll = Dec(r, "Payroll");
                rep.Utilities = Dec(r, "Utilities");
                rep.Transport = Dec(r, "Transport");
                rep.RepairsMaintenance = Dec(r, "RepairsMaintenance");
                rep.Administration = Dec(r, "Administration");
                rep.Marketing = Dec(r, "Marketing");
                rep.OtherOperatingExpenses = Dec(r, "OtherOperatingExpenses");
                rep.TotalOperatingExpenses = Dec(r, "TotalOperatingExpenses");

                rep.OperatingProfit = Dec(r, "OperatingProfit");
                rep.OperatingMarginPercent = DecN(r, "OperatingMarginPercent");

                rep.Depreciation = Dec(r, "Depreciation");
                rep.LoanInterest = Dec(r, "LoanInterest");
                rep.LoanFees = Dec(r, "LoanFees");
                rep.OtherFinancingCosts = Dec(r, "OtherFinancingCosts");
                rep.TotalOtherCosts = Dec(r, "TotalOtherCosts");

                rep.NetProfit = Dec(r, "NetProfit");
                rep.NetMarginPercent = DecN(r, "NetMarginPercent");
                rep.Status = Str(r, "Status");

                rep.OwnerContributions = Dec(r, "OwnerContributions");
                rep.OwnerDraws = Dec(r, "OwnerDraws");
                rep.NetOwnerFunding = Dec(r, "NetOwnerFunding");
                rep.LoansReceived = Dec(r, "LoansReceived");
                rep.LoanPrincipalRepaid = Dec(r, "LoanPrincipalRepaid");
                rep.NetBorrowing = Dec(r, "NetBorrowing");
                rep.TotalCapitalInvestments = Dec(r, "TotalCapitalInvestments");

                rep.FeedRecognitionMethod = StrN(r, "FeedRecognitionMethod");
                rep.MedicationRecognitionMethod = StrN(r, "MedicationRecognitionMethod");
                rep.HasItemOverrides = Bool(r, "HasItemOverrides");
                rep.RecognitionConfigured = Bool(r, "RecognitionConfigured");
                rep.LegacyExpenses = Int(r, "LegacyExpenses");
                rep.ClassifiedExpenses = Int(r, "ClassifiedExpenses");
            }

            if (await r.NextResultAsync())
            {
                while (await r.ReadAsync())
                {
                    rep.Lines.Add(new PoultryProfitLossLine
                    {
                        Section = Str(r, "Section"),
                        LineKey = Str(r, "LineKey"),
                        LineLabel = Str(r, "LineLabel"),
                        Amount = Dec(r, "Amount"),
                        SortOrder = Int(r, "SortOrder"),
                        IsInformational = Bool(r, "IsInformational"),
                        EntryCount = Int(r, "EntryCount"),
                    });
                }
            }

            return rep;
        }

        public async Task<List<PoultryProfitLossExpenseRow>> GetExpenseDetailAsync(
            string farmId, DateTime start, DateTime end, string? lineKey)
        {
            var list = new List<PoultryProfitLossExpenseRow>();
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryreport_plexpensedetail(p_farmid => @FarmId::text, " +
                "p_startdate => @Start::date, p_enddate => @End::date, p_linekey => @Line::text)", conn);
            Range(cmd, farmId, start, end);
            cmd.Parameters.AddWithValue("@Line", (object?)(string.IsNullOrWhiteSpace(lineKey) ? null : lineKey) ?? DBNull.Value);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                list.Add(new PoultryProfitLossExpenseRow
                {
                    ExpenseId = Int(r, "ExpenseId"),
                    ExpenseDate = Date(r, "ExpenseDate"),
                    Category = StrN(r, "Category"),
                    Description = StrN(r, "Description"),
                    Amount = Dec(r, "Amount"),
                    SupplierName = StrN(r, "SupplierName"),
                    SourceType = StrN(r, "SourceType"),
                    SourceLabel = StrN(r, "SourceLabel"),
                    PaymentMethod = StrN(r, "PaymentMethod"),
                    PaymentStatus = StrN(r, "PaymentStatus"),
                    CostType = StrN(r, "CostType"),
                    PlLine = StrN(r, "PlLine"),
                    PlLineLabel = StrN(r, "PlLineLabel"),
                    PoultryCapitalAssetId = IntN(r, "PoultryCapitalAssetId"),
                    IsLegacy = Bool(r, "IsLegacy"),
                });
            }
            return list;
        }

        public async Task<List<PoultryProfitLossRevenueRow>> GetRevenueDetailAsync(
            string farmId, DateTime start, DateTime end, string? lineKey)
        {
            var list = new List<PoultryProfitLossRevenueRow>();
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryreport_plrevenuedetail(p_farmid => @FarmId::text, " +
                "p_startdate => @Start::date, p_enddate => @End::date, p_linekey => @Line::text)", conn);
            Range(cmd, farmId, start, end);
            cmd.Parameters.AddWithValue("@Line", (object?)(string.IsNullOrWhiteSpace(lineKey) ? null : lineKey) ?? DBNull.Value);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                list.Add(new PoultryProfitLossRevenueRow
                {
                    SaleId = Int(r, "SaleId"),
                    SaleDate = Date(r, "SaleDate"),
                    Product = StrN(r, "Product"),
                    CustomerName = StrN(r, "CustomerName"),
                    Quantity = Dec(r, "Quantity"),
                    UnitPrice = Dec(r, "UnitPrice"),
                    TotalAmount = Dec(r, "TotalAmount"),
                    AmountPaid = Dec(r, "AmountPaid"),
                    PaymentMethod = StrN(r, "PaymentMethod"),
                    RevenueLine = StrN(r, "RevenueLine"),
                    RevenueLabel = StrN(r, "RevenueLabel"),
                });
            }
            return list;
        }

        public async Task<List<PoultryProfitLossInventoryRow>> GetInventoryDetailAsync(
            string farmId, DateTime start, DateTime end, string lineKey)
        {
            var list = new List<PoultryProfitLossInventoryRow>();
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryreport_plinventorydetail(p_farmid => @FarmId::text, " +
                "p_startdate => @Start::date, p_enddate => @End::date, p_linekey => @Line::text)", conn);
            Range(cmd, farmId, start, end);
            cmd.Parameters.AddWithValue("@Line", lineKey);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                list.Add(new PoultryProfitLossInventoryRow
                {
                    ExpenseId = Int(r, "ExpenseId"),
                    ExpenseDate = Date(r, "ExpenseDate"),
                    ItemName = StrN(r, "ItemName"),
                    ItemCategory = StrN(r, "ItemCategory"),
                    Description = StrN(r, "Description"),
                    Amount = Dec(r, "Amount"),
                    SourceType = StrN(r, "SourceType"),
                    SourceLabel = StrN(r, "SourceLabel"),
                    Recognition = StrN(r, "Recognition"),
                    SourceId = IntN(r, "SourceId"),
                    Quantity = DecN(r, "Quantity"),
                    UnitOfMeasure = StrN(r, "UnitOfMeasure"),
                    CostLayers = IntN(r, "CostLayers"),
                });
            }
            return list;
        }

        public async Task<List<PoultryAssetDepreciationModel>> GetDepreciationDetailAsync(
            string farmId, DateTime start, DateTime end)
        {
            var list = new List<PoultryAssetDepreciationModel>();
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryreport_pldepreciationdetail(p_farmid => @FarmId::text, " +
                "p_startdate => @Start::date, p_enddate => @End::date)", conn);
            Range(cmd, farmId, start, end);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                list.Add(new PoultryAssetDepreciationModel
                {
                    PoultryAssetDepreciationId = Int(r, "PoultryAssetDepreciationId"),
                    PoultryCapitalAssetId = Int(r, "PoultryCapitalAssetId"),
                    AssetNumber = StrN(r, "AssetNumber"),
                    AssetName = StrN(r, "AssetName"),
                    CategoryName = StrN(r, "CategoryName"),
                    PeriodStart = Date(r, "PeriodStart"),
                    PeriodEnd = Date(r, "PeriodEnd"),
                    Amount = Dec(r, "Amount"),
                    OriginalCost = DecN(r, "OriginalCost"),
                    MonthlyDepreciation = DecN(r, "MonthlyDepreciation"),
                    AccumulatedAfter = DecN(r, "AccumulatedDepreciation"),
                    BookValueAfter = DecN(r, "CurrentBookValue"),
                    SourceType = StrN(r, "SourceType"),
                    Status = StrN(r, "Status"),
                });
            }
            return list;
        }

        public async Task<List<PoultryProfitLossFinancingRow>> GetFinancingDetailAsync(
            string farmId, DateTime start, DateTime end, string? lineKey)
        {
            var list = new List<PoultryProfitLossFinancingRow>();
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryreport_plfinancingdetail(p_farmid => @FarmId::text, " +
                "p_startdate => @Start::date, p_enddate => @End::date, p_linekey => @Line::text)", conn);
            Range(cmd, farmId, start, end);
            cmd.Parameters.AddWithValue("@Line", (object?)(string.IsNullOrWhiteSpace(lineKey) ? null : lineKey) ?? DBNull.Value);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                list.Add(new PoultryProfitLossFinancingRow
                {
                    LineKey = StrN(r, "LineKey"),
                    EntryDate = Date(r, "EntryDate"),
                    Reference = StrN(r, "Reference"),
                    Party = StrN(r, "Party"),
                    Description = StrN(r, "Description"),
                    Amount = Dec(r, "Amount"),
                    EntryId = Int(r, "EntryId"),
                });
            }
            return list;
        }

        public async Task<List<PoultryProfitLossCapitalRow>> GetCapitalDetailAsync(
            string farmId, DateTime start, DateTime end)
        {
            var list = new List<PoultryProfitLossCapitalRow>();
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryreport_plcapitaldetail(p_farmid => @FarmId::text, " +
                "p_startdate => @Start::date, p_enddate => @End::date)", conn);
            Range(cmd, farmId, start, end);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                list.Add(new PoultryProfitLossCapitalRow
                {
                    PoultryCapitalAssetCostId = Int(r, "PoultryCapitalAssetCostId"),
                    PoultryCapitalAssetId = Int(r, "PoultryCapitalAssetId"),
                    AssetNumber = StrN(r, "AssetNumber"),
                    AssetName = StrN(r, "AssetName"),
                    CategoryName = StrN(r, "CategoryName"),
                    CostDate = Date(r, "CostDate"),
                    Description = StrN(r, "Description"),
                    CostCategory = StrN(r, "CostCategory"),
                    Amount = Dec(r, "Amount"),
                    SupplierName = StrN(r, "SupplierName"),
                    ExpenseId = IntN(r, "ExpenseId"),
                    AssetStatus = StrN(r, "AssetStatus"),
                    OriginalCost = Dec(r, "OriginalCost"),
                    CurrentBookValue = Dec(r, "CurrentBookValue"),
                });
            }
            return list;
        }
    }
}
