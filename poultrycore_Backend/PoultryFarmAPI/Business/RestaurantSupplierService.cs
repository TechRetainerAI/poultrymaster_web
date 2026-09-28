// =============================================================================
// Restaurant suppliers, purchases, supplier payments and deferred inventory cost
// (migration 329).
//
// Every rule lives in the sprestaurant_* functions, each one database
// transaction: a purchase's stock, lot and ledger row, a supplier payment's
// allocations and its single cash-out, a reversal's refund all commit together
// or not at all. This class passes parameters and reads rows back by column
// NAME. Refusals (P0001) become a 400 through RestaurantBusinessRuleFilter.
//
// Supplier Balances / Supplier Payments return the shared BalanceModels DTOs
// with the same field meanings PoultryBalanceService gives them, so the shared
// components/balances pages work unchanged.
// =============================================================================

using System.Reflection;
using System.Text.Json;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IRestaurantSupplierService
    {
        // Purchases & cost recognition
        Task<int> CreatePurchaseAsync(string farmId, RestaurantPurchaseCreateRequest req, string by);
        Task ReversePurchaseAsync(string farmId, int purchaseId, string? reason, string by);
        Task<List<RestaurantPurchase>> ListPurchasesAsync(string farmId, DateTime? from, DateTime? to, int? supplierId, int? ingredientId, int? purchaseId);
        Task<List<RestaurantCostMode>> CostModesAsync(string farmId);
        Task SetCostModeAsync(string farmId, RestaurantCostModeRequest req, string by);

        // Deferred inventory cost
        Task<RestaurantDeferredResponse> DeferredAsync(string farmId, string? scope, int? ingredientId, int? supplierId,
                                                       string? category, DateTime? from, DateTime? to, string? search);
        Task<List<RestaurantDeferredHistory>> DeferredHistoryAsync(string farmId, int purchaseId);

        // Supplier balances & payments (shared contract)
        Task<List<PartyBalanceRow>> BalancesAsync(string farmId, DateTime? from, DateTime? to, int? supplierId,
                                                  string? status, decimal? minBalance, string? search);
        Task<BalanceSummary> SummaryAsync(string farmId);
        Task<List<OpenDocumentRow>> OpenDocumentsAsync(string farmId, int supplierId, DateTime? from, DateTime? to, string? status);
        Task<int> RecordPaymentAsync(RecordPaymentRequest r, string by);
        Task<int> ReversePaymentAsync(string farmId, int paymentId, string? reason, string by);
        Task<List<PaymentHistoryRow>> HistoryAsync(string farmId, int? supplierId, string? documentType, int? documentId,
                                                   DateTime? from, DateTime? to);
        Task<List<PaymentAllocationRow>> AllocationsAsync(string farmId, int paymentId);
        Task<List<StatementLine>> StatementAsync(string farmId, int supplierId, DateTime? from, DateTime? to);

        // Expenses
        Task<List<RestaurantExpensePayment>> ExpensePaymentsAsync(string farmId, DateTime? from, DateTime? to);

        // Supplier master
        Task UpdateSupplierAsync(int id, RestaurantSupplierUpdateRequest req);
        Task DeleteSupplierAsync(int id, string farmId);
    }

    public class RestaurantSupplierService : IRestaurantSupplierService
    {
        private readonly string _cs;
        public RestaurantSupplierService(string connectionString) { _cs = connectionString; }

        private static string? Blank(string? s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();

        // ── Purchases ──────────────────────────────────────────────────────

        public Task<int> CreatePurchaseAsync(string farmId, RestaurantPurchaseCreateRequest req, string by) =>
            ScalarIntAsync(
                "SELECT sprestaurant_purchase_create(p_farmid => @f::text, p_ingredientid => @i::int, " +
                "p_quantity => @q::numeric, p_totalcost => @t::numeric, p_purchasedate => @d::date, " +
                "p_supplierid => @s::int, p_suppliername => @sn::text, p_paymentmethod => @m::text, " +
                "p_amountpaid => @p::numeric, p_cashaccountid => @a::int, p_duedate => @due::date, " +
                "p_notes => @n::text, p_createdby => @by::text)",
                ("f", farmId), ("i", req.IngredientId), ("q", req.Quantity), ("t", req.TotalCost),
                ("d", req.PurchaseDate?.Date), ("s", req.SupplierId), ("sn", Blank(req.SupplierName)),
                ("m", Blank(req.PaymentMethod) ?? "Cash"), ("p", req.AmountPaid), ("a", req.CashAccountId),
                ("due", req.DueDate?.Date), ("n", Blank(req.Notes)), ("by", by));

        public Task ReversePurchaseAsync(string farmId, int purchaseId, string? reason, string by) =>
            ExecAsync("SELECT sprestaurant_purchase_reverse(p_farmid => @f::text, p_purchaseid => @p::int, " +
                      "p_reason => @r::text, p_reversedby => @by::text)",
                      ("f", farmId), ("p", purchaseId), ("r", Blank(reason)), ("by", by));

        public Task<List<RestaurantPurchase>> ListPurchasesAsync(string farmId, DateTime? from, DateTime? to,
                                                                 int? supplierId, int? ingredientId, int? purchaseId) =>
            QueryAsync<RestaurantPurchase>(
                "SELECT * FROM sprestaurant_purchase_list(p_farmid => @f::text, p_from => @a::date, p_to => @b::date, " +
                "p_supplierid => @s::int, p_ingredientid => @i::int, p_purchaseid => @p::int)",
                ("f", farmId), ("a", from?.Date), ("b", to?.Date), ("s", supplierId), ("i", ingredientId), ("p", purchaseId));

        public Task<List<RestaurantCostMode>> CostModesAsync(string farmId) =>
            QueryAsync<RestaurantCostMode>("SELECT * FROM sprestaurant_costmode_list(p_farmid => @f::text)", ("f", farmId));

        public Task SetCostModeAsync(string farmId, RestaurantCostModeRequest req, string by) =>
            ExecAsync("SELECT sprestaurant_costmode_set(p_farmid => @f::text, p_category => @c::text, " +
                      "p_costmode => @m::text, p_updatedby => @by::text)",
                      ("f", farmId), ("c", req.Category), ("m", req.CostMode), ("by", by));

        // ── Deferred inventory cost ────────────────────────────────────────

        private static string Scope(string? s)
        {
            var u = (s ?? "").Trim().ToUpperInvariant();
            return u is "DEFERRED" or "RECOGNIZED" or "EXCEPTION" or "ALL" ? u : "DEFERRED";
        }

        public async Task<RestaurantDeferredResponse> DeferredAsync(string farmId, string? scope, int? ingredientId, int? supplierId,
                                                                    string? category, DateTime? from, DateTime? to, string? search)
        {
            const string args = "p_farmid => @f::text, p_scope => @sc::text, p_ingredientid => @i::int, p_supplierid => @s::int, " +
                                "p_category => @c::text, p_fromdate => @a::date, p_todate => @b::date, p_search => @q::text";
            var ps = new (string, object?)[] { ("f", farmId), ("sc", Scope(scope)), ("i", ingredientId), ("s", supplierId),
                                               ("c", Blank(category)), ("a", from?.Date), ("b", to?.Date), ("q", Blank(search)) };
            var summary = (await QueryAsync<RestaurantDeferredSummary>(
                $"SELECT * FROM sprestaurant_deferredpurchase_summary({args})", ps)).FirstOrDefault() ?? new();
            var rows = await QueryAsync<RestaurantDeferredPurchase>(
                $"SELECT * FROM sprestaurant_deferredpurchase_getall({args})", ps);
            return new RestaurantDeferredResponse { Summary = summary, Purchases = rows };
        }

        public Task<List<RestaurantDeferredHistory>> DeferredHistoryAsync(string farmId, int purchaseId) =>
            QueryAsync<RestaurantDeferredHistory>(
                "SELECT * FROM sprestaurant_deferredpurchase_history(p_farmid => @f::text, p_purchaseid => @p::int)",
                ("f", farmId), ("p", purchaseId));

        // ── Supplier balances & payments ───────────────────────────────────

        public async Task<List<PartyBalanceRow>> BalancesAsync(string farmId, DateTime? from, DateTime? to, int? supplierId,
                                                               string? status, decimal? minBalance, string? search)
        {
            var rows = await RowsAsync(
                "SELECT * FROM sprestaurant_supplierbalances(p_farmid => @f::text, p_from => @a::date, p_to => @b::date, " +
                "p_supplierid => @s::int, p_status => @st::text, p_minbalance => @m::numeric, p_search => @q::text)",
                ("f", farmId), ("a", from?.Date), ("b", to?.Date), ("s", supplierId),
                ("st", Blank(status) ?? BalanceStatusFilters.All), ("m", minBalance), ("q", Blank(search)));
            return rows.Select(r => new PartyBalanceRow
            {
                PartyId = I(r, "supplierid"),
                PartyName = S(r, "suppliername") ?? "",
                ContactPhone = S(r, "contactphone"),
                ContactEmail = S(r, "contactemail"),
                PaymentTermsDays = I(r, "paymenttermsdays"),
                TotalBalance = D(r, "totalbalance"),
                OpenDocumentCount = I(r, "openpurchasecount"),
                OldestDocumentDate = Dt(r, "oldestpurchasedate"),
                LatestDocumentDate = Dt(r, "latestpurchasedate"),
                LastPaymentDate = Dt(r, "lastpaymentdate"),
                OverdueAmount = D(r, "overdueamount"),
                TotalInvoiced = D(r, "totalpurchases"),
                TotalPaid = D(r, "totalpaid"),
            }).ToList();
        }

        public async Task<BalanceSummary> SummaryAsync(string farmId)
        {
            var r = (await RowsAsync("SELECT * FROM sprestaurant_supplierbalancesummary(p_farmid => @f::text)", ("f", farmId)))
                .FirstOrDefault();
            if (r == null) return new BalanceSummary();
            return new BalanceSummary
            {
                TotalBalance = D(r, "totalbalance"),
                PartyCount = I(r, "suppliersowed"),
                OverdueBalance = D(r, "overduepayables"),
                PaymentsToday = D(r, "paymentsmadetoday"),
                LargestBalance = D(r, "largestbalance"),
                LargestBalanceParty = S(r, "largestbalancesupplier"),
            };
        }

        public async Task<List<OpenDocumentRow>> OpenDocumentsAsync(string farmId, int supplierId, DateTime? from, DateTime? to, string? status)
        {
            var rows = await RowsAsync(
                "SELECT * FROM sprestaurant_supplieropenpurchases(p_farmid => @f::text, p_supplierid => @s::int, " +
                "p_from => @a::date, p_to => @b::date, p_status => @st::text)",
                ("f", farmId), ("s", supplierId), ("a", from?.Date), ("b", to?.Date), ("st", Blank(status) ?? BalanceStatusFilters.All));
            return rows.Select(r => new OpenDocumentRow
            {
                DocumentType = S(r, "documenttype") ?? "",
                DocumentId = I(r, "documentid"),
                Reference = S(r, "reference"),
                DocumentDate = Dt(r, "docdate") ?? DateTime.MinValue,
                Label = S(r, "label"),
                TotalAmount = D(r, "totalcost"),
                AmountPaid = D(r, "amountpaid"),
                Balance = D(r, "balance"),
                DueDate = Dt(r, "duedate"),
                AgeDays = I(r, "agedays"),
                Status = S(r, "status") ?? "",
                IsOverdue = r.TryGetValue("isoverdue", out var o) && o is bool b && b,
                CashAccountId = r.TryGetValue("cashaccountid", out var c) && c != null ? Convert.ToInt32(c) : null,
            }).ToList();
        }

        public Task<int> RecordPaymentAsync(RecordPaymentRequest r, string by)
        {
            var allocations = JsonSerializer.Serialize(r.Allocations.Select(a => new Dictionary<string, object?>
            {
                ["documenttype"] = a.DocumentType,
                ["documentid"] = a.DocumentId,
                ["amount"] = a.Amount,
            }));
            return ScalarIntAsync(
                "SELECT sprestaurant_supplierpayment_record(p_farmid => @f::text, p_supplierid => @s::int, " +
                "p_amount => @amt::numeric, p_allocations => @al::jsonb, p_paymentmethod => @m::text, " +
                "p_paymentdate => @d::timestamp, p_cashaccountid => @acc::int, p_reference => @ref::text, " +
                "p_notes => @n::text, p_sourcetype => @src::text, p_createdby => @by::text)",
                ("f", r.FarmId), ("s", r.PartyId), ("amt", r.Amount), ("al", allocations), ("m", Blank(r.PaymentMethod)),
                ("d", r.PaymentDate), ("acc", r.CashAccountId), ("ref", Blank(r.Reference)), ("n", Blank(r.Notes)),
                ("src", Blank(r.SourceType) ?? PaymentSourceTypes.SupplierBalances), ("by", by));
        }

        public Task<int> ReversePaymentAsync(string farmId, int paymentId, string? reason, string by) =>
            ScalarIntAsync("SELECT sprestaurant_supplierpayment_reverse(p_farmid => @f::text, p_paymentid => @p::int, " +
                           "p_reason => @r::text, p_reversedby => @by::text)",
                           ("f", farmId), ("p", paymentId), ("r", Blank(reason)), ("by", by));

        public async Task<List<PaymentHistoryRow>> HistoryAsync(string farmId, int? supplierId, string? documentType, int? documentId,
                                                                DateTime? from, DateTime? to)
        {
            var rows = await RowsAsync(
                "SELECT * FROM sprestaurant_supplierpayment_history(p_farmid => @f::text, p_supplierid => @s::int, " +
                "p_documenttype => @t::text, p_documentid => @d::int, p_from => @a::date, p_to => @b::date)",
                ("f", farmId), ("s", supplierId), ("t", Blank(documentType)), ("d", documentId), ("a", from?.Date), ("b", to?.Date));
            return rows.Select(r => new PaymentHistoryRow
            {
                PaymentId = I(r, "paymentid").ToString(),
                PartyId = r["supplierid"] == null ? null : I(r, "supplierid"),
                PartyName = S(r, "suppliername"),
                PaymentDate = Dt(r, "paymentdate") ?? DateTime.MinValue,
                TotalAmount = D(r, "totalamount"),
                PaymentMethod = S(r, "paymentmethod"),
                Reference = S(r, "referenceno"),
                Notes = S(r, "notes"),
                SourceType = S(r, "sourcetype"),
                Status = S(r, "status") ?? "Posted",
                AllocationCount = I(r, "allocationcount"),
                CashAccountId = r["cashaccountid"] == null ? null : I(r, "cashaccountid"),
                CreatedBy = S(r, "createdby"),
                ReversedBy = S(r, "reversedby"),
                ReversedAt = Dt(r, "reversedat"),
                ReversalReason = S(r, "reversalreason"),
                CreatedAt = Dt(r, "createdat"),
            }).ToList();
        }

        public async Task<List<PaymentAllocationRow>> AllocationsAsync(string farmId, int paymentId)
        {
            var rows = await RowsAsync(
                "SELECT * FROM sprestaurant_supplierpayment_allocations(p_farmid => @f::text, p_paymentid => @p::int)",
                ("f", farmId), ("p", paymentId));
            return rows.Select(r => new PaymentAllocationRow
            {
                AllocationId = I(r, "allocationid"),
                DocumentType = S(r, "documenttype") ?? "",
                DocumentId = I(r, "documentid"),
                Reference = S(r, "reference"),
                DocumentDate = Dt(r, "docdate"),
                Label = S(r, "label"),
                DocumentTotal = D(r, "documenttotal"),
                AmountApplied = D(r, "amountapplied"),
                BalanceBefore = D(r, "documentbalancebefore"),
                BalanceAfter = D(r, "documentbalanceafter"),
                Status = S(r, "status") ?? "Posted",
            }).ToList();
        }

        public async Task<List<StatementLine>> StatementAsync(string farmId, int supplierId, DateTime? from, DateTime? to)
        {
            var rows = await RowsAsync(
                "SELECT * FROM sprestaurant_supplierstatement(p_farmid => @f::text, p_supplierid => @s::int, " +
                "p_from => @a::date, p_to => @b::date)",
                ("f", farmId), ("s", supplierId), ("a", from?.Date), ("b", to?.Date));
            // As in PoultryBalanceService: the SQL "credit" (billed) is what the
            // shared statement calls a debit -- something that increases what is owed.
            return rows.Select(r => new StatementLine
            {
                EntryDate = Dt(r, "entrydate"),
                EntryType = S(r, "entrytype") ?? "",
                Reference = S(r, "reference"),
                Description = S(r, "description"),
                Debit = D(r, "credit"),
                Credit = D(r, "debit"),
                RunningBalance = D(r, "runningbalance"),
                DocumentType = S(r, "documenttype"),
                DocumentId = r["documentid"] == null ? null : I(r, "documentid"),
            }).ToList();
        }

        // ── Expenses ───────────────────────────────────────────────────────

        public Task<List<RestaurantExpensePayment>> ExpensePaymentsAsync(string farmId, DateTime? from, DateTime? to) =>
            QueryAsync<RestaurantExpensePayment>(
                "SELECT * FROM sprestaurant_expense_payments(p_farmid => @f::text, p_from => @a::date, p_to => @b::date)",
                ("f", farmId), ("a", from?.Date), ("b", to?.Date));

        // ── Supplier master ────────────────────────────────────────────────

        public Task UpdateSupplierAsync(int id, RestaurantSupplierUpdateRequest req) =>
            ExecAsync("SELECT sprestaurant_supplier_update(p_id => @i::int, p_farmid => @f::text, p_name => @n::text, " +
                      "p_contactname => @c::text, p_phone => @p::text, p_email => @e::text, p_address => @a::text, " +
                      "p_category => @cat::text, p_notes => @nt::text, p_isactive => @act::boolean)",
                      ("i", id), ("f", req.FarmId), ("n", req.Name.Trim()), ("c", Blank(req.ContactName)),
                      ("p", Blank(req.Phone)), ("e", Blank(req.Email)), ("a", Blank(req.Address)),
                      ("cat", Blank(req.Category)), ("nt", Blank(req.Notes)), ("act", req.IsActive));

        public Task DeleteSupplierAsync(int id, string farmId) =>
            ExecAsync("SELECT sprestaurant_supplier_delete(p_id => @i::int, p_farmid => @f::text)", ("i", id), ("f", farmId));

        // ── Plumbing (same as RestaurantCapitalAssetService) ──────────────

        private static int I(Dictionary<string, object?> r, string k) => r.TryGetValue(k, out var v) && v != null ? Convert.ToInt32(v) : 0;
        private static decimal D(Dictionary<string, object?> r, string k) => r.TryGetValue(k, out var v) && v != null ? Convert.ToDecimal(v) : 0m;
        private static string? S(Dictionary<string, object?> r, string k) => r.TryGetValue(k, out var v) && v != null ? v.ToString() : null;
        private static DateTime? Dt(Dictionary<string, object?> r, string k)
        {
            if (!r.TryGetValue(k, out var v) || v == null) return null;
            return v switch { DateOnly d => d.ToDateTime(TimeOnly.MinValue), DateTime t => t, _ => Convert.ToDateTime(v) };
        }

        private static NpgsqlCommand Command(NpgsqlConnection conn, string sql, (string name, object? value)[] ps)
        {
            var cmd = new NpgsqlCommand(sql, conn);
            foreach (var (name, value) in ps)
                cmd.Parameters.AddWithValue("@" + name, value ?? DBNull.Value);
            return cmd;
        }

        private async Task<int> ScalarIntAsync(string sql, params (string, object?)[] ps)
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            await using var cmd = Command(conn, sql, ps);
            var v = await cmd.ExecuteScalarAsync();
            return v == null || v is DBNull ? 0 : Convert.ToInt32(v);
        }

        private async Task ExecAsync(string sql, params (string, object?)[] ps)
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            await using var cmd = Command(conn, sql, ps);
            await cmd.ExecuteNonQueryAsync();
        }

        private async Task<List<Dictionary<string, object?>>> RowsAsync(string sql, params (string, object?)[] ps)
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            await using var cmd = Command(conn, sql, ps);
            await using var r = await cmd.ExecuteReaderAsync();
            var list = new List<Dictionary<string, object?>>();
            while (await r.ReadAsync())
            {
                var d = new Dictionary<string, object?>(StringComparer.OrdinalIgnoreCase);
                for (var i = 0; i < r.FieldCount; i++) d[r.GetName(i)] = r.IsDBNull(i) ? null : r.GetValue(i);
                list.Add(d);
            }
            return list;
        }

        private async Task<List<T>> QueryAsync<T>(string sql, params (string, object?)[] ps) where T : new()
        {
            var rows = await RowsAsync(sql, ps);
            var props = typeof(T).GetProperties(BindingFlags.Public | BindingFlags.Instance)
                .Where(p => p.CanWrite)
                .ToDictionary(p => p.Name, StringComparer.OrdinalIgnoreCase);
            var list = new List<T>();
            foreach (var row in rows)
            {
                var item = new T();
                foreach (var (k, v) in row)
                    if (v != null && props.TryGetValue(k, out var p)) p.SetValue(item, ConvertTo(v, p.PropertyType));
                list.Add(item);
            }
            return list;
        }

        private static object? ConvertTo(object value, Type target)
        {
            var t = Nullable.GetUnderlyingType(target) ?? target;
            if (value is DateOnly d) value = d.ToDateTime(TimeOnly.MinValue);
            if (t.IsInstanceOfType(value)) return value;
            return System.Convert.ChangeType(value, t, System.Globalization.CultureInfo.InvariantCulture);
        }
    }
}
