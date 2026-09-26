// =============================================================================
// Restaurant finance (migration 323): cash accounts, till shifts, transfers,
// owner money, loans, cash counts, daily closing and the P&L line statement.
//
// Every rule lives in the sprestaurant_* functions, each of which runs as one
// database transaction -- a transfer's two legs, a shift close's variance and
// drop, a loan repayment's ledger row and balance update all commit together or
// not at all. This class only passes parameters and reads rows back.
//
// A refusal from those functions (RAISE EXCEPTION, SQLSTATE P0001) propagates
// as a PostgresException; RestaurantBusinessRuleFilter turns it into a 400.
// =============================================================================

using System.Reflection;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IRestaurantFinanceService
    {
        // Accounts
        Task<List<RestaurantCashAccount>> ListAccountsAsync(string farmId);
        Task<int> CreateAccountAsync(RestaurantCashAccountCreateRequest req, string by);
        Task UpdateAccountAsync(int id, string farmId, RestaurantCashAccountUpdateRequest req);
        Task<List<RestaurantCashLedgerRow>> LedgerAsync(string farmId, int accountId, DateTime? from, DateTime? to);

        // Shifts
        Task<List<RestaurantCashShift>> ListShiftsAsync(string farmId, string? status, DateTime? from, DateTime? to);
        Task<int> OpenShiftAsync(string farmId, RestaurantShiftOpenRequest req, string by);
        Task<RestaurantShiftCloseResult> CloseShiftAsync(string farmId, int shiftId, RestaurantShiftCloseRequest req, string by);
        Task<List<RestaurantZReportLine>> ZReportAsync(string farmId, int shiftId);

        // Transfers
        Task<List<RestaurantCashTransfer>> ListTransfersAsync(string farmId, DateTime? from, DateTime? to);
        Task<int> CreateTransferAsync(string farmId, RestaurantTransferRequest req, string by);
        Task ReverseTransferAsync(string farmId, int id, string reason, string by);

        // Owner money
        Task<List<RestaurantOwnerMoneyEntry>> ListOwnerMoneyAsync(string farmId, DateTime? from, DateTime? to);
        Task<int> RecordOwnerMoneyAsync(string farmId, RestaurantOwnerMoneyRequest req, string by);
        Task ReverseOwnerMoneyAsync(string farmId, int id, string reason, string by);

        // Loans
        Task<List<RestaurantLoan>> ListLoansAsync(string farmId);
        Task<List<RestaurantLoanPayment>> ListLoanPaymentsAsync(string farmId, int loanId);
        Task<int> CreateLoanAsync(string farmId, RestaurantLoanCreateRequest req, string by);
        Task<int> RepayLoanAsync(string farmId, int loanId, RestaurantLoanRepayRequest req, string by);
        Task ReverseLoanPaymentAsync(string farmId, int paymentId, string reason, string by);
        Task CancelLoanAsync(string farmId, int loanId, string reason, string by);

        // Counts
        Task<List<RestaurantCashCount>> ListCountsAsync(string farmId, int? accountId);
        Task<int> PostCountAsync(string farmId, RestaurantCashCountRequest req, string by);
        Task ReverseCountAsync(string farmId, int countId, string reason, string by);

        // Daily closing
        Task<RestaurantDailyClosingPreview?> PreviewDayAsync(string farmId, DateTime date);
        Task<List<RestaurantDailyClosing>> ListClosingsAsync(string farmId, int limit, DateTime? from = null, DateTime? to = null);
        Task<int> CloseDayAsync(string farmId, DateTime date, string? notes, string by);
        Task ReopenDayAsync(string farmId, DateTime date, string reason, string by);

        // P&L statement lines
        Task<List<RestaurantPnlLine>> PnlLinesAsync(string farmId, DateTime from, DateTime to);

        // Reports (migration 324)
        Task<List<RestaurantLedgerPeriodRow>> LedgerPeriodAsync(string farmId, DateTime from, DateTime to);
        Task<List<RestaurantLedgerRow>> LedgerRowsAsync(string farmId, DateTime from, DateTime to, int? accountId);
        Task<List<RestaurantTakingsByAccountRow>> TakingsByAccountAsync(string farmId, DateTime from, DateTime to);
        Task<List<RestaurantCashBridgeLine>> CashProfitBridgeAsync(string farmId, DateTime from, DateTime to);
    }

    public class RestaurantFinanceService : IRestaurantFinanceService
    {
        private readonly string _cs;
        public RestaurantFinanceService(string cs) => _cs = cs;

        // ---- accounts ----------------------------------------------------------

        public Task<List<RestaurantCashAccount>> ListAccountsAsync(string farmId) =>
            QueryAsync<RestaurantCashAccount>("SELECT * FROM sprestaurant_cashaccount_list(p_farmid => @f::text)",
                ("f", farmId));

        public Task<int> CreateAccountAsync(RestaurantCashAccountCreateRequest req, string by) =>
            ScalarIntAsync("SELECT sprestaurant_cashaccount_create(p_farmid => @f::text, p_name => @n::text, " +
                           "p_accounttype => @t::text, p_openingbalance => @o::numeric, p_allownegative => @a::boolean, " +
                           "p_defaultfor => @d::text, p_notes => @no::text, p_createdby => @by::text)",
                ("f", req.FarmId), ("n", req.Name), ("t", req.AccountType), ("o", req.OpeningBalance),
                ("a", req.AllowNegative), ("d", Blank(req.DefaultFor)), ("no", req.Notes), ("by", by));

        public Task UpdateAccountAsync(int id, string farmId, RestaurantCashAccountUpdateRequest req) =>
            ExecAsync("SELECT sprestaurant_cashaccount_update(p_id => @id::int, p_farmid => @f::text, p_name => @n::text, " +
                      "p_accounttype => @t::text, p_allownegative => @a::boolean, p_isactive => @ia::boolean, " +
                      "p_defaultfor => @d::text, p_notes => @no::text)",
                ("id", id), ("f", farmId), ("n", req.Name), ("t", req.AccountType), ("a", req.AllowNegative),
                ("ia", req.IsActive), ("d", Blank(req.DefaultFor)), ("no", req.Notes));

        public Task<List<RestaurantCashLedgerRow>> LedgerAsync(string farmId, int accountId, DateTime? from, DateTime? to) =>
            QueryAsync<RestaurantCashLedgerRow>(
                "SELECT * FROM sprestaurant_cashaccount_ledger(p_farmid => @f::text, p_accountid => @a::int, " +
                "p_from => @fr::date, p_to => @to::date)",
                ("f", farmId), ("a", accountId), ("fr", from?.Date), ("to", to?.Date));

        // ---- shifts ------------------------------------------------------------

        public Task<List<RestaurantCashShift>> ListShiftsAsync(string farmId, string? status, DateTime? from, DateTime? to) =>
            QueryAsync<RestaurantCashShift>(
                "SELECT * FROM sprestaurant_cashshift_list(p_farmid => @f::text, p_status => @s::text, " +
                "p_from => @fr::date, p_to => @to::date)",
                ("f", farmId), ("s", Blank(status)), ("fr", from?.Date), ("to", to?.Date));

        public Task<int> OpenShiftAsync(string farmId, RestaurantShiftOpenRequest req, string by) =>
            ScalarIntAsync("SELECT sprestaurant_cashshift_open(p_farmid => @f::text, p_tillaccountid => @t::int, " +
                           "p_openingfloat => @fl::numeric, p_floatfromaccountid => @ff::int, p_openedby => @by::text, " +
                           "p_notes => @n::text)",
                ("f", farmId), ("t", req.TillAccountId), ("fl", req.OpeningFloat), ("ff", req.FloatFromAccountId),
                ("by", by), ("n", req.Notes));

        public async Task<RestaurantShiftCloseResult> CloseShiftAsync(string farmId, int shiftId, RestaurantShiftCloseRequest req, string by)
        {
            var rows = await QueryAsync<RestaurantShiftCloseResult>(
                "SELECT * FROM sprestaurant_cashshift_close(p_farmid => @f::text, p_shiftid => @s::int, " +
                "p_countedcash => @c::numeric, p_dropamount => @d::numeric, p_droptoaccountid => @dt::int, " +
                "p_closedby => @by::text, p_notes => @n::text)",
                ("f", farmId), ("s", shiftId), ("c", req.CountedCash), ("d", req.DropAmount),
                ("dt", req.DropToAccountId), ("by", by), ("n", req.Notes));
            return rows.FirstOrDefault() ?? new RestaurantShiftCloseResult();
        }

        public Task<List<RestaurantZReportLine>> ZReportAsync(string farmId, int shiftId) =>
            QueryAsync<RestaurantZReportLine>(
                "SELECT * FROM sprestaurant_cashshift_zreport(p_farmid => @f::text, p_shiftid => @s::int) " +
                "ORDER BY sortorder, label", ("f", farmId), ("s", shiftId));

        // ---- transfers ---------------------------------------------------------

        public Task<List<RestaurantCashTransfer>> ListTransfersAsync(string farmId, DateTime? from, DateTime? to) =>
            QueryAsync<RestaurantCashTransfer>(
                "SELECT * FROM sprestaurant_cashtransfer_list(p_farmid => @f::text, p_from => @fr::date, p_to => @to::date)",
                ("f", farmId), ("fr", from?.Date), ("to", to?.Date));

        public Task<int> CreateTransferAsync(string farmId, RestaurantTransferRequest req, string by) =>
            ScalarIntAsync("SELECT sprestaurant_cashtransfer_create(p_farmid => @f::text, p_fromaccountid => @fa::int, " +
                           "p_toaccountid => @ta::int, p_amount => @a::numeric, p_transferdate => @d::date, " +
                           "p_reference => @r::text, p_notes => @n::text, p_createdby => @by::text)",
                ("f", farmId), ("fa", req.FromAccountId), ("ta", req.ToAccountId), ("a", req.Amount),
                ("d", req.TransferDate?.Date), ("r", req.Reference), ("n", req.Notes), ("by", by));

        public Task ReverseTransferAsync(string farmId, int id, string reason, string by) =>
            ExecAsync("SELECT sprestaurant_cashtransfer_reverse(p_farmid => @f::text, p_transferid => @id::int, " +
                      "p_reason => @r::text, p_reversedby => @by::text)",
                ("f", farmId), ("id", id), ("r", reason), ("by", by));

        // ---- owner money -------------------------------------------------------

        public Task<List<RestaurantOwnerMoneyEntry>> ListOwnerMoneyAsync(string farmId, DateTime? from, DateTime? to) =>
            QueryAsync<RestaurantOwnerMoneyEntry>(
                "SELECT * FROM sprestaurant_ownermoney_list(p_farmid => @f::text, p_from => @fr::date, p_to => @to::date)",
                ("f", farmId), ("fr", from?.Date), ("to", to?.Date));

        public Task<int> RecordOwnerMoneyAsync(string farmId, RestaurantOwnerMoneyRequest req, string by) =>
            ScalarIntAsync("SELECT sprestaurant_ownermoney_record(p_farmid => @f::text, p_entrytype => @t::text, " +
                           "p_cashaccountid => @a::int, p_amount => @amt::numeric, p_entrydate => @d::date, " +
                           "p_ownername => @o::text, p_notes => @n::text, p_createdby => @by::text)",
                ("f", farmId), ("t", req.EntryType), ("a", req.CashAccountId), ("amt", req.Amount),
                ("d", req.EntryDate?.Date), ("o", req.OwnerName), ("n", req.Notes), ("by", by));

        public Task ReverseOwnerMoneyAsync(string farmId, int id, string reason, string by) =>
            ExecAsync("SELECT sprestaurant_ownermoney_reverse(p_farmid => @f::text, p_id => @id::int, " +
                      "p_reason => @r::text, p_reversedby => @by::text)",
                ("f", farmId), ("id", id), ("r", reason), ("by", by));

        // ---- loans -------------------------------------------------------------

        public Task<List<RestaurantLoan>> ListLoansAsync(string farmId) =>
            QueryAsync<RestaurantLoan>("SELECT * FROM sprestaurant_loan_list(p_farmid => @f::text)", ("f", farmId));

        /// <summary>loanId 0 = every repayment on every loan (migration 324).</summary>
        public Task<List<RestaurantLoanPayment>> ListLoanPaymentsAsync(string farmId, int loanId) =>
            QueryAsync<RestaurantLoanPayment>(
                "SELECT * FROM sprestaurant_loan_payments(p_farmid => @f::text, p_loanid => @l::int)",
                ("f", farmId), ("l", loanId > 0 ? loanId : null));

        public Task<int> CreateLoanAsync(string farmId, RestaurantLoanCreateRequest req, string by) =>
            ScalarIntAsync("SELECT sprestaurant_loan_create(p_farmid => @f::text, p_lendername => @ln::text, " +
                           "p_principal => @p::numeric, p_amountreceived => @r::numeric, p_receivedaccountid => @a::int, " +
                           "p_loandate => @d::date, p_interestrate => @ir::numeric, p_duedate => @dd::date, " +
                           "p_notes => @n::text, p_createdby => @by::text)",
                ("f", farmId), ("ln", req.LenderName), ("p", req.Principal), ("r", req.AmountReceived),
                ("a", req.ReceivedAccountId), ("d", req.LoanDate?.Date), ("ir", req.InterestRate),
                ("dd", req.DueDate?.Date), ("n", req.Notes), ("by", by));

        public Task<int> RepayLoanAsync(string farmId, int loanId, RestaurantLoanRepayRequest req, string by) =>
            ScalarIntAsync("SELECT sprestaurant_loan_repay(p_farmid => @f::text, p_loanid => @l::int, " +
                           "p_cashaccountid => @a::int, p_principal => @p::numeric, p_interest => @i::numeric, " +
                           "p_fees => @fe::numeric, p_paymentdate => @d::date, p_notes => @n::text, p_createdby => @by::text)",
                ("f", farmId), ("l", loanId), ("a", req.CashAccountId), ("p", req.Principal), ("i", req.Interest),
                ("fe", req.Fees), ("d", req.PaymentDate?.Date), ("n", req.Notes), ("by", by));

        public Task ReverseLoanPaymentAsync(string farmId, int paymentId, string reason, string by) =>
            ExecAsync("SELECT sprestaurant_loan_payment_reverse(p_farmid => @f::text, p_loanpaymentid => @id::int, " +
                      "p_reason => @r::text, p_reversedby => @by::text)",
                ("f", farmId), ("id", paymentId), ("r", reason), ("by", by));

        public Task CancelLoanAsync(string farmId, int loanId, string reason, string by) =>
            ExecAsync("SELECT sprestaurant_loan_cancel(p_farmid => @f::text, p_loanid => @id::int, " +
                      "p_reason => @r::text, p_cancelledby => @by::text)",
                ("f", farmId), ("id", loanId), ("r", reason), ("by", by));

        // ---- counts ------------------------------------------------------------

        public Task<List<RestaurantCashCount>> ListCountsAsync(string farmId, int? accountId) =>
            QueryAsync<RestaurantCashCount>(
                "SELECT * FROM sprestaurant_cashcount_list(p_farmid => @f::text, p_cashaccountid => @a::int)",
                ("f", farmId), ("a", accountId));

        public Task<int> PostCountAsync(string farmId, RestaurantCashCountRequest req, string by) =>
            ScalarIntAsync("SELECT sprestaurant_cashcount_post(p_farmid => @f::text, p_cashaccountid => @a::int, " +
                           "p_counted => @c::numeric, p_notes => @n::text, p_createdby => @by::text)",
                ("f", farmId), ("a", req.CashAccountId), ("c", req.Counted), ("n", req.Notes), ("by", by));

        public Task ReverseCountAsync(string farmId, int countId, string reason, string by) =>
            ExecAsync("SELECT sprestaurant_cashcount_reverse(p_farmid => @f::text, p_countid => @id::int, " +
                      "p_reason => @r::text, p_reversedby => @by::text)",
                ("f", farmId), ("id", countId), ("r", reason), ("by", by));

        // ---- daily closing -----------------------------------------------------

        public async Task<RestaurantDailyClosingPreview?> PreviewDayAsync(string farmId, DateTime date) =>
            (await QueryAsync<RestaurantDailyClosingPreview>(
                "SELECT * FROM sprestaurant_dailyclosing_preview(p_farmid => @f::text, p_date => @d::date)",
                ("f", farmId), ("d", date.Date))).FirstOrDefault();

        public Task<List<RestaurantDailyClosing>> ListClosingsAsync(string farmId, int limit, DateTime? from = null, DateTime? to = null) =>
            QueryAsync<RestaurantDailyClosing>(
                "SELECT * FROM sprestaurant_dailyclosing_list(p_farmid => @f::text, p_limit => @l::int, " +
                "p_from => @fr::date, p_to => @to::date)",
                ("f", farmId), ("l", limit), ("fr", from?.Date), ("to", to?.Date));

        public Task<int> CloseDayAsync(string farmId, DateTime date, string? notes, string by) =>
            ScalarIntAsync("SELECT sprestaurant_dailyclosing_close(p_farmid => @f::text, p_date => @d::date, " +
                           "p_notes => @n::text, p_closedby => @by::text)",
                ("f", farmId), ("d", date.Date), ("n", notes), ("by", by));

        public Task ReopenDayAsync(string farmId, DateTime date, string reason, string by) =>
            ExecAsync("SELECT sprestaurant_dailyclosing_reopen(p_farmid => @f::text, p_date => @d::date, " +
                      "p_reason => @r::text, p_reopenedby => @by::text)",
                ("f", farmId), ("d", date.Date), ("r", reason), ("by", by));

        // ---- P&L ---------------------------------------------------------------

        public Task<List<RestaurantPnlLine>> PnlLinesAsync(string farmId, DateTime from, DateTime to) =>
            QueryAsync<RestaurantPnlLine>(
                "SELECT * FROM sprestaurant_report_pnl_lines(p_farmid => @f::text, p_from => @fr::date, p_to => @to::date) " +
                "ORDER BY sortorder, amount",
                ("f", farmId), ("fr", from.Date), ("to", to.Date));

        // ---- reports (migration 324) --------------------------------------------

        public Task<List<RestaurantLedgerPeriodRow>> LedgerPeriodAsync(string farmId, DateTime from, DateTime to) =>
            QueryAsync<RestaurantLedgerPeriodRow>(
                "SELECT * FROM sprestaurant_cashledger_period(p_farmid => @f::text, p_from => @fr::date, p_to => @to::date)",
                ("f", farmId), ("fr", from.Date), ("to", to.Date));

        public Task<List<RestaurantLedgerRow>> LedgerRowsAsync(string farmId, DateTime from, DateTime to, int? accountId) =>
            QueryAsync<RestaurantLedgerRow>(
                "SELECT * FROM sprestaurant_cashledger_rows(p_farmid => @f::text, p_from => @fr::date, p_to => @to::date, " +
                "p_accountid => @a::int)",
                ("f", farmId), ("fr", from.Date), ("to", to.Date), ("a", accountId));

        public Task<List<RestaurantTakingsByAccountRow>> TakingsByAccountAsync(string farmId, DateTime from, DateTime to) =>
            QueryAsync<RestaurantTakingsByAccountRow>(
                "SELECT * FROM sprestaurant_report_takings_by_account(p_farmid => @f::text, p_from => @fr::date, p_to => @to::date)",
                ("f", farmId), ("fr", from.Date), ("to", to.Date));

        public Task<List<RestaurantCashBridgeLine>> CashProfitBridgeAsync(string farmId, DateTime from, DateTime to) =>
            QueryAsync<RestaurantCashBridgeLine>(
                "SELECT * FROM sprestaurant_report_cash_profit_bridge(p_farmid => @f::text, p_from => @fr::date, p_to => @to::date) " +
                "ORDER BY sortorder",
                ("f", farmId), ("fr", from.Date), ("to", to.Date));

        // ---- plumbing ----------------------------------------------------------

        private static string? Blank(string? s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();

        private NpgsqlCommand Command(NpgsqlConnection conn, string sql, (string name, object? value)[] ps)
        {
            var cmd = new NpgsqlCommand(sql, conn);
            foreach (var (name, value) in ps)
                cmd.Parameters.AddWithValue("@" + name, value ?? DBNull.Value);
            return cmd;
        }

        private async Task<int> ScalarIntAsync(string sql, params (string, object?)[] ps)
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            await using var cmd = Command(conn, sql, ps);
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        private async Task ExecAsync(string sql, params (string, object?)[] ps)
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            await using var cmd = Command(conn, sql, ps);
            await cmd.ExecuteNonQueryAsync();
        }

        private async Task<List<T>> QueryAsync<T>(string sql, params (string, object?)[] ps) where T : new()
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            await using var cmd = Command(conn, sql, ps);
            await using var r = await cmd.ExecuteReaderAsync();
            return await ReadAll<T>(r);
        }

        /// <summary>
        /// Column -> property by name, ignoring case. Unknown columns are skipped
        /// and missing ones leave the default, so adding a column to a function
        /// never breaks this reader (the ordinal-read trap migration 292 hit).
        /// </summary>
        private static async Task<List<T>> ReadAll<T>(NpgsqlDataReader r) where T : new()
        {
            var props = typeof(T).GetProperties(BindingFlags.Public | BindingFlags.Instance)
                .Where(p => p.CanWrite)
                .ToDictionary(p => p.Name, StringComparer.OrdinalIgnoreCase);
            var map = new List<(int ordinal, PropertyInfo prop)>();
            for (var i = 0; i < r.FieldCount; i++)
                if (props.TryGetValue(r.GetName(i), out var p)) map.Add((i, p));

            var list = new List<T>();
            while (await r.ReadAsync())
            {
                var item = new T();
                foreach (var (i, p) in map)
                {
                    if (r.IsDBNull(i)) continue;
                    p.SetValue(item, ConvertTo(r.GetValue(i), p.PropertyType));
                }
                list.Add(item);
            }
            return list;
        }

        private static object? ConvertTo(object value, Type target)
        {
            var t = Nullable.GetUnderlyingType(target) ?? target;
            if (value is DateOnly d) value = d.ToDateTime(TimeOnly.MinValue);
            if (t.IsInstanceOfType(value)) return value;
            return System.Convert.ChangeType(value, t, System.Globalization.CultureInfo.InvariantCulture);
        }
    }
}
