using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class HotelEmployeeLoanService : IHotelEmployeeLoanService
    {
        private readonly string _cs;
        public HotelEmployeeLoanService(string connectionString) { _cs = connectionString; }

        private static string? StrN(NpgsqlDataReader r, string col) { var o = r.GetOrdinal(col); return r.IsDBNull(o) ? null : r.GetString(o); }
        private static string Str(NpgsqlDataReader r, string col) => r.GetString(r.GetOrdinal(col));
        private static int Int(NpgsqlDataReader r, string col) => r.GetInt32(r.GetOrdinal(col));
        private static int? IntN(NpgsqlDataReader r, string col) { var o = r.GetOrdinal(col); return r.IsDBNull(o) ? null : r.GetInt32(o); }
        private static decimal Dec(NpgsqlDataReader r, string col) { var o = r.GetOrdinal(col); return r.IsDBNull(o) ? 0m : r.GetDecimal(o); }
        private static bool Bool(NpgsqlDataReader r, string col) { var o = r.GetOrdinal(col); return !r.IsDBNull(o) && r.GetBoolean(o); }
        private static DateTime Dt(NpgsqlDataReader r, string col) => r.GetDateTime(r.GetOrdinal(col));
        private static DateTime? DtN(NpgsqlDataReader r, string col) { var o = r.GetOrdinal(col); return r.IsDBNull(o) ? null : r.GetDateTime(o); }
        private static object Db(object? v) => v ?? DBNull.Value;
        private static object DateOrNull(string? s) => string.IsNullOrEmpty(s) ? DBNull.Value : DateTime.Parse(s);

        private static HotelEmployeeLoanModel MapLoan(NpgsqlDataReader r) => new()
        {
            HotelEmployeeLoanId = Int(r, "hotelemployeeloanid"),
            FarmId = Str(r, "farmid"),
            HotelStaffId = Int(r, "hotelstaffid"),
            StaffName = StrN(r, "staffname"),
            StaffIsActive = Bool(r, "staffisactive"),
            LoanNumber = StrN(r, "loannumber"),
            LoanType = Str(r, "loantype"),
            Status = Str(r, "status"),
            PrincipalAmount = Dec(r, "principalamount"),
            InterestAmount = Dec(r, "interestamount"),
            TotalRepayable = Dec(r, "totalrepayable"),
            TotalPrincipalRepaid = Dec(r, "totalprincipalrepaid"),
            TotalInterestRepaid = Dec(r, "totalinterestrepaid"),
            OutstandingBalance = Dec(r, "outstandingbalance"),
            RepaymentMethod = Str(r, "repaymentmethod"),
            DefaultPayrollDeduction = Dec(r, "defaultpayrolldeduction"),
            DisbursementDate = DtN(r, "disbursementdate"),
            ExpectedEndDate = DtN(r, "expectedenddate"),
            HotelCashAccountId = IntN(r, "hotelcashaccountid"),
            CashAccountName = StrN(r, "cashaccountname"),
            Reference = StrN(r, "reference"),
            Notes = StrN(r, "notes"),
            CreatedBy = StrN(r, "createdby"),
            CreatedAt = Dt(r, "createdat"),
            UpdatedAt = DtN(r, "updatedat"),
            ReversedBy = StrN(r, "reversedby"),
            ReversedReason = StrN(r, "reversedreason"),
            ReversedAt = DtN(r, "reversedat"),
            RepaymentCount = Int(r, "repaymentcount"),
            LastRepaymentDate = DtN(r, "lastrepaymentdate"),
            DraftPayrollClaims = Dec(r, "draftpayrollclaims"),
        };

        private static HotelEmployeeLoanRepaymentModel MapRepayment(NpgsqlDataReader r) => new()
        {
            HotelEmployeeLoanRepaymentId = Int(r, "hotelemployeeloanrepaymentid"),
            FarmId = Str(r, "farmid"),
            HotelEmployeeLoanId = Int(r, "hotelemployeeloanid"),
            LoanNumber = StrN(r, "loannumber"),
            HotelStaffId = Int(r, "hotelstaffid"),
            StaffName = StrN(r, "staffname"),
            Amount = Dec(r, "amount"),
            PrincipalAmount = Dec(r, "principalamount"),
            InterestAmount = Dec(r, "interestamount"),
            SourceType = Str(r, "sourcetype"),
            PaymentMethod = StrN(r, "paymentmethod"),
            HotelCashAccountId = IntN(r, "hotelcashaccountid"),
            CashAccountName = StrN(r, "cashaccountname"),
            CashTransactionId = IntN(r, "cashtransactionid"),
            HotelPayrollRunId = IntN(r, "hotelpayrollrunid"),
            PayrollPeriod = StrN(r, "payrollperiod"),
            BalanceBefore = Dec(r, "balancebefore"),
            BalanceAfter = Dec(r, "balanceafter"),
            RepaymentDate = Dt(r, "repaymentdate"),
            Reference = StrN(r, "reference"),
            Notes = StrN(r, "notes"),
            Status = Str(r, "status"),
            CreatedBy = StrN(r, "createdby"),
            CreatedAt = Dt(r, "createdat"),
            ReversedBy = StrN(r, "reversedby"),
            ReversedReason = StrN(r, "reversedreason"),
            ReversedAt = DtN(r, "reversedat"),
        };

        public async Task<List<HotelEmployeeLoanModel>> GetAllAsync(string farmId, string? status, int? staffId)
        {
            var list = new List<HotelEmployeeLoanModel>();
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM sphotelemployeeloan_getall(@f, @s, @st)", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            cmd.Parameters.AddWithValue("@s", Db(status));
            cmd.Parameters.Add(new NpgsqlParameter("@st", NpgsqlTypes.NpgsqlDbType.Integer) { Value = Db(staffId) });
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(MapLoan(r));
            return list;
        }

        public async Task<HotelEmployeeLoanModel?> GetByIdAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM sphotelemployeeloan_getbyid(@id, @f)", conn);
            cmd.Parameters.AddWithValue("@id", id);
            cmd.Parameters.AddWithValue("@f", farmId);
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? MapLoan(r) : null;
        }

        public async Task<int> CreateAsync(HotelEmployeeLoanCreateRequest req, string? createdBy)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand(
                "SELECT sphotelemployeeloan_create(@f, @sid, @sn, @type, @princ, @int, @meth, @ded, @end, @ref, @notes, @by, @disburse, @acct, @ddate)", conn);
            cmd.Parameters.AddWithValue("@f", req.FarmId);
            cmd.Parameters.AddWithValue("@sid", req.HotelStaffId);
            cmd.Parameters.AddWithValue("@sn", Db(req.StaffName));
            cmd.Parameters.AddWithValue("@type", req.LoanType);
            cmd.Parameters.AddWithValue("@princ", req.PrincipalAmount);
            cmd.Parameters.AddWithValue("@int", req.InterestAmount);
            cmd.Parameters.AddWithValue("@meth", req.RepaymentMethod);
            cmd.Parameters.AddWithValue("@ded", req.DefaultPayrollDeduction);
            cmd.Parameters.AddWithValue("@end", DateOrNull(req.ExpectedEndDate));
            cmd.Parameters.AddWithValue("@ref", Db(req.Reference));
            cmd.Parameters.AddWithValue("@notes", Db(req.Notes));
            cmd.Parameters.AddWithValue("@by", Db(createdBy));
            cmd.Parameters.AddWithValue("@disburse", req.DisburseNow);
            cmd.Parameters.Add(new NpgsqlParameter("@acct", NpgsqlTypes.NpgsqlDbType.Integer) { Value = Db(req.HotelCashAccountId) });
            cmd.Parameters.AddWithValue("@ddate", DateOrNull(req.DisbursementDate));
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateAsync(int id, HotelEmployeeLoanUpdateRequest req, string? by)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand(
                "SELECT sphotelemployeeloan_update(@id, @f, @type, @princ, @int, @meth, @ded, @end, @ref, @notes, @by)", conn);
            cmd.Parameters.AddWithValue("@id", id);
            cmd.Parameters.AddWithValue("@f", req.FarmId);
            cmd.Parameters.AddWithValue("@type", req.LoanType);
            cmd.Parameters.AddWithValue("@princ", req.PrincipalAmount);
            cmd.Parameters.AddWithValue("@int", req.InterestAmount);
            cmd.Parameters.AddWithValue("@meth", req.RepaymentMethod);
            cmd.Parameters.AddWithValue("@ded", req.DefaultPayrollDeduction);
            cmd.Parameters.AddWithValue("@end", DateOrNull(req.ExpectedEndDate));
            cmd.Parameters.AddWithValue("@ref", Db(req.Reference));
            cmd.Parameters.AddWithValue("@notes", Db(req.Notes));
            cmd.Parameters.AddWithValue("@by", Db(by));
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DisburseAsync(int id, string farmId, int? cashAccountId, DateTime? date, string? reference, string? by)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT sphotelemployeeloan_disburse(@id, @f, @acct, @date, @ref, @by)", conn);
            cmd.Parameters.AddWithValue("@id", id);
            cmd.Parameters.AddWithValue("@f", farmId);
            cmd.Parameters.Add(new NpgsqlParameter("@acct", NpgsqlTypes.NpgsqlDbType.Integer) { Value = Db(cashAccountId) });
            cmd.Parameters.AddWithValue("@date", Db(date));
            cmd.Parameters.AddWithValue("@ref", Db(reference));
            cmd.Parameters.AddWithValue("@by", Db(by));
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task CancelAsync(int id, string farmId, string? reason, string? by)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT sphotelemployeeloan_cancel(@id, @f, @reason, @by)", conn);
            cmd.Parameters.AddWithValue("@id", id);
            cmd.Parameters.AddWithValue("@f", farmId);
            cmd.Parameters.AddWithValue("@reason", Db(reason));
            cmd.Parameters.AddWithValue("@by", Db(by));
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task ReverseAsync(int id, string farmId, string? reason, string? by)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT sphotelemployeeloan_reverse(@id, @f, @reason, @by)", conn);
            cmd.Parameters.AddWithValue("@id", id);
            cmd.Parameters.AddWithValue("@f", farmId);
            cmd.Parameters.AddWithValue("@reason", Db(reason));
            cmd.Parameters.AddWithValue("@by", Db(by));
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<List<HotelEmployeeLoanRepaymentModel>> GetRepaymentsAsync(int? loanId, string farmId)
        {
            var list = new List<HotelEmployeeLoanRepaymentModel>();
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM sphotelemployeeloanrepayment_getall(@id, @f)", conn);
            cmd.Parameters.Add(new NpgsqlParameter("@id", NpgsqlTypes.NpgsqlDbType.Integer) { Value = Db(loanId) });
            cmd.Parameters.AddWithValue("@f", farmId);
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(MapRepayment(r));
            return list;
        }

        public async Task<int> RecordRepaymentAsync(HotelEmployeeLoanRepaymentRequest req, string? createdBy)
        {
            if (req.SourceType == "Payroll") throw new InvalidOperationException("Payroll repayments are created by approving a payroll run.");
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand(
                "SELECT sphotelemployeeloanrepayment_record(@lid, @f, @amt, @src, @acct, @date, @ref, @notes, @by)", conn);
            cmd.Parameters.AddWithValue("@lid", req.HotelEmployeeLoanId);
            cmd.Parameters.AddWithValue("@f", req.FarmId);
            cmd.Parameters.AddWithValue("@amt", req.Amount);
            cmd.Parameters.AddWithValue("@src", req.SourceType);
            cmd.Parameters.Add(new NpgsqlParameter("@acct", NpgsqlTypes.NpgsqlDbType.Integer) { Value = Db(req.HotelCashAccountId) });
            cmd.Parameters.AddWithValue("@date", DateOrNull(req.RepaymentDate));
            cmd.Parameters.AddWithValue("@ref", Db(req.Reference));
            cmd.Parameters.AddWithValue("@notes", Db(req.Notes));
            cmd.Parameters.AddWithValue("@by", Db(createdBy));
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task ReverseRepaymentAsync(int repaymentId, string farmId, string? reason, string? by)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            // p_allowpayroll is left at FALSE: a payroll repayment is only
            // reversed by reopening or cancelling its payroll run.
            using var cmd = new NpgsqlCommand("SELECT sphotelemployeeloanrepayment_reverse(@id, @f, @reason, @by)", conn);
            cmd.Parameters.AddWithValue("@id", repaymentId);
            cmd.Parameters.AddWithValue("@f", farmId);
            cmd.Parameters.AddWithValue("@reason", Db(reason));
            cmd.Parameters.AddWithValue("@by", Db(by));
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<HotelEmployeeLoanSummaryModel> GetSummaryAsync(string farmId, DateTime? from, DateTime? to)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM sphotelemployeeloan_summary(@f, @from, @to)", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            cmd.Parameters.AddWithValue("@from", Db(from));
            cmd.Parameters.AddWithValue("@to", Db(to));
            using var r = await cmd.ExecuteReaderAsync();
            if (await r.ReadAsync())
                return new HotelEmployeeLoanSummaryModel
                {
                    TotalOutstanding = Dec(r, "totaloutstanding"),
                    TotalDisbursed = Dec(r, "totaldisbursed"),
                    TotalRepaid = Dec(r, "totalrepaid"),
                    ActiveCount = Int(r, "activecount"),
                    StaffWithLoans = Int(r, "staffwithloans"),
                    DraftCount = Int(r, "draftcount"),
                    PaidCount = Int(r, "paidcount"),
                    InterestEarned = Dec(r, "interestearned"),
                    RepaidViaPayroll = Dec(r, "repaidviapayroll"),
                    DraftPayrollClaims = Dec(r, "draftpayrollclaims"),
                };
            return new HotelEmployeeLoanSummaryModel();
        }

        public async Task<List<HotelEmployeeLoanEligibleModel>> GetEligibleAsync(string farmId, int staffId, int? excludeItemId)
        {
            var list = new List<HotelEmployeeLoanEligibleModel>();
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM sphotelemployeeloan_eligible(@f, @s, @x)", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            cmd.Parameters.AddWithValue("@s", staffId);
            cmd.Parameters.Add(new NpgsqlParameter("@x", NpgsqlTypes.NpgsqlDbType.Integer) { Value = Db(excludeItemId) });
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Add(new HotelEmployeeLoanEligibleModel
                {
                    HotelEmployeeLoanId = Int(r, "hotelemployeeloanid"),
                    LoanNumber = StrN(r, "loannumber"),
                    LoanType = Str(r, "loantype"),
                    RepaymentMethod = Str(r, "repaymentmethod"),
                    OutstandingBalance = Dec(r, "outstandingbalance"),
                    DefaultPayrollDeduction = Dec(r, "defaultpayrolldeduction"),
                    ClaimedElsewhere = Dec(r, "claimedelsewhere"),
                    Available = Dec(r, "available"),
                    SuggestedDeduction = Dec(r, "suggesteddeduction"),
                    CurrentDeduction = Dec(r, "currentdeduction"),
                });
            return list;
        }

        public async Task<List<HotelEmployeeLoanStaffReportRow>> GetStaffReportAsync(string farmId, DateTime? from, DateTime? to)
        {
            var list = new List<HotelEmployeeLoanStaffReportRow>();
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM sphotelemployeeloan_staffreport(@f, @from, @to)", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            cmd.Parameters.AddWithValue("@from", Db(from));
            cmd.Parameters.AddWithValue("@to", Db(to));
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Add(new HotelEmployeeLoanStaffReportRow
                {
                    HotelStaffId = Int(r, "hotelstaffid"),
                    StaffName = StrN(r, "staffname") ?? "",
                    Department = StrN(r, "department"),
                    StaffIsActive = Bool(r, "staffisactive"),
                    ActiveLoans = Int(r, "activeloans"),
                    Outstanding = Dec(r, "outstanding"),
                    DisbursedInPeriod = Dec(r, "disbursedinperiod"),
                    RepaidCashInPeriod = Dec(r, "repaidcashinperiod"),
                    RepaidPayrollInPeriod = Dec(r, "repaidpayrollinperiod"),
                    InterestInPeriod = Dec(r, "interestinperiod"),
                    LastRepaymentDate = DtN(r, "lastrepaymentdate"),
                    TotalEver = Dec(r, "totalever"),
                });
            return list;
        }

        public async Task<List<HotelPayrollDeductionModel>> GetPayrollDeductionsAsync(string farmId, int runId)
        {
            var list = new List<HotelPayrollDeductionModel>();
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM sphotelpayrolldeduction_getforrun(@f, @r)", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            cmd.Parameters.AddWithValue("@r", runId);
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Add(new HotelPayrollDeductionModel
                {
                    HotelPayrollDeductionId = Int(r, "hotelpayrolldeductionid"),
                    HotelPayrollItemId = Int(r, "hotelpayrollitemid"),
                    HotelStaffId = Int(r, "hotelstaffid"),
                    HotelEmployeeLoanId = Int(r, "hotelemployeeloanid"),
                    LoanNumber = StrN(r, "loannumber"),
                    LoanType = Str(r, "loantype"),
                    DeductionType = Str(r, "deductiontype"),
                    Amount = Dec(r, "amount"),
                    Status = Str(r, "status"),
                    HotelEmployeeLoanRepaymentId = IntN(r, "hotelemployeeloanrepaymentid"),
                    OutstandingBalance = Dec(r, "outstandingbalance"),
                });
            return list;
        }

    }
}
