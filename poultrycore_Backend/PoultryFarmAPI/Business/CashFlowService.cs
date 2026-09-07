// =============================================================================
// Cash Flow — the transaction-sourced report, shared by Poultry and Water.
//
// Reads sp{rail}cashflow_detail / _summary (migrations 235 and 236). Those
// functions are built on the business transactions that move money -- customer
// receipts, expenses, capital in and out -- and deliberately do NOT read the
// cash-account ledger, account balances, transfers or reconciliation records.
//
// One implementation for both rails. The two rails' functions return identical
// shapes on purpose, so the only thing that varies is the name prefix; a second
// copy of this class would be two places for the same bug to live.
// =============================================================================

using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface ICashFlowService
    {
        Task<CashFlowResponse> GetAsync(string rail, string farmId, DateTime? from, DateTime? to);
    }

    public class CashFlowService : ICashFlowService
    {
        private readonly string _connectionString;
        public CashFlowService(string connectionString) => _connectionString = connectionString;

        /// <summary>
        /// Only these two rails have cash-flow functions. Validated against a
        /// fixed list rather than interpolated, because the value reaches a
        /// function name in SQL text and must never be caller-controlled.
        /// </summary>
        private static string Prefix(string rail) => rail?.ToLowerInvariant() switch
        {
            "poultry" => "sppoultrycashflow",
            "water"   => "spwatercashflow",
            _ => throw new ArgumentException($"Unknown rail '{rail}'. Expected 'poultry' or 'water'."),
        };

        public async Task<CashFlowResponse> GetAsync(string rail, string farmId, DateTime? from, DateTime? to)
        {
            var prefix = Prefix(rail);
            var res = new CashFlowResponse { FarmId = farmId, FromDate = from, ToDate = to };

            using var conn = new NpgsqlConnection(_connectionString);
            await conn.OpenAsync();

            // ---- rows ------------------------------------------------------
            using (var cmd = new NpgsqlCommand(
                $"SELECT * FROM {prefix}_detail(p_farmid => @FarmId::text, " +
                "p_fromdate => @From::timestamp, p_todate => @To::timestamp) " +
                "ORDER BY transactiondate, rowsource, sourcerowid", conn))
            {
                cmd.Parameters.AddWithValue("@FarmId", farmId ?? "");
                cmd.Parameters.AddWithValue("@From", (object?)from ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@To", (object?)to ?? DBNull.Value);

                using var r = await cmd.ExecuteReaderAsync();
                while (await r.ReadAsync())
                {
                    var amount = Dec(r, "amount");
                    res.Rows.Add(new CashFlowRow
                    {
                        Id = Int(r, "sourcerowid"),
                        RowSource = Str(r, "rowsource") ?? "",
                        SourceType = Str(r, "sourcetype") ?? "",
                        SourceId = IntN(r, "sourceid"),
                        FlowGroup = Str(r, "flowgroup") ?? "",
                        Category = Str(r, "category") ?? "Other",
                        TransactionDate = DateN(r, "transactiondate") ?? DateTime.UtcNow,
                        Description = Str(r, "description"),
                        CashAccountId = IntN(r, "cashaccountid"),
                        Amount = amount,
                        Inflow = amount > 0 ? amount : 0m,
                        Outflow = amount < 0 ? -amount : 0m,
                    });
                }
            }

            // ---- summary ---------------------------------------------------
            using (var cmd = new NpgsqlCommand(
                $"SELECT * FROM {prefix}_summary(p_farmid => @FarmId::text, " +
                "p_fromdate => @From::timestamp, p_todate => @To::timestamp)", conn))
            {
                cmd.Parameters.AddWithValue("@FarmId", farmId ?? "");
                cmd.Parameters.AddWithValue("@From", (object?)from ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@To", (object?)to ?? DBNull.Value);

                using var r = await cmd.ExecuteReaderAsync();
                if (await r.ReadAsync())
                {
                    res.Summary = new CashFlowSummary
                    {
                        MoneyIn = Dec(r, "moneyin"),
                        MoneyOut = Dec(r, "moneyout"),
                        NetCashFlow = Dec(r, "netcashflow"),
                        OpeningCash = Dec(r, "openingbalance"),
                        ClosingCash = Dec(r, "cashathand"),
                        MovementCount = (int)Dec(r, "rowcount"),
                    };
                }
            }

            // The four flow groups, summed here rather than in SQL so one pass
            // over the rows serves both the totals and the breakdowns.
            foreach (var g in res.Rows.GroupBy(x => x.FlowGroup))
            {
                var total = g.Sum(x => Math.Abs(x.Amount));
                switch (g.Key)
                {
                    case "OperatingIn":  res.Summary.OperatingIn  = total; break;
                    case "OperatingOut": res.Summary.OperatingOut = total; break;
                    case "FinancingIn":  res.Summary.FinancingIn  = total; break;
                    case "FinancingOut": res.Summary.FinancingOut = total; break;
                }
            }

            return res;
        }

        // ---- readers -------------------------------------------------------
        // Tolerate a missing column so a slightly older database does not throw;
        // same approach as PoultryReportHelpers.
        private static int? Ordinal(NpgsqlDataReader r, string col)
        {
            for (var i = 0; i < r.FieldCount; i++)
                if (string.Equals(r.GetName(i), col, StringComparison.OrdinalIgnoreCase)) return i;
            return null;
        }

        private static string? Str(NpgsqlDataReader r, string col)
        {
            var i = Ordinal(r, col);
            return i == null || r.IsDBNull(i.Value) ? null : Convert.ToString(r.GetValue(i.Value));
        }

        private static decimal Dec(NpgsqlDataReader r, string col)
        {
            var i = Ordinal(r, col);
            return i == null || r.IsDBNull(i.Value) ? 0m : Convert.ToDecimal(r.GetValue(i.Value));
        }

        private static int Int(NpgsqlDataReader r, string col)
        {
            var i = Ordinal(r, col);
            return i == null || r.IsDBNull(i.Value) ? 0 : Convert.ToInt32(r.GetValue(i.Value));
        }

        private static int? IntN(NpgsqlDataReader r, string col)
        {
            var i = Ordinal(r, col);
            return i == null || r.IsDBNull(i.Value) ? (int?)null : Convert.ToInt32(r.GetValue(i.Value));
        }

        private static DateTime? DateN(NpgsqlDataReader r, string col)
        {
            var i = Ordinal(r, col);
            return i == null || r.IsDBNull(i.Value) ? (DateTime?)null : Convert.ToDateTime(r.GetValue(i.Value));
        }
    }
}
