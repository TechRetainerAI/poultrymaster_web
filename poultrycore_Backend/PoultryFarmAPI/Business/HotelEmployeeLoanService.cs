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
        private static decimal Dec(NpgsqlDataReader r, string col) => r.GetDecimal(r.GetOrdinal(col));
        private static DateTime Dt(NpgsqlDataReader r, string col) => r.GetDateTime(r.GetOrdinal(col));
        private static DateTime? DtN(NpgsqlDataReader r, string col) { var o = r.GetOrdinal(col); return r.IsDBNull(o) ? null : r.GetDateTime(o); }

        private static HotelEmployeeLoanModel MapLoan(NpgsqlDataReader r) => new()
        {
            HotelEmployeeLoanId = Int(r, "hotelemployeeloanid"),
            FarmId = Str(r, "farmid"),
            HotelStaffId = Int(r, "hotelstaffid"),
            StaffName = StrN(r, "staffname"),
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
            Reference = StrN(r, "reference"),
            Notes = StrN(r, "notes"),
            CreatedBy = StrN(r, "createdby"),
            CreatedAt = Dt(r, "createdat"),
            UpdatedAt = DtN(r, "updatedat"),
            ReversedBy = StrN(r, "reversedby"),
            ReversedReason = StrN(r, "reversedreason"),
            ReversedAt = DtN(r, "reversedat"),
        };

        private static HotelEmployeeLoanRepaymentModel MapRepayment(NpgsqlDataReader r) => new()
        {
            HotelEmployeeLoanRepaymentId = Int(r, "hotelemployeeloanrepaymentid"),
            FarmId = Str(r, "farmid"),
            HotelEmployeeLoanId = Int(r, "hotelemployeeloanid"),
            Amount = Dec(r, "amount"),
            PrincipalAmount = Dec(r, "principalamount"),
            InterestAmount = Dec(r, "interestamount"),
            SourceType = Str(r, "sourcetype"),
            PaymentMethod = StrN(r, "paymentmethod"),
            HotelCashAccountId = IntN(r, "hotelcashaccountid"),
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
            cmd.Parameters.AddWithValue("@s", (object?)status ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@st", (object?)(staffId.HasValue ? (object)staffId.Value : null) ?? DBNull.Value);
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
            cmd.Parameters.AddWithValue("@sn", (object?)req.StaffName ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@type", req.LoanType);
            cmd.Parameters.AddWithValue("@princ", req.PrincipalAmount);
            cmd.Parameters.AddWithValue("@int", req.InterestAmount);
            cmd.Parameters.AddWithValue("@meth", req.RepaymentMethod);
            cmd.Parameters.AddWithValue("@ded", req.DefaultPayrollDeduction);
            cmd.Parameters.AddWithValue("@end", string.IsNullOrEmpty(req.ExpectedEndDate) ? DBNull.Value : (object)DateTime.Parse(req.ExpectedEndDate));
            cmd.Parameters.AddWithValue("@ref", (object?)req.Reference ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@notes", (object?)req.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@by", (object?)createdBy ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@disburse", req.DisburseNow);
            cmd.Parameters.AddWithValue("@acct", (object?)req.HotelCashAccountId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ddate", string.IsNullOrEmpty(req.DisbursementDate) ? DBNull.Value : (object)DateTime.Parse(req.DisbursementDate));
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task DisburseAsync(int id, string farmId, int? cashAccountId, DateTime? date, string? reference, string? by)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT sphotelemployeeloan_disburse(@id, @f, @acct, @date, @ref, @by)", conn);
            cmd.Parameters.AddWithValue("@id", id);
            cmd.Parameters.AddWithValue("@f", farmId);
            cmd.Parameters.AddWithValue("@acct", (object?)cashAccountId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@date", (object?)date ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ref", (object?)reference ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@by", (object?)by ?? DBNull.Value);
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task CancelAsync(int id, string farmId, string? reason, string? by)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT sphotelemployeeloan_cancel(@id, @f, @reason, @by)", conn);
            cmd.Parameters.AddWithValue("@id", id);
            cmd.Parameters.AddWithValue("@f", farmId);
            cmd.Parameters.AddWithValue("@reason", (object?)reason ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@by", (object?)by ?? DBNull.Value);
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task ReverseAsync(int id, string farmId, string? reason, string? by)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT sphotelemployeeloan_reverse(@id, @f, @reason, @by)", conn);
            cmd.Parameters.AddWithValue("@id", id);
            cmd.Parameters.AddWithValue("@f", farmId);
            cmd.Parameters.AddWithValue("@reason", (object?)reason ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@by", (object?)by ?? DBNull.Value);
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<List<HotelEmployeeLoanRepaymentModel>> GetRepaymentsAsync(int loanId, string farmId)
        {
            var list = new List<HotelEmployeeLoanRepaymentModel>();
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM sphotelemployeeloanrepayment_getall(@id, @f)", conn);
            cmd.Parameters.AddWithValue("@id", loanId);
            cmd.Parameters.AddWithValue("@f", farmId);
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(MapRepayment(r));
            return list;
        }

        public async Task<int> RecordRepaymentAsync(HotelEmployeeLoanRepaymentRequest req, string? createdBy)
        {
            if (req.SourceType == "Payroll") throw new InvalidOperationException("Payroll repayments must be created via payroll approval");
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand(
                "SELECT sphotelemployeeloanrepayment_record(@lid, @f, @amt, @src, @acct, @date, @ref, @notes, @by)", conn);
            cmd.Parameters.AddWithValue("@lid", req.HotelEmployeeLoanId);
            cmd.Parameters.AddWithValue("@f", req.FarmId);
            cmd.Parameters.AddWithValue("@amt", req.Amount);
            cmd.Parameters.AddWithValue("@src", req.SourceType);
            cmd.Parameters.AddWithValue("@acct", (object?)req.HotelCashAccountId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@date", string.IsNullOrEmpty(req.RepaymentDate) ? DBNull.Value : (object)DateTime.Parse(req.RepaymentDate));
            cmd.Parameters.AddWithValue("@ref", (object?)req.Reference ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@notes", (object?)req.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@by", (object?)createdBy ?? DBNull.Value);
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task ReverseRepaymentAsync(int repaymentId, string farmId, string? reason, string? by)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT sphotelemployeeloanrepayment_reverse(@id, @f, @reason, @by)", conn);
            cmd.Parameters.AddWithValue("@id", repaymentId);
            cmd.Parameters.AddWithValue("@f", farmId);
            cmd.Parameters.AddWithValue("@reason", (object?)reason ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@by", (object?)by ?? DBNull.Value);
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<HotelEmployeeLoanSummaryModel> GetSummaryAsync(string farmId, DateTime? from, DateTime? to)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM sphotelemployeeloan_summary(@f, @from, @to)", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            cmd.Parameters.AddWithValue("@from", (object?)from ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@to", (object?)to ?? DBNull.Value);
            using var r = await cmd.ExecuteReaderAsync();
            if (await r.ReadAsync())
                return new HotelEmployeeLoanSummaryModel
                {
                    TotalOutstanding = Dec(r, "totaloutstanding"),
                    TotalDisbursed = Dec(r, "totaldisbursed"),
                    TotalRepaid = Dec(r, "totalrepaid"),
                    ActiveCount = Int(r, "activecount"),
                };
            return new HotelEmployeeLoanSummaryModel();
        }
    }
}
