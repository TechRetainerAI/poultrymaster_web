// Employee Credit (migration 460 (Water port of 441)). Thin: every rule -- the balance check on a
// payout, the cash rows, the NonCash payroll cost for wages owed, refusing to
// reverse money already paid out -- is in the SQL functions.
//
// Payroll savings are NOT created here. They are a payroll deduction of type
// 'EmployeeCredit' and are posted by approving the payroll run, so this service
// has no way to add one.

using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IWaterEmployeeCreditService
    {
        Task<List<WaterEmployeeCreditBalance>> GetBalancesAsync(string farmId);
        Task<List<WaterEmployeeCreditEntry>> GetEntriesAsync(string farmId, int? staffId);
        Task<WaterEmployeeCreditTotal> GetTotalAsync(string farmId);
        Task<int> AddAsync(WaterEmployeeCreditAddRequest r);
        Task<int> PayoutAsync(WaterEmployeeCreditPayoutRequest r);
        Task ReverseAsync(int id, WaterEmployeeCreditReverseRequest r);
    }

    public class WaterEmployeeCreditService : IWaterEmployeeCreditService
    {
        private readonly string _cs;
        public WaterEmployeeCreditService(string cs) => _cs = cs;

        private static object Db(object? v) => v ?? DBNull.Value;
        private static object DbDate(DateTime? v) => v.HasValue ? v.Value.Date : (object)DBNull.Value;
        private static string? Str(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? null : r.GetString(i); }
        private static int? IntN(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? null : Convert.ToInt32(r.GetValue(i)); }
        private static decimal Dec(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? 0m : r.GetDecimal(i); }
        private static DateTime? DateN(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? null : r.GetDateTime(i); }

        public async Task<List<WaterEmployeeCreditBalance>> GetBalancesAsync(string farmId)
        {
            var list = new List<WaterEmployeeCreditBalance>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spwateremployeecredit_balances(p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Add(new WaterEmployeeCreditBalance
                {
                    WaterStaffId = r.GetInt32(r.GetOrdinal("waterstaffid")),
                    StaffName = Str(r, "staffname"),
                    StaffRole = Str(r, "staffrole"),
                    IsActive = !r.IsDBNull(r.GetOrdinal("isactive")) && r.GetBoolean(r.GetOrdinal("isactive")),
                    Balance = Dec(r, "balance"),
                    TotalIn = Dec(r, "totalin"),
                    TotalPaidOut = Dec(r, "totalpaidout"),
                    LastEntryDate = DateN(r, "lastentrydate"),
                    EntryCount = r.GetInt32(r.GetOrdinal("entrycount")),
                });
            return list;
        }

        public async Task<List<WaterEmployeeCreditEntry>> GetEntriesAsync(string farmId, int? staffId)
        {
            var list = new List<WaterEmployeeCreditEntry>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spwateremployeecredit_getall(" +
                "p_farmid => @FarmId::text, p_waterstaffid => @StaffId::int)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@StaffId", Db(staffId));
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Add(new WaterEmployeeCreditEntry
                {
                    WaterEmployeeCreditId = r.GetInt32(r.GetOrdinal("wateremployeecreditid")),
                    WaterStaffId = r.GetInt32(r.GetOrdinal("waterstaffid")),
                    StaffName = Str(r, "staffname"),
                    EntryType = Str(r, "entrytype") ?? string.Empty,
                    Amount = Dec(r, "amount"),
                    SignedAmount = Dec(r, "signedamount"),
                    RunningBalance = Dec(r, "runningbalance"),
                    EntryDate = r.GetDateTime(r.GetOrdinal("entrydate")),
                    WaterCashAccountId = IntN(r, "watercashaccountid"),
                    AccountName = Str(r, "accountname"),
                    PaymentMethod = Str(r, "paymentmethod"),
                    Reference = Str(r, "reference"),
                    Description = Str(r, "description"),
                    WaterPayrollRunId = IntN(r, "waterpayrollrunid"),
                    PayrollPeriod = Str(r, "payrollperiod"),
                    ExpenseId = IntN(r, "waterexpenseid"),
                    Status = Str(r, "status") ?? "Posted",
                    CreatedBy = Str(r, "createdby"),
                    CreatedAt = DateN(r, "createdat"),
                    ReversedBy = Str(r, "reversedby"),
                    ReversedAt = DateN(r, "reversedat"),
                    ReversalReason = Str(r, "reversalreason"),
                });
            return list;
        }

        public async Task<WaterEmployeeCreditTotal> GetTotalAsync(string farmId)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spwateremployeecredit_total(p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            if (!await r.ReadAsync()) return new WaterEmployeeCreditTotal();
            return new WaterEmployeeCreditTotal
            {
                TotalHeld = Dec(r, "totalheld"),
                StaffCount = r.GetInt32(r.GetOrdinal("staffcount")),
            };
        }

        public async Task<int> AddAsync(WaterEmployeeCreditAddRequest q)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT spwateremployeecredit_add(" +
                "p_farmid => @FarmId::text, p_waterstaffid => @StaffId::int, " +
                "p_entrytype => @Type::text, p_amount => @Amount::numeric, " +
                "p_entrydate => @Date::date, p_watercashaccountid => @AccountId::int, " +
                "p_paymentmethod => @Method::text, p_reference => @Ref::text, " +
                "p_description => @Desc::text, p_createdby => @By::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", q.FarmId);
            cmd.Parameters.AddWithValue("@StaffId", q.WaterStaffId);
            cmd.Parameters.AddWithValue("@Type", q.EntryType);
            cmd.Parameters.AddWithValue("@Amount", q.Amount);
            cmd.Parameters.AddWithValue("@Date", DbDate(q.EntryDate));
            cmd.Parameters.AddWithValue("@AccountId", Db(q.WaterCashAccountId));
            cmd.Parameters.AddWithValue("@Method", Db(q.PaymentMethod));
            cmd.Parameters.AddWithValue("@Ref", Db(q.Reference));
            cmd.Parameters.AddWithValue("@Desc", Db(q.Description));
            cmd.Parameters.AddWithValue("@By", Db(q.CreatedBy));
            await c.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task<int> PayoutAsync(WaterEmployeeCreditPayoutRequest q)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT spwateremployeecredit_payout(" +
                "p_farmid => @FarmId::text, p_waterstaffid => @StaffId::int, " +
                "p_amount => @Amount::numeric, p_watercashaccountid => @AccountId::int, " +
                "p_entrydate => @Date::date, p_paymentmethod => @Method::text, " +
                "p_reference => @Ref::text, p_description => @Desc::text, p_createdby => @By::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", q.FarmId);
            cmd.Parameters.AddWithValue("@StaffId", q.WaterStaffId);
            cmd.Parameters.AddWithValue("@Amount", q.Amount);
            cmd.Parameters.AddWithValue("@AccountId", q.WaterCashAccountId);
            cmd.Parameters.AddWithValue("@Date", DbDate(q.EntryDate));
            cmd.Parameters.AddWithValue("@Method", Db(q.PaymentMethod));
            cmd.Parameters.AddWithValue("@Ref", Db(q.Reference));
            cmd.Parameters.AddWithValue("@Desc", Db(q.Description));
            cmd.Parameters.AddWithValue("@By", Db(q.CreatedBy));
            await c.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task ReverseAsync(int id, WaterEmployeeCreditReverseRequest q)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT spwateremployeecredit_reverse(" +
                "p_farmid => @FarmId::text, p_wateremployeecreditid => @Id::int, " +
                "p_reason => @Reason::text, p_reversedby => @By::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", q.FarmId);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@Reason", Db(q.Reason));
            cmd.Parameters.AddWithValue("@By", Db(q.ActionBy));
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }
    }
}
