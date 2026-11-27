// Generic Employee Loans & Advances (migration 387).
//
// Every rule that matters lives in the SQL functions -- one cash row for a
// disbursement, NO cash row for a payroll deduction, append-only reversal, the
// balance re-read under FOR UPDATE at posting time. This file sends parameters
// and maps rows.
//
// The one rule this layer enforces itself is that RecordRepaymentAsync refuses
// SourceType 'Payroll'. A payroll repayment is posted by approving the payroll
// run and by nothing else.

using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IGenericEmployeeLoanService
    {
        Task<GenericEmployeeLoanPage> GetAllAsync(
            string farmId, int? staffId, string? loanType, string? status,
            string? repaymentMethod, DateTime? from, DateTime? to, string? search,
            int limit, int offset);
        Task<GenericEmployeeLoanModel?> GetByIdAsync(int id, string farmId);
        Task<GenericEmployeeLoanSummary> GetSummaryAsync(string farmId, DateTime? from, DateTime? to);
        Task<List<GenericEmployeeLoanEligible>> GetEligibleAsync(string farmId, int staffId);

        Task<int> CreateAsync(GenericEmployeeLoanCreateRequest r);
        Task UpdateAsync(int id, GenericEmployeeLoanUpdateRequest r);
        Task DisburseAsync(int id, GenericEmployeeLoanDisburseRequest r);
        Task CancelAsync(int id, GenericEmployeeLoanReasonRequest r);
        Task ReverseAsync(int id, GenericEmployeeLoanReasonRequest r);

        Task<List<GenericEmployeeLoanRepaymentModel>> GetRepaymentsAsync(string farmId, int loanId);
        Task<int> RecordRepaymentAsync(GenericEmployeeLoanRepaymentRequest r);
        Task ReverseRepaymentAsync(int repaymentId, GenericEmployeeLoanReasonRequest r);
    }

    public class GenericEmployeeLoanService : IGenericEmployeeLoanService
    {
        private readonly string _cs;
        public GenericEmployeeLoanService(string cs) => _cs = cs;

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

        private static GenericEmployeeLoanModel ReadLoan(NpgsqlDataReader r) => new()
        {
            GenericEmployeeLoanId = r.GetInt32(r.GetOrdinal("GenericEmployeeLoanId")),
            FarmId = Str(r, "FarmId") ?? string.Empty,
            GenericStaffId = r.GetInt32(r.GetOrdinal("GenericStaffId")),
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
            GenericCashAccountId = IntN(r, "GenericCashAccountId"),
            CashAccountName = Str(r, "CashAccountName"),
            PaymentMethod = Str(r, "PaymentMethod"),
            ReferenceNumber = Str(r, "ReferenceNumber"),
            GenericCashTransactionId = IntN(r, "GenericCashTransactionId"),
            DisbursedBy = Str(r, "DisbursedBy"),
            DisbursedAt = DateN(r, "DisbursedAt"),
            CreatedBy = Str(r, "CreatedBy"),
            CreatedAt = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            ReversedBy = Str(r, "ReversedBy"),
            ReversedAt = DateN(r, "ReversedAt"),
            ReversalReason = Str(r, "ReversalReason"),
        };

        private static GenericEmployeeLoanRepaymentModel ReadRepayment(NpgsqlDataReader r) => new()
        {
            GenericEmployeeLoanRepaymentId = r.GetInt32(r.GetOrdinal("GenericEmployeeLoanRepaymentId")),
            GenericEmployeeLoanId = r.GetInt32(r.GetOrdinal("GenericEmployeeLoanId")),
            GenericStaffId = r.GetInt32(r.GetOrdinal("GenericStaffId")),
            StaffName = Str(r, "StaffName"),
            RepaymentNumber = Str(r, "RepaymentNumber"),
            RepaymentDate = r.GetDateTime(r.GetOrdinal("RepaymentDate")),
            Amount = r.GetDecimal(r.GetOrdinal("Amount")),
            PrincipalAmount = r.GetDecimal(r.GetOrdinal("PrincipalAmount")),
            InterestAmount = r.GetDecimal(r.GetOrdinal("InterestAmount")),
            SourceType = Str(r, "SourceType") ?? "ManualCash",
            GenericPayrollRunId = IntN(r, "GenericPayrollRunId"),
            PayrollPeriodStart = DateN(r, "PayrollPeriodStart"),
            PayrollPeriodEnd = DateN(r, "PayrollPeriodEnd"),
            GenericPayrollItemId = IntN(r, "GenericPayrollItemId"),
            GenericCashAccountId = IntN(r, "GenericCashAccountId"),
            CashAccountName = Str(r, "CashAccountName"),
            PaymentMethod = Str(r, "PaymentMethod"),
            ReferenceNumber = Str(r, "ReferenceNumber"),
            Description = Str(r, "Description"),
            Notes = Str(r, "Notes"),
            BalanceBefore = r.GetDecimal(r.GetOrdinal("BalanceBefore")),
            BalanceAfter = r.GetDecimal(r.GetOrdinal("BalanceAfter")),
            Status = Str(r, "Status") ?? "Posted",
            GenericCashTransactionId = IntN(r, "GenericCashTransactionId"),
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
        public async Task<GenericEmployeeLoanPage> GetAllAsync(
            string farmId, int? staffId, string? loanType, string? status,
            string? repaymentMethod, DateTime? from, DateTime? to, string? search,
            int limit, int offset)
        {
            var page = new GenericEmployeeLoanPage();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spgenericemployeeloan_getall(" +
                "p_farmid => @FarmId::text, p_genericstaffid => @StaffId::int, " +
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
                page.TotalCount = Convert.ToInt64(r.GetValue(r.GetOrdinal("TotalCount")));
            }
            return page;
        }

        public async Task<GenericEmployeeLoanModel?> GetByIdAsync(int id, string farmId)
        {
            var page = await GetAllAsync(farmId, null, null, null, null, null, null, null, 1000, 0);
            return page.Items.FirstOrDefault(l => l.GenericEmployeeLoanId == id);
        }

        public async Task<GenericEmployeeLoanSummary> GetSummaryAsync(
            string farmId, DateTime? from, DateTime? to)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spgenericemployeeloan_summary(" +
                "p_farmid => @FarmId::text, p_fromdate => @FromDate::date, p_todate => @ToDate::date)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@FromDate", DbDate(from));
            cmd.Parameters.AddWithValue("@ToDate", DbDate(to));
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            if (!await r.ReadAsync()) return new GenericEmployeeLoanSummary();
            return new GenericEmployeeLoanSummary
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

        public async Task<List<GenericEmployeeLoanEligible>> GetEligibleAsync(string farmId, int staffId)
        {
            var list = new List<GenericEmployeeLoanEligible>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spgenericemployeeloan_eligible(" +
                "p_farmid => @FarmId::text, p_genericstaffid => @StaffId::int)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@StaffId", staffId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Add(new GenericEmployeeLoanEligible
                {
                    GenericEmployeeLoanId = r.GetInt32(r.GetOrdinal("GenericEmployeeLoanId")),
                    LoanNumber = Str(r, "LoanNumber"),
                    LoanType = Str(r, "LoanType") ?? "EmployeeLoan",
                    OutstandingBalance = r.GetDecimal(r.GetOrdinal("OutstandingBalance")),
                    DefaultPayrollDeduction = DecN(r, "DefaultPayrollDeduction"),
                    RepaymentMethod = Str(r, "RepaymentMethod"),
                    DisbursementDate = r.GetDateTime(r.GetOrdinal("DisbursementDate")),
                });
            return list;
        }

        public async Task<List<GenericEmployeeLoanRepaymentModel>> GetRepaymentsAsync(
            string farmId, int loanId)
        {
            var list = new List<GenericEmployeeLoanRepaymentModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spgenericemployeeloanrepayment_getall(" +
                "p_farmid => @FarmId::text, p_genericemployeeloanid => @LoanId::int)", c);
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
        public async Task<int> CreateAsync(GenericEmployeeLoanCreateRequest q)
        {
            using var c = new NpgsqlConnection(_cs);
            // 501: the project split (if any) is saved in the same statement.
            var withProject = GenericProjectAttach.Has(q.Projects);
            const string createCall = "spgenericemployeeloan_create(" +
                "p_farmid => @FarmId::text, p_genericstaffid => @StaffId::int, " +
                "p_principalamount => @Principal::numeric, p_disbursementdate => @DisbDate::date, " +
                "p_loantype => @LoanType::text, p_interestenabled => @IntOn::boolean, " +
                "p_interestamount => @IntAmt::numeric, p_interestrate => @IntRate::numeric, " +
                "p_interesttype => @IntType::text, p_repaymentmethod => @RepayMethod::text, " +
                "p_defaultpayrolldeduction => @DefaultDed::numeric, " +
                "p_expectedstartdate => @ExpStart::date, p_expectedenddate => @ExpEnd::date, " +
                "p_purpose => @Purpose::text, p_description => @Description::text, " +
                "p_notes => @Notes::text, p_disbursenow => @DisburseNow::boolean, " +
                "p_genericcashaccountid => @CashAccountId::int, p_paymentmethod => @PayMethod::text, " +
                "p_referencenumber => @Reference::text, p_createdby => @CreatedBy::text)";
            using var cmd = new NpgsqlCommand(withProject
                ? GenericProjectAttach.WrapInsert(createCall, "EmployeeLoan")
                : "SELECT * FROM " + createCall, c);
            if (withProject) GenericProjectAttach.AddParams(cmd, q.FarmId, q.Projects, q.CreatedBy);
            cmd.Parameters.AddWithValue("@FarmId", q.FarmId);
            cmd.Parameters.AddWithValue("@StaffId", q.GenericStaffId);
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
            cmd.Parameters.AddWithValue("@CashAccountId", Db(q.GenericCashAccountId));
            cmd.Parameters.AddWithValue("@PayMethod", Db(q.PaymentMethod));
            cmd.Parameters.AddWithValue("@Reference", Db(q.ReferenceNumber));
            cmd.Parameters.AddWithValue("@CreatedBy", Db(q.CreatedBy));
            await c.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateAsync(int id, GenericEmployeeLoanUpdateRequest q)
        {
            using var c = new NpgsqlConnection(_cs);
            var withProject = GenericProjectAttach.Has(q.Projects);
            const string updateCall = "spgenericemployeeloan_update(" +
                "p_farmid => @FarmId::text, p_genericemployeeloanid => @Id::int, " +
                "p_principalamount => @Principal::numeric, p_disbursementdate => @DisbDate::date, " +
                "p_loantype => @LoanType::text, p_interestenabled => @IntOn::boolean, " +
                "p_interestamount => @IntAmt::numeric, p_interestrate => @IntRate::numeric, " +
                "p_interesttype => @IntType::text, p_repaymentmethod => @RepayMethod::text, " +
                "p_defaultpayrolldeduction => @DefaultDed::numeric, " +
                "p_expectedstartdate => @ExpStart::date, p_expectedenddate => @ExpEnd::date, " +
                "p_purpose => @Purpose::text, p_description => @Description::text, " +
                "p_notes => @Notes::text, p_updatedby => @UpdatedBy::text)";
            using var cmd = new NpgsqlCommand(withProject
                ? GenericProjectAttach.WrapUpdate(updateCall, "EmployeeLoan")
                : "SELECT " + updateCall, c);
            if (withProject) GenericProjectAttach.AddParams(cmd, q.FarmId, q.Projects, q.UpdatedBy, id);
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

        public async Task DisburseAsync(int id, GenericEmployeeLoanDisburseRequest q)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT spgenericemployeeloan_disburse(" +
                "p_farmid => @FarmId::text, p_genericemployeeloanid => @Id::int, " +
                "p_genericcashaccountid => @CashAccountId::int, p_paymentmethod => @PayMethod::text, " +
                "p_referencenumber => @Reference::text, p_disbursedby => @By::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", q.FarmId);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@CashAccountId", q.GenericCashAccountId);
            cmd.Parameters.AddWithValue("@PayMethod", Db(q.PaymentMethod));
            cmd.Parameters.AddWithValue("@Reference", Db(q.ReferenceNumber));
            cmd.Parameters.AddWithValue("@By", Db(q.DisbursedBy));
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task CancelAsync(int id, GenericEmployeeLoanReasonRequest q)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT spgenericemployeeloan_cancel(" +
                "p_farmid => @FarmId::text, p_genericemployeeloanid => @Id::int, " +
                "p_cancelledby => @By::text, p_reason => @Reason::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", q.FarmId);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@By", Db(q.ActionBy));
            cmd.Parameters.AddWithValue("@Reason", Db(q.Reason));
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task ReverseAsync(int id, GenericEmployeeLoanReasonRequest q)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT spgenericemployeeloan_reverse(" +
                "p_farmid => @FarmId::text, p_genericemployeeloanid => @Id::int, " +
                "p_reversedby => @By::text, p_reason => @Reason::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", q.FarmId);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@By", Db(q.ActionBy));
            cmd.Parameters.AddWithValue("@Reason", Db(q.Reason));
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<int> RecordRepaymentAsync(GenericEmployeeLoanRepaymentRequest q)
        {
            var source = string.IsNullOrWhiteSpace(q.SourceType) ? "ManualCash" : q.SourceType.Trim();
            if (string.Equals(source, "Payroll", StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException(
                    "A payroll repayment is recorded by approving the payroll run, not here.");

            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spgenericemployeeloanrepayment_record(" +
                "p_farmid => @FarmId::text, p_genericemployeeloanid => @LoanId::int, " +
                "p_amount => @Amount::numeric, p_sourcetype => @Source::text, " +
                "p_principalamount => @Principal::numeric, p_interestamount => @Interest::numeric, " +
                "p_repaymentdate => @Date::timestamp, p_genericcashaccountid => @CashAccountId::int, " +
                "p_paymentmethod => @PayMethod::text, p_referencenumber => @Reference::text, " +
                "p_description => @Description::text, p_notes => @Notes::text, " +
                "p_createdby => @CreatedBy::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", q.FarmId);
            cmd.Parameters.AddWithValue("@LoanId", q.GenericEmployeeLoanId);
            cmd.Parameters.AddWithValue("@Amount", q.Amount);
            cmd.Parameters.AddWithValue("@Source", source);
            cmd.Parameters.AddWithValue("@Principal", Db(q.PrincipalAmount));
            cmd.Parameters.AddWithValue("@Interest", q.InterestAmount ?? 0m);
            cmd.Parameters.AddWithValue("@Date", Db(q.RepaymentDate));
            cmd.Parameters.AddWithValue("@CashAccountId", Db(q.GenericCashAccountId));
            cmd.Parameters.AddWithValue("@PayMethod", Db(q.PaymentMethod));
            cmd.Parameters.AddWithValue("@Reference", Db(q.ReferenceNumber));
            cmd.Parameters.AddWithValue("@Description", Db(q.Description));
            cmd.Parameters.AddWithValue("@Notes", Db(q.Notes));
            cmd.Parameters.AddWithValue("@CreatedBy", Db(q.CreatedBy));
            await c.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task ReverseRepaymentAsync(int repaymentId, GenericEmployeeLoanReasonRequest q)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT spgenericemployeeloanrepayment_reverse(" +
                "p_farmid => @FarmId::text, " +
                "p_genericemployeeloanrepaymentid => @Id::int, " +
                "p_reversedby => @By::text, p_reason => @Reason::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", q.FarmId);
            cmd.Parameters.AddWithValue("@Id", repaymentId);
            cmd.Parameters.AddWithValue("@By", Db(q.ActionBy));
            cmd.Parameters.AddWithValue("@Reason", Db(q.Reason));
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }
    }
}
