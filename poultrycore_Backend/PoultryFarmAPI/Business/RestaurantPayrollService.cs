// =============================================================================
// Restaurant payroll and staff loans & advances (migration 326).
//
// Every rule lives in the sprestaurant_* functions, each one database
// transaction: a payout's ledger row and balance, an approval's repayments, a
// payroll payment's net-pay posting all commit together or not at all. This
// class only passes parameters and reads rows back. Refusals (P0001) become a
// 400 through RestaurantBusinessRuleFilter.
// =============================================================================

using System.Reflection;
using System.Text.Json;
using Npgsql;
using NpgsqlTypes;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IRestaurantPayrollService
    {
        // Staff loans
        Task<List<RestaurantStaffLoan>> ListLoansAsync(string farmId, string? status, int? staffId);
        Task<RestaurantStaffLoanSummary> LoanSummaryAsync(string farmId, DateTime? from, DateTime? to);
        Task<List<RestaurantStaffLoanRepayment>> LoanRepaymentsAsync(string farmId, int? loanId);
        Task<List<RestaurantStaffLoanEligible>> EligibleAsync(string farmId, int staffId, int? excludeLineId);
        Task<List<RestaurantStaffLoanStaffRow>> StaffReportAsync(string farmId, DateTime? from, DateTime? to);
        Task<int> CreateLoanAsync(string farmId, RestaurantStaffLoanCreateRequest req, string by);
        Task UpdateLoanAsync(string farmId, int loanId, RestaurantStaffLoanUpdateRequest req);
        Task DisburseLoanAsync(string farmId, int loanId, RestaurantStaffLoanDisburseRequest req, string by);
        Task CancelLoanAsync(string farmId, int loanId, string? reason, string by);
        Task ReverseLoanAsync(string farmId, int loanId, string? reason, string by);
        Task<int> RepayLoanAsync(string farmId, int loanId, RestaurantStaffLoanRepayRequest req, string by);
        Task ReverseRepaymentAsync(string farmId, int repaymentId, string? reason, string by);

        // Payroll
        Task<List<RestaurantPayrollRun>> ListRunsAsync(string farmId, string? status);
        Task<RestaurantPayrollRunDetail?> GetRunAsync(string farmId, int runId);
        Task<int> CreateRunAsync(string farmId, RestaurantPayrollRunRequest req, string by);
        Task UpdateRunAsync(string farmId, int runId, RestaurantPayrollRunRequest req);
        Task DeleteRunAsync(string farmId, int runId);
        Task<int> SaveLineAsync(string farmId, int runId, RestaurantPayrollLineRequest req, string by);
        Task DeleteLineAsync(string farmId, int lineId);
        Task<int> AddAllStaffAsync(string farmId, int runId, string by);
        Task<int> ApproveRunAsync(string farmId, int runId, string by);
        Task<int> ReopenRunAsync(string farmId, int runId, string? reason, string by);
        Task<int> CancelRunAsync(string farmId, int runId, string? reason, string by);
        Task MarkPaidAsync(string farmId, int runId, RestaurantPayrollPayRequest req, string by);
        Task<List<RestaurantPayrollReportRow>> PayrollReportAsync(string farmId, DateTime from, DateTime to);
    }

    public class RestaurantPayrollService : IRestaurantPayrollService
    {
        private readonly string _cs;
        public RestaurantPayrollService(string connectionString) { _cs = connectionString; }

        private static string? Blank(string? s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();

        // ── Staff loans ────────────────────────────────────────────────────

        public Task<List<RestaurantStaffLoan>> ListLoansAsync(string farmId, string? status, int? staffId) =>
            QueryAsync<RestaurantStaffLoan>(
                "SELECT * FROM sprestaurant_staffloan_list(p_farmid => @f::text, p_status => @s::text, p_staffid => @st::int)",
                ("f", farmId), ("s", Blank(status)), ("st", staffId));

        public async Task<RestaurantStaffLoanSummary> LoanSummaryAsync(string farmId, DateTime? from, DateTime? to) =>
            (await QueryAsync<RestaurantStaffLoanSummary>(
                "SELECT * FROM sprestaurant_staffloan_summary(p_farmid => @f::text, p_from => @a::date, p_to => @b::date)",
                ("f", farmId), ("a", from?.Date), ("b", to?.Date))).FirstOrDefault() ?? new();

        public Task<List<RestaurantStaffLoanRepayment>> LoanRepaymentsAsync(string farmId, int? loanId) =>
            QueryAsync<RestaurantStaffLoanRepayment>(
                "SELECT * FROM sprestaurant_staffloan_repayments(p_farmid => @f::text, p_loanid => @l::int)",
                ("f", farmId), ("l", loanId));

        public Task<List<RestaurantStaffLoanEligible>> EligibleAsync(string farmId, int staffId, int? excludeLineId) =>
            QueryAsync<RestaurantStaffLoanEligible>(
                "SELECT * FROM sprestaurant_staffloan_eligible(p_farmid => @f::text, p_staffid => @s::int, p_excludelineid => @x::int)",
                ("f", farmId), ("s", staffId), ("x", excludeLineId));

        public Task<List<RestaurantStaffLoanStaffRow>> StaffReportAsync(string farmId, DateTime? from, DateTime? to) =>
            QueryAsync<RestaurantStaffLoanStaffRow>(
                "SELECT * FROM sprestaurant_staffloan_staffreport(p_farmid => @f::text, p_from => @a::date, p_to => @b::date)",
                ("f", farmId), ("a", from?.Date), ("b", to?.Date));

        public Task<int> CreateLoanAsync(string farmId, RestaurantStaffLoanCreateRequest req, string by) =>
            ScalarIntAsync(
                "SELECT sprestaurant_staffloan_create(p_farmid => @f::text, p_staffid => @s::int, p_loantype => @t::text, " +
                "p_principal => @p::numeric, p_interest => @i::numeric, p_repaymentmethod => @m::text, " +
                "p_defaultdeduction => @d::numeric, p_expectedenddate => @e::date, p_reference => @r::text, " +
                "p_notes => @n::text, p_createdby => @by::text, p_disbursenow => @now::boolean, " +
                "p_cashaccountid => @a::int, p_disbursementdate => @dd::date)",
                ("f", farmId), ("s", req.RestaurantStaffId), ("t", req.LoanType), ("p", req.PrincipalAmount),
                ("i", req.InterestAmount), ("m", req.RepaymentMethod), ("d", req.DefaultPayrollDeduction),
                ("e", req.ExpectedEndDate?.Date), ("r", Blank(req.Reference)), ("n", Blank(req.Notes)), ("by", by),
                ("now", req.DisburseNow), ("a", req.DisburseNow ? req.CashAccountId : null),
                ("dd", req.DisburseNow ? req.DisbursementDate?.Date : null));

        public Task UpdateLoanAsync(string farmId, int loanId, RestaurantStaffLoanUpdateRequest req) =>
            ExecAsync(
                "SELECT sprestaurant_staffloan_update(p_farmid => @f::text, p_loanid => @l::int, p_loantype => @t::text, " +
                "p_principal => @p::numeric, p_interest => @i::numeric, p_repaymentmethod => @m::text, " +
                "p_defaultdeduction => @d::numeric, p_expectedenddate => @e::date, p_reference => @r::text, p_notes => @n::text)",
                ("f", farmId), ("l", loanId), ("t", req.LoanType), ("p", req.PrincipalAmount), ("i", req.InterestAmount),
                ("m", req.RepaymentMethod), ("d", req.DefaultPayrollDeduction), ("e", req.ExpectedEndDate?.Date),
                ("r", Blank(req.Reference)), ("n", Blank(req.Notes)));

        public Task DisburseLoanAsync(string farmId, int loanId, RestaurantStaffLoanDisburseRequest req, string by) =>
            ExecAsync(
                "SELECT sprestaurant_staffloan_disburse(p_farmid => @f::text, p_loanid => @l::int, p_cashaccountid => @a::int, " +
                "p_date => @d::date, p_reference => @r::text, p_by => @by::text)",
                ("f", farmId), ("l", loanId), ("a", req.CashAccountId), ("d", req.DisbursementDate?.Date),
                ("r", Blank(req.Reference)), ("by", by));

        public Task CancelLoanAsync(string farmId, int loanId, string? reason, string by) =>
            ExecAsync("SELECT sprestaurant_staffloan_cancel(p_farmid => @f::text, p_loanid => @l::int, p_reason => @r::text, p_by => @by::text)",
                ("f", farmId), ("l", loanId), ("r", Blank(reason)), ("by", by));

        public Task ReverseLoanAsync(string farmId, int loanId, string? reason, string by) =>
            ExecAsync("SELECT sprestaurant_staffloan_reverse(p_farmid => @f::text, p_loanid => @l::int, p_reason => @r::text, p_by => @by::text)",
                ("f", farmId), ("l", loanId), ("r", Blank(reason)), ("by", by));

        public Task<int> RepayLoanAsync(string farmId, int loanId, RestaurantStaffLoanRepayRequest req, string by)
        {
            if (string.Equals(req.SourceType, "Payroll", StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Payroll repayments are created by approving a payroll run.");
            return ScalarIntAsync(
                "SELECT sprestaurant_staffloanrepayment_record(p_farmid => @f::text, p_loanid => @l::int, p_amount => @amt::numeric, " +
                "p_sourcetype => @s::text, p_cashaccountid => @a::int, p_date => @d::date, p_reference => @r::text, " +
                "p_notes => @n::text, p_by => @by::text)",
                ("f", farmId), ("l", loanId), ("amt", req.Amount), ("s", req.SourceType), ("a", req.CashAccountId),
                ("d", req.RepaymentDate?.Date), ("r", Blank(req.Reference)), ("n", Blank(req.Notes)), ("by", by));
        }

        // p_allowpayroll stays FALSE: payroll repayments are reversed only through the payroll run.
        public Task ReverseRepaymentAsync(string farmId, int repaymentId, string? reason, string by) =>
            ExecAsync("SELECT sprestaurant_staffloanrepayment_reverse(p_farmid => @f::text, p_repaymentid => @id::int, " +
                      "p_reason => @r::text, p_by => @by::text)",
                ("f", farmId), ("id", repaymentId), ("r", Blank(reason)), ("by", by));

        // ── Payroll ────────────────────────────────────────────────────────

        public Task<List<RestaurantPayrollRun>> ListRunsAsync(string farmId, string? status) =>
            QueryAsync<RestaurantPayrollRun>("SELECT * FROM sprestaurant_payrollrun_list(p_farmid => @f::text, p_status => @s::text)",
                ("f", farmId), ("s", Blank(status)));

        public async Task<RestaurantPayrollRunDetail?> GetRunAsync(string farmId, int runId)
        {
            var run = (await ListRunsAsync(farmId, null)).FirstOrDefault(r => r.PayrollRunId == runId);
            if (run == null) return null;
            return new RestaurantPayrollRunDetail
            {
                Run = run,
                Lines = await QueryAsync<RestaurantPayrollLine>(
                    "SELECT * FROM sprestaurant_payrollrun_lines(p_farmid => @f::text, p_runid => @r::int)", ("f", farmId), ("r", runId)),
                Deductions = await QueryAsync<RestaurantPayrollDeduction>(
                    "SELECT * FROM sprestaurant_payrollrun_deductions(p_farmid => @f::text, p_runid => @r::int)", ("f", farmId), ("r", runId)),
            };
        }

        public Task<int> CreateRunAsync(string farmId, RestaurantPayrollRunRequest req, string by) =>
            ScalarIntAsync(
                "SELECT sprestaurant_payrollrun_create(p_farmid => @f::text, p_periodstart => @a::date, p_periodend => @b::date, " +
                "p_paydate => @p::date, p_cashaccountid => @c::int, p_notes => @n::text, p_by => @by::text)",
                ("f", farmId), ("a", req.PeriodStart.Date), ("b", req.PeriodEnd.Date), ("p", req.PayDate?.Date),
                ("c", req.CashAccountId), ("n", Blank(req.Notes)), ("by", by));

        public Task UpdateRunAsync(string farmId, int runId, RestaurantPayrollRunRequest req) =>
            ExecAsync(
                "SELECT sprestaurant_payrollrun_update(p_farmid => @f::text, p_runid => @r::int, p_periodstart => @a::date, " +
                "p_periodend => @b::date, p_paydate => @p::date, p_cashaccountid => @c::int, p_notes => @n::text)",
                ("f", farmId), ("r", runId), ("a", req.PeriodStart.Date), ("b", req.PeriodEnd.Date), ("p", req.PayDate?.Date),
                ("c", req.CashAccountId), ("n", Blank(req.Notes)));

        public Task DeleteRunAsync(string farmId, int runId) =>
            ExecAsync("SELECT sprestaurant_payrollrun_delete(p_farmid => @f::text, p_runid => @r::int)", ("f", farmId), ("r", runId));

        public async Task<int> SaveLineAsync(string farmId, int runId, RestaurantPayrollLineRequest req, string by)
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            await using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_payrollline_save(p_farmid => @f::text, p_runid => @r::int, p_staffid => @s::int, " +
                "p_basicpay => @bp::numeric, p_allowances => @al::numeric, p_overtime => @ot::numeric, p_bonus => @bo::numeric, " +
                "p_otherdeductions => @od::numeric, p_paymentmethod => @pm::text, p_notes => @n::text, p_loans => @ld, p_by => @by::text)", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            cmd.Parameters.AddWithValue("@r", runId);
            cmd.Parameters.AddWithValue("@s", req.RestaurantStaffId);
            cmd.Parameters.AddWithValue("@bp", req.BasicPay);
            cmd.Parameters.AddWithValue("@al", req.Allowances);
            cmd.Parameters.AddWithValue("@ot", req.Overtime);
            cmd.Parameters.AddWithValue("@bo", req.Bonus);
            cmd.Parameters.AddWithValue("@od", req.OtherDeductions);
            cmd.Parameters.AddWithValue("@pm", (object?)Blank(req.PaymentMethod) ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@n", (object?)Blank(req.Notes) ?? DBNull.Value);
            cmd.Parameters.Add(new NpgsqlParameter("@ld", NpgsqlDbType.Jsonb)
            {
                Value = req.LoanDeductions == null
                    ? DBNull.Value
                    : JsonSerializer.Serialize(req.LoanDeductions.Select(d => new { loanId = d.LoanId, amount = d.Amount })),
            });
            cmd.Parameters.AddWithValue("@by", by);
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public Task DeleteLineAsync(string farmId, int lineId) =>
            ExecAsync("SELECT sprestaurant_payrollline_delete(p_farmid => @f::text, p_lineid => @l::int)", ("f", farmId), ("l", lineId));

        public Task<int> AddAllStaffAsync(string farmId, int runId, string by) =>
            ScalarIntAsync("SELECT sprestaurant_payrollrun_addallstaff(p_farmid => @f::text, p_runid => @r::int, p_by => @by::text)",
                ("f", farmId), ("r", runId), ("by", by));

        public Task<int> ApproveRunAsync(string farmId, int runId, string by) =>
            ScalarIntAsync("SELECT sprestaurant_payrollrun_approve(p_farmid => @f::text, p_runid => @r::int, p_by => @by::text)",
                ("f", farmId), ("r", runId), ("by", by));

        public Task<int> ReopenRunAsync(string farmId, int runId, string? reason, string by) =>
            ScalarIntAsync("SELECT sprestaurant_payrollrun_unapprove(p_farmid => @f::text, p_runid => @r::int, p_reason => @x::text, p_by => @by::text)",
                ("f", farmId), ("r", runId), ("x", Blank(reason)), ("by", by));

        public Task<int> CancelRunAsync(string farmId, int runId, string? reason, string by) =>
            ScalarIntAsync("SELECT sprestaurant_payrollrun_cancel(p_farmid => @f::text, p_runid => @r::int, p_reason => @x::text, p_by => @by::text)",
                ("f", farmId), ("r", runId), ("x", Blank(reason)), ("by", by));

        public Task MarkPaidAsync(string farmId, int runId, RestaurantPayrollPayRequest req, string by) =>
            ExecAsync("SELECT sprestaurant_payrollrun_markpaid(p_farmid => @f::text, p_runid => @r::int, p_paydate => @d::date, " +
                      "p_cashaccountid => @a::int, p_by => @by::text)",
                ("f", farmId), ("r", runId), ("d", req.PayDate?.Date), ("a", req.CashAccountId), ("by", by));

        public Task<List<RestaurantPayrollReportRow>> PayrollReportAsync(string farmId, DateTime from, DateTime to) =>
            QueryAsync<RestaurantPayrollReportRow>(
                "SELECT * FROM sprestaurant_payroll_report(p_farmid => @f::text, p_from => @a::date, p_to => @b::date)",
                ("f", farmId), ("a", from.Date), ("b", to.Date));

        // ── Plumbing (same as RestaurantFinanceService) ───────────────────

        private static NpgsqlCommand Command(NpgsqlConnection conn, string sql, (string name, object? value)[] ps)
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
            var v = await cmd.ExecuteScalarAsync();
            return v == null || v is DBNull ? 0 : Convert.ToInt32(v);
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
