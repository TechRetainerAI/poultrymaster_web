// Water loans and repayments (migration 259).
//
// Every rule that matters lives in the SPs -- one cash row for the total,
// interest and fees as NonCash expenses so they cost without paying twice, and
// no supplier payment anywhere. This file sends parameters and maps rows.
//
// The water twin of WaterLoanService, parameter for parameter.

using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IWaterLoanService
    {
        Task<List<WaterLoanModel>> GetAllAsync(string farmId, string? status);
        Task<WaterLoanModel?> GetByIdAsync(int id, string farmId);
        Task<WaterLoanSummary> GetSummaryAsync(string farmId);
        Task<int> CreateAsync(WaterLoanCreateRequest r);
        Task UpdateAsync(int id, string farmId, WaterLoanUpdateRequest r, string? updatedBy);
        Task CancelAsync(int id, string farmId, string reason, string? cancelledBy);

        Task<List<WaterLoanPaymentModel>> GetPaymentsAsync(
            string farmId, int? loanId, DateTime? from, DateTime? to);
        Task<int> RecordPaymentAsync(WaterLoanPaymentRequest r);
        Task ReversePaymentAsync(int paymentId, string farmId, string reason, string? reversedBy);
    }

    public class WaterLoanService : IWaterLoanService
    {
        private readonly string _cs;
        public WaterLoanService(string cs) => _cs = cs;

        private static object Db(object? v) => v ?? DBNull.Value;
        private static object DbDate(DateTime? v) => v.HasValue ? v.Value.Date : (object)DBNull.Value;

        private static string? Str(NpgsqlDataReader r, string c)
        {
            var i = r.GetOrdinal(c);
            return r.IsDBNull(i) ? null : r.GetString(i);
        }
        private static int? IntN(NpgsqlDataReader r, string c)
        {
            var i = r.GetOrdinal(c);
            return r.IsDBNull(i) ? null : Convert.ToInt32(r.GetValue(i));
        }
        private static decimal? DecN(NpgsqlDataReader r, string c)
        {
            var i = r.GetOrdinal(c);
            return r.IsDBNull(i) ? null : r.GetDecimal(i);
        }
        private static DateTime? DateN(NpgsqlDataReader r, string c)
        {
            var i = r.GetOrdinal(c);
            return r.IsDBNull(i) ? null : r.GetDateTime(i);
        }

        private static WaterLoanModel ReadLoan(NpgsqlDataReader r) => new()
        {
            WaterLoanId = r.GetInt32(r.GetOrdinal("WaterLoanId")),
            FarmId = r.GetString(r.GetOrdinal("FarmId")),
            LoanNumber = Str(r, "LoanNumber"),
            LenderName = r.GetString(r.GetOrdinal("LenderName")),
            LenderType = r.GetString(r.GetOrdinal("LenderType")),
            AccountNumber = Str(r, "AccountNumber"),
            LoanDate = r.GetDateTime(r.GetOrdinal("LoanDate")),
            OriginalPrincipal = r.GetDecimal(r.GetOrdinal("OriginalPrincipal")),
            AmountReceived = r.GetDecimal(r.GetOrdinal("AmountReceived")),
            InterestRate = DecN(r, "InterestRate"),
            InterestType = Str(r, "InterestType"),
            TermMonths = IntN(r, "TermMonths"),
            PaymentFrequency = Str(r, "PaymentFrequency"),
            StartDate = r.GetDateTime(r.GetOrdinal("StartDate")),
            EndDate = DateN(r, "EndDate"),
            NextPaymentDate = DateN(r, "NextPaymentDate"),
            WaterCashAccountId = IntN(r, "WaterCashAccountId"),
            AccountName = Str(r, "AccountName"),
            OutstandingPrincipal = r.GetDecimal(r.GetOrdinal("OutstandingPrincipal")),
            TotalPrincipalRepaid = r.GetDecimal(r.GetOrdinal("TotalPrincipalRepaid")),
            TotalInterestPaid = r.GetDecimal(r.GetOrdinal("TotalInterestPaid")),
            TotalFeesPaid = r.GetDecimal(r.GetOrdinal("TotalFeesPaid")),
            Status = r.GetString(r.GetOrdinal("Status")),
            IsOverdue = !r.IsDBNull(r.GetOrdinal("IsOverdue")) && r.GetBoolean(r.GetOrdinal("IsOverdue")),
            PaymentCount = r.GetInt32(r.GetOrdinal("PaymentCount")),
            PaidOffDate = DateN(r, "PaidOffDate"),
            Notes = Str(r, "Notes"),
            CreatedBy = Str(r, "CreatedBy"),
            CreatedAt = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            ReversalReason = Str(r, "ReversalReason"),
        };

        public async Task<List<WaterLoanModel>> GetAllAsync(string farmId, string? status)
        {
            var list = new List<WaterLoanModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spwaterloan_getall(p_farmid => @FarmId::text, p_status => @Status::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status", Db(status));
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(ReadLoan(r));
            return list;
        }

        public async Task<WaterLoanModel?> GetByIdAsync(int id, string farmId)
        {
            var all = await GetAllAsync(farmId, null);
            return all.FirstOrDefault(l => l.WaterLoanId == id);
        }

        public async Task<WaterLoanSummary> GetSummaryAsync(string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spwaterloan_summary(p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            if (!await r.ReadAsync()) return new WaterLoanSummary();
            return new WaterLoanSummary
            {
                ActiveLoans = r.GetInt32(r.GetOrdinal("ActiveLoans")),
                TotalBorrowed = r.GetDecimal(r.GetOrdinal("TotalBorrowed")),
                TotalReceived = r.GetDecimal(r.GetOrdinal("TotalReceived")),
                OutstandingPrincipal = r.GetDecimal(r.GetOrdinal("OutstandingPrincipal")),
                TotalPrincipalRepaid = r.GetDecimal(r.GetOrdinal("TotalPrincipalRepaid")),
                TotalInterestPaid = r.GetDecimal(r.GetOrdinal("TotalInterestPaid")),
                TotalFeesPaid = r.GetDecimal(r.GetOrdinal("TotalFeesPaid")),
                OverdueLoans = r.GetInt32(r.GetOrdinal("OverdueLoans")),
                NextPaymentDate = DateN(r, "NextPaymentDate"),
            };
        }

        public async Task<int> CreateAsync(WaterLoanCreateRequest q)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT spwaterloan_create("
                + "p_farmid => @FarmId::text,"
                + "p_lendername => @Lender::text,"
                + "p_originalprincipal => @Principal::numeric,"
                + "p_startdate => @StartDate::date,"
                + "p_amountreceived => @Received::numeric,"
                + "p_watercashaccountid => @AccountId::int,"
                + "p_lendertype => @LenderType::text,"
                + "p_accountnumber => @AccountNumber::text,"
                + "p_loandate => @LoanDate::date,"
                + "p_interestrate => @Rate::numeric,"
                + "p_interesttype => @RateType::text,"
                + "p_termmonths => @Term::int,"
                + "p_paymentfrequency => @Frequency::text,"
                + "p_enddate => @EndDate::date,"
                + "p_nextpaymentdate => @NextDate::date,"
                + "p_status => @Status::text,"
                + "p_notes => @Notes::text,"
                + "p_createdby => @CreatedBy::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", q.FarmId);
            cmd.Parameters.AddWithValue("@Lender", q.LenderName);
            cmd.Parameters.AddWithValue("@Principal", q.OriginalPrincipal);
            cmd.Parameters.AddWithValue("@StartDate", q.StartDate.Date);
            cmd.Parameters.AddWithValue("@Received", q.AmountReceived);
            cmd.Parameters.AddWithValue("@AccountId", Db(q.WaterCashAccountId));
            cmd.Parameters.AddWithValue("@LenderType", q.LenderType ?? "Other");
            cmd.Parameters.AddWithValue("@AccountNumber", Db(q.AccountNumber));
            cmd.Parameters.AddWithValue("@LoanDate", DbDate(q.LoanDate));
            cmd.Parameters.AddWithValue("@Rate", Db(q.InterestRate));
            cmd.Parameters.AddWithValue("@RateType", Db(q.InterestType));
            cmd.Parameters.AddWithValue("@Term", Db(q.TermMonths));
            cmd.Parameters.AddWithValue("@Frequency", Db(q.PaymentFrequency));
            cmd.Parameters.AddWithValue("@EndDate", DbDate(q.EndDate));
            cmd.Parameters.AddWithValue("@NextDate", DbDate(q.NextPaymentDate));
            cmd.Parameters.AddWithValue("@Status", q.Status ?? "Active");
            cmd.Parameters.AddWithValue("@Notes", Db(q.Notes));
            cmd.Parameters.AddWithValue("@CreatedBy", Db(q.CreatedBy));
            await c.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateAsync(int id, string farmId, WaterLoanUpdateRequest q, string? updatedBy)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT spwaterloan_update("
                + "p_waterloanid => @Id::int,"
                + "p_farmid => @FarmId::text,"
                + "p_lendername => @Lender::text,"
                + "p_lendertype => @LenderType::text,"
                + "p_accountnumber => @AccountNumber::text,"
                + "p_interestrate => @Rate::numeric,"
                + "p_interesttype => @RateType::text,"
                + "p_termmonths => @Term::int,"
                + "p_paymentfrequency => @Frequency::text,"
                + "p_enddate => @EndDate::date,"
                + "p_nextpaymentdate => @NextDate::date,"
                + "p_notes => @Notes::text,"
                + "p_updatedby => @UpdatedBy::text)", c);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Lender", Db(q.LenderName));
            cmd.Parameters.AddWithValue("@LenderType", Db(q.LenderType));
            cmd.Parameters.AddWithValue("@AccountNumber", Db(q.AccountNumber));
            cmd.Parameters.AddWithValue("@Rate", Db(q.InterestRate));
            cmd.Parameters.AddWithValue("@RateType", Db(q.InterestType));
            cmd.Parameters.AddWithValue("@Term", Db(q.TermMonths));
            cmd.Parameters.AddWithValue("@Frequency", Db(q.PaymentFrequency));
            cmd.Parameters.AddWithValue("@EndDate", DbDate(q.EndDate));
            cmd.Parameters.AddWithValue("@NextDate", DbDate(q.NextPaymentDate));
            cmd.Parameters.AddWithValue("@Notes", Db(q.Notes));
            cmd.Parameters.AddWithValue("@UpdatedBy", Db(updatedBy));
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task CancelAsync(int id, string farmId, string reason, string? cancelledBy)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT spwaterloan_cancel(p_waterloanid => @Id::int, p_farmid => @FarmId::text, p_reason => @Reason::text, p_cancelledby => @By::text)", c);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Reason", reason);
            cmd.Parameters.AddWithValue("@By", Db(cancelledBy));
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<List<WaterLoanPaymentModel>> GetPaymentsAsync(
            string farmId, int? loanId, DateTime? from, DateTime? to)
        {
            var list = new List<WaterLoanPaymentModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spwaterloanpayment_getall(p_farmid => @FarmId::text, p_loanid => @LoanId::int, p_from => @From::date, p_to => @To::date)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@LoanId", Db(loanId));
            cmd.Parameters.AddWithValue("@From", DbDate(from));
            cmd.Parameters.AddWithValue("@To", DbDate(to));
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                list.Add(new WaterLoanPaymentModel
                {
                    WaterLoanPaymentId = r.GetInt32(r.GetOrdinal("WaterLoanPaymentId")),
                    FarmId = r.GetString(r.GetOrdinal("FarmId")),
                    WaterLoanId = r.GetInt32(r.GetOrdinal("WaterLoanId")),
                    LoanNumber = Str(r, "LoanNumber"),
                    LenderName = Str(r, "LenderName"),
                    PaymentNumber = Str(r, "PaymentNumber"),
                    PaymentDate = r.GetDateTime(r.GetOrdinal("PaymentDate")),
                    TotalAmount = r.GetDecimal(r.GetOrdinal("TotalAmount")),
                    PrincipalAmount = r.GetDecimal(r.GetOrdinal("PrincipalAmount")),
                    InterestAmount = r.GetDecimal(r.GetOrdinal("InterestAmount")),
                    FeeAmount = r.GetDecimal(r.GetOrdinal("FeeAmount")),
                    OtherAmount = r.GetDecimal(r.GetOrdinal("OtherAmount")),
                    WaterCashAccountId = r.GetInt32(r.GetOrdinal("WaterCashAccountId")),
                    AccountName = Str(r, "AccountName"),
                    PaymentMethod = Str(r, "PaymentMethod"),
                    ReferenceNumber = Str(r, "ReferenceNumber"),
                    Notes = Str(r, "Notes"),
                    Status = r.GetString(r.GetOrdinal("Status")),
                    InterestExpenseId = IntN(r, "InterestExpenseId"),
                    FeeExpenseId = IntN(r, "FeeExpenseId"),
                    CreatedBy = Str(r, "CreatedBy"),
                    CreatedAt = r.GetDateTime(r.GetOrdinal("CreatedAt")),
                    ReversedBy = Str(r, "ReversedBy"),
                    ReversedAt = DateN(r, "ReversedAt"),
                    ReversalReason = Str(r, "ReversalReason"),
                });
            }
            return list;
        }

        public async Task<int> RecordPaymentAsync(WaterLoanPaymentRequest q)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT spwaterloanpayment_record("
                + "p_farmid => @FarmId::text,"
                + "p_waterloanid => @LoanId::int,"
                + "p_watercashaccountid => @AccountId::int,"
                + "p_principalamount => @Principal::numeric,"
                + "p_interestamount => @Interest::numeric,"
                + "p_feeamount => @Fee::numeric,"
                + "p_otheramount => @Other::numeric,"
                + "p_paymentdate => @Date::timestamp,"
                + "p_paymentmethod => @Method::text,"
                + "p_referencenumber => @Reference::text,"
                + "p_notes => @Notes::text,"
                + "p_nextpaymentdate => @NextDate::date,"
                + "p_createdby => @CreatedBy::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", q.FarmId);
            cmd.Parameters.AddWithValue("@LoanId", q.WaterLoanId);
            cmd.Parameters.AddWithValue("@AccountId", q.WaterCashAccountId);
            cmd.Parameters.AddWithValue("@Principal", q.PrincipalAmount);
            cmd.Parameters.AddWithValue("@Interest", q.InterestAmount);
            cmd.Parameters.AddWithValue("@Fee", q.FeeAmount);
            cmd.Parameters.AddWithValue("@Other", q.OtherAmount);
            cmd.Parameters.AddWithValue("@Date", q.PaymentDate.HasValue ? q.PaymentDate.Value : (object)DBNull.Value);
            cmd.Parameters.AddWithValue("@Method", Db(q.PaymentMethod));
            cmd.Parameters.AddWithValue("@Reference", Db(q.ReferenceNumber));
            cmd.Parameters.AddWithValue("@Notes", Db(q.Notes));
            cmd.Parameters.AddWithValue("@NextDate", DbDate(q.NextPaymentDate));
            cmd.Parameters.AddWithValue("@CreatedBy", Db(q.CreatedBy));
            await c.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task ReversePaymentAsync(int paymentId, string farmId, string reason, string? reversedBy)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT spwaterloanpayment_reverse(p_waterloanpaymentid => @Id::int, p_farmid => @FarmId::text, p_reason => @Reason::text, p_reversedby => @By::text)", c);
            cmd.Parameters.AddWithValue("@Id", paymentId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Reason", reason);
            cmd.Parameters.AddWithValue("@By", Db(reversedBy));
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }
    }
}
