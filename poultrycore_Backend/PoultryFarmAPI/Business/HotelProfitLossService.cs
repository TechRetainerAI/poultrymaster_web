using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IHotelProfitLossService
    {
        Task<HotelProfitLossReport> GetAsync(string farmId, DateTime start, DateTime end);
        Task<List<HotelPlExpenseRow>> GetExpenseDetailAsync(string farmId, DateTime start, DateTime end, string? lineKey);
        Task<List<HotelPlRevenueRow>> GetRevenueDetailAsync(string farmId, DateTime start, DateTime end, string? lineKey);
    }

    public class HotelProfitLossService : IHotelProfitLossService
    {
        private readonly string _cs;
        public HotelProfitLossService(string cs) => _cs = cs;

        private static string? StrN(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? null : r.GetString(i); }
        private static string Str(NpgsqlDataReader r, string c) => StrN(r, c) ?? string.Empty;
        private static int Int(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? 0 : r.GetInt32(i); }
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

        public async Task<HotelProfitLossReport> GetAsync(string farmId, DateTime start, DateTime end)
        {
            var rep = new HotelProfitLossReport { StartDate = start.Date, EndDate = end.Date };

            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sphotelreport_plsummary(p_farmid => @FarmId::text, " +
                "p_startdate => @Start::date, p_enddate => @End::date); " +
                "SELECT * FROM sphotelreport_pllines(p_farmid => @FarmId::text, " +
                "p_startdate => @Start::date, p_enddate => @End::date)", conn);
            Range(cmd, farmId, start, end);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();

            if (await r.ReadAsync())
            {
                rep.RoomRevenue = Dec(r, "roomrevenue");
                rep.RestaurantRevenue = Dec(r, "restaurantrevenue");
                rep.DepositsNet = Dec(r, "depositsnet");
                rep.TotalRevenue = Dec(r, "totalrevenue");

                rep.StaffWages = Dec(r, "staffwages");
                rep.TotalExpenseCategory = Dec(r, "totalexpensecategory");
                rep.TotalExpenses = Dec(r, "totalexpenses");

                rep.NetProfit = Dec(r, "netprofit");
                rep.NetMarginPercent = DecN(r, "netmarginpercent");
                rep.Status = Str(r, "status");

                rep.RevenueEntries = Int(r, "revenueentries");
                rep.ExpenseEntries = Int(r, "expenseentries");
            }

            if (await r.NextResultAsync())
            {
                while (await r.ReadAsync())
                {
                    rep.Lines.Add(new HotelProfitLossLine
                    {
                        Section = Str(r, "section"),
                        LineKey = Str(r, "linekey"),
                        LineLabel = Str(r, "linelabel"),
                        Amount = Dec(r, "amount"),
                        SortOrder = Int(r, "sortorder"),
                        IsInformational = Bool(r, "isinformational"),
                        EntryCount = Int(r, "entrycount"),
                    });
                }
            }

            return rep;
        }

        public async Task<List<HotelPlExpenseRow>> GetExpenseDetailAsync(
            string farmId, DateTime start, DateTime end, string? lineKey)
        {
            var rows = new List<HotelPlExpenseRow>();
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sphotelreport_plexpensedetail(p_farmid => @FarmId::text, " +
                "p_startdate => @Start::date, p_enddate => @End::date, " +
                "p_linekey => @LineKey::text)", conn);
            Range(cmd, farmId, start, end);
            cmd.Parameters.AddWithValue("@LineKey", (object?)lineKey ?? DBNull.Value);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                rows.Add(new HotelPlExpenseRow
                {
                    HotelExpenseId = Int(r, "hotelexpenseid"),
                    ExpenseDate = Date(r, "expensedate"),
                    Category = StrN(r, "category"),
                    Description = StrN(r, "description"),
                    Amount = Dec(r, "amount"),
                    Vendor = StrN(r, "vendor"),
                    PaymentMethod = StrN(r, "paymentmethod"),
                    Status = StrN(r, "status"),
                    PlLineKey = StrN(r, "pllinekey"),
                });
            }
            return rows;
        }

        public async Task<List<HotelPlRevenueRow>> GetRevenueDetailAsync(
            string farmId, DateTime start, DateTime end, string? lineKey)
        {
            var rows = new List<HotelPlRevenueRow>();
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sphotelreport_plrevenuedetail(p_farmid => @FarmId::text, " +
                "p_startdate => @Start::date, p_enddate => @End::date, " +
                "p_linekey => @LineKey::text)", conn);
            Range(cmd, farmId, start, end);
            cmd.Parameters.AddWithValue("@LineKey", (object?)lineKey ?? DBNull.Value);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                rows.Add(new HotelPlRevenueRow
                {
                    SourceType = StrN(r, "sourcetype"),
                    SourceId = Int(r, "sourceid"),
                    EntryDate = Date(r, "entrydate"),
                    Description = StrN(r, "description"),
                    Amount = Dec(r, "amount"),
                    Method = StrN(r, "method"),
                    PlLineKey = StrN(r, "pllinekey"),
                });
            }
            return rows;
        }
    }
}
