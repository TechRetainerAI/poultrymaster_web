using System.Text.Json;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IPoultryBalanceService
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

        // 351: customer credit (money received and kept, applied to no active
        // sale) and refunds of it.
        Task<List<CustomerCreditSummaryRow>> GetCustomerCreditSummary(string farmId);
        Task<List<CustomerCreditRow>> GetCustomerCredit(string farmId, int customerId);
        Task<decimal> ApplyCustomerCredit(CustomerCreditApplyRequest r);
        Task<int> RecordCustomerRefund(CustomerRefundRequest r);
        Task<List<CustomerRefundRow>> GetCustomerRefunds(string farmId, int? customerId);
        Task<string> CreateManualCredit(ManualCreditRequest r);
        Task<int> ReverseManualCredit(Guid paymentGroupId, ManualCreditReverseRequest r);
        Task<List<ManualCreditRow>> GetManualCredits(string farmId);
        Task<List<CustomerCreditEventRow>> GetCustomerCreditEvents(string farmId, int? customerId);
        Task<int> ReverseCustomerRefund(int refundId, CustomerRefundReverseRequest r);
        Task<string> CreateCustomerDebt(CustomerDebtRequest r);
        Task<int> ReverseCustomerDebt(int debtId, CustomerDebtReverseRequest r);
        Task<List<CustomerDebtRow>> GetCustomerDebts(string farmId, int? customerId);

        // 370: supplier credit, advances, refunds and debt.
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
    /// Reads and writes for the poultry Customer Balances / Supplier Balances
    /// pages (migrations 222-224).
    ///
    /// Every write is a SINGLE function call. That is not a style choice: a
    /// PostgreSQL function invoked as one statement runs in one implicit
    /// transaction, so a payment either lands completely -- header, allocations,
    /// document balances, expense rows and cash -- or not at all. Splitting the
    /// steps across several round trips from here is what would let a payment
    /// post while its cash posting failed.
    /// </summary>
    public class PoultryBalanceService : IPoultryBalanceService
    {
        private readonly string _connectionString;

        public PoultryBalanceService(string connectionString) => _connectionString = connectionString;

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
                    ["documenttype"] = string.IsNullOrWhiteSpace(a.DocumentType)
                        ? PayableDocumentTypes.RawMaterialPurchase
                        : a.DocumentType,
                    ["documentid"] = a.DocumentId,
                    ["amount"] = a.Amount,
                }
                // 369: a customer debt is paid like a sale, as {debtid, amount}.
                : string.Equals(a.DocumentType, CustomerDebtDocumentType, StringComparison.OrdinalIgnoreCase)
                    ? new Dictionary<string, object?>
                    {
                        ["debtid"] = a.DocumentId,
                        ["amount"] = a.Amount,
                    }
                    : new Dictionary<string, object?>
                    {
                        ["saleid"] = a.SaleId != 0 ? a.SaleId : a.DocumentId,
                        ["amount"] = a.Amount,
                    });
            return JsonSerializer.Serialize(rows);
        }

        // ------------------------------------------------------------- customers

        private static PartyBalanceRow ReadParty(NpgsqlDataReader r, bool supplierSide) => new()
        {
            PartyId = Int(r, supplierSide ? "supplierid" : "customerid"),
            PartyName = Str(r, supplierSide ? "suppliername" : "customername") ?? string.Empty,
            ContactPhone = Str(r, "contactphone"),
            ContactEmail = Str(r, "contactemail"),
            PaymentTermsDays = Int(r, "paymenttermsdays"),
            TotalBalance = Dec(r, "totalbalance"),
            OpenDocumentCount = Int(r, supplierSide ? "openpurchasecount" : "opensalecount"),
            OldestDocumentDate = DateN(r, supplierSide ? "oldestpurchasedate" : "oldestsaledate"),
            LatestDocumentDate = DateN(r, supplierSide ? "latestpurchasedate" : "latestsaledate"),
            LastPaymentDate = DateN(r, "lastpaymentdate"),
            OverdueAmount = Dec(r, "overdueamount"),
            TotalInvoiced = Dec(r, supplierSide ? "totalpurchases" : "totalsales"),
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
            "SELECT * FROM sppoultrycustomerbalances(p_farmid => @FarmId::text, p_from => @From::date, p_to => @To::date, p_customerid => @PartyId::int, p_status => @Status::text, p_minbalance => @MinBalance::numeric, p_search => @Search::text)",
            cmd => BindBalanceQuery(cmd, q),
            r => ReadParty(r, supplierSide: false));

        public Task<List<PartyBalanceRow>> GetSupplierBalances(BalanceQuery q) => Query(
            "SELECT * FROM sppoultrysupplierbalances(p_farmid => @FarmId::text, p_from => @From::date, p_to => @To::date, p_supplierid => @PartyId::int, p_status => @Status::text, p_minbalance => @MinBalance::numeric, p_search => @Search::text)",
            cmd => BindBalanceQuery(cmd, q),
            r => ReadParty(r, supplierSide: true));

        private async Task<BalanceSummary> Summary(string sql, string farmId, bool supplierSide)
        {
            var rows = await Query(sql,
                cmd => cmd.Parameters.AddWithValue("@FarmId", farmId),
                r => new BalanceSummary
                {
                    TotalBalance = Dec(r, "totalbalance"),
                    PartyCount = Int(r, supplierSide ? "suppliersowed" : "customersowing"),
                    OverdueBalance = Dec(r, supplierSide ? "overduepayables" : "overduebalance"),
                    PaymentsToday = Dec(r, supplierSide ? "paymentsmadetoday" : "paymentsreceivedtoday"),
                    LargestBalance = Dec(r, "largestbalance"),
                    LargestBalanceParty = Str(r, supplierSide ? "largestbalancesupplier" : "largestbalancecustomer"),
                });
            return rows.FirstOrDefault() ?? new BalanceSummary();
        }

        public Task<BalanceSummary> GetCustomerSummary(string farmId) =>
            Summary("SELECT * FROM sppoultrycustomerbalancesummary(p_farmid => @FarmId::text)", farmId, false);

        public Task<BalanceSummary> GetSupplierSummary(string farmId) =>
            Summary("SELECT * FROM sppoultrysupplierbalancesummary(p_farmid => @FarmId::text)", farmId, true);

        /// <summary>369: the document type of a customer debt in open items and allocations.</summary>
        public const string CustomerDebtDocumentType = "CustomerDebt";

        /// <summary>A customer's open sales, then (369) their open debts -- both payable in one payment.</summary>
        public async Task<List<OpenDocumentRow>> GetOpenSales(string farmId, int customerId, DateTime? from, DateTime? to, string? status)
        {
            var sales = await GetOpenSaleRows(farmId, customerId, from, to, status);
            var debts = await Query(
                "SELECT * FROM sppoultrycustomeropendebts(p_farmid => @FarmId::text, p_customerid => @PartyId::int)",
                cmd =>
                {
                    cmd.Parameters.AddWithValue("@FarmId", farmId);
                    cmd.Parameters.AddWithValue("@PartyId", customerId);
                },
                r => new OpenDocumentRow
                {
                    DocumentType = CustomerDebtDocumentType,
                    DocumentId = Int(r, "debtid"),
                    Reference = Str(r, "debtnumber"),
                    DocumentDate = r.GetDateTime(r.GetOrdinal("debtdate")),
                    Label = "Customer debt",
                    Description = Str(r, "description"),
                    TotalAmount = Dec(r, "amount"),
                    AmountPaid = Dec(r, "paid"),
                    Balance = Dec(r, "balance"),
                    DueDate = DateN(r, "duedate"),
                    AgeDays = Int(r, "agedays"),
                    Status = Str(r, "status") ?? string.Empty,
                    IsOverdue = Bool(r, "isoverdue"),
                    CashAccountId = null,
                });
            // The same filters as the sales list (date window, status).
            debts = debts.Where(d =>
                (from is null || d.DocumentDate.Date >= from.Value.Date) &&
                (to is null || d.DocumentDate.Date <= to.Value.Date) &&
                (status ?? BalanceStatusFilters.All) switch
                {
                    "Partial" => d.AmountPaid > 0,
                    "Unpaid" => d.AmountPaid == 0,
                    "Overdue" => d.IsOverdue,
                    _ => true,
                }).ToList();
            sales.AddRange(debts);
            return sales.OrderBy(d => d.DocumentDate).ThenBy(d => d.DocumentId).ToList();
        }

        private Task<List<OpenDocumentRow>> GetOpenSaleRows(string farmId, int customerId, DateTime? from, DateTime? to, string? status) => Query(
            "SELECT * FROM sppoultrycustomeropensales(p_farmid => @FarmId::text, p_customerid => @PartyId::int, p_from => @From::date, p_to => @To::date, p_status => @Status::text)",
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
                DocumentType = "Sale",
                DocumentId = Int(r, "saleid"),
                Reference = "S" + Int(r, "saleid"),
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
                CashAccountId = IntN(r, "poultrycashaccountid"),
            });

        public Task<List<OpenDocumentRow>> GetOpenPurchases(string farmId, int supplierId, DateTime? from, DateTime? to, string? status) => Query(
            "SELECT * FROM sppoultrysupplieropenpurchases(p_farmid => @FarmId::text, p_supplierid => @PartyId::int, p_from => @From::date, p_to => @To::date, p_status => @Status::text)",
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
                DocumentDate = r.GetDateTime(r.GetOrdinal("docdate")),
                Label = Str(r, "label"),
                TotalAmount = Dec(r, "totalcost"),
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
                "SELECT sppoultrycustomerpayment_record(p_farmid => @FarmId::text, p_customerid => @PartyId::int, p_amount => @Amount::numeric, p_allocations => @Allocations::jsonb, p_paymentmethod => @PaymentMethod::text, p_paymentdate => @PaymentDate::timestamp, p_cashaccountid => @CashAccountId::int, p_reference => @Reference::text, p_note => @Notes::text, p_sourcetype => @SourceType::text, p_createdby => @CreatedBy::text)", conn);
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
                "SELECT sppoultrysupplierpayment_record(p_farmid => @FarmId::text, p_supplierid => @PartyId::int, p_amount => @Amount::numeric, p_allocations => @Allocations::jsonb, p_paymentmethod => @PaymentMethod::text, p_paymentdate => @PaymentDate::timestamp, p_cashaccountid => @CashAccountId::int, p_reference => @Reference::text, p_notes => @Notes::text, p_sourcetype => @SourceType::text, p_createdby => @CreatedBy::text)", conn);
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
                "SELECT sppoultrycustomerpayment_reverse(p_farmid => @FarmId::text, p_paymentgroupid => @PaymentId::uuid, p_reason => @Reason::text, p_reversedby => @ReversedBy::text)", conn);
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
                "SELECT sppoultrysupplierpayment_reverse(p_farmid => @FarmId::text, p_paymentid => @PaymentId::int, p_reason => @Reason::text, p_reversedby => @ReversedBy::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@PaymentId", paymentId);
            cmd.Parameters.AddWithValue("@Reason", Db(reason));
            cmd.Parameters.AddWithValue("@ReversedBy", Db(reversedBy));
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public Task<List<PaymentHistoryRow>> GetCustomerPayments(string farmId, int? customerId, int? saleId, DateTime? from, DateTime? to) => Query(
            "SELECT * FROM sppoultrycustomerpayment_history(p_farmid => @FarmId::text, p_customerid => @PartyId::int, p_saleid => @DocumentId::int, p_from => @From::date, p_to => @To::date)",
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
                // 304: the time the payments tables show beside the date.
                CreatedAt = r.OptionalDateTime("CreatedAt"),
                // Guarded, not GetGuid: `paymentgroupid` is nullable with no default,
                // and a writer that forgets it used to throw here -- which took the
                // WHOLE ledger down over one bad row. Migration 245 stops the nulls
                // arriving; this stops one that slipped through being fatal. The row
                // still shows its amount, date and customer; it just cannot be
                // grouped, expanded or reversed until its group id is repaired.
                PaymentId = GuidN(r, "paymentgroupid") ?? string.Empty,
                PaymentNumber = Str(r, "paymentnumber"),
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
                CashAccountId = IntN(r, "poultrycashaccountid"),
                CreatedBy = Str(r, "createdby"),
                ReversedBy = Str(r, "reversedby"),
                ReversedAt = DateN(r, "reversedat"),
                ReversalReason = Str(r, "reversalreason"),
                SaleId = IntN(r, "saleid"),
                SaleTotal = DecN(r, "saletotal"),
                BalanceBefore = DecN(r, "balancebefore"),
                AmountApplied = DecN(r, "amountapplied"),
                BalanceAfter = DecN(r, "balanceafter"),
            });

        public Task<List<PaymentHistoryRow>> GetSupplierPayments(string farmId, int? supplierId, string? documentType, int? documentId, DateTime? from, DateTime? to) => Query(
            "SELECT * FROM sppoultrysupplierpayment_history(p_farmid => @FarmId::text, p_supplierid => @PartyId::int, p_documenttype => @DocumentType::text, p_documentid => @DocumentId::int, p_from => @From::date, p_to => @To::date)",
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
                // 304: the time the payments tables show beside the date.
                CreatedAt = r.OptionalDateTime("CreatedAt"),
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
                CashAccountId = IntN(r, "poultrycashaccountid"),
                CreatedBy = Str(r, "createdby"),
                ReversedBy = Str(r, "reversedby"),
                ReversedAt = DateN(r, "reversedat"),
                ReversalReason = Str(r, "reversalreason"),
            });

        public Task<List<PaymentAllocationRow>> GetCustomerPaymentAllocations(string farmId, Guid paymentGroupId) => Query(
            "SELECT * FROM sppoultrycustomerpayment_allocations(p_farmid => @FarmId::text, p_paymentgroupid => @PaymentId::uuid)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                cmd.Parameters.AddWithValue("@PaymentId", paymentGroupId);
            },
            r => new PaymentAllocationRow
            {
                AllocationId = Int(r, "allocationid"),
                // 369: a line with no sale paid a customer debt; its label is "Debt CD-00001".
                DocumentType = IntN(r, "saleid") is null ? CustomerDebtDocumentType : "Sale",
                DocumentId = IntN(r, "saleid") ?? 0,
                Reference = IntN(r, "saleid") is int sid ? "S" + sid : Str(r, "product"),
                DocumentDate = DateN(r, "saledate"),
                Label = Str(r, "product"),
                DocumentTotal = Dec(r, "saletotal"),
                AmountApplied = Dec(r, "amountapplied"),
                BalanceBefore = Dec(r, "salebalancebefore"),
                BalanceAfter = Dec(r, "salebalanceafter"),
                Status = Str(r, "status") ?? "Posted",
            });

        public Task<List<PaymentAllocationRow>> GetSupplierPaymentAllocations(string farmId, int paymentId) => Query(
            "SELECT * FROM sppoultrysupplierpayment_allocations(p_farmid => @FarmId::text, p_paymentid => @PaymentId::int)",
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
                DocumentDate = DateN(r, "docdate"),
                Label = Str(r, "label"),
                DocumentTotal = Dec(r, "documenttotal"),
                AmountApplied = Dec(r, "amountapplied"),
                BalanceBefore = Dec(r, "documentbalancebefore"),
                BalanceAfter = Dec(r, "documentbalanceafter"),
                Status = Str(r, "status") ?? "Posted",
            });

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
                // The supplier statement is the mirror image: a purchase is a
                // credit to the supplier and a payment is a debit, so the two
                // columns swap. The API exposes one shape either way, with Debit
                // always meaning "increases what is owed".
                Debit = supplierSide ? Dec(r, "credit") : Dec(r, "debit"),
                Credit = supplierSide ? Dec(r, "debit") : Dec(r, "credit"),
                RunningBalance = Dec(r, "runningbalance"),
                DocumentType = supplierSide ? Str(r, "documenttype") : "Sale",
                DocumentId = supplierSide ? IntN(r, "documentid") : IntN(r, "saleid"),
                // Guarded, not just null-coalesced: the supplier statement does
                // not return these columns at all, and asking for one by name
                // that is not in the result throws.
                PaymentId = supplierSide ? null : GuidN(r, "paymentgroupid"),
                AllocationCount = supplierSide ? null : IntN(r, "allocationcount"),
                SourceType = supplierSide ? null : Str(r, "sourcetype"),
            });

        public Task<List<StatementLine>> GetCustomerStatement(string farmId, int customerId, DateTime? from, DateTime? to) =>
            Statement("SELECT * FROM sppoultrycustomerstatement(p_farmid => @FarmId::text, p_customerid => @PartyId::int, p_from => @From::date, p_to => @To::date)",
                      farmId, customerId, from, to, supplierSide: false);

        public Task<List<StatementLine>> GetSupplierStatement(string farmId, int supplierId, DateTime? from, DateTime? to) =>
            Statement("SELECT * FROM sppoultrysupplierstatement(p_farmid => @FarmId::text, p_supplierid => @PartyId::int, p_from => @From::date, p_to => @To::date)",
                      farmId, supplierId, from, to, supplierSide: true);

        // ------------------------------------------------- 351 customer credit

        public Task<List<CustomerCreditSummaryRow>> GetCustomerCreditSummary(string farmId) => Query(
            "SELECT * FROM sppoultrycustomercredit_summary(p_farmid => @FarmId::text)",
            cmd => cmd.Parameters.AddWithValue("@FarmId", farmId),
            r => new CustomerCreditSummaryRow
            {
                CustomerId = Int(r, "customerid"),
                CustomerName = Str(r, "customername") ?? string.Empty,
                AvailableCredit = Dec(r, "availablecredit"),
                PaymentCount = Int(r, "paymentcount"),
                Outstanding = Dec(r, "outstanding"),
            });

        public Task<List<CustomerCreditRow>> GetCustomerCredit(string farmId, int customerId) => Query(
            "SELECT * FROM sppoultrycustomercredit_list(p_farmid => @FarmId::text, p_customerid => @CustomerId::int)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                cmd.Parameters.AddWithValue("@CustomerId", customerId);
            },
            r => new CustomerCreditRow
            {
                PoultryPaymentId = Int(r, "poultrypaymentid"),
                PaymentGroupId = Guid.TryParse(GuidN(r, "paymentgroupid"), out var g) ? g : null,
                PaymentNumber = Str(r, "paymentnumber"),
                PaymentDate = DateN(r, "paymentdate"),
                Amount = Dec(r, "amount"),
                Unapplied = Dec(r, "unapplied"),
                SourceType = Str(r, "sourcetype"),
                SaleId = Int(r, "saleid"),
                SaleStatus = Str(r, "salestatus"),
                PoultryCashAccountId = IntN(r, "poultrycashaccountid"),
            });

        /// <summary>An allocation only: no payment, no Money In, no cash movement.</summary>
        public async Task<decimal> ApplyCustomerCredit(CustomerCreditApplyRequest r)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand(
                "SELECT sppoultrycustomercredit_apply(p_farmid => @FarmId::text, p_customerid => @CustomerId::int, " +
                "p_saleid => @SaleId::int, p_amount => @Amount::numeric, p_by => @By::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", r.FarmId);
            cmd.Parameters.AddWithValue("@CustomerId", r.CustomerId);
            cmd.Parameters.AddWithValue("@SaleId", r.SaleId);
            cmd.Parameters.AddWithValue("@Amount", r.Amount);
            cmd.Parameters.AddWithValue("@By", Db(r.CreatedBy));
            await conn.OpenAsync();
            return Convert.ToDecimal(await cmd.ExecuteScalarAsync());
        }

        /// <summary>Real Money Out from the chosen account. Not an expense; no stock moves.</summary>
        public async Task<int> RecordCustomerRefund(CustomerRefundRequest r)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand(
                "SELECT sppoultrycustomerrefund_record(p_farmid => @FarmId::text, p_customerid => @CustomerId::int, " +
                "p_amount => @Amount::numeric, p_cashaccountid => @Account::int, p_paymentmethod => @Method::text, " +
                "p_refunddate => @Date::date, p_reason => @Reason::text, p_by => @By::text, " +
                "p_paymentid => @PaymentId::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", r.FarmId);
            cmd.Parameters.AddWithValue("@PaymentId", (object?)r.PoultryPaymentId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CustomerId", r.CustomerId);
            cmd.Parameters.AddWithValue("@Amount", r.Amount);
            cmd.Parameters.AddWithValue("@Account", r.PoultryCashAccountId);
            cmd.Parameters.AddWithValue("@Method", Db(r.PaymentMethod));
            cmd.Parameters.AddWithValue("@Date", DbDate(r.RefundDate));
            cmd.Parameters.AddWithValue("@Reason", r.Reason ?? string.Empty);
            cmd.Parameters.AddWithValue("@By", Db(r.CreatedBy));
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public Task<List<CustomerRefundRow>> GetCustomerRefunds(string farmId, int? customerId) => Query(
            "SELECT * FROM sppoultrycustomerrefund_list(p_farmid => @FarmId::text, p_customerid => @CustomerId::int)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                cmd.Parameters.AddWithValue("@CustomerId", (object?)customerId ?? DBNull.Value);
            },
            r => new CustomerRefundRow
            {
                RefundId = Int(r, "refundid"),
                RefundNumber = Str(r, "refundnumber") ?? string.Empty,
                CustomerId = Int(r, "customerid"),
                CustomerName = Str(r, "customername"),
                Amount = Dec(r, "amount"),
                RefundDate = DateN(r, "refunddate") ?? DateTime.MinValue,
                PoultryCashAccountId = Int(r, "poultrycashaccountid"),
                AccountName = Str(r, "accountname"),
                PaymentMethod = Str(r, "paymentmethod"),
                Reason = Str(r, "reason") ?? string.Empty,
                Status = Str(r, "status") ?? "Posted",
                CreatedBy = Str(r, "createdby"),
                CreatedAt = DateN(r, "createdat") ?? DateTime.MinValue,
                PaymentNumbers = Str(r, "paymentnumbers"),
                ReversedAt = DateN(r, "reversedat"),
                ReversedBy = Str(r, "reversedby"),
                ReversalReason = Str(r, "reversalreason"),
                ReversalDate = DateN(r, "reversaldate"),
            });

        /// <summary>
        /// 367: the refund stays (Reversed); the money goes back into the account
        /// it left from and the credit comes back. Owner / admin only.
        /// </summary>
        public async Task<int> ReverseCustomerRefund(int refundId, CustomerRefundReverseRequest r)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand(
                "SELECT sppoultrycustomerrefund_reverse(p_farmid => @FarmId::text, p_refundid => @Refund::int, " +
                "p_reason => @Reason::text, p_by => @By::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", r.FarmId);
            cmd.Parameters.AddWithValue("@Refund", refundId);
            cmd.Parameters.AddWithValue("@Reason", r.Reason ?? string.Empty);
            cmd.Parameters.AddWithValue("@By", Db(r.ReversedBy));
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        /// <summary>369: record what a customer owes without a sale. No cash, no revenue.</summary>
        public async Task<string> CreateCustomerDebt(CustomerDebtRequest r)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand(
                "SELECT sppoultrycustomerdebt_create(p_farmid => @FarmId::text, p_customerid => @CustomerId::int, " +
                "p_amount => @Amount::numeric, p_debtdate => @Date::date, p_entrytype => @Type::text, " +
                "p_description => @Description::text, p_reference => @Reference::text, p_notes => @Notes::text, " +
                "p_by => @By::text)::text", conn);
            cmd.Parameters.AddWithValue("@FarmId", r.FarmId);
            cmd.Parameters.AddWithValue("@CustomerId", r.CustomerId);
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

        /// <summary>369: refused while any payment is applied to the debt.</summary>
        public async Task<int> ReverseCustomerDebt(int debtId, CustomerDebtReverseRequest r)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand(
                "SELECT sppoultrycustomerdebt_reverse(p_farmid => @FarmId::text, p_debtid => @Debt::int, " +
                "p_reason => @Reason::text, p_by => @By::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", r.FarmId);
            cmd.Parameters.AddWithValue("@Debt", debtId);
            cmd.Parameters.AddWithValue("@Reason", r.Reason ?? string.Empty);
            cmd.Parameters.AddWithValue("@By", Db(r.ReversedBy));
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public Task<List<CustomerDebtRow>> GetCustomerDebts(string farmId, int? customerId) => Query(
            "SELECT * FROM sppoultrycustomerdebt_list(p_farmid => @FarmId::text, p_customerid => @CustomerId::int)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                cmd.Parameters.AddWithValue("@CustomerId", (object?)customerId ?? DBNull.Value);
            },
            r => new CustomerDebtRow
            {
                DebtId = Int(r, "debtid"),
                DebtNumber = Str(r, "debtnumber") ?? string.Empty,
                CustomerId = Int(r, "customerid"),
                CustomerName = Str(r, "customername"),
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

        // ------------------------------------------------------- 370 supplier credit

        private async Task<int> ScalarInt(string sql, Action<NpgsqlCommand> bind)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand(sql, conn);
            bind(cmd);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public Task<List<SupplierCreditSummaryRow>> GetSupplierCreditSummary(string farmId) => Query(
            "SELECT * FROM sppoultrysuppliercredit_summary(p_farmid => @FarmId::text)",
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
            "SELECT * FROM sppoultrysuppliercredit_events(p_farmid => @FarmId::text, p_supplierid => @SupplierId::int)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                cmd.Parameters.AddWithValue("@SupplierId", (object?)supplierId ?? DBNull.Value);
            },
            r => new SupplierCreditEventRow
            {
                PoultrySupplierPaymentId = Int(r, "poultrysupplierpaymentid"),
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
                PoultryCashAccountId = IntN(r, "poultrycashaccountid"),
                AccountName = Str(r, "accountname"),
            });

        public Task<List<SupplierCreditApplicationRow>> GetSupplierCreditApplications(string farmId, int? supplierId) => Query(
            "SELECT * FROM sppoultrysuppliercredit_applications(p_farmid => @FarmId::text, p_supplierid => @SupplierId::int)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                cmd.Parameters.AddWithValue("@SupplierId", (object?)supplierId ?? DBNull.Value);
            },
            r => new SupplierCreditApplicationRow
            {
                AllocationId = Int(r, "allocationid"),
                PoultrySupplierPaymentId = Int(r, "poultrysupplierpaymentid"),
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

        public Task<int> CreateSupplierCredit(SupplierCreditCreateRequest r) => ScalarInt(
            "SELECT sppoultrysuppliercredit_create(p_farmid => @FarmId::text, p_supplierid => @SupplierId::int, " +
            "p_kind => @Kind::text, p_amount => @Amount::numeric, p_date => @Date::timestamp, " +
            "p_reference => @Reference::text, p_reason => @Reason::text, p_by => @By::text)",
            cmd =>
            {
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
            "SELECT sppoultrysuppliercredit_reverse(p_farmid => @FarmId::text, p_paymentid => @Id::int, p_reason => @Reason::text, p_by => @By::text)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", r.FarmId);
                cmd.Parameters.AddWithValue("@Id", paymentId);
                cmd.Parameters.AddWithValue("@Reason", r.Reason ?? string.Empty);
                cmd.Parameters.AddWithValue("@By", Db(r.By));
            });

        public Task<int> ApplySupplierCredit(SupplierCreditApplyRequest r) => ScalarInt(
            "SELECT sppoultrysuppliercredit_apply(p_farmid => @FarmId::text, p_paymentid => @Id::int, " +
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
            "SELECT sppoultrysuppliercredit_unapply(p_farmid => @FarmId::text, p_allocationid => @Id::int, p_reason => @Reason::text, p_by => @By::text)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", r.FarmId);
                cmd.Parameters.AddWithValue("@Id", allocationId);
                cmd.Parameters.AddWithValue("@Reason", r.Reason ?? string.Empty);
                cmd.Parameters.AddWithValue("@By", Db(r.By));
            });

        public Task<int> RecordSupplierRefund(SupplierRefundRequest r) => ScalarInt(
            "SELECT sppoultrysupplierrefund_record(p_farmid => @FarmId::text, p_paymentid => @Id::int, p_amount => @Amount::numeric, " +
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
            "SELECT sppoultrysupplierrefund_reverse(p_farmid => @FarmId::text, p_refundid => @Id::int, p_reason => @Reason::text, p_by => @By::text)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", r.FarmId);
                cmd.Parameters.AddWithValue("@Id", refundId);
                cmd.Parameters.AddWithValue("@Reason", r.Reason ?? string.Empty);
                cmd.Parameters.AddWithValue("@By", Db(r.By));
            });

        public Task<List<SupplierRefundRow>> GetSupplierRefunds(string farmId, int? supplierId) => Query(
            "SELECT * FROM sppoultrysupplierrefund_list(p_farmid => @FarmId::text, p_supplierid => @SupplierId::int)",
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
                PoultryCashAccountId = Int(r, "poultrycashaccountid"),
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
                "SELECT sppoultrysupplierdebt_create(p_farmid => @FarmId::text, p_supplierid => @SupplierId::int, " +
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
            "SELECT sppoultrysupplierdebt_reverse(p_farmid => @FarmId::text, p_debtid => @Id::int, p_reason => @Reason::text, p_by => @By::text)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", r.FarmId);
                cmd.Parameters.AddWithValue("@Id", debtId);
                cmd.Parameters.AddWithValue("@Reason", r.Reason ?? string.Empty);
                cmd.Parameters.AddWithValue("@By", Db(r.By));
            });

        public Task<List<SupplierDebtRow>> GetSupplierDebts(string farmId, int? supplierId) => Query(
            "SELECT * FROM sppoultrysupplierdebt_list(p_farmid => @FarmId::text, p_supplierid => @SupplierId::int)",
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

        /// <summary>367: every credit event, with Original / Applied / Refunded / Available.</summary>
        public Task<List<CustomerCreditEventRow>> GetCustomerCreditEvents(string farmId, int? customerId) => Query(
            "SELECT * FROM sppoultrycustomercredit_events(p_farmid => @FarmId::text, p_customerid => @CustomerId::int)",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                cmd.Parameters.AddWithValue("@CustomerId", (object?)customerId ?? DBNull.Value);
            },
            r => new CustomerCreditEventRow
            {
                PoultryPaymentId = Int(r, "poultrypaymentid"),
                PaymentGroupId = Guid.TryParse(GuidN(r, "paymentgroupid"), out var g) ? g : null,
                PaymentNumber = Str(r, "paymentnumber"),
                CreditDate = DateN(r, "creditdate"),
                CustomerId = Int(r, "customerid"),
                CustomerName = Str(r, "customername"),
                Source = Str(r, "source") ?? string.Empty,
                SourceType = Str(r, "sourcetype"),
                SaleId = IntN(r, "saleid"),
                SaleGroupNo = Str(r, "salegroupno"),
                Reference = Str(r, "reference"),
                OriginalAmount = Dec(r, "originalamount"),
                Applied = Dec(r, "applied"),
                Refunded = Dec(r, "refunded"),
                Available = Dec(r, "available"),
                Status = Str(r, "status") ?? string.Empty,
                IsManual = Bool(r, "ismanual"),
                PoultryCashAccountId = IntN(r, "poultrycashaccountid"),
            });

        // ------------------------------------------------- 363 manual credit

        /// <summary>Opening credit / credit note: no cash. Deposit: one CashIn on its account.</summary>
        public async Task<string> CreateManualCredit(ManualCreditRequest r)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand(
                "SELECT sppoultrycustomercredit_create(p_farmid => @FarmId::text, p_customerid => @CustomerId::int, " +
                "p_kind => @Kind::text, p_amount => @Amount::numeric, p_date => @Date::timestamp, " +
                "p_cashaccountid => @Account::int, p_paymentmethod => @Method::text, p_reference => @Reference::text, " +
                "p_reason => @Reason::text, p_by => @By::text)::text", conn);
            cmd.Parameters.AddWithValue("@FarmId", r.FarmId);
            cmd.Parameters.AddWithValue("@CustomerId", r.CustomerId);
            cmd.Parameters.AddWithValue("@Kind", r.Kind ?? string.Empty);
            cmd.Parameters.AddWithValue("@Amount", r.Amount);
            cmd.Parameters.AddWithValue("@Date", r.CreditDate.HasValue ? r.CreditDate.Value : DBNull.Value);
            cmd.Parameters.AddWithValue("@Account", Db(r.PoultryCashAccountId));
            cmd.Parameters.AddWithValue("@Method", Db(r.PaymentMethod));
            cmd.Parameters.AddWithValue("@Reference", Db(r.Reference));
            cmd.Parameters.AddWithValue("@Reason", r.Reason ?? string.Empty);
            cmd.Parameters.AddWithValue("@By", Db(r.CreatedBy));
            await conn.OpenAsync();
            return (string?)await cmd.ExecuteScalarAsync() ?? "{}";
        }

        /// <summary>Releases what was used on sales; a deposit's cash goes back out.</summary>
        public async Task<int> ReverseManualCredit(Guid paymentGroupId, ManualCreditReverseRequest r)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand(
                "SELECT sppoultrycustomercredit_reverse(p_farmid => @FarmId::text, p_paymentgroupid => @Group::uuid, " +
                "p_reason => @Reason::text, p_by => @By::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", r.FarmId);
            cmd.Parameters.AddWithValue("@Group", paymentGroupId);
            cmd.Parameters.AddWithValue("@Reason", r.Reason ?? string.Empty);
            cmd.Parameters.AddWithValue("@By", Db(r.ReversedBy));
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public Task<List<ManualCreditRow>> GetManualCredits(string farmId) => Query(
            "SELECT * FROM sppoultrycustomercredit_manuallist(p_farmid => @FarmId::text)",
            cmd => cmd.Parameters.AddWithValue("@FarmId", farmId),
            r => new ManualCreditRow
            {
                PaymentGroupId = Guid.TryParse(GuidN(r, "paymentgroupid"), out var g) ? g : Guid.Empty,
                PoultryPaymentId = Int(r, "poultrypaymentid"),
                PaymentNumber = Str(r, "paymentnumber"),
                Kind = Str(r, "kind") ?? string.Empty,
                CreditDate = DateN(r, "creditdate"),
                CustomerId = Int(r, "customerid"),
                CustomerName = Str(r, "customername"),
                Amount = Dec(r, "amount"),
                Used = Dec(r, "used"),
                Refunded = Dec(r, "refunded"),
                Remaining = Dec(r, "remaining"),
                Status = Str(r, "status") ?? "Posted",
                PoultryCashAccountId = IntN(r, "poultrycashaccountid"),
                CashAccountName = Str(r, "cashaccountname"),
                PaymentMethod = Str(r, "paymentmethod"),
                Reference = Str(r, "reference"),
                Reason = Str(r, "reason"),
                CreatedBy = Str(r, "createdby"),
                CreatedAt = DateN(r, "createdat"),
                ReversedAt = DateN(r, "reversedat"),
                ReversalReason = Str(r, "reversalreason"),
            });

        // ----------------------------------------------------------------- audit

        public Task<List<BalanceAuditRow>> Audit(string farmId) => Query(
            "SELECT * FROM fnbalanceaudit(p_farmid => @FarmId::text, p_module => 'poultry')",
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
