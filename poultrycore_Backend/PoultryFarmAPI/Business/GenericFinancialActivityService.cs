// =============================================================================
// Generic Financial Activity (migration 419). Same pattern as Hotel (336):
// one call returns the period's totals, its events and each event's position
// changes, in the shared FinancialActivity* DTOs.
// =============================================================================

using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IGenericFinancialActivityService
    {
        Task<FinancialActivityResponse> GetAsync(string farmId, DateTime from, DateTime to);
    }

    public class GenericFinancialActivityService : IGenericFinancialActivityService
    {
        private readonly string _connectionString;
        public GenericFinancialActivityService(string connectionString) => _connectionString = connectionString;

        public async Task<FinancialActivityResponse> GetAsync(string farmId, DateTime from, DateTime to)
        {
            var res = new FinancialActivityResponse
            {
                FarmId = farmId,
                FromDate = from.Date,
                ToDate = to.Date,
            };

            using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();

            // ---- summary -------------------------------------------------------
            using (var cmd = new NpgsqlCommand(
                "SELECT * FROM spgenericfinancialactivity_summary(" +
                "p_farmid => @FarmId::text, p_from => @From::date, p_to => @To::date)", conn))
            {
                AddRange(cmd, farmId, from, to);
                using var r = await cmd.ExecuteReaderAsync();
                if (await r.ReadAsync())
                {
                    res.Summary = new FinancialActivitySummary
                    {
                        MoneyIn       = Dec(r, "moneyin"),
                        MoneyOut      = Dec(r, "moneyout"),
                        NetCashFlow   = Dec(r, "netcashflow"),
                        OpeningCash   = Dec(r, "openingcash"),
                        ClosingCash   = Dec(r, "closingcash"),
                        Revenue       = Dec(r, "revenue"),
                        Expense       = Dec(r, "expense"),
                        NetProfit     = Dec(r, "netprofit"),
                        EventCount    = Int(r, "eventcount"),
                        CashEvents    = Int(r, "cashevents"),
                        NonCashEvents = Int(r, "noncashevents"),
                    };
                }
            }

            // ---- rows ----------------------------------------------------------
            var byKey = new Dictionary<string, FinancialActivityRow>(StringComparer.Ordinal);
            using (var cmd = new NpgsqlCommand(
                "SELECT * FROM spgenericfinancialactivity_get(" +
                "p_farmid => @FarmId::text, p_from => @From::date, p_to => @To::date)", conn))
            {
                AddRange(cmd, farmId, from, to);
                using var r = await cmd.ExecuteReaderAsync();
                while (await r.ReadAsync())
                {
                    var row = new FinancialActivityRow
                    {
                        EventKey          = Str(r, "eventkey") ?? "",
                        BusinessDate      = Date(r, "businessdate"),
                        OccurredAt        = Date(r, "occurredat"),
                        CreatedAt         = DateN(r, "createdat"),
                        ActivityType      = Str(r, "activitytype") ?? "",
                        Type              = Str(r, "type") ?? "",
                        Category          = Str(r, "category") ?? "",
                        Description       = Str(r, "description"),
                        SourceType        = Str(r, "sourcetype"),
                        SourceId          = NullInt(r, "sourceid"),
                        SourceNumber      = Str(r, "sourcenumber"),
                        MoneyIn           = Dec(r, "moneyin"),
                        MoneyOut          = Dec(r, "moneyout"),
                        Revenue           = Dec(r, "revenue"),
                        Expense           = Dec(r, "expense"),
                        ProfitImpact      = Dec(r, "profitimpact"),
                        RunningCash       = Dec(r, "runningcash"),
                        IsCashActivity    = Bool(r, "iscash"),
                        IsNonCashActivity = Bool(r, "isnoncash"),
                        IsInternalTransfer= Bool(r, "istransfer"),
                        CashAccountId     = NullInt(r, "cashaccountid"),
                        CashAccountName   = Str(r, "cashaccountname"),
                        PartyName         = Str(r, "partyname"),
                        PlLine            = Str(r, "plline"),
                        Status            = Str(r, "status"),
                    };
                    res.Rows.Add(row);
                    byKey[row.EventKey] = row;
                }
            }

            // ---- position changes, attached to the rows they belong to ---------
            using (var cmd = new NpgsqlCommand(
                "SELECT * FROM fngenericfa_positions(" +
                "p_farmid => @FarmId::text, p_from => @From::date, p_to => @To::date)", conn))
            {
                AddRange(cmd, farmId, from, to);
                using var r = await cmd.ExecuteReaderAsync();
                while (await r.ReadAsync())
                {
                    var key = Str(r, "eventkey") ?? "";
                    if (!byKey.TryGetValue(key, out var row)) continue;
                    row.PositionChanges.Add(new FinancialPositionChange
                    {
                        PositionType   = Str(r, "positiontype") ?? "",
                        PositionName   = Str(r, "positionname") ?? "",
                        IncreaseAmount = Dec(r, "increaseamount"),
                        DecreaseAmount = Dec(r, "decreaseamount"),
                        Explanation    = Str(r, "explanation"),
                    });
                }
            }

            return res;
        }

        private static void AddRange(NpgsqlCommand cmd, string farmId, DateTime from, DateTime to)
        {
            cmd.Parameters.AddWithValue("@FarmId", farmId ?? "");
            cmd.Parameters.AddWithValue("@From", from.Date);
            cmd.Parameters.AddWithValue("@To", to.Date);
        }

        private static string? Str(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? null : r.GetValue(i)?.ToString(); }

        private static decimal Dec(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? 0m : r.GetDecimal(i); }

        private static int Int(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? 0 : r.GetInt32(i); }

        private static int? NullInt(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? null : r.GetInt32(i); }

        private static bool Bool(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return !r.IsDBNull(i) && r.GetBoolean(i); }

        private static DateTime Date(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? default : r.GetDateTime(i); }

        private static DateTime? DateN(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? (DateTime?)null : r.GetDateTime(i); }
    }
}
