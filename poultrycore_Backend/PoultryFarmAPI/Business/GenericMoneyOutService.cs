using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    /// <summary>
    /// The Generic company's money-out side (migration 249): recurring expenses,
    /// staff and contractor payments, and owner contributions and draws.
    ///
    /// One service for three things because they end in the same two places --
    /// an expense and a cash movement -- and every write is a SINGLE function
    /// call for the usual reason: one statement is one implicit transaction, so
    /// a payment either lands completely or not at all.
    /// </summary>
    public interface IGenericMoneyOutService
    {
        // Recurring expenses
        Task<List<GenericRecurringExpenseRow>> GetRecurring(string farmId, string? status);
        Task<int> CreateRecurring(CreateRecurringExpenseRequest r);
        Task<int> SetRecurringStatus(int id, SetRecurringExpenseStatusRequest r);
        Task<List<RecurringExpensePreviewRow>> PreviewRecurring(string farmId, DateTime? asOf);
        Task<int> GenerateRecurring(GenerateRecurringRequest r);

        // Staff payments
        Task<List<GenericStaffPaymentRow>> GetStaffPayments(string farmId, int? staffId, DateTime? from, DateTime? to);
        Task<int> RecordStaffPayment(RecordStaffPaymentRequest r);
        Task<int> ReverseStaffPayment(string farmId, int paymentId, string? reason, string? reversedBy);

        // Owner money
        Task<List<GenericOwnerEntryRow>> GetOwnerEntries(string farmId, string? entryType, DateTime? from, DateTime? to);
        Task<int> RecordOwnerEntry(RecordOwnerEntryRequest r);
        Task<int> ReverseOwnerEntry(string farmId, int entryId, string? reason, string? reversedBy);
    }

    public class GenericMoneyOutService : IGenericMoneyOutService
    {
        private readonly string _connectionString;

        public GenericMoneyOutService(string connectionString) => _connectionString = connectionString;

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

        private static DateTime Date(NpgsqlDataReader r, string col)
        {
            var i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? default : r.GetDateTime(i);
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

        private async Task<int> Scalar(string sql, Action<NpgsqlCommand> bind)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand(sql, conn);
            bind(cmd);
            await conn.OpenAsync();
            var result = await cmd.ExecuteScalarAsync();
            return result is null || result is DBNull ? 0 : Convert.ToInt32(result);
        }

        // ------------------------------------------------------------- recurring

        public Task<List<GenericRecurringExpenseRow>> GetRecurring(string farmId, string? status) => Query(
            "SELECT * FROM spgenericrecurringexpense_getall(p_farmid => @FarmId::text, p_status => @Status::text)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                cmd.Parameters.AddWithValue("@Status", Db(status));
            },
            r => new GenericRecurringExpenseRow
            {
                GenericRecurringExpenseId = Int(r, "genericrecurringexpenseid"),
                FarmId = Str(r, "farmid") ?? string.Empty,
                ExpenseName = Str(r, "expensename") ?? string.Empty,
                GenericExpenseCategoryId = Int(r, "genericexpensecategoryid"),
                CategoryName = Str(r, "categoryname"),
                GenericSupplierId = IntN(r, "genericsupplierid"),
                SupplierName = Str(r, "suppliername"),
                Amount = Dec(r, "amount"),
                Frequency = Str(r, "frequency") ?? string.Empty,
                StartDate = Date(r, "startdate"),
                EndDate = DateN(r, "enddate"),
                NextDueDate = DateN(r, "nextduedate"),
                LastGeneratedDate = DateN(r, "lastgenerateddate"),
                PaymentMethod = Str(r, "paymentmethod"),
                DefaultCashAccountId = IntN(r, "defaultcashaccountid"),
                AutoPayOnGenerate = Bool(r, "autopayongenerate"),
                ReminderEnabled = Bool(r, "reminderenabled"),
                Status = Str(r, "status") ?? string.Empty,
                Notes = Str(r, "notes"),
                IsDue = Bool(r, "isdue"),
                GeneratedCount = Int(r, "generatedcount"),
                CreatedBy = Str(r, "createdby"),
                CreatedAt = DateN(r, "createdat"),
            });

        public Task<int> CreateRecurring(CreateRecurringExpenseRequest r) => Scalar(
            "SELECT spgenericrecurringexpense_insert(p_farmid => @FarmId::text, p_expensename => @Name::text, p_genericexpensecategoryid => @CategoryId::int, p_amount => @Amount::numeric, p_frequency => @Frequency::text, p_startdate => @StartDate::date, p_genericsupplierid => @SupplierId::int, p_enddate => @EndDate::date, p_paymentmethod => @Method::text, p_defaultcashaccountid => @CashAccountId::int, p_autopayongenerate => @AutoPay::boolean, p_reminderenabled => @Reminder::boolean, p_notes => @Notes::text, p_createdby => @CreatedBy::text)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", r.FarmId);
                cmd.Parameters.AddWithValue("@Name", r.ExpenseName);
                cmd.Parameters.AddWithValue("@CategoryId", r.GenericExpenseCategoryId);
                cmd.Parameters.AddWithValue("@Amount", r.Amount);
                cmd.Parameters.AddWithValue("@Frequency", r.Frequency);
                cmd.Parameters.AddWithValue("@StartDate", r.StartDate.Date);
                cmd.Parameters.AddWithValue("@SupplierId", Db(r.GenericSupplierId));
                cmd.Parameters.AddWithValue("@EndDate", DbDate(r.EndDate));
                cmd.Parameters.AddWithValue("@Method", Db(r.PaymentMethod));
                cmd.Parameters.AddWithValue("@CashAccountId", Db(r.DefaultCashAccountId));
                cmd.Parameters.AddWithValue("@AutoPay", r.AutoPayOnGenerate);
                cmd.Parameters.AddWithValue("@Reminder", r.ReminderEnabled);
                cmd.Parameters.AddWithValue("@Notes", Db(r.Notes));
                cmd.Parameters.AddWithValue("@CreatedBy", Db(r.CreatedBy));
            });

        public Task<int> SetRecurringStatus(int id, SetRecurringExpenseStatusRequest r) => Scalar(
            "SELECT spgenericrecurringexpense_setstatus(p_id => @Id::int, p_farmid => @FarmId::text, p_status => @Status::text, p_by => @By::text, p_reason => @Reason::text)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@Id", id);
                cmd.Parameters.AddWithValue("@FarmId", r.FarmId);
                cmd.Parameters.AddWithValue("@Status", r.Status);
                cmd.Parameters.AddWithValue("@By", Db(r.By));
                cmd.Parameters.AddWithValue("@Reason", Db(r.Reason));
            });

        /// <summary>
        /// What generating right now would raise. Preview and generate share the
        /// same selection in SQL, so the owner cannot be shown one set and have
        /// another raised.
        /// </summary>
        public Task<List<RecurringExpensePreviewRow>> PreviewRecurring(string farmId, DateTime? asOf) => Query(
            "SELECT * FROM spgenericrecurringexpense_preview(p_farmid => @FarmId::text, p_asof => @AsOf::date)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                cmd.Parameters.AddWithValue("@AsOf", DbDate(asOf));
            },
            r => new RecurringExpensePreviewRow
            {
                GenericRecurringExpenseId = Int(r, "genericrecurringexpenseid"),
                ExpenseName = Str(r, "expensename") ?? string.Empty,
                CategoryName = Str(r, "categoryname"),
                SupplierName = Str(r, "suppliername"),
                Amount = Dec(r, "amount"),
                Frequency = Str(r, "frequency") ?? string.Empty,
                PeriodStart = Date(r, "periodstart"),
                PeriodEnd = Date(r, "periodend"),
                AlreadyGenerated = Bool(r, "alreadygenerated"),
            });

        /// <summary>
        /// Raises one expense per unbilled period, catching up anything behind.
        /// Returns how many were raised. Running it twice raises nothing twice —
        /// a partial unique index on (farm, template, period) makes the second
        /// attempt fail rather than double the month.
        /// </summary>
        public Task<int> GenerateRecurring(GenerateRecurringRequest r) => Scalar(
            "SELECT spgenericrecurringexpense_generate(p_farmid => @FarmId::text, p_asof => @AsOf::date, p_createdby => @CreatedBy::text)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", r.FarmId);
                cmd.Parameters.AddWithValue("@AsOf", DbDate(r.AsOf));
                cmd.Parameters.AddWithValue("@CreatedBy", Db(r.CreatedBy));
            });

        // -------------------------------------------------------- staff payments

        public Task<List<GenericStaffPaymentRow>> GetStaffPayments(string farmId, int? staffId, DateTime? from, DateTime? to) => Query(
            "SELECT * FROM spgenericstaffpayment_getall(p_farmid => @FarmId::text, p_staffid => @StaffId::int, p_from => @From::date, p_to => @To::date)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                cmd.Parameters.AddWithValue("@StaffId", Db(staffId));
                cmd.Parameters.AddWithValue("@From", DbDate(from));
                cmd.Parameters.AddWithValue("@To", DbDate(to));
            },
            r => new GenericStaffPaymentRow
            {
                GenericStaffPaymentId = Int(r, "genericstaffpaymentid"),
                GenericStaffId = Int(r, "genericstaffid"),
                StaffName = Str(r, "staffname"),
                StaffRole = Str(r, "staffrole"),
                WorkerType = Str(r, "workertype"),
                PaymentDate = Date(r, "paymentdate"),
                PeriodStart = DateN(r, "periodstart"),
                PeriodEnd = DateN(r, "periodend"),
                Amount = Dec(r, "amount"),
                PaymentMethod = Str(r, "paymentmethod"),
                GenericCashAccountId = IntN(r, "genericcashaccountid"),
                CashAccountName = Str(r, "cashaccountname"),
                GenericExpenseId = IntN(r, "genericexpenseid"),
                CategoryName = Str(r, "categoryname"),
                Description = Str(r, "description"),
                ReferenceNo = Str(r, "referenceno"),
                Status = Str(r, "status") ?? "Posted",
                CreatedBy = Str(r, "createdby"),
                ReversedBy = Str(r, "reversedby"),
                ReversedAt = DateN(r, "reversedat"),
                ReversalReason = Str(r, "reversalreason"),
            });

        /// <summary>
        /// Pays one person now, without a payroll run. Posts the expense so the
        /// cost reaches the P&amp;L, and one CashOut so it reaches cash flow.
        /// </summary>
        public Task<int> RecordStaffPayment(RecordStaffPaymentRequest r) => Scalar(
            "SELECT spgenericstaffpayment_record(p_farmid => @FarmId::text, p_genericstaffid => @StaffId::int, p_amount => @Amount::numeric, p_paymentdate => @PaymentDate::timestamp, p_paymentmethod => @Method::text, p_cashaccountid => @CashAccountId::int, p_genericexpensecategoryid => @CategoryId::int, p_periodstart => @PeriodStart::date, p_periodend => @PeriodEnd::date, p_description => @Description::text, p_reference => @Reference::text, p_createdby => @CreatedBy::text)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", r.FarmId);
                cmd.Parameters.AddWithValue("@StaffId", r.GenericStaffId);
                cmd.Parameters.AddWithValue("@Amount", r.Amount);
                cmd.Parameters.AddWithValue("@PaymentDate", Db(r.PaymentDate));
                cmd.Parameters.AddWithValue("@Method", Db(r.PaymentMethod));
                cmd.Parameters.AddWithValue("@CashAccountId", Db(r.CashAccountId));
                cmd.Parameters.AddWithValue("@CategoryId", Db(r.GenericExpenseCategoryId));
                cmd.Parameters.AddWithValue("@PeriodStart", DbDate(r.PeriodStart));
                cmd.Parameters.AddWithValue("@PeriodEnd", DbDate(r.PeriodEnd));
                cmd.Parameters.AddWithValue("@Description", Db(r.Description));
                cmd.Parameters.AddWithValue("@Reference", Db(r.Reference));
                cmd.Parameters.AddWithValue("@CreatedBy", Db(r.CreatedBy));
            });

        /// <summary>
        /// Append-only: the payment row is marked Reversed and kept, its expense
        /// leaves the books, and the cash comes back as its own transaction
        /// rather than by editing the original.
        /// </summary>
        public Task<int> ReverseStaffPayment(string farmId, int paymentId, string? reason, string? reversedBy) => Scalar(
            "SELECT spgenericstaffpayment_reverse(p_farmid => @FarmId::text, p_paymentid => @PaymentId::int, p_reason => @Reason::text, p_reversedby => @ReversedBy::text)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                cmd.Parameters.AddWithValue("@PaymentId", paymentId);
                cmd.Parameters.AddWithValue("@Reason", Db(reason));
                cmd.Parameters.AddWithValue("@ReversedBy", Db(reversedBy));
            });

        // ------------------------------------------------------------ owner money

        public Task<List<GenericOwnerEntryRow>> GetOwnerEntries(string farmId, string? entryType, DateTime? from, DateTime? to) => Query(
            "SELECT * FROM spgenericownerentry_getall(p_farmid => @FarmId::text, p_entrytype => @EntryType::text, p_from => @From::date, p_to => @To::date)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                cmd.Parameters.AddWithValue("@EntryType", Db(entryType));
                cmd.Parameters.AddWithValue("@From", DbDate(from));
                cmd.Parameters.AddWithValue("@To", DbDate(to));
            },
            r => new GenericOwnerEntryRow
            {
                GenericOwnerEntryId = Int(r, "genericownerentryid"),
                EntryDate = Date(r, "entrydate"),
                EntryType = Str(r, "entrytype") ?? string.Empty,
                Amount = Dec(r, "amount"),
                GenericCashAccountId = IntN(r, "genericcashaccountid"),
                CashAccountName = Str(r, "cashaccountname"),
                PaymentMethod = Str(r, "paymentmethod"),
                OwnerName = Str(r, "ownername"),
                ReferenceNo = Str(r, "referenceno"),
                Notes = Str(r, "notes"),
                Status = Str(r, "status") ?? "Posted",
                CreatedBy = Str(r, "createdby"),
                ReversedBy = Str(r, "reversedby"),
                ReversedAt = DateN(r, "reversedat"),
                ReversalReason = Str(r, "reversalreason"),
            });

        /// <summary>
        /// Owner money moves cash and NOTHING else — no expense, no sale — so
        /// profit is unaffected by how the owner funds the business.
        /// </summary>
        public Task<int> RecordOwnerEntry(RecordOwnerEntryRequest r) => Scalar(
            "SELECT spgenericownerentry_record(p_farmid => @FarmId::text, p_entrytype => @EntryType::text, p_amount => @Amount::numeric, p_cashaccountid => @CashAccountId::int, p_entrydate => @EntryDate::timestamp, p_paymentmethod => @Method::text, p_ownername => @OwnerName::text, p_reference => @Reference::text, p_notes => @Notes::text, p_createdby => @CreatedBy::text)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", r.FarmId);
                cmd.Parameters.AddWithValue("@EntryType", r.EntryType);
                cmd.Parameters.AddWithValue("@Amount", r.Amount);
                cmd.Parameters.AddWithValue("@CashAccountId", Db(r.CashAccountId));
                cmd.Parameters.AddWithValue("@EntryDate", Db(r.EntryDate));
                cmd.Parameters.AddWithValue("@Method", Db(r.PaymentMethod));
                cmd.Parameters.AddWithValue("@OwnerName", Db(r.OwnerName));
                cmd.Parameters.AddWithValue("@Reference", Db(r.Reference));
                cmd.Parameters.AddWithValue("@Notes", Db(r.Notes));
                cmd.Parameters.AddWithValue("@CreatedBy", Db(r.CreatedBy));
            });

        public Task<int> ReverseOwnerEntry(string farmId, int entryId, string? reason, string? reversedBy) => Scalar(
            "SELECT spgenericownerentry_reverse(p_farmid => @FarmId::text, p_entryid => @EntryId::int, p_reason => @Reason::text, p_reversedby => @ReversedBy::text)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                cmd.Parameters.AddWithValue("@EntryId", entryId);
                cmd.Parameters.AddWithValue("@Reason", Db(reason));
                cmd.Parameters.AddWithValue("@ReversedBy", Db(reversedBy));
            });
    }
}
