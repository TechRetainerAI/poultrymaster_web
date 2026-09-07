using System.Text.Json;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    /// <summary>
    /// Reads and writes for the Generic company's Customer Balances page
    /// (migration 244 -- the migration 222 promised and nobody wrote).
    ///
    /// Every write is a SINGLE function call, for the same reason as
    /// PoultryBalanceService: a PostgreSQL function invoked as one statement
    /// runs in one implicit transaction, so a payment either lands completely --
    /// header, allocations, invoice balances, customer ledger, customer balance
    /// and cash -- or not at all.
    ///
    /// Mapping is thinner than the poultry service because migration 244 was
    /// written to return the API's own column names (partyid, documenttype,
    /// balancebefore, ...) rather than table-specific ones.
    /// </summary>
    public class GenericBalanceService : IGenericBalanceService
    {
        private readonly string _connectionString;

        public GenericBalanceService(string connectionString) => _connectionString = connectionString;

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

        /// <summary>
        /// The allocation grid, as the JSON spgenericcustomerpayment_record expects.
        /// Keys are lower case on purpose -- jsonb_to_recordset matches them
        /// case-sensitively against unquoted (therefore lower-cased) column
        /// identifiers, and a camelCase key would silently produce NULL rows.
        /// Migration 214 lost a whole entry's lines to exactly that.
        /// </summary>
        private static string AllocationsJson(IEnumerable<PaymentAllocationInput> allocations)
        {
            var rows = allocations.Select(a => new Dictionary<string, object?>
            {
                ["saleid"] = a.SaleId != 0 ? a.SaleId : a.DocumentId,
                ["amount"] = a.Amount,
            });
            return JsonSerializer.Serialize(rows);
        }

        /// <summary>
        /// The supplier grid. Generic payables span TWO tables -- purchases and
        /// expenses -- so an id alone is ambiguous and the type has to travel
        /// with it. Keys lower case, for the same jsonb_to_recordset reason.
        /// </summary>
        private static string SupplierAllocationsJson(IEnumerable<PaymentAllocationInput> allocations)
        {
            var rows = allocations.Select(a => new Dictionary<string, object?>
            {
                ["documenttype"] = string.IsNullOrWhiteSpace(a.DocumentType)
                    ? PayableDocumentTypes.Purchase
                    : a.DocumentType,
                ["documentid"] = a.DocumentId != 0 ? a.DocumentId : a.SaleId,
                ["amount"] = a.Amount,
            });
            return JsonSerializer.Serialize(rows);
        }

        // ------------------------------------------------------------- balances

        public Task<List<PartyBalanceRow>> GetCustomerBalances(BalanceQuery q) => Query(
            "SELECT * FROM spgenericcustomerbalances(p_farmid => @FarmId::text, p_from => @From::date, p_to => @To::date, p_customerid => @PartyId::int, p_status => @Status::text, p_minbalance => @MinBalance::numeric, p_search => @Search::text)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", q.FarmId);
                cmd.Parameters.AddWithValue("@From", DbDate(q.From));
                cmd.Parameters.AddWithValue("@To", DbDate(q.To));
                cmd.Parameters.AddWithValue("@PartyId", Db(q.PartyId));
                cmd.Parameters.AddWithValue("@Status", Db(q.Status ?? BalanceStatusFilters.All));
                cmd.Parameters.AddWithValue("@MinBalance", Db(q.MinBalance));
                cmd.Parameters.AddWithValue("@Search", Db(q.Search));
            },
            r => new PartyBalanceRow
            {
                PartyId = Int(r, "partyid"),
                PartyName = Str(r, "partyname") ?? string.Empty,
                ContactPhone = Str(r, "contactphone"),
                ContactEmail = Str(r, "contactemail"),
                PaymentTermsDays = Int(r, "paymenttermsdays"),
                TotalBalance = Dec(r, "totalbalance"),
                OpenDocumentCount = Int(r, "opendocumentcount"),
                OldestDocumentDate = DateN(r, "oldestdocumentdate"),
                LatestDocumentDate = DateN(r, "latestdocumentdate"),
                LastPaymentDate = DateN(r, "lastpaymentdate"),
                OverdueAmount = Dec(r, "overdueamount"),
                TotalInvoiced = Dec(r, "totalinvoiced"),
                TotalPaid = Dec(r, "totalpaid"),
            });

        public async Task<BalanceSummary> GetCustomerSummary(string farmId)
        {
            var rows = await Query(
                "SELECT * FROM spgenericcustomerbalancesummary(p_farmid => @FarmId::text)",
                cmd => cmd.Parameters.AddWithValue("@FarmId", farmId),
                r => new BalanceSummary
                {
                    TotalBalance = Dec(r, "totalbalance"),
                    PartyCount = Int(r, "partycount"),
                    OverdueBalance = Dec(r, "overduebalance"),
                    PaymentsToday = Dec(r, "paymentstoday"),
                    LargestBalance = Dec(r, "largestbalance"),
                    LargestBalanceParty = Str(r, "largestbalanceparty"),
                });
            return rows.FirstOrDefault() ?? new BalanceSummary();
        }

        public Task<List<OpenDocumentRow>> GetOpenInvoices(string farmId, int customerId, DateTime? from, DateTime? to, string? status) => Query(
            "SELECT * FROM spgenericcustomeropeninvoices(p_farmid => @FarmId::text, p_customerid => @PartyId::int, p_from => @From::date, p_to => @To::date, p_status => @Status::text)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                cmd.Parameters.AddWithValue("@PartyId", customerId);
                cmd.Parameters.AddWithValue("@From", DbDate(from));
                cmd.Parameters.AddWithValue("@To", DbDate(to));
                cmd.Parameters.AddWithValue("@Status", Db(status ?? BalanceStatusFilters.All));
            },
            r => new OpenDocumentRow
            {
                DocumentType = Str(r, "documenttype") ?? "Sale",
                DocumentId = Int(r, "documentid"),
                Reference = Str(r, "reference"),
                DocumentDate = r.GetDateTime(r.GetOrdinal("documentdate")),
                Label = Str(r, "label"),
                TotalAmount = Dec(r, "totalamount"),
                AmountPaid = Dec(r, "amountpaid"),
                Balance = Dec(r, "balance"),
                DueDate = DateN(r, "duedate"),
                AgeDays = Int(r, "agedays"),
                Status = Str(r, "status") ?? string.Empty,
                IsOverdue = Bool(r, "isoverdue"),
                CashAccountId = IntN(r, "cashaccountid"),
            });

        // -------------------------------------------------------------- payments

        public async Task<int> RecordCustomerPayment(RecordPaymentRequest r)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand(
                "SELECT spgenericcustomerpayment_record(p_farmid => @FarmId::text, p_customerid => @PartyId::int, p_amount => @Amount::numeric, p_allocations => @Allocations::jsonb, p_paymentmethod => @PaymentMethod::text, p_paymentdate => @PaymentDate::timestamp, p_cashaccountid => @CashAccountId::int, p_reference => @Reference::text, p_notes => @Notes::text, p_sourcetype => @SourceType::text, p_createdby => @CreatedBy::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", r.FarmId);
            cmd.Parameters.AddWithValue("@PartyId", Db(r.PartyId));
            cmd.Parameters.AddWithValue("@Amount", r.Amount);
            cmd.Parameters.AddWithValue("@Allocations", AllocationsJson(r.Allocations));
            cmd.Parameters.AddWithValue("@PaymentMethod", Db(r.PaymentMethod));
            cmd.Parameters.AddWithValue("@PaymentDate", Db(r.PaymentDate));
            cmd.Parameters.AddWithValue("@CashAccountId", Db(r.CashAccountId));
            cmd.Parameters.AddWithValue("@Reference", Db(r.Reference));
            cmd.Parameters.AddWithValue("@Notes", Db(r.Notes));
            cmd.Parameters.AddWithValue("@SourceType", Db(r.SourceType ?? PaymentSourceTypes.CustomerBalances));
            cmd.Parameters.AddWithValue("@CreatedBy", Db(r.CreatedBy));

            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task<int> ReverseCustomerPayment(string farmId, int paymentId, string? reason, string? reversedBy)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand(
                "SELECT spgenericcustomerpayment_reverse(p_farmid => @FarmId::text, p_paymentid => @PaymentId::int, p_reason => @Reason::text, p_reversedby => @ReversedBy::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@PaymentId", paymentId);
            cmd.Parameters.AddWithValue("@Reason", Db(reason));
            cmd.Parameters.AddWithValue("@ReversedBy", Db(reversedBy));
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public Task<List<PaymentHistoryRow>> GetCustomerPayments(string farmId, int? customerId, int? saleId, DateTime? from, DateTime? to) => Query(
            "SELECT * FROM spgenericcustomerpayment_history(p_farmid => @FarmId::text, p_customerid => @PartyId::int, p_saleid => @DocumentId::int, p_from => @From::date, p_to => @To::date)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                cmd.Parameters.AddWithValue("@PartyId", Db(customerId));
                cmd.Parameters.AddWithValue("@DocumentId", Db(saleId));
                cmd.Parameters.AddWithValue("@From", DbDate(from));
                cmd.Parameters.AddWithValue("@To", DbDate(to));
            },
            r => new PaymentHistoryRow
            {
                // An int, not a uuid: genericcustomerpayments already stores one
                // row per payment, so there is no group to stand in for it.
                // The DTO carries it as a string either way.
                PaymentId = Int(r, "paymentid").ToString(),
                PartyId = IntN(r, "partyid"),
                PartyName = Str(r, "partyname"),
                PaymentDate = r.GetDateTime(r.GetOrdinal("paymentdate")),
                TotalAmount = Dec(r, "totalamount"),
                PaymentMethod = Str(r, "paymentmethod"),
                Reference = Str(r, "reference"),
                Notes = Str(r, "notes"),
                SourceType = Str(r, "sourcetype"),
                // The SP already translates Draft|Approved|Cancelled into the
                // Posted|Reversed the frontend's PaymentHistoryRow expects.
                Status = Str(r, "status") ?? "Posted",
                AllocationCount = Int(r, "allocationcount"),
                CashAccountId = IntN(r, "cashaccountid"),
                CreatedBy = Str(r, "createdby"),
                ReversedBy = Str(r, "reversedby"),
                ReversedAt = DateN(r, "reversedat"),
                ReversalReason = Str(r, "reversalreason"),
            });

        public Task<List<PaymentAllocationRow>> GetCustomerPaymentAllocations(string farmId, int paymentId) => Query(
            "SELECT * FROM spgenericcustomerpayment_allocations(p_farmid => @FarmId::text, p_paymentid => @PaymentId::int)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                cmd.Parameters.AddWithValue("@PaymentId", paymentId);
            },
            r => new PaymentAllocationRow
            {
                AllocationId = Int(r, "allocationid"),
                DocumentType = Str(r, "documenttype") ?? "Sale",
                DocumentId = Int(r, "documentid"),
                Reference = Str(r, "reference"),
                DocumentDate = DateN(r, "documentdate"),
                Label = Str(r, "label"),
                DocumentTotal = Dec(r, "documenttotal"),
                AmountApplied = Dec(r, "amountapplied"),
                BalanceBefore = Dec(r, "balancebefore"),
                BalanceAfter = Dec(r, "balanceafter"),
                Status = Str(r, "status") ?? "Posted",
            });

        // ------------------------------------------------------------ statements

        public Task<List<StatementLine>> GetCustomerStatement(string farmId, int customerId, DateTime? from, DateTime? to) => Query(
            "SELECT * FROM spgenericcustomerstatement(p_farmid => @FarmId::text, p_customerid => @PartyId::int, p_from => @From::date, p_to => @To::date)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                cmd.Parameters.AddWithValue("@PartyId", customerId);
                cmd.Parameters.AddWithValue("@From", DbDate(from));
                cmd.Parameters.AddWithValue("@To", DbDate(to));
            },
            r => new StatementLine
            {
                EntryDate = DateN(r, "entrydate"),
                EntryType = Str(r, "entrytype") ?? string.Empty,
                Reference = Str(r, "reference"),
                Description = Str(r, "description"),
                Debit = Dec(r, "debit"),
                Credit = Dec(r, "credit"),
                RunningBalance = Dec(r, "runningbalance"),
                DocumentType = Str(r, "documenttype"),
                DocumentId = IntN(r, "documentid"),
            });

        // -------------------------------------------------------- suppliers (248)

        public Task<List<PartyBalanceRow>> GetSupplierBalances(BalanceQuery q) => Query(
            "SELECT * FROM spgenericsupplierbalances(p_farmid => @FarmId::text, p_from => @From::date, p_to => @To::date, p_supplierid => @PartyId::int, p_status => @Status::text, p_minbalance => @MinBalance::numeric, p_search => @Search::text)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", q.FarmId);
                cmd.Parameters.AddWithValue("@From", DbDate(q.From));
                cmd.Parameters.AddWithValue("@To", DbDate(q.To));
                cmd.Parameters.AddWithValue("@PartyId", Db(q.PartyId));
                cmd.Parameters.AddWithValue("@Status", Db(q.Status ?? BalanceStatusFilters.All));
                cmd.Parameters.AddWithValue("@MinBalance", Db(q.MinBalance));
                cmd.Parameters.AddWithValue("@Search", Db(q.Search));
            },
            r => new PartyBalanceRow
            {
                PartyId = Int(r, "partyid"),
                PartyName = Str(r, "partyname") ?? string.Empty,
                ContactPhone = Str(r, "contactphone"),
                ContactEmail = Str(r, "contactemail"),
                PaymentTermsDays = Int(r, "paymenttermsdays"),
                TotalBalance = Dec(r, "totalbalance"),
                OpenDocumentCount = Int(r, "opendocumentcount"),
                OldestDocumentDate = DateN(r, "oldestdocumentdate"),
                LatestDocumentDate = DateN(r, "latestdocumentdate"),
                LastPaymentDate = DateN(r, "lastpaymentdate"),
                OverdueAmount = Dec(r, "overdueamount"),
                TotalInvoiced = Dec(r, "totalinvoiced"),
                TotalPaid = Dec(r, "totalpaid"),
            });

        public async Task<BalanceSummary> GetSupplierSummary(string farmId)
        {
            var rows = await Query(
                "SELECT * FROM spgenericsupplierbalancesummary(p_farmid => @FarmId::text)",
                cmd => cmd.Parameters.AddWithValue("@FarmId", farmId),
                r => new BalanceSummary
                {
                    TotalBalance = Dec(r, "totalbalance"),
                    PartyCount = Int(r, "partycount"),
                    OverdueBalance = Dec(r, "overduebalance"),
                    PaymentsToday = Dec(r, "paymentstoday"),
                    LargestBalance = Dec(r, "largestbalance"),
                    LargestBalanceParty = Str(r, "largestbalanceparty"),
                });
            return rows.FirstOrDefault() ?? new BalanceSummary();
        }

        public Task<List<OpenDocumentRow>> GetOpenBills(string farmId, int supplierId, DateTime? from, DateTime? to, string? status) => Query(
            "SELECT * FROM spgenericsupplieropenbills(p_farmid => @FarmId::text, p_supplierid => @PartyId::int, p_from => @From::date, p_to => @To::date, p_status => @Status::text)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                cmd.Parameters.AddWithValue("@PartyId", supplierId);
                cmd.Parameters.AddWithValue("@From", DbDate(from));
                cmd.Parameters.AddWithValue("@To", DbDate(to));
                cmd.Parameters.AddWithValue("@Status", Db(status ?? BalanceStatusFilters.All));
            },
            r => new OpenDocumentRow
            {
                DocumentType = Str(r, "documenttype") ?? string.Empty,
                DocumentId = Int(r, "documentid"),
                Reference = Str(r, "reference"),
                DocumentDate = r.GetDateTime(r.GetOrdinal("documentdate")),
                Label = Str(r, "label"),
                TotalAmount = Dec(r, "totalamount"),
                AmountPaid = Dec(r, "amountpaid"),
                Balance = Dec(r, "balance"),
                DueDate = DateN(r, "duedate"),
                AgeDays = Int(r, "agedays"),
                Status = Str(r, "status") ?? string.Empty,
                IsOverdue = Bool(r, "isoverdue"),
                CashAccountId = IntN(r, "cashaccountid"),
            });

        /// <summary>
        /// One payment, N allocations across purchases AND expenses, one cash
        /// movement -- in a single function call, so it either lands completely
        /// or not at all. Paying a bill books NO expense row: the bill is
        /// already the cost.
        /// </summary>
        public async Task<int> RecordSupplierPayment(RecordPaymentRequest r)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand(
                "SELECT spgenericsupplierpayment_record(p_farmid => @FarmId::text, p_supplierid => @PartyId::int, p_amount => @Amount::numeric, p_allocations => @Allocations::jsonb, p_paymentmethod => @PaymentMethod::text, p_paymentdate => @PaymentDate::timestamp, p_cashaccountid => @CashAccountId::int, p_reference => @Reference::text, p_notes => @Notes::text, p_sourcetype => @SourceType::text, p_createdby => @CreatedBy::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", r.FarmId);
            cmd.Parameters.AddWithValue("@PartyId", Db(r.PartyId));
            cmd.Parameters.AddWithValue("@Amount", r.Amount);
            cmd.Parameters.AddWithValue("@Allocations", SupplierAllocationsJson(r.Allocations));
            cmd.Parameters.AddWithValue("@PaymentMethod", Db(r.PaymentMethod));
            cmd.Parameters.AddWithValue("@PaymentDate", Db(r.PaymentDate));
            cmd.Parameters.AddWithValue("@CashAccountId", Db(r.CashAccountId));
            cmd.Parameters.AddWithValue("@Reference", Db(r.Reference));
            cmd.Parameters.AddWithValue("@Notes", Db(r.Notes));
            cmd.Parameters.AddWithValue("@SourceType", Db(r.SourceType ?? PaymentSourceTypes.SupplierBalances));
            cmd.Parameters.AddWithValue("@CreatedBy", Db(r.CreatedBy));

            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task<int> ReverseSupplierPayment(string farmId, int paymentId, string? reason, string? reversedBy)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand(
                "SELECT spgenericsupplierpayment_reverse(p_farmid => @FarmId::text, p_paymentid => @PaymentId::int, p_reason => @Reason::text, p_reversedby => @ReversedBy::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@PaymentId", paymentId);
            cmd.Parameters.AddWithValue("@Reason", Db(reason));
            cmd.Parameters.AddWithValue("@ReversedBy", Db(reversedBy));
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public Task<List<PaymentHistoryRow>> GetSupplierPayments(string farmId, int? supplierId, string? documentType, int? documentId, DateTime? from, DateTime? to) => Query(
            "SELECT * FROM spgenericsupplierpayment_history(p_farmid => @FarmId::text, p_supplierid => @PartyId::int, p_documenttype => @DocumentType::text, p_documentid => @DocumentId::int, p_from => @From::date, p_to => @To::date)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                cmd.Parameters.AddWithValue("@PartyId", Db(supplierId));
                cmd.Parameters.AddWithValue("@DocumentType", Db(documentType));
                cmd.Parameters.AddWithValue("@DocumentId", Db(documentId));
                cmd.Parameters.AddWithValue("@From", DbDate(from));
                cmd.Parameters.AddWithValue("@To", DbDate(to));
            },
            r => new PaymentHistoryRow
            {
                PaymentId = Int(r, "paymentid").ToString(),
                PartyId = IntN(r, "partyid"),
                PartyName = Str(r, "partyname"),
                PaymentDate = r.GetDateTime(r.GetOrdinal("paymentdate")),
                TotalAmount = Dec(r, "totalamount"),
                PaymentMethod = Str(r, "paymentmethod"),
                Reference = Str(r, "reference"),
                Notes = Str(r, "notes"),
                SourceType = Str(r, "sourcetype"),
                // The SP translates Draft|Approved|Cancelled into Posted|Reversed.
                Status = Str(r, "status") ?? "Posted",
                AllocationCount = Int(r, "allocationcount"),
                CashAccountId = IntN(r, "cashaccountid"),
                CreatedBy = Str(r, "createdby"),
                ReversedBy = Str(r, "reversedby"),
                ReversedAt = DateN(r, "reversedat"),
                ReversalReason = Str(r, "reversalreason"),
            });

        public Task<List<PaymentAllocationRow>> GetSupplierPaymentAllocations(string farmId, int paymentId) => Query(
            "SELECT * FROM spgenericsupplierpayment_allocations(p_farmid => @FarmId::text, p_paymentid => @PaymentId::int)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                cmd.Parameters.AddWithValue("@PaymentId", paymentId);
            },
            r => new PaymentAllocationRow
            {
                AllocationId = Int(r, "allocationid"),
                DocumentType = Str(r, "documenttype") ?? string.Empty,
                DocumentId = Int(r, "documentid"),
                Reference = Str(r, "reference"),
                DocumentDate = DateN(r, "documentdate"),
                Label = Str(r, "label"),
                DocumentTotal = Dec(r, "documenttotal"),
                AmountApplied = Dec(r, "amountapplied"),
                BalanceBefore = Dec(r, "balancebefore"),
                BalanceAfter = Dec(r, "balanceafter"),
                Status = Str(r, "status") ?? "Posted",
            });

        public Task<List<StatementLine>> GetSupplierStatement(string farmId, int supplierId, DateTime? from, DateTime? to) => Query(
            "SELECT * FROM spgenericsupplierstatement(p_farmid => @FarmId::text, p_supplierid => @PartyId::int, p_from => @From::date, p_to => @To::date)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                cmd.Parameters.AddWithValue("@PartyId", supplierId);
                cmd.Parameters.AddWithValue("@From", DbDate(from));
                cmd.Parameters.AddWithValue("@To", DbDate(to));
            },
            r => new StatementLine
            {
                EntryDate = DateN(r, "entrydate"),
                EntryType = Str(r, "entrytype") ?? string.Empty,
                Reference = Str(r, "reference"),
                Description = Str(r, "description"),
                // The API exposes ONE shape either way, with Debit always meaning
                // "increases what is owed" -- so the supplier columns swap here.
                Debit = Dec(r, "credit"),
                Credit = Dec(r, "debit"),
                RunningBalance = Dec(r, "runningbalance"),
                DocumentType = Str(r, "documenttype"),
                DocumentId = IntN(r, "documentid"),
            });

        // ----------------------------------------------------------------- audit

        /// <summary>
        /// The invariant that returns NOTHING when the books are healthy: every
        /// invoice's AmountPaid equals the sum of its posted allocations.
        /// </summary>
        public Task<List<BalanceAuditRow>> Audit(string farmId) => Query(
            "SELECT * FROM fngenericbalanceaudit(p_farmid => @FarmId::text)",
            cmd => cmd.Parameters.AddWithValue("@FarmId", farmId),
            r => new BalanceAuditRow
            {
                Side = Str(r, "side") ?? string.Empty,
                DocumentType = Str(r, "documenttype") ?? string.Empty,
                DocumentId = Int(r, "documentid"),
                AmountPaid = Dec(r, "amountpaid"),
                Allocated = Dec(r, "allocated"),
                Difference = Dec(r, "difference"),
            });
    }
}
