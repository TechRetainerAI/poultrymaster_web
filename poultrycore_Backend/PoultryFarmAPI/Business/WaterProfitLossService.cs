// The structured water Profit & Loss and its drilldowns (migration 316).
//
// Thin, like every other service here: it sends parameters and maps rows.
// Nothing about what water counts as profit lives in this file -- that is
// spwaterreport_periodpnl's, and 316's statement is built on top of it.
//
// In particular NOTHING here adds a figure up. If the statement and the summary
// ever disagreed, the fix belongs in SQL where both are defined, not in a C#
// reconciliation nobody would think to look for.

using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IWaterProfitLossService
    {
        /// <summary>Summary and statement lines in ONE round trip.</summary>
        Task<WaterProfitLossReport> GetReportAsync(string farmId, DateTime start, DateTime end);

        /// <summary>
        /// The rows behind one figure. `kind` picks the SQL function; `lineKey`
        /// narrows it to a single line, or null for the whole band.
        /// </summary>
        Task<List<WaterPlDetailRow>> GetDetailAsync(
            string farmId, DateTime start, DateTime end, string kind, string? lineKey);
    }

    public class WaterProfitLossService : IWaterProfitLossService
    {
        private readonly string _cs;
        public WaterProfitLossService(string cs) => _cs = cs;

        // ---- reader helpers -------------------------------------------------
        private static string? StrN(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? null : r.GetString(i); }
        private static string Str(NpgsqlDataReader r, string c) => StrN(r, c) ?? string.Empty;
        private static int Int(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? 0 : r.GetInt32(i); }
        private static decimal Dec(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? 0m : r.GetDecimal(i); }
        private static DateTime? DateN(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? (DateTime?)null : r.GetDateTime(i); }
        private static DateTime Date(NpgsqlDataReader r, string c) => DateN(r, c) ?? default;
        private static bool Bool(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return !r.IsDBNull(i) && r.GetBoolean(i); }

        /// <summary>
        /// Which SQL function a drilldown kind reads.
        ///
        /// An ALLOWLIST, not string interpolation: `kind` arrives from a query
        /// string and is about to name a function. Anything not on this list is
        /// refused rather than passed through.
        /// </summary>
        private static string? FunctionFor(string kind) => kind?.ToLowerInvariant() switch
        {
            WaterPlDetailKind.Revenue      => "spwaterreport_plrevenuedetail",
            WaterPlDetailKind.DirectCost   => "spwaterreport_pldirectcostdetail",
            WaterPlDetailKind.Expense      => "spwaterreport_plexpensedetail",
            WaterPlDetailKind.Loss         => "spwaterreport_pllossdetail",
            WaterPlDetailKind.Financing    => "spwaterreport_plfinancingdetail",
            WaterPlDetailKind.Capital      => "spwaterreport_plcapitaldetail",
            WaterPlDetailKind.Depreciation => "spwaterreport_pldepreciationdetail",
            _ => null,
        };

        public async Task<WaterProfitLossReport> GetReportAsync(string farmId, DateTime start, DateTime end)
        {
            var report = new WaterProfitLossReport();

            using var conn = new NpgsqlConnection(_cs);
            // One batch: a page that fetched the summary and the statement
            // separately could show a net profit and a set of lines that do not
            // add up to it, if a row landed between the two calls.
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spwaterreport_plsummary(p_farmid => @FarmId::text, " +
                "p_startdate => @Start::date, p_enddate => @End::date); " +
                "SELECT * FROM spwaterreport_pllines(p_farmid => @FarmId::text, " +
                "p_startdate => @Start::date, p_enddate => @End::date)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Start", start.Date);
            cmd.Parameters.AddWithValue("@End", end.Date);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();

            if (await r.ReadAsync())
            {
                report.Summary = new WaterPlSummary
                {
                    StartDate = Date(r, "StartDate"),
                    EndDate = Date(r, "EndDate"),
                    StorefrontSales = Dec(r, "StorefrontSales"),
                    DeliveryCollections = Dec(r, "DeliveryCollections"),
                    TotalRevenue = Dec(r, "TotalRevenue"),
                    RawMaterials = Dec(r, "RawMaterials"),
                    ProductionCost = Dec(r, "ProductionCost"),
                    TotalDirectCosts = Dec(r, "TotalDirectCosts"),
                    GrossProfit = Dec(r, "GrossProfit"),
                    GrossMarginPercent = Dec(r, "GrossMarginPercent"),
                    TotalOperatingExpenses = Dec(r, "TotalOperatingExpenses"),
                    TotalOtherCosts = Dec(r, "TotalOtherCosts"),
                    OperatingProfit = Dec(r, "OperatingProfit"),
                    OperatingMarginPercent = Dec(r, "OperatingMarginPercent"),
                    ProductionLosses = Dec(r, "ProductionLosses"),
                    DriverShortages = Dec(r, "DriverShortages"),
                    TotalLosses = Dec(r, "TotalLosses"),
                    NetProfit = Dec(r, "NetProfit"),
                    NetMarginPercent = Dec(r, "NetMarginPercent"),
                    OwnerContributions = Dec(r, "OwnerContributions"),
                    OwnerDraws = Dec(r, "OwnerDraws"),
                    NetOwnerFunding = Dec(r, "NetOwnerFunding"),
                    LoansReceived = Dec(r, "LoansReceived"),
                    LoanPrincipalRepaid = Dec(r, "LoanPrincipalRepaid"),
                    NetBorrowing = Dec(r, "NetBorrowing"),
                    TotalCapitalInvestments = Dec(r, "TotalCapitalInvestments"),
                    BagsProduced = Int(r, "BagsProduced"),
                    BagsSold = Int(r, "BagsSold"),
                    AvgProfitPerBag = Dec(r, "AvgProfitPerBag"),
                    CapitalInExpenses = Dec(r, "CapitalInExpenses"),
                    EntryCount = Int(r, "EntryCount"),
                };
            }

            if (await r.NextResultAsync())
            {
                while (await r.ReadAsync())
                {
                    report.Lines.Add(new WaterPlLine
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

            return report;
        }

        public async Task<List<WaterPlDetailRow>> GetDetailAsync(
            string farmId, DateTime start, DateTime end, string kind, string? lineKey)
        {
            var fn = FunctionFor(kind ?? string.Empty);
            if (fn is null) throw new ArgumentException($"Unknown drilldown '{kind}'.", nameof(kind));

            var rows = new List<WaterPlDetailRow>();
            using var conn = new NpgsqlConnection(_cs);

            // The depreciation drilldown is the one that takes no line key: it is
            // the whole asset register's charge for the period, not one line of it.
            var takesLineKey = fn != "spwaterreport_pldepreciationdetail";
            var sql = takesLineKey
                ? $"SELECT * FROM {fn}(p_farmid => @FarmId::text, p_startdate => @Start::date, " +
                   "p_enddate => @End::date, p_linekey => @LineKey::text)"
                : $"SELECT * FROM {fn}(p_farmid => @FarmId::text, p_startdate => @Start::date, " +
                   "p_enddate => @End::date)";

            using var cmd = new NpgsqlCommand(sql, conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Start", start.Date);
            cmd.Parameters.AddWithValue("@End", end.Date);
            if (takesLineKey)
            {
                cmd.Parameters.AddWithValue("@LineKey",
                    string.IsNullOrWhiteSpace(lineKey) ? (object)DBNull.Value : lineKey);
            }

            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                rows.Add(new WaterPlDetailRow
                {
                    EntryDate = DateN(r, "EntryDate"),
                    Reference = StrN(r, "Reference"),
                    Party = StrN(r, "Party"),
                    Detail = StrN(r, "Detail"),
                    Amount = Dec(r, "Amount"),
                });
            }
            return rows;
        }
    }
}
