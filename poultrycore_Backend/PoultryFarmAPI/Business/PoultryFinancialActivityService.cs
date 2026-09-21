// =============================================================================
// Financial Activity — the reporting service.
//
// Reads migration 290's three functions and nothing else:
//
//   sppoultryfinancialactivity_get      one row per event, with running cash
//   sppoultryfinancialactivity_summary  period totals (cash side from Cash Flow)
//   fnpoultryfa_positions               what each event did to the farm's position
//
// Positions are fetched for the WHOLE period in one query and attached in
// memory. Asking per row would be an N+1 against a report that can easily carry
// a thousand events, and the page lets you expand any row without warning.
//
// This service classifies nothing. Every judgement about what counts as revenue,
// what counts as an expense and what a deferred purchase does lives in SQL,
// shared with Cash Flow and P&L, so the three reports cannot drift apart.
// =============================================================================

using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IPoultryFinancialActivityService
    {
        Task<FinancialActivityResponse> GetAsync(string farmId, DateTime from, DateTime to);
    }

    public class PoultryFinancialActivityService : IPoultryFinancialActivityService
    {
        private readonly string _connectionString;
        public PoultryFinancialActivityService(string connectionString) => _connectionString = connectionString;

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
                "SELECT * FROM public.sppoultryfinancialactivity_summary(" +
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
                "SELECT * FROM public.sppoultryfinancialactivity_get(" +
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
                        // 315. The entry time, so a row whose business date is
                        // midnight can still say when it was typed.
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
                    // Last write wins, but keys are unique by construction — the
                    // SQL groups by event key before returning.
                    byKey[row.EventKey] = row;
                }
            }

            // ---- position changes, attached to the rows they belong to ---------
            using (var cmd = new NpgsqlCommand(
                "SELECT * FROM public.fnpoultryfa_positions(" +
                "p_farmid => @FarmId::text, p_from => @From::date, p_to => @To::date)", conn))
            {
                AddRange(cmd, farmId, from, to);
                using var r = await cmd.ExecuteReaderAsync();
                while (await r.ReadAsync())
                {
                    var key = Str(r, "eventkey") ?? "";
                    // A position whose event is not in the period is dropped rather
                    // than shown loose: the two functions filter on the same dates,
                    // so this only fires if they ever disagree.
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

        /// <summary>
        /// 315. Nullable, unlike <see cref="Date"/>: an entry time can genuinely
        /// be absent, and `default` would serialise as 0001-01-01 and be rendered
        /// as a real timestamp by anything downstream.
        /// </summary>
        private static DateTime? DateN(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? (DateTime?)null : r.GetDateTime(i); }
    }
}
