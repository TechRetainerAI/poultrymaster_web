// Employee Loans & Advances (migrations 305/306).
//
// Every rule that matters lives in the SQL functions -- one cash row for a
// disbursement, NO cash row for a payroll deduction, append-only reversal, the
// balance re-read under FOR UPDATE at posting time. This file sends parameters
// and maps rows, exactly like PoultryLoanService does for borrowing.
//
// The one rule this layer enforces itself is that RecordRepaymentAsync refuses
// SourceType 'Payroll'. A payroll repayment is posted by approving the payroll
// run and by nothing else; letting an HTTP caller post one directly would
// create a repayment with no deduction behind it, which 305 would then have no
// way to reverse when the payroll was reopened.

using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IPoultryEmployeeLoanService
    {
        Task<PoultryEmployeeLoanPage> GetAllAsync(
            string farmId, int? staffId, string? loanType, string? status,
            string? repaymentMethod, DateTime? from, DateTime? to, string? search,
            int limit, int offset);
        Task<PoultryEmployeeLoanModel?> GetByIdAsync(int id, string farmId);
        Task<PoultryEmployeeLoanSummary> GetSummaryAsync(string farmId, DateTime? from, DateTime? to);
        Task<List<PoultryEmployeeLoanEligible>> GetEligibleAsync(string farmId, int staffId);

        Task<int> CreateAsync(PoultryEmployeeLoanCreateRequest r);
        Task UpdateAsync(int id, PoultryEmployeeLoanUpdateRequest r);
        Task DisburseAsync(int id, PoultryEmployeeLoanDisburseRequest r);
        Task CancelAsync(int id, PoultryEmployeeLoanReasonRequest r);
        Task ReverseAsync(int id, PoultryEmployeeLoanReasonRequest r);

        Task<List<PoultryEmployeeLoanRepaymentModel>> GetRepaymentsAsync(string farmId, int loanId);
        Task<int> RecordRepaymentAsync(PoultryEmployeeLoanRepaymentRequest r);
        Task ReverseRepaymentAsync(int repaymentId, PoultryEmployeeLoanReasonRequest r);

        // ---- structured payroll deductions (306) ----
        Task<List<PoultryPayrollDeductionModel>> GetDeductionsAsync(string farmId, int payrollItemId);
        Task<List<PoultryPayrollDeductionRunRow>> GetRunDeductionsAsync(string farmId, int runId);
        Task<int> SaveDeductionAsync(PoultryPayrollDeductionSaveRequest r);
        Task DeleteDeductionAsync(int deductionId, string farmId, string? deletedBy);
    }

    public class PoultryEmployeeLoanService : IPoultryEmployeeLoanService
    {
        private readonly string _cs;
        public PoultryEmployeeLoanService(string cs) => _cs = cs;

        private static object Db(object? v) => v ?? DBNull.Value;
        private static object DbDate(DateTime? v) => v.HasValue ? v.Value.Date : (object)DBNull.Value;

        private static string? Str(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? null : r.GetString(i); }
        private static int? IntN(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? null : Convert.ToInt32(r.GetValue(i)); }
        private static decimal? DecN(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? null : r.GetDecimal(i); }
        private static DateTime? DateN(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? null : r.GetDateTime(i); }
        private static bool Bool(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return !r.IsDBNull(i) && r.GetBoolean(i); }

        private static PoultryEmployeeLoanModel ReadLoan(NpgsqlDataReader r) => new()
        {
            PoultryEmployeeLoanId = r.GetInt32(r.GetOrdinal("PoultryEmployeeLoanId")),
            FarmId = Str(r, "FarmId") ?? string.Empty,
            PoultryStaffId = r.GetInt32(r.GetOrdinal("PoultryStaffId")),
            StaffName = Str(r, "StaffName"),
            StaffRole = Str(r, "StaffRole"),
            LoanNumber = Str(r, "LoanNumber"),
            LoanType = Str(r, "LoanType") ?? "EmployeeLoan",
            PrincipalAmount = r.GetDecimal(r.GetOrdinal("PrincipalAmount")),
            InterestEnabled = Bool(r, "InterestEnabled"),
            InterestAmount = r.GetDecimal(r.GetOrdinal("InterestAmount")),
            InterestRate = DecN(r, "InterestRate"),
            InterestType = Str(r, "InterestType"),
            TotalRepayable = r.GetDecimal(r.GetOrdinal("TotalRepayable")),
            DisbursementDate = r.GetDateTime(r.GetOrdinal("DisbursementDate")),
            RepaymentMethod = Str(r, "RepaymentMethod") ?? "PayrollDeduction",
            DefaultPayrollDeduction = DecN(r, "DefaultPayrollDeduction"),
            ExpectedStartDate = DateN(r, "ExpectedStartDate"),
            ExpectedEndDate = DateN(r, "ExpectedEndDate"),
            Purpose = Str(r, "Purpose"),
            Description = Str(r, "Description"),
            Notes = Str(r, "Notes"),
            Status = Str(r, "Status") ?? "Draft",
            PaidAt = DateN(r, "PaidAt"),
            TotalRepaid = r.GetDecimal(r.GetOrdinal("TotalRepaid")),
            TotalPrincipalRepaid = r.GetDecimal(r.GetOrdinal("TotalPrincipalRepaid")),
            TotalInterestRepaid = r.GetDecimal(r.GetOrdinal("TotalInterestRepaid")),
            OutstandingBalance = r.GetDecimal(r.GetOrdinal("OutstandingBalance")),
            RepaymentCount = Convert.ToInt32(r.GetValue(r.GetOrdinal("RepaymentCount"))),
            PoultryCashAccountId = IntN(r, "PoultryCashAccountId"),
            CashAccountName = Str(r, "CashAccountName"),
            PaymentMethod = Str(r, "PaymentMethod"),
            ReferenceNumber = Str(r, "ReferenceNumber"),
            PoultryCashTransactionId = IntN(r, "PoultryCashTransactionId"),
            DisbursedBy = Str(r, "DisbursedBy"),
            DisbursedAt = DateN(r, "DisbursedAt"),
            CreatedBy = Str(r, "CreatedBy"),
            CreatedAt = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            ReversedBy = Str(r, "ReversedBy"),
            ReversedAt = DateN(r, "ReversedAt"),
            ReversalReason = Str(r, "ReversalReason"),
        };

        private static PoultryEmployeeLoanRepaymentModel ReadRepayment(NpgsqlDataReader r) => new()
        {
            PoultryEmployeeLoanRepaymentId = r.GetInt32(r.GetOrdinal("PoultryEmployeeLoanRepaymentId")),
            PoultryEmployeeLoanId = r.GetInt32(r.GetOrdinal("PoultryEmployeeLoanId")),
            PoultryStaffId = r.GetInt32(r.GetOrdinal("PoultryStaffId")),
            StaffName = Str(r, "StaffName"),
            RepaymentNumber = Str(r, "RepaymentNumber"),
            RepaymentDate = r.GetDateTime(r.GetOrdinal("RepaymentDate")),
            Amount = r.GetDecimal(r.GetOrdinal("Amount")),
            PrincipalAmount = r.GetDecimal(r.GetOrdinal("PrincipalAmount")),
            InterestAmount = r.GetDecimal(r.GetOrdinal("InterestAmount")),
            SourceType = Str(r, "SourceType") ?? "ManualCash",
            PoultryPayrollRunId = IntN(r, "PoultryPayrollRunId"),
            PayrollPeriodStart = DateN(r, "PayrollPeriodStart"),
            PayrollPeriodEnd = DateN(r, "PayrollPeriodEnd"),
            PoultryPayrollItemId = IntN(r, "PoultryPayrollItemId"),
            PoultryPayrollDeductionId = IntN(r, "PoultryPayrollDeductionId"),
            PoultryCashAccountId = IntN(r, "PoultryCashAccountId"),
            CashAccountName = Str(r, "CashAccountName"),
            PaymentMethod = Str(r, "PaymentMethod"),
            ReferenceNumber = Str(r, "ReferenceNumber"),
            Description = Str(r, "Description"),
            Notes = Str(r, "Notes"),
            BalanceBefore = r.GetDecimal(r.GetOrdinal("BalanceBefore")),
            BalanceAfter = r.GetDecimal(r.GetOrdinal("BalanceAfter")),
            Status = Str(r, "Status") ?? "Posted",
            PoultryCashTransactionId = IntN(r, "PoultryCashTransactionId"),
            ReversalCashTransactionId = IntN(r, "ReversalCashTransactionId"),
            CreatedBy = Str(r, "CreatedBy"),
            CreatedAt = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            ReversedBy = Str(r, "ReversedBy"),
            ReversedAt = DateN(r, "ReversedAt"),
            ReversalReason = Str(r, "ReversalReason"),
        };

        // ==================================================================
        // Reads
        // ==================================================================
        public async Task<PoultryEmployeeLoanPage> GetAllAsync(
            string farmId, int? staffId, string? loanType, string? status,
            string? repaymentMethod, DateTime? from, DateTime? to, string? search,
            int limit, int offset)
        {
            var page = new PoultryEmployeeLoanPage();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryemployeeloan_getall(" +
                "p_farmid => @FarmId::text, p_poultrystaffid => @StaffId::int, " +
                "p_loantype => @LoanType::text, p_status => @Status::text, " +
                "p_repaymentmethod => @RepaymentMethod::text, " +
                "p_fromdate => @FromDate::date, p_todate => @ToDate::date, " +
                "p_search => @Search::text, p_limit => @Limit::int, p_offset => @Offset::int)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@StaffId", Db(staffId));
            cmd.Parameters.AddWithValue("@LoanType", Db(loanType));
            cmd.Parameters.AddWithValue("@Status", Db(status));
            cmd.Parameters.AddWithValue("@RepaymentMethod", Db(repaymentMethod));
            cmd.Parameters.AddWithValue("@FromDate", DbDate(from));
            cmd.Parameters.AddWithValue("@ToDate", DbDate(to));
            cmd.Parameters.AddWithValue("@Search", Db(search));
            cmd.Parameters.AddWithValue("@Limit", limit);
            cmd.Parameters.AddWithValue("@Offset", offset);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                page.Items.Add(ReadLoan(r));
                // Same value on every row -- the function carries it so the
                // count and the page come back in one trip.
                page.TotalCount = Convert.ToInt64(r.GetValue(r.GetOrdinal("TotalCount")));
            }
            return page;
        }

        public async Task<PoultryEmployeeLoanModel?> GetByIdAsync(int id, string farmId)
        {
            // No single-row function: the list function already resolves the
            // staff name, the account name and the repayment count, and one
            // more function that could disagree with it is worth less than a
            // filter.
            var page = await GetAllAsync(farmId, null, null, null, null, null, null, null, 1000, 0);
            return page.Items.FirstOrDefault(l => l.PoultryEmployeeLoanId == id);
        }

        public async Task<PoultryEmployeeLoanSummary> GetSummaryAsync(
            string farmId, DateTime? from, DateTime? to)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryemployeeloan_summary(" +
                "p_farmid => @FarmId::text, p_fromdate => @FromDate::date, p_todate => @ToDate::date)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@FromDate", DbDate(from));
            cmd.Parameters.AddWithValue("@ToDate", DbDate(to));
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            if (!await r.ReadAsync()) return new PoultryEmployeeLoanSummary();
            return new PoultryEmployeeLoanSummary
            {
                OutstandingTotal = r.GetDecimal(r.GetOrdinal("OutstandingTotal")),
                DisbursedInPeriod = r.GetDecimal(r.GetOrdinal("DisbursedInPeriod")),
                RepaidInPeriod = r.GetDecimal(r.GetOrdinal("RepaidInPeriod")),
                ActiveLoans = Convert.ToInt32(r.GetValue(r.GetOrdinal("ActiveLoans"))),
                StaffWithActiveLoans = Convert.ToInt32(r.GetValue(r.GetOrdinal("StaffWithActiveLoans"))),
                PaidLoans = Convert.ToInt32(r.GetValue(r.GetOrdinal("PaidLoans"))),
                DraftLoans = Convert.ToInt32(r.GetValue(r.GetOrdinal("DraftLoans"))),
            };
        }

        public async Task<List<PoultryEmployeeLoanEligible>> GetEligibleAsync(string farmId, int staffId)
        {
            var list = new List<PoultryEmployeeLoanEligible>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryemployeeloan_eligible(" +
                "p_farmid => @FarmId::text, p_poultrystaffid => @StaffId::int)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@StaffId", staffId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Add(new PoultryEmployeeLoanEligible
                {
                    PoultryEmployeeLoanId = r.GetInt32(r.GetOrdinal("PoultryEmployeeLoanId")),
                    LoanNumber = Str(r, "LoanNumber"),
                    LoanType = Str(r, "LoanType") ?? "EmployeeLoan",
                    OutstandingBalance = r.GetDecimal(r.GetOrdinal("OutstandingBalance")),
                    DefaultPayrollDeduction = DecN(r, "DefaultPayrollDeduction"),
                    RepaymentMethod = Str(r, "RepaymentMethod"),
                    DisbursementDate = r.GetDateTime(r.GetOrdinal("DisbursementDate")),
                });
            return list;
        }

        public async Task<List<PoultryEmployeeLoanRepaymentModel>> GetRepaymentsAsync(
            string farmId, int loanId)
        {
            var list = new List<PoultryEmployeeLoanRepaymentModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryemployeeloanrepayment_getall(" +
                "p_farmid => @FarmId::text, p_poultryemployeeloanid => @LoanId::int)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@LoanId", loanId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(ReadRepayment(r));
            return list;
        }

        // ==================================================================
        // Writes
        // ==================================================================
        public async Task<int> CreateAsync(PoultryEmployeeLoanCreateRequest q)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryemployeeloan_create(" +
                "p_farmid => @FarmId::text, p_poultrystaffid => @StaffId::int, " +
                "p_principalamount => @Principal::numeric, p_disbursementdate => @DisbDate::date, " +
                "p_loantype => @LoanType::text, p_interestenabled => @IntOn::boolean, " +
                "p_interestamount => @IntAmt::numeric, p_interestrate => @IntRate::numeric, " +
                "p_interesttype => @IntType::text, p_repaymentmethod => @RepayMethod::text, " +
                "p_defaultpayrolldeduction => @DefaultDed::numeric, " +
                "p_expectedstartdate => @ExpStart::date, p_expectedenddate => @ExpEnd::date, " +
                "p_purpose => @Purpose::text, p_description => @Description::text, " +
                "p_notes => @Notes::text, p_disbursenow => @DisburseNow::boolean, " +
                "p_poultrycashaccountid => @CashAccountId::int, p_paymentmethod => @PayMethod::text, " +
                "p_referencenumber => @Reference::text, p_createdby => @CreatedBy::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", q.FarmId);
            cmd.Parameters.AddWithValue("@StaffId", q.PoultryStaffId);
            cmd.Parameters.AddWithValue("@Principal", q.PrincipalAmount);
            cmd.Parameters.AddWithValue("@DisbDate", q.DisbursementDate.Date);
            cmd.Parameters.AddWithValue("@LoanType", Db(q.LoanType));
            cmd.Parameters.AddWithValue("@IntOn", q.InterestEnabled);
            cmd.Parameters.AddWithValue("@IntAmt", Db(q.InterestAmount));
            cmd.Parameters.AddWithValue("@IntRate", Db(q.InterestRate));
            cmd.Parameters.AddWithValue("@IntType", Db(q.InterestType));
            cmd.Parameters.AddWithValue("@RepayMethod", Db(q.RepaymentMethod));
            cmd.Parameters.AddWithValue("@DefaultDed", Db(q.DefaultPayrollDeduction));
            cmd.Parameters.AddWithValue("@ExpStart", DbDate(q.ExpectedStartDate));
            cmd.Parameters.AddWithValue("@ExpEnd", DbDate(q.ExpectedEndDate));
            cmd.Parameters.AddWithValue("@Purpose", Db(q.Purpose));
            cmd.Parameters.AddWithValue("@Description", Db(q.Description));
            cmd.Parameters.AddWithValue("@Notes", Db(q.Notes));
            cmd.Parameters.AddWithValue("@DisburseNow", q.DisburseNow);
            cmd.Parameters.AddWithValue("@CashAccountId", Db(q.PoultryCashAccountId));
            cmd.Parameters.AddWithValue("@PayMethod", Db(q.PaymentMethod));
            cmd.Parameters.AddWithValue("@Reference", Db(q.ReferenceNumber));
            cmd.Parameters.AddWithValue("@CreatedBy", Db(q.CreatedBy));
            await c.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateAsync(int id, PoultryEmployeeLoanUpdateRequest q)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sppoultryemployeeloan_update(" +
                "p_farmid => @FarmId::text, p_poultryemployeeloanid => @Id::int, " +
                "p_principalamount => @Principal::numeric, p_disbursementdate => @DisbDate::date, " +
                "p_loantype => @LoanType::text, p_interestenabled => @IntOn::boolean, " +
                "p_interestamount => @IntAmt::numeric, p_interestrate => @IntRate::numeric, " +
                "p_interesttype => @IntType::text, p_repaymentmethod => @RepayMethod::text, " +
                "p_defaultpayrolldeduction => @DefaultDed::numeric, " +
                "p_expectedstartdate => @ExpStart::date, p_expectedenddate => @ExpEnd::date, " +
                "p_purpose => @Purpose::text, p_description => @Description::text, " +
                "p_notes => @Notes::text, p_updatedby => @UpdatedBy::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", q.FarmId);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@Principal", Db(q.PrincipalAmount));
            cmd.Parameters.AddWithValue("@DisbDate", DbDate(q.DisbursementDate));
            cmd.Parameters.AddWithValue("@LoanType", Db(q.LoanType));
            cmd.Parameters.AddWithValue("@IntOn", Db(q.InterestEnabled));
            cmd.Parameters.AddWithValue("@IntAmt", Db(q.InterestAmount));
            cmd.Parameters.AddWithValue("@IntRate", Db(q.InterestRate));
            cmd.Parameters.AddWithValue("@IntType", Db(q.InterestType));
            cmd.Parameters.AddWithValue("@RepayMethod", Db(q.RepaymentMethod));
            cmd.Parameters.AddWithValue("@DefaultDed", Db(q.DefaultPayrollDeduction));
            cmd.Parameters.AddWithValue("@ExpStart", DbDate(q.ExpectedStartDate));
            cmd.Parameters.AddWithValue("@ExpEnd", DbDate(q.ExpectedEndDate));
            cmd.Parameters.AddWithValue("@Purpose", Db(q.Purpose));
            cmd.Parameters.AddWithValue("@Description", Db(q.Description));
            cmd.Parameters.AddWithValue("@Notes", Db(q.Notes));
            cmd.Parameters.AddWithValue("@UpdatedBy", Db(q.UpdatedBy));
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DisburseAsync(int id, PoultryEmployeeLoanDisburseRequest q)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sppoultryemployeeloan_disburse(" +
                "p_farmid => @FarmId::text, p_poultryemployeeloanid => @Id::int, " +
                "p_poultrycashaccountid => @CashAccountId::int, p_paymentmethod => @PayMethod::text, " +
                "p_referencenumber => @Reference::text, p_disbursedby => @By::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", q.FarmId);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@CashAccountId", q.PoultryCashAccountId);
            cmd.Parameters.AddWithValue("@PayMethod", Db(q.PaymentMethod));
            cmd.Parameters.AddWithValue("@Reference", Db(q.ReferenceNumber));
            cmd.Parameters.AddWithValue("@By", Db(q.DisbursedBy));
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task CancelAsync(int id, PoultryEmployeeLoanReasonRequest q)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sppoultryemployeeloan_cancel(" +
                "p_farmid => @FarmId::text, p_poultryemployeeloanid => @Id::int, " +
                "p_cancelledby => @By::text, p_reason => @Reason::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", q.FarmId);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@By", Db(q.ActionBy));
            cmd.Parameters.AddWithValue("@Reason", Db(q.Reason));
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task ReverseAsync(int id, PoultryEmployeeLoanReasonRequest q)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sppoultryemployeeloan_reverse(" +
                "p_farmid => @FarmId::text, p_poultryemployeeloanid => @Id::int, " +
                "p_reversedby => @By::text, p_reason => @Reason::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", q.FarmId);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@By", Db(q.ActionBy));
            cmd.Parameters.AddWithValue("@Reason", Db(q.Reason));
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<int> RecordRepaymentAsync(PoultryEmployeeLoanRepaymentRequest q)
        {
            // See the file header. A payroll repayment has a deduction behind it
            // and is posted by approving that payroll; one posted here would be
            // unreversible when the run was reopened.
            var source = string.IsNullOrWhiteSpace(q.SourceType) ? "ManualCash" : q.SourceType.Trim();
            if (string.Equals(source, "Payroll", StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException(
                    "A payroll repayment is recorded by approving the payroll run, not here.");

            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryemployeeloanrepayment_record(" +
                "p_farmid => @FarmId::text, p_poultryemployeeloanid => @LoanId::int, " +
                "p_amount => @Amount::numeric, p_sourcetype => @Source::text, " +
                "p_principalamount => @Principal::numeric, p_interestamount => @Interest::numeric, " +
                "p_repaymentdate => @Date::timestamp, p_poultrycashaccountid => @CashAccountId::int, " +
                "p_paymentmethod => @PayMethod::text, p_referencenumber => @Reference::text, " +
                "p_description => @Description::text, p_notes => @Notes::text, " +
                "p_createdby => @CreatedBy::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", q.FarmId);
            cmd.Parameters.AddWithValue("@LoanId", q.PoultryEmployeeLoanId);
            cmd.Parameters.AddWithValue("@Amount", q.Amount);
            cmd.Parameters.AddWithValue("@Source", source);
            cmd.Parameters.AddWithValue("@Principal", Db(q.PrincipalAmount));
            cmd.Parameters.AddWithValue("@Interest", q.InterestAmount ?? 0m);
            cmd.Parameters.AddWithValue("@Date", Db(q.RepaymentDate));
            cmd.Parameters.AddWithValue("@CashAccountId", Db(q.PoultryCashAccountId));
            cmd.Parameters.AddWithValue("@PayMethod", Db(q.PaymentMethod));
            cmd.Parameters.AddWithValue("@Reference", Db(q.ReferenceNumber));
            cmd.Parameters.AddWithValue("@Description", Db(q.Description));
            cmd.Parameters.AddWithValue("@Notes", Db(q.Notes));
            cmd.Parameters.AddWithValue("@CreatedBy", Db(q.CreatedBy));
            await c.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task ReverseRepaymentAsync(int repaymentId, PoultryEmployeeLoanReasonRequest q)
        {
            using var c = new NpgsqlConnection(_cs);
            // p_allowpayroll is deliberately NOT passed, so it defaults to
            // FALSE: a payroll-created repayment can only be undone by
            // reopening its payroll (spec section 60), and the SQL refuses it
            // here with a message naming the run.
            using var cmd = new NpgsqlCommand(
                "SELECT sppoultryemployeeloanrepayment_reverse(" +
                "p_farmid => @FarmId::text, " +
                "p_poultryemployeeloanrepaymentid => @Id::int, " +
                "p_reversedby => @By::text, p_reason => @Reason::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", q.FarmId);
            cmd.Parameters.AddWithValue("@Id", repaymentId);
            cmd.Parameters.AddWithValue("@By", Db(q.ActionBy));
            cmd.Parameters.AddWithValue("@Reason", Db(q.Reason));
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // ==================================================================
        // Structured payroll deductions (306)
        // ==================================================================
        public async Task<List<PoultryPayrollDeductionModel>> GetDeductionsAsync(
            string farmId, int payrollItemId)
        {
            var list = new List<PoultryPayrollDeductionModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultrypayrollitemdeduction_getall(" +
                "p_farmid => @FarmId::text, p_poultrypayrollitemid => @ItemId::int)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ItemId", payrollItemId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Add(new PoultryPayrollDeductionModel
                {
                    PoultryPayrollItemDeductionId = IntN(r, "PoultryPayrollItemDeductionId"),
                    PoultryPayrollItemId = r.GetInt32(r.GetOrdinal("PoultryPayrollItemId")),
                    PoultryStaffId = r.GetInt32(r.GetOrdinal("PoultryStaffId")),
                    DeductionType = Str(r, "DeductionType") ?? "OtherDeduction",
                    Amount = r.GetDecimal(r.GetOrdinal("Amount")),
                    PoultryEmployeeLoanId = IntN(r, "PoultryEmployeeLoanId"),
                    LoanNumber = Str(r, "LoanNumber"),
                    LoanType = Str(r, "LoanType"),
                    LoanOutstanding = DecN(r, "LoanOutstanding"),
                    PoultryEmployeeLoanRepaymentId = IntN(r, "PoultryEmployeeLoanRepaymentId"),
                    Description = Str(r, "Description"),
                    Reference = Str(r, "Reference"),
                    Status = Str(r, "Status") ?? "Draft",
                    IsLegacy = Bool(r, "IsLegacy"),
                    CreatedBy = Str(r, "CreatedBy"),
                    CreatedAt = DateN(r, "CreatedAt"),
                });
            return list;
        }

        public async Task<List<PoultryPayrollDeductionRunRow>> GetRunDeductionsAsync(
            string farmId, int runId)
        {
            var list = new List<PoultryPayrollDeductionRunRow>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultrypayrollitemdeduction_getforrun(" +
                "p_farmid => @FarmId::text, p_poultrypayrollrunid => @RunId::int)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@RunId", runId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Add(new PoultryPayrollDeductionRunRow
                {
                    PoultryPayrollItemId = r.GetInt32(r.GetOrdinal("PoultryPayrollItemId")),
                    PoultryStaffId = r.GetInt32(r.GetOrdinal("PoultryStaffId")),
                    StaffName = Str(r, "StaffName"),
                    Deductions = r.GetDecimal(r.GetOrdinal("Deductions")),
                    LegacyDeductions = r.GetDecimal(r.GetOrdinal("LegacyDeductions")),
                    StructuredTotal = r.GetDecimal(r.GetOrdinal("StructuredTotal")),
                    StructuredCount = Convert.ToInt32(r.GetValue(r.GetOrdinal("StructuredCount"))),
                    LoanRepaymentTotal = r.GetDecimal(r.GetOrdinal("LoanRepaymentTotal")),
                    ActiveLoanCount = Convert.ToInt32(r.GetValue(r.GetOrdinal("ActiveLoanCount"))),
                    ActiveLoanOutstanding = r.GetDecimal(r.GetOrdinal("ActiveLoanOutstanding")),
                    SuggestedDeduction = r.GetDecimal(r.GetOrdinal("SuggestedDeduction")),
                });
            return list;
        }

        public async Task<int> SaveDeductionAsync(PoultryPayrollDeductionSaveRequest q)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultrypayrollitemdeduction_save(" +
                "p_farmid => @FarmId::text, p_poultrypayrollitemid => @ItemId::int, " +
                "p_deductiontype => @Type::text, p_amount => @Amount::numeric, " +
                "p_poultryemployeeloanid => @LoanId::int, p_description => @Description::text, " +
                "p_reference => @Reference::text, " +
                "p_poultrypayrollitemdeductionid => @Id::int, p_savedby => @By::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", q.FarmId);
            cmd.Parameters.AddWithValue("@ItemId", q.PoultryPayrollItemId);
            cmd.Parameters.AddWithValue("@Type", q.DeductionType);
            cmd.Parameters.AddWithValue("@Amount", q.Amount);
            cmd.Parameters.AddWithValue("@LoanId", Db(q.PoultryEmployeeLoanId));
            cmd.Parameters.AddWithValue("@Description", Db(q.Description));
            cmd.Parameters.AddWithValue("@Reference", Db(q.Reference));
            cmd.Parameters.AddWithValue("@Id", Db(q.PoultryPayrollItemDeductionId));
            cmd.Parameters.AddWithValue("@By", Db(q.SavedBy));
            await c.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task DeleteDeductionAsync(int deductionId, string farmId, string? deletedBy)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sppoultrypayrollitemdeduction_delete(" +
                "p_farmid => @FarmId::text, p_poultrypayrollitemdeductionid => @Id::int, " +
                "p_deletedby => @By::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Id", deductionId);
            cmd.Parameters.AddWithValue("@By", Db(deletedBy));
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }
    }
}
