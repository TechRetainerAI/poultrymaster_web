using System.Text.Json;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IWaterBalanceService
    {
        // Customer side
        Task<List<PartyBalanceRow>> GetCustomerBalances(BalanceQuery q);
        Task<BalanceSummary> GetCustomerSummary(string farmId);
        Task<List<OpenDocumentRow>> GetOpenSales(string farmId, int customerId, DateTime? from, DateTime? to, string? status);
        Task<string> RecordCustomerPayment(RecordPaymentRequest r);
        Task<int> ReverseCustomerPayment(string farmId, Guid paymentGroupId, string? reason, string? reversedBy);
        Task<List<PaymentHistoryRow>> GetCustomerPayments(string farmId, int? customerId, int? saleId, DateTime? from, DateTime? to);
        Task<List<PaymentAllocationRow>> GetCustomerPaymentAllocations(string farmId, Guid paymentGroupId);
        Task<List<StatementLine>> GetCustomerStatement(string farmId, int customerId, DateTime? from, DateTime? to);

        // Supplier side
        Task<List<PartyBalanceRow>> GetSupplierBalances(BalanceQuery q);
        Task<BalanceSummary> GetSupplierSummary(string farmId);
        Task<List<OpenDocumentRow>> GetOpenPurchases(string farmId, int supplierId, DateTime? from, DateTime? to, string? status);
        Task<int> RecordSupplierPayment(RecordPaymentRequest r);
        Task<int> ReverseSupplierPayment(string farmId, int paymentId, string? reason, string? reversedBy);
        Task<List<PaymentHistoryRow>> GetSupplierPayments(string farmId, int? supplierId, string? documentType, int? documentId, DateTime? from, DateTime? to);
        Task<List<PaymentAllocationRow>> GetSupplierPaymentAllocations(string farmId, int paymentId);
        Task<List<StatementLine>> GetSupplierStatement(string farmId, int supplierId, DateTime? from, DateTime? to);

        Task<List<BalanceAuditRow>> Audit(string farmId);
    }

    /// <summary>
    /// Reads and writes for the water Customer Balances / Supplier Balances
    /// pages (migration 227). The DTOs in BalanceModels.cs are module-agnostic
    /// and shared with PoultryBalanceService -- only the function names and a
    /// handful of column names differ.
    ///
    /// Every write is a SINGLE function call. That is not a style choice: a
    /// PostgreSQL function invoked as one statement runs in one implicit
    /// transaction, so a payment either lands completely -- header, allocations,
    /// document balances, expense rows and cash -- or not at all. Splitting the
    /// steps across several round trips from here is what would let a payment
    /// post while its cash posting failed.
    /// </summary>
    public class WaterBalanceService : IWaterBalanceService
    {
        private readonly string _connectionString;

        public WaterBalanceService(string connectionString) => _connectionString = connectionString;

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

        /// <summary>
        /// The allocation grid, as the JSON the recording functions expect.
        /// Keys are lower case on purpose -- jsonb_to_recordset matches them
        /// case-sensitively against unquoted (therefore lower-cased) column
        /// identifiers, and a camelCase key would silently produce NULL rows.
        /// Migration 214 lost a whole entry's lines to exactly that.
        /// </summary>
        private static string AllocationsJson(IEnumerable<PaymentAllocationInput> allocations, bool supplierSide)
        {
            var rows = allocations.Select(a => supplierSide
                ? (object)new Dictionary<string, object?>
                {
                    // Water buys through one table today, but the column is
                    // written so a second payable table later needs no change
                    // here or in the shared allocation table.
                    ["documenttype"] = string.IsNullOrWhiteSpace(a.DocumentType)
                        ? PayableDocumentTypes.RawMaterialPurchase
                        : a.DocumentType,
                    ["documentid"] = a.DocumentId,
                    ["amount"] = a.Amount,
                }
                : new Dictionary<string, object?>
                {
                    ["saleid"] = a.SaleId != 0 ? a.SaleId : a.DocumentId,
                    ["amount"] = a.Amount,
                });
            return JsonSerializer.Serialize(rows);
        }

        // ------------------------------------------------------------- balances

        private static PartyBalanceRow ReadParty(NpgsqlDataReader r, bool supplierSide) => new()
        {
            PartyId = Int(r, supplierSide ? "supplierid" : "customerid"),
            PartyName = Str(r, supplierSide ? "suppliername" : "customername") ?? string.Empty,
            ContactPhone = Str(r, "contactphone"),
            ContactEmail = Str(r, "contactemail"),
            PaymentTermsDays = Int(r, "paymenttermsdays"),
            TotalBalance = Dec(r, "totalbalance"),
            OpenDocumentCount = Int(r, supplierSide ? "opendoccount" : "opensalecount"),
            OldestDocumentDate = DateN(r, supplierSide ? "oldestdocdate" : "oldestsaledate"),
            LatestDocumentDate = DateN(r, supplierSide ? "latestdocdate" : "latestsaledate"),
            LastPaymentDate = DateN(r, "lastpaymentdate"),
            OverdueAmount = Dec(r, "overdueamount"),
            TotalInvoiced = Dec(r, supplierSide ? "totalpurchased" : "totalsales"),
            TotalPaid = Dec(r, "totalpaid"),
        };

        private static void BindBalanceQuery(NpgsqlCommand cmd, BalanceQuery q)
        {
            cmd.Parameters.AddWithValue("@FarmId", q.FarmId);
            cmd.Parameters.AddWithValue("@From", DbDate(q.From));
            cmd.Parameters.AddWithValue("@To", DbDate(q.To));
            cmd.Parameters.AddWithValue("@PartyId", Db(q.PartyId));
            cmd.Parameters.AddWithValue("@Status", Db(q.Status ?? BalanceStatusFilters.All));
            cmd.Parameters.AddWithValue("@MinBalance", Db(q.MinBalance));
            cmd.Parameters.AddWithValue("@Search", Db(q.Search));
        }

        public Task<List<PartyBalanceRow>> GetCustomerBalances(BalanceQuery q) => Query(
            "SELECT * FROM spwatercustomerbalances(p_farmid => @FarmId::text, p_from => @From::date, p_to => @To::date, p_customerid => @PartyId::int, p_status => @Status::text, p_minbalance => @MinBalance::numeric, p_search => @Search::text)",
            cmd => BindBalanceQuery(cmd, q),
            r => ReadParty(r, supplierSide: false));

        public Task<List<PartyBalanceRow>> GetSupplierBalances(BalanceQuery q) => Query(
            "SELECT * FROM spwatersupplierbalances(p_farmid => @FarmId::text, p_from => @From::date, p_to => @To::date, p_supplierid => @PartyId::int, p_status => @Status::text, p_minbalance => @MinBalance::numeric, p_search => @Search::text)",
            cmd => BindBalanceQuery(cmd, q),
            r => ReadParty(r, supplierSide: true));

        // Both water summary functions return the SAME column names, unlike the
        // poultry pair -- so one reader serves both.
        private async Task<BalanceSummary> Summary(string sql, string farmId)
        {
            var rows = await Query(sql,
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

        public Task<BalanceSummary> GetCustomerSummary(string farmId) =>
            Summary("SELECT * FROM spwatercustomerbalancesummary(p_farmid => @FarmId::text)", farmId);

        public Task<BalanceSummary> GetSupplierSummary(string farmId) =>
            Summary("SELECT * FROM spwatersupplierbalancesummary(p_farmid => @FarmId::text)", farmId);

        public Task<List<OpenDocumentRow>> GetOpenSales(string farmId, int customerId, DateTime? from, DateTime? to, string? status) => Query(
            "SELECT * FROM spwatercustomeropensales(p_farmid => @FarmId::text, p_customerid => @PartyId::int, p_from => @From::date, p_to => @To::date, p_status => @Status::text)",
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
                DocumentType = "WaterSale",
                DocumentId = Int(r, "saleid"),
                Reference = "W" + Int(r, "saleid"),
                DocumentDate = r.GetDateTime(r.GetOrdinal("saledate")),
                Label = Str(r, "product"),
                Description = Str(r, "saledescription"),
                TotalAmount = Dec(r, "totalamount"),
                AmountPaid = Dec(r, "amountpaid"),
                Balance = Dec(r, "balance"),
                DueDate = DateN(r, "duedate"),
                AgeDays = Int(r, "agedays"),
                Status = Str(r, "status") ?? string.Empty,
                IsOverdue = Bool(r, "isoverdue"),
                CashAccountId = IntN(r, "watercashaccountid"),
            });

        public Task<List<OpenDocumentRow>> GetOpenPurchases(string farmId, int supplierId, DateTime? from, DateTime? to, string? status) => Query(
            "SELECT * FROM spwatersupplieropenpurchases(p_farmid => @FarmId::text, p_supplierid => @PartyId::int, p_from => @From::date, p_to => @To::date, p_status => @Status::text)",
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

        // -------------------------------------------------------------- payments

        public async Task<string> RecordCustomerPayment(RecordPaymentRequest r)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand(
                "SELECT spwatercustomerpayment_record(p_farmid => @FarmId::text, p_customerid => @PartyId::int, p_amount => @Amount::numeric, p_allocations => @Allocations::jsonb, p_paymentmethod => @PaymentMethod::text, p_paymentdate => @PaymentDate::timestamp, p_cashaccountid => @CashAccountId::int, p_reference => @Reference::text, p_note => @Notes::text, p_sourcetype => @SourceType::text, p_createdby => @CreatedBy::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", r.FarmId);
            cmd.Parameters.AddWithValue("@PartyId", Db(r.PartyId));
            cmd.Parameters.AddWithValue("@Amount", r.Amount);
            cmd.Parameters.AddWithValue("@Allocations", AllocationsJson(r.Allocations, supplierSide: false));
            cmd.Parameters.AddWithValue("@PaymentMethod", Db(r.PaymentMethod));
            cmd.Parameters.AddWithValue("@PaymentDate", Db(r.PaymentDate));
            cmd.Parameters.AddWithValue("@CashAccountId", Db(r.CashAccountId));
            cmd.Parameters.AddWithValue("@Reference", Db(r.Reference));
            cmd.Parameters.AddWithValue("@Notes", Db(r.Notes));
            cmd.Parameters.AddWithValue("@SourceType", Db(r.SourceType ?? PaymentSourceTypes.CustomerBalances));
            cmd.Parameters.AddWithValue("@CreatedBy", Db(r.CreatedBy));

            await conn.OpenAsync();
            var result = await cmd.ExecuteScalarAsync();
            return result?.ToString() ?? string.Empty;
        }

        public async Task<int> RecordSupplierPayment(RecordPaymentRequest r)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand(
                "SELECT spwatersupplierpayment_record(p_farmid => @FarmId::text, p_supplierid => @PartyId::int, p_amount => @Amount::numeric, p_allocations => @Allocations::jsonb, p_paymentmethod => @PaymentMethod::text, p_paymentdate => @PaymentDate::timestamp, p_cashaccountid => @CashAccountId::int, p_reference => @Reference::text, p_note => @Notes::text, p_sourcetype => @SourceType::text, p_createdby => @CreatedBy::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", r.FarmId);
            cmd.Parameters.AddWithValue("@PartyId", Db(r.PartyId));
            cmd.Parameters.AddWithValue("@Amount", r.Amount);
            cmd.Parameters.AddWithValue("@Allocations", AllocationsJson(r.Allocations, supplierSide: true));
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

        public async Task<int> ReverseCustomerPayment(string farmId, Guid paymentGroupId, string? reason, string? reversedBy)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand(
                "SELECT spwatercustomerpayment_reverse(p_farmid => @FarmId::text, p_paymentgroupid => @PaymentId::uuid, p_reason => @Reason::text, p_reversedby => @ReversedBy::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@PaymentId", paymentGroupId);
            cmd.Parameters.AddWithValue("@Reason", Db(reason));
            cmd.Parameters.AddWithValue("@ReversedBy", Db(reversedBy));
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task<int> ReverseSupplierPayment(string farmId, int paymentId, string? reason, string? reversedBy)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand(
                "SELECT spwatersupplierpayment_reverse(p_farmid => @FarmId::text, p_paymentid => @PaymentId::int, p_reason => @Reason::text, p_reversedby => @ReversedBy::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@PaymentId", paymentId);
            cmd.Parameters.AddWithValue("@Reason", Db(reason));
            cmd.Parameters.AddWithValue("@ReversedBy", Db(reversedBy));
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public Task<List<PaymentHistoryRow>> GetCustomerPayments(string farmId, int? customerId, int? saleId, DateTime? from, DateTime? to) => Query(
            "SELECT * FROM spwatercustomerpayment_history(p_farmid => @FarmId::text, p_customerid => @PartyId::int, p_saleid => @DocumentId::int, p_from => @From::date, p_to => @To::date)",
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
                // Guarded, not GetGuid: `paymentgroupid` is nullable with no default,
                // and a writer that forgets it used to throw here -- which took the
                // WHOLE ledger down over one bad row. Migration 245 stops the nulls
                // arriving; this stops one that slipped through being fatal. The row
                // still shows its amount, date and customer; it just cannot be
                // grouped, expanded or reversed until its group id is repaired.
                PaymentId = GuidN(r, "paymentgroupid") ?? string.Empty,
                PartyId = IntN(r, "customerid"),
                PartyName = Str(r, "customername"),
                PaymentDate = r.GetDateTime(r.GetOrdinal("paymentdate")),
                TotalAmount = Dec(r, "totalamount"),
                PaymentMethod = Str(r, "paymentmethod"),
                Reference = Str(r, "reference"),
                Notes = Str(r, "note"),
                SourceType = Str(r, "sourcetype"),
                Status = Str(r, "status") ?? "Posted",
                AllocationCount = Int(r, "allocationcount"),
                CashAccountId = IntN(r, "watercashaccountid"),
                CreatedBy = Str(r, "createdby"),
                ReversedBy = Str(r, "reversedby"),
                ReversedAt = DateN(r, "reversedat"),
                ReversalReason = Str(r, "reversalreason"),
                PaymentNumber = Str(r, "paymentnumber"),
                SaleId = IntN(r, "saleid"),
                SaleTotal = DecN(r, "saletotal"),
                BalanceBefore = DecN(r, "balancebefore"),
                AmountApplied = DecN(r, "amountapplied"),
                BalanceAfter = DecN(r, "balanceafter"),
            });

        public Task<List<PaymentHistoryRow>> GetSupplierPayments(string farmId, int? supplierId, string? documentType, int? documentId, DateTime? from, DateTime? to) => Query(
            "SELECT * FROM spwatersupplierpayment_history(p_farmid => @FarmId::text, p_supplierid => @PartyId::int, p_documenttype => @DocumentType::text, p_documentid => @DocumentId::int, p_from => @From::date, p_to => @To::date)",
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
                PartyId = IntN(r, "supplierid"),
                PartyName = Str(r, "suppliername"),
                PaymentDate = r.GetDateTime(r.GetOrdinal("paymentdate")),
                TotalAmount = Dec(r, "totalamount"),
                PaymentMethod = Str(r, "paymentmethod"),
                Reference = Str(r, "referenceno"),
                Notes = Str(r, "notes"),
                SourceType = Str(r, "sourcetype"),
                Status = Str(r, "status") ?? "Posted",
                AllocationCount = Int(r, "allocationcount"),
                CashAccountId = IntN(r, "watercashaccountid"),
                CreatedBy = Str(r, "createdby"),
                ReversedBy = Str(r, "reversedby"),
                ReversedAt = DateN(r, "reversedat"),
                ReversalReason = Str(r, "reversalreason"),
            });

        // Both water allocation functions return the same column names, so one
        // reader serves both sides.
        private static PaymentAllocationRow ReadAllocation(NpgsqlDataReader r) => new()
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
        };

        public Task<List<PaymentAllocationRow>> GetCustomerPaymentAllocations(string farmId, Guid paymentGroupId) => Query(
            "SELECT * FROM spwatercustomerpayment_allocations(p_farmid => @FarmId::text, p_paymentgroupid => @PaymentId::uuid)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                cmd.Parameters.AddWithValue("@PaymentId", paymentGroupId);
            },
            ReadAllocation);

        public Task<List<PaymentAllocationRow>> GetSupplierPaymentAllocations(string farmId, int paymentId) => Query(
            "SELECT * FROM spwatersupplierpayment_allocations(p_farmid => @FarmId::text, p_paymentid => @PaymentId::int)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                cmd.Parameters.AddWithValue("@PaymentId", paymentId);
            },
            ReadAllocation);

        // ------------------------------------------------------------ statements

        private Task<List<StatementLine>> Statement(string sql, string farmId, int partyId, DateTime? from, DateTime? to, bool supplierSide) => Query(
            sql,
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                cmd.Parameters.AddWithValue("@PartyId", partyId);
                cmd.Parameters.AddWithValue("@From", DbDate(from));
                cmd.Parameters.AddWithValue("@To", DbDate(to));
            },
            r => new StatementLine
            {
                EntryDate = DateN(r, "entrydate"),
                EntryType = Str(r, "entrytype") ?? string.Empty,
                Reference = Str(r, "reference"),
                Description = Str(r, "description"),
                // Both water statements already put "increases what is owed" in
                // debit -- a sale on the customer side, a purchase on the
                // supplier side -- so unlike the poultry pair there is nothing
                // to swap here. The flag stays only to pick the document columns.
                Debit = Dec(r, "debit"),
                Credit = Dec(r, "credit"),
                RunningBalance = Dec(r, "runningbalance"),
                DocumentType = supplierSide ? Str(r, "documenttype") : "WaterSale",
                DocumentId = supplierSide ? IntN(r, "documentid") : IntN(r, "saleid"),
                // Guarded, not just null-coalesced: the supplier statement does
                // not return these columns at all, and asking for one by name
                // that is not in the result throws.
                PaymentId = supplierSide ? null : GuidN(r, "paymentgroupid"),
                AllocationCount = supplierSide ? null : IntN(r, "allocationcount"),
                SourceType = supplierSide ? null : Str(r, "sourcetype"),
            });

        public Task<List<StatementLine>> GetCustomerStatement(string farmId, int customerId, DateTime? from, DateTime? to) =>
            Statement("SELECT * FROM spwatercustomerstatement(p_farmid => @FarmId::text, p_customerid => @PartyId::int, p_from => @From::date, p_to => @To::date)",
                      farmId, customerId, from, to, supplierSide: false);

        public Task<List<StatementLine>> GetSupplierStatement(string farmId, int supplierId, DateTime? from, DateTime? to) =>
            Statement("SELECT * FROM spwatersupplierstatement(p_farmid => @FarmId::text, p_supplierid => @PartyId::int, p_from => @From::date, p_to => @To::date)",
                      farmId, supplierId, from, to, supplierSide: true);

        // ----------------------------------------------------------------- audit

        // fnbalanceaudit (222) is hardcoded to the poultry document tables, so
        // water has its own (227) rather than a module parameter that would only
        // ever branch.
        public Task<List<BalanceAuditRow>> Audit(string farmId) => Query(
            "SELECT * FROM fnwaterbalanceaudit(p_farmid => @FarmId::text)",
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
