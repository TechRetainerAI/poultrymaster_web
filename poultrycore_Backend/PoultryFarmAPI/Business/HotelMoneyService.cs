// =============================================================================
// Hotel money: Owner Money, Loans (Financing), Cash Transfers, Reconciliation,
// cash adjustments and the Cash Account status feed (migration 331).
//
// A thin caller of the 331 Postgres functions. Every money movement happens
// inside one of those functions, in one transaction, through fnhotelcash_post;
// nothing here writes a table. Rows are read by column NAME and returned with
// camelCase keys (the functions return lowercase column names).
// =============================================================================

using Npgsql;
using NpgsqlTypes;

namespace PoultryFarmAPIWeb.Business
{
    public interface IHotelMoneyService
    {
        // Cash accounts
        Task<List<Dictionary<string, object?>>> CashAccountStatusAsync(string farmId);
        Task UpdateCashAccountAsync(string farmId, int id, string name, string? type, bool? allowNegative, bool? isActive, string? notes, string? purpose);
        Task<int> RecalculateAsync(string farmId);
        Task<int> RecordAdjustmentAsync(string farmId, int accountId, decimal amount, string reason, string by);
        Task ReverseAdjustmentAsync(string farmId, int id, string reason, string by);

        // Owner money
        Task<List<Dictionary<string, object?>>> OwnerMoneyListAsync(string farmId, string? type, DateTime? from, DateTime? to, string? status);
        Task<Dictionary<string, object?>?> OwnerMoneySummaryAsync(string farmId, DateTime? from, DateTime? to);
        Task<int> RecordOwnerMoneyAsync(string farmId, string type, decimal amount, int accountId, DateTime? date, string? method, string? owner, string? reference, string? notes, string by);
        Task ReverseOwnerMoneyAsync(string farmId, int id, string reason, string by);

        // Loans
        Task<List<Dictionary<string, object?>>> LoanListAsync(string farmId, string? status);
        Task<Dictionary<string, object?>?> LoanSummaryAsync(string farmId);
        Task<List<Dictionary<string, object?>>> LoanPaymentListAsync(string farmId, int? loanId);
        Task<int> CreateLoanAsync(string farmId, HotelMoneyLoanInput i, string by);
        Task UpdateLoanAsync(string farmId, int id, HotelMoneyLoanInput i, string by);
        Task CancelLoanAsync(string farmId, int id, string reason, string by);
        Task<int> RecordLoanPaymentAsync(string farmId, int loanId, HotelMoneyLoanPaymentInput i, string by);
        Task ReverseLoanPaymentAsync(string farmId, int id, string reason, string by);

        // Transfers
        Task<List<Dictionary<string, object?>>> TransferListAsync(string farmId);
        Task<int> RecordTransferAsync(string farmId, int fromId, int toId, decimal amount, DateTime? date, string? reference, string? notes, string by);
        Task ReverseTransferAsync(string farmId, int id, string reason, string by);

        // Reconciliation
        Task<List<Dictionary<string, object?>>> ReconListAsync(string farmId, int? accountId);
        Task<int> ReconCreateAsync(string farmId, int accountId, DateTime? date, decimal? actual, string? reason, string? notes, string by);
        Task ReconUpdateAsync(string farmId, int id, DateTime? date, decimal? actual, string? reason, string? notes);
        Task ReconDeleteAsync(string farmId, int id);
        Task<int?> ReconPostAsync(string farmId, int id, string by);
        Task ReconReverseAsync(string farmId, int id, string reason, string by);
    }

    public class HotelMoneyLoanInput
    {
        public string? LenderName { get; set; }
        public string? LenderType { get; set; }
        public string? AccountNumber { get; set; }
        public decimal OriginalPrincipal { get; set; }
        public decimal AmountReceived { get; set; }
        public int? HotelCashAccountId { get; set; }
        public DateTime? StartDate { get; set; }
        public DateTime? LoanDate { get; set; }
        public decimal? InterestRate { get; set; }
        public string? InterestType { get; set; }
        public int? TermMonths { get; set; }
        public string? PaymentFrequency { get; set; }
        public DateTime? EndDate { get; set; }
        public DateTime? NextPaymentDate { get; set; }
        public string? Notes { get; set; }
    }

    public class HotelMoneyLoanPaymentInput
    {
        public int HotelCashAccountId { get; set; }
        public decimal PrincipalAmount { get; set; }
        public decimal InterestAmount { get; set; }
        public decimal FeeAmount { get; set; }
        public decimal OtherAmount { get; set; }
        public DateTime? PaymentDate { get; set; }
        public string? PaymentMethod { get; set; }
        public string? ReferenceNumber { get; set; }
        public string? Notes { get; set; }
        public DateTime? NextPaymentDate { get; set; }
    }

    public class HotelMoneyService : IHotelMoneyService
    {
        private readonly string _cs;
        public HotelMoneyService(string connectionString) { _cs = connectionString; }

        // lowercase column name -> the camelCase key the frontend reads.
        private static readonly Dictionary<string, string> Keys = new[]
        {
            "hotelCashAccountId", "accountName", "accountType", "isActive", "currentBalance", "ledgerBalance",
            "cacheDrift", "lastReconciledAt", "lastReconciledBalance", "daysSinceReconciled", "unclearedCount",
            "unclearedAmount", "hotelOwnerMoneyId", "transactionNumber", "transactionDate", "transactionType",
            "amount", "paymentMethod", "ownerName", "referenceNumber", "notes", "status", "createdBy", "createdAt",
            "reversedBy", "reversedAt", "reversalReason", "totalContributions", "totalDraws", "netFunding",
            "periodContributions", "periodDraws", "contributionCount", "drawCount", "hotelLoanId", "loanNumber",
            "lenderName", "lenderType", "accountNumber", "loanDate", "originalPrincipal", "amountReceived",
            "interestRate", "interestType", "termMonths", "paymentFrequency", "startDate", "endDate",
            "nextPaymentDate", "outstandingPrincipal", "totalPrincipalRepaid", "totalInterestPaid", "totalFeesPaid",
            "isOverdue", "paymentCount", "paidOffDate", "activeLoans", "totalBorrowed", "totalReceived",
            "overdueLoans", "hotelLoanPaymentId", "paymentNumber", "paymentDate", "totalAmount", "principalAmount",
            "interestAmount", "feeAmount", "otherAmount", "hotelCashTransferId", "transferNumber",
            "fromHotelCashAccountId", "fromAccountName", "toHotelCashAccountId", "toAccountName", "transferDate",
            "hotelCashReconciliationId", "referenceNo", "reconciliationDate", "systemBalance", "actualBalance",
            "difference", "reason", "adjustmentTransactionId", "postedAt",
        }.ToDictionary(k => k.ToLowerInvariant(), k => k);

        private static object Db(object? v) => v ?? DBNull.Value;

        private async Task<List<Dictionary<string, object?>>> RowsAsync(string sql, params (string name, object? value)[] ps)
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            await using var cmd = new NpgsqlCommand(sql, conn);
            foreach (var (n, v) in ps) cmd.Parameters.AddWithValue(n, Db(v));
            await using var r = await cmd.ExecuteReaderAsync();
            var list = new List<Dictionary<string, object?>>();
            while (await r.ReadAsync())
            {
                var d = new Dictionary<string, object?>();
                for (var i = 0; i < r.FieldCount; i++)
                {
                    var name = r.GetName(i);
                    d[Keys.TryGetValue(name, out var k) ? k : name] = r.IsDBNull(i) ? null : r.GetValue(i);
                }
                list.Add(d);
            }
            return list;
        }

        private async Task<object?> ScalarAsync(string sql, params (string name, object? value)[] ps)
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            await using var cmd = new NpgsqlCommand(sql, conn);
            foreach (var (n, v) in ps) cmd.Parameters.AddWithValue(n, Db(v));
            var o = await cmd.ExecuteScalarAsync();
            return o is DBNull ? null : o;
        }

        private static (string, object?) P(string n, object? v) => (n, v);
        private static object? D(DateTime? d) => d?.Date;

        // ---- cash accounts ------------------------------------------------------
        public Task<List<Dictionary<string, object?>>> CashAccountStatusAsync(string farmId) =>
            RowsAsync("SELECT * FROM sphotelcashaccount_countstatus(@f)", P("f", farmId));

        public Task UpdateCashAccountAsync(string farmId, int id, string name, string? type, bool? allowNegative, bool? isActive, string? notes, string? purpose) =>
            ScalarAsync("SELECT sphotelcashaccount_update(@f, @id, @n, @t, @neg, @act, @notes, @p)",
                P("f", farmId), P("id", id), P("n", name), P("t", type), P("neg", allowNegative), P("act", isActive), P("notes", notes), P("p", purpose));

        public async Task<int> RecalculateAsync(string farmId) =>
            Convert.ToInt32(await ScalarAsync("SELECT sphotelcashaccount_recalculate(@f)", P("f", farmId)));

        public async Task<int> RecordAdjustmentAsync(string farmId, int accountId, decimal amount, string reason, string by) =>
            Convert.ToInt32(await ScalarAsync("SELECT sphotelcashadjustment_record(@f, @a, @amt, @r, @by)",
                P("f", farmId), P("a", accountId), P("amt", amount), P("r", reason), P("by", by)));

        public Task ReverseAdjustmentAsync(string farmId, int id, string reason, string by) =>
            ScalarAsync("SELECT sphotelcashadjustment_reverse(@f, @id, @r, @by)", P("f", farmId), P("id", id), P("r", reason), P("by", by));

        // ---- owner money --------------------------------------------------------
        public Task<List<Dictionary<string, object?>>> OwnerMoneyListAsync(string farmId, string? type, DateTime? from, DateTime? to, string? status) =>
            RowsAsync("SELECT * FROM sphotelownermoney_list(@f, @t, @from::date, @to::date, @s)",
                P("f", farmId), P("t", type), P("from", D(from)), P("to", D(to)), P("s", status));

        public async Task<Dictionary<string, object?>?> OwnerMoneySummaryAsync(string farmId, DateTime? from, DateTime? to) =>
            (await RowsAsync("SELECT * FROM sphotelownermoney_summary(@f, @from::date, @to::date)",
                P("f", farmId), P("from", D(from)), P("to", D(to)))).FirstOrDefault();

        public async Task<int> RecordOwnerMoneyAsync(string farmId, string type, decimal amount, int accountId, DateTime? date, string? method, string? owner, string? reference, string? notes, string by) =>
            Convert.ToInt32(await ScalarAsync(
                "SELECT sphotelownermoney_record(@f, @t, @amt, @a, @d::timestamp, @m, @o, @ref, @n, @by)",
                P("f", farmId), P("t", type), P("amt", amount), P("a", accountId), P("d", date), P("m", method),
                P("o", owner), P("ref", reference), P("n", notes), P("by", by)));

        public Task ReverseOwnerMoneyAsync(string farmId, int id, string reason, string by) =>
            ScalarAsync("SELECT sphotelownermoney_reverse(@f, @id, @r, @by)", P("f", farmId), P("id", id), P("r", reason), P("by", by));

        // ---- loans --------------------------------------------------------------
        public Task<List<Dictionary<string, object?>>> LoanListAsync(string farmId, string? status) =>
            RowsAsync("SELECT * FROM sphotelloan_list(@f, @s)", P("f", farmId), P("s", status));

        public async Task<Dictionary<string, object?>?> LoanSummaryAsync(string farmId) =>
            (await RowsAsync("SELECT * FROM sphotelloan_summary(@f)", P("f", farmId))).FirstOrDefault();

        public Task<List<Dictionary<string, object?>>> LoanPaymentListAsync(string farmId, int? loanId) =>
            RowsAsync("SELECT * FROM sphotelloanpayment_list(@f, @l)", P("f", farmId), P("l", loanId));

        public async Task<int> CreateLoanAsync(string farmId, HotelMoneyLoanInput i, string by) =>
            Convert.ToInt32(await ScalarAsync(
                "SELECT sphotelloan_create(@f, @lender, @princ, @start::date, @recv, @acct, @ltype, @accno, @ldate::date, " +
                "@rate, @itype, @term, @freq, @end::date, @next::date, @notes, @by)",
                P("f", farmId), P("lender", i.LenderName), P("princ", i.OriginalPrincipal), P("start", D(i.StartDate)),
                P("recv", i.AmountReceived), P("acct", i.HotelCashAccountId), P("ltype", i.LenderType ?? "Other"),
                P("accno", i.AccountNumber), P("ldate", D(i.LoanDate)), P("rate", i.InterestRate), P("itype", i.InterestType),
                P("term", i.TermMonths), P("freq", i.PaymentFrequency), P("end", D(i.EndDate)), P("next", D(i.NextPaymentDate)),
                P("notes", i.Notes), P("by", by)));

        public Task UpdateLoanAsync(string farmId, int id, HotelMoneyLoanInput i, string by) =>
            ScalarAsync("SELECT sphotelloan_update(@f, @id, @lender, @ltype, @accno, @rate, @itype, @term, @freq, @end::date, @next::date, @notes, @by)",
                P("f", farmId), P("id", id), P("lender", i.LenderName), P("ltype", i.LenderType), P("accno", i.AccountNumber),
                P("rate", i.InterestRate), P("itype", i.InterestType), P("term", i.TermMonths), P("freq", i.PaymentFrequency),
                P("end", D(i.EndDate)), P("next", D(i.NextPaymentDate)), P("notes", i.Notes), P("by", by));

        public Task CancelLoanAsync(string farmId, int id, string reason, string by) =>
            ScalarAsync("SELECT sphotelloan_cancel(@f, @id, @r, @by)", P("f", farmId), P("id", id), P("r", reason), P("by", by));

        public async Task<int> RecordLoanPaymentAsync(string farmId, int loanId, HotelMoneyLoanPaymentInput i, string by) =>
            Convert.ToInt32(await ScalarAsync(
                "SELECT sphotelloanpayment_record(@f, @l, @a, @pr, @in, @fee, @oth, @d::timestamp, @m, @ref, @n, @next::date, @by)",
                P("f", farmId), P("l", loanId), P("a", i.HotelCashAccountId), P("pr", i.PrincipalAmount), P("in", i.InterestAmount),
                P("fee", i.FeeAmount), P("oth", i.OtherAmount), P("d", i.PaymentDate), P("m", i.PaymentMethod),
                P("ref", i.ReferenceNumber), P("n", i.Notes), P("next", D(i.NextPaymentDate)), P("by", by)));

        public Task ReverseLoanPaymentAsync(string farmId, int id, string reason, string by) =>
            ScalarAsync("SELECT sphotelloanpayment_reverse(@f, @id, @r, @by)", P("f", farmId), P("id", id), P("r", reason), P("by", by));

        // ---- transfers ----------------------------------------------------------
        public Task<List<Dictionary<string, object?>>> TransferListAsync(string farmId) =>
            RowsAsync("SELECT * FROM sphotelcashtransfer_list(@f)", P("f", farmId));

        public async Task<int> RecordTransferAsync(string farmId, int fromId, int toId, decimal amount, DateTime? date, string? reference, string? notes, string by) =>
            Convert.ToInt32(await ScalarAsync("SELECT sphotelcashtransfer_record(@f, @from, @to, @amt, @d::timestamp, @ref, @n, @by)",
                P("f", farmId), P("from", fromId), P("to", toId), P("amt", amount), P("d", date), P("ref", reference), P("n", notes), P("by", by)));

        public Task ReverseTransferAsync(string farmId, int id, string reason, string by) =>
            ScalarAsync("SELECT sphotelcashtransfer_reverse(@f, @id, @r, @by)", P("f", farmId), P("id", id), P("r", reason), P("by", by));

        // ---- reconciliation -----------------------------------------------------
        public Task<List<Dictionary<string, object?>>> ReconListAsync(string farmId, int? accountId) =>
            RowsAsync("SELECT * FROM sphotelcashrecon_list(@f, @a)", P("f", farmId), P("a", accountId));

        public async Task<int> ReconCreateAsync(string farmId, int accountId, DateTime? date, decimal? actual, string? reason, string? notes, string by) =>
            Convert.ToInt32(await ScalarAsync("SELECT sphotelcashrecon_insert(@f, @a, @d::timestamp, @act::numeric, @r, @n, @by)",
                P("f", farmId), P("a", accountId), P("d", date), P("act", actual), P("r", reason), P("n", notes), P("by", by)));

        public Task ReconUpdateAsync(string farmId, int id, DateTime? date, decimal? actual, string? reason, string? notes) =>
            ScalarAsync("SELECT sphotelcashrecon_update(@f, @id, @d::timestamp, @act::numeric, @r, @n)",
                P("f", farmId), P("id", id), P("d", date), P("act", actual), P("r", reason), P("n", notes));

        public Task ReconDeleteAsync(string farmId, int id) =>
            ScalarAsync("SELECT sphotelcashrecon_delete(@f, @id)", P("f", farmId), P("id", id));

        public async Task<int?> ReconPostAsync(string farmId, int id, string by)
        {
            var o = await ScalarAsync("SELECT sphotelcashrecon_post(@f, @id, @by)", P("f", farmId), P("id", id), P("by", by));
            return o == null ? null : Convert.ToInt32(o);
        }

        public Task ReconReverseAsync(string farmId, int id, string reason, string by) =>
            ScalarAsync("SELECT sphotelcashrecon_reverse(@f, @id, @r, @by)", P("f", farmId), P("id", id), P("r", reason), P("by", by));
    }
}
