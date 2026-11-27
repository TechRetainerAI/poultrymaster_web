using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    // Generic supplier credit, advances, refunds and supplier debts (migration
    // 449, Report 40). The water twin's code (WaterBalanceService, 426) on the
    // spgeneric* functions: same DTOs, so the shared Poultry Supplier Credits
    // page, dialogs and supplier-debt buttons work for Generic unchanged.
    public interface IGenericSupplierCreditsLedgerService
    {
        Task<List<SupplierCreditSummaryRow>> GetSupplierCreditSummary(string farmId);
        Task<List<SupplierCreditEventRow>> GetSupplierCreditEvents(string farmId, int? supplierId);
        Task<List<SupplierCreditApplicationRow>> GetSupplierCreditApplications(string farmId, int? supplierId);
        Task<int> CreateSupplierCredit(SupplierCreditCreateRequest r);
        Task<int> ReverseSupplierCredit(int paymentId, SupplierReasonRequest r);
        Task<int> ApplySupplierCredit(SupplierCreditApplyRequest r);
        Task<int> UnapplySupplierCredit(int allocationId, SupplierReasonRequest r);
        Task<int> RecordSupplierRefund(SupplierRefundRequest r);
        Task<int> ReverseSupplierRefund(int refundId, SupplierReasonRequest r);
        Task<List<SupplierRefundRow>> GetSupplierRefunds(string farmId, int? supplierId);
        Task<string> CreateSupplierDebt(SupplierDebtRequest r);
        Task<int> ReverseSupplierDebt(int debtId, SupplierReasonRequest r);
        Task<List<SupplierDebtRow>> GetSupplierDebts(string farmId, int? supplierId);
    }

    public class GenericSupplierCreditsLedgerService : IGenericSupplierCreditsLedgerService
    {
        private readonly string _connectionString;
        public GenericSupplierCreditsLedgerService(string connectionString) => _connectionString = connectionString;

        // ---------------------------------------------------------------- helpers

        private static object Db(object? v) => v ?? DBNull.Value;
        private static object DbDate(DateTime? v) => v.HasValue ? v.Value.Date : DBNull.Value;

        private static string? Str(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? null : r.GetString(i);
        }

        private static decimal Dec(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? 0m : r.GetDecimal(i);
        }

        private static int Int(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? 0 : Convert.ToInt32(r.GetValue(i));
        }

        private static int? IntN(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? null : Convert.ToInt32(r.GetValue(i));
        }

        private static decimal? DecN(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? null : r.GetDecimal(i);
        }

        private static string? GuidN(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? null : r.GetGuid(i).ToString();
        }

        private static DateTime? DateN(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? null : r.GetDateTime(i);
        }

        private static bool Bool(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return !r.IsDBNull(i) && r.GetBoolean(i);
        }

        private async Task<List<T>> Query<T>(string sql, Action<NpgsqlCommand> bind, Func<NpgsqlDataReader, T> map)
        {
            var list = new List<T>();
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand(sql, conn);
            bind(cmd);
            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync()) list.Add(map(reader));
            return list;
        }

        
        // ------------------------------------------------- 426 supplier credit
        // Translated from PoultryBalanceService (370): same DTOs, generic functions,
        // generic column names mapped onto the shared fields.

        private async Task<int> ScalarInt(string sql, Action<NpgsqlCommand> bind)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand(sql, conn);
            bind(cmd);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public Task<List<SupplierCreditSummaryRow>> GetSupplierCreditSummary(string farmId) => Query(
            "SELECT * FROM spgenericsuppliercredit_summary(p_farmid => @FarmId::text)",
            cmd => cmd.Parameters.AddWithValue("@FarmId", farmId),
            r => new SupplierCreditSummaryRow
            {
                SupplierId = Int(r, "supplierid"),
                SupplierName = Str(r, "suppliername") ?? string.Empty,
                AvailableCredit = Dec(r, "availablecredit"),
                CreditCount = Int(r, "creditcount"),
                Owed = Dec(r, "owed"),
            });

        public Task<List<SupplierCreditEventRow>> GetSupplierCreditEvents(string farmId, int? supplierId) => Query(
            "SELECT * FROM spgenericsuppliercredit_events(p_farmid => @FarmId::text, p_supplierid => @SupplierId::int)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                cmd.Parameters.AddWithValue("@SupplierId", (object?)supplierId ?? DBNull.Value);
            },
            r => new SupplierCreditEventRow
            {
                PoultrySupplierPaymentId = Int(r, "genericsupplierpaymentid"),
                CreditNumber = Str(r, "creditnumber") ?? string.Empty,
                CreditDate = DateN(r, "creditdate"),
                SupplierId = Int(r, "supplierid"),
                SupplierName = Str(r, "suppliername"),
                Source = Str(r, "source") ?? string.Empty,
                SourceType = Str(r, "sourcetype"),
                Reference = Str(r, "reference"),
                Notes = Str(r, "notes"),
                OriginalAmount = Dec(r, "originalamount"),
                Applied = Dec(r, "applied"),
                Refunded = Dec(r, "refunded"),
                Available = Dec(r, "available"),
                Status = Str(r, "status") ?? string.Empty,
                IsManual = Bool(r, "ismanual"),
                PoultryCashAccountId = IntN(r, "genericcashaccountid"),
                AccountName = Str(r, "accountname"),
            });

        public Task<List<SupplierCreditApplicationRow>> GetSupplierCreditApplications(string farmId, int? supplierId) => Query(
            "SELECT * FROM spgenericsuppliercredit_applications(p_farmid => @FarmId::text, p_supplierid => @SupplierId::int)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                cmd.Parameters.AddWithValue("@SupplierId", (object?)supplierId ?? DBNull.Value);
            },
            r => new SupplierCreditApplicationRow
            {
                AllocationId = Int(r, "allocationid"),
                PoultrySupplierPaymentId = Int(r, "genericsupplierpaymentid"),
                CreditNumber = Str(r, "creditnumber") ?? string.Empty,
                SupplierId = Int(r, "supplierid"),
                SupplierName = Str(r, "suppliername"),
                DocumentType = Str(r, "documenttype") ?? string.Empty,
                DocumentId = Int(r, "documentid"),
                Reference = Str(r, "reference"),
                Label = Str(r, "label"),
                Amount = Dec(r, "amount"),
                AppliedDate = DateN(r, "applieddate"),
                Status = Str(r, "status") ?? "Posted",
                CreatedBy = Str(r, "createdby"),
                ReversedAt = DateN(r, "reversedat"),
                ReversalReason = Str(r, "reversalreason"),
            });

        // 501: a supplier credit IS a supplier payment row, so its project is the
        // payment's designated advance split ("SupplierPayment"), saved in the
        // same statement as the credit.
        private const string CreateManualCall =
            "spgenericsuppliercredit_createmanual(p_farmid => @FarmId::text, p_supplierid => @SupplierId::int, " +
            "p_kind => @Kind::text, p_amount => @Amount::numeric, p_date => @Date::timestamp, " +
            "p_reference => @Reference::text, p_reason => @Reason::text, p_by => @By::text)";

        public Task<int> CreateSupplierCredit(SupplierCreditCreateRequest r) => ScalarInt(
            GenericProjectAttach.Has(r.Projects)
                ? GenericProjectAttach.WrapInsert(CreateManualCall, "SupplierPayment")
                : "SELECT " + CreateManualCall,
            cmd =>
            {
                if (GenericProjectAttach.Has(r.Projects)) GenericProjectAttach.AddParams(cmd, r.FarmId, r.Projects, r.CreatedBy);
                cmd.Parameters.AddWithValue("@FarmId", r.FarmId);
                cmd.Parameters.AddWithValue("@SupplierId", r.SupplierId);
                cmd.Parameters.AddWithValue("@Kind", r.Kind ?? string.Empty);
                cmd.Parameters.AddWithValue("@Amount", r.Amount);
                cmd.Parameters.AddWithValue("@Date", r.CreditDate.HasValue ? r.CreditDate.Value : DBNull.Value);
                cmd.Parameters.AddWithValue("@Reference", Db(r.Reference));
                cmd.Parameters.AddWithValue("@Reason", r.Reason ?? string.Empty);
                cmd.Parameters.AddWithValue("@By", Db(r.CreatedBy));
            });

        public Task<int> ReverseSupplierCredit(int paymentId, SupplierReasonRequest r) => ScalarInt(
            "SELECT spgenericsuppliercredit_reverse(p_farmid => @FarmId::text, p_paymentid => @Id::int, p_reason => @Reason::text, p_by => @By::text)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", r.FarmId);
                cmd.Parameters.AddWithValue("@Id", paymentId);
                cmd.Parameters.AddWithValue("@Reason", r.Reason ?? string.Empty);
                cmd.Parameters.AddWithValue("@By", Db(r.By));
            });

        public Task<int> ApplySupplierCredit(SupplierCreditApplyRequest r) => ScalarInt(
            "SELECT spgenericsuppliercredit_apply(p_farmid => @FarmId::text, p_paymentid => @Id::int, " +
            "p_documenttype => @Type::text, p_documentid => @Doc::int, p_amount => @Amount::numeric, p_by => @By::text)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", r.FarmId);
                cmd.Parameters.AddWithValue("@Id", r.PoultrySupplierPaymentId);
                cmd.Parameters.AddWithValue("@Type", r.DocumentType ?? string.Empty);
                cmd.Parameters.AddWithValue("@Doc", r.DocumentId);
                cmd.Parameters.AddWithValue("@Amount", r.Amount);
                cmd.Parameters.AddWithValue("@By", Db(r.CreatedBy));
            });

        public Task<int> UnapplySupplierCredit(int allocationId, SupplierReasonRequest r) => ScalarInt(
            "SELECT spgenericsuppliercredit_unapply(p_farmid => @FarmId::text, p_allocationid => @Id::int, p_reason => @Reason::text, p_by => @By::text)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", r.FarmId);
                cmd.Parameters.AddWithValue("@Id", allocationId);
                cmd.Parameters.AddWithValue("@Reason", r.Reason ?? string.Empty);
                cmd.Parameters.AddWithValue("@By", Db(r.By));
            });

        public Task<int> RecordSupplierRefund(SupplierRefundRequest r) => ScalarInt(
            "SELECT spgenericsupplierrefund_record(p_farmid => @FarmId::text, p_paymentid => @Id::int, p_amount => @Amount::numeric, " +
            "p_cashaccountid => @Account::int, p_paymentmethod => @Method::text, p_refunddate => @Date::date, " +
            "p_reason => @Reason::text, p_by => @By::text)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", r.FarmId);
                cmd.Parameters.AddWithValue("@Id", r.PoultrySupplierPaymentId);
                cmd.Parameters.AddWithValue("@Amount", r.Amount);
                cmd.Parameters.AddWithValue("@Account", r.PoultryCashAccountId);
                cmd.Parameters.AddWithValue("@Method", Db(r.PaymentMethod));
                cmd.Parameters.AddWithValue("@Date", DbDate(r.RefundDate));
                cmd.Parameters.AddWithValue("@Reason", r.Reason ?? string.Empty);
                cmd.Parameters.AddWithValue("@By", Db(r.CreatedBy));
            });

        public Task<int> ReverseSupplierRefund(int refundId, SupplierReasonRequest r) => ScalarInt(
            "SELECT spgenericsupplierrefund_reverse(p_farmid => @FarmId::text, p_refundid => @Id::int, p_reason => @Reason::text, p_by => @By::text)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", r.FarmId);
                cmd.Parameters.AddWithValue("@Id", refundId);
                cmd.Parameters.AddWithValue("@Reason", r.Reason ?? string.Empty);
                cmd.Parameters.AddWithValue("@By", Db(r.By));
            });

        public Task<List<SupplierRefundRow>> GetSupplierRefunds(string farmId, int? supplierId) => Query(
            "SELECT * FROM spgenericsupplierrefund_list(p_farmid => @FarmId::text, p_supplierid => @SupplierId::int)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                cmd.Parameters.AddWithValue("@SupplierId", (object?)supplierId ?? DBNull.Value);
            },
            r => new SupplierRefundRow
            {
                RefundId = Int(r, "refundid"),
                RefundNumber = Str(r, "refundnumber") ?? string.Empty,
                SupplierId = Int(r, "supplierid"),
                SupplierName = Str(r, "suppliername"),
                Amount = Dec(r, "amount"),
                RefundDate = DateN(r, "refunddate"),
                PoultryCashAccountId = Int(r, "genericcashaccountid"),
                AccountName = Str(r, "accountname"),
                PaymentMethod = Str(r, "paymentmethod"),
                Reason = Str(r, "reason") ?? string.Empty,
                Status = Str(r, "status") ?? "Posted",
                CreatedBy = Str(r, "createdby"),
                CreatedAt = DateN(r, "createdat"),
                CreditNumbers = Str(r, "creditnumbers"),
                ReversedAt = DateN(r, "reversedat"),
                ReversedBy = Str(r, "reversedby"),
                ReversalReason = Str(r, "reversalreason"),
                ReversalDate = DateN(r, "reversaldate"),
            });

        public async Task<string> CreateSupplierDebt(SupplierDebtRequest r)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand(
                "SELECT spgenericsupplierdebt_create(p_farmid => @FarmId::text, p_supplierid => @SupplierId::int, " +
                "p_amount => @Amount::numeric, p_debtdate => @Date::date, p_entrytype => @Type::text, " +
                "p_description => @Description::text, p_reference => @Reference::text, p_notes => @Notes::text, " +
                "p_by => @By::text)::text", conn);
            cmd.Parameters.AddWithValue("@FarmId", r.FarmId);
            cmd.Parameters.AddWithValue("@SupplierId", r.SupplierId);
            cmd.Parameters.AddWithValue("@Amount", r.Amount);
            cmd.Parameters.AddWithValue("@Date", DbDate(r.DebtDate));
            cmd.Parameters.AddWithValue("@Type", r.EntryType ?? string.Empty);
            cmd.Parameters.AddWithValue("@Description", r.Description ?? string.Empty);
            cmd.Parameters.AddWithValue("@Reference", Db(r.Reference));
            cmd.Parameters.AddWithValue("@Notes", Db(r.Notes));
            cmd.Parameters.AddWithValue("@By", Db(r.CreatedBy));
            await conn.OpenAsync();
            return (string?)await cmd.ExecuteScalarAsync() ?? "{}";
        }

        public Task<int> ReverseSupplierDebt(int debtId, SupplierReasonRequest r) => ScalarInt(
            "SELECT spgenericsupplierdebt_reverse(p_farmid => @FarmId::text, p_debtid => @Id::int, p_reason => @Reason::text, p_by => @By::text)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", r.FarmId);
                cmd.Parameters.AddWithValue("@Id", debtId);
                cmd.Parameters.AddWithValue("@Reason", r.Reason ?? string.Empty);
                cmd.Parameters.AddWithValue("@By", Db(r.By));
            });

        public Task<List<SupplierDebtRow>> GetSupplierDebts(string farmId, int? supplierId) => Query(
            "SELECT * FROM spgenericsupplierdebt_list(p_farmid => @FarmId::text, p_supplierid => @SupplierId::int)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                cmd.Parameters.AddWithValue("@SupplierId", (object?)supplierId ?? DBNull.Value);
            },
            r => new SupplierDebtRow
            {
                DebtId = Int(r, "debtid"),
                DebtNumber = Str(r, "debtnumber") ?? string.Empty,
                SupplierId = Int(r, "supplierid"),
                SupplierName = Str(r, "suppliername"),
                Amount = Dec(r, "amount"),
                Paid = Dec(r, "paid"),
                Balance = Dec(r, "balance"),
                DebtDate = DateN(r, "debtdate"),
                EntryType = Str(r, "entrytype") ?? string.Empty,
                Description = Str(r, "description") ?? string.Empty,
                Reference = Str(r, "reference"),
                Notes = Str(r, "notes"),
                Status = Str(r, "status") ?? "Posted",
                CreatedBy = Str(r, "createdby"),
                CreatedAt = DateN(r, "createdat"),
                ReversedBy = Str(r, "reversedby"),
                ReversedAt = DateN(r, "reversedat"),
                ReversalReason = Str(r, "reversalreason"),
            });
    }
}
