// =============================================================================
// Restaurant pay-later orders, Customer Balances and Payments (migration 333).
//
// Answers the SAME contract as PoultryBalanceService (Models/BalanceModels.cs)
// so the shared components/balances and components/payments pages work
// unchanged. Every rule lives in the sprestaurant_customer* functions (one
// transaction each). Rows are read by column NAME; refusals (P0001) become 400
// through RestaurantBusinessRuleFilter. Payment ids are strings: 'CP-n' a
// balance payment, 'OP-n' a payment taken on an order.
// =============================================================================

using System.Text.Json;
using Npgsql;
using NpgsqlTypes;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IRestaurantCustomerBalanceService
    {
        Task MarkPayLaterAsync(string farmId, int orderId, int? customerId, DateTime? dueDate, string? notes, string by);
        Task<List<PartyBalanceRow>> BalancesAsync(string farmId, DateTime? from, DateTime? to, int? customerId,
                                                  string? status, decimal? minBalance, string? search);
        Task<BalanceSummary> SummaryAsync(string farmId);
        Task<List<OpenDocumentRow>> OpenOrdersAsync(string farmId, int customerId, DateTime? from, DateTime? to, string? status);
        Task<int> RecordAsync(RecordPaymentRequest r, string by);
        Task<int> ReverseAsync(string farmId, string paymentId, string? reason, string by);
        Task<List<PaymentHistoryRow>> HistoryAsync(string farmId, int? customerId, int? saleId, DateTime? from, DateTime? to);
        Task<List<PaymentAllocationRow>> AllocationsAsync(string farmId, string paymentId);
        Task<List<StatementLine>> StatementAsync(string farmId, int customerId, DateTime? from, DateTime? to);
        Task<List<BalanceAuditRow>> AuditAsync(string farmId);
    }

    public class RestaurantCustomerBalanceService : IRestaurantCustomerBalanceService
    {
        private readonly string _cs;
        public RestaurantCustomerBalanceService(string connectionString) { _cs = connectionString; }

        private static string? Blank(string? s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();

        public Task MarkPayLaterAsync(string farmId, int orderId, int? customerId, DateTime? dueDate, string? notes, string by) =>
            ExecAsync("SELECT sprestaurant_order_paylater(p_farmid => @f::text, p_orderid => @o::int, p_customerid => @c::int, " +
                      "p_duedate => @d::date, p_notes => @n::text, p_markedby => @by::text)",
                      ("f", farmId), ("o", orderId), ("c", customerId), ("d", dueDate?.Date), ("n", Blank(notes)), ("by", by));

        public async Task<List<PartyBalanceRow>> BalancesAsync(string farmId, DateTime? from, DateTime? to, int? customerId,
                                                               string? status, decimal? minBalance, string? search)
        {
            var rows = await RowsAsync(
                "SELECT * FROM sprestaurant_customerbalances(p_farmid => @f::text, p_from => @a::date, p_to => @b::date, " +
                "p_customerid => @c::int, p_status => @s::text, p_minbalance => @m::numeric, p_search => @q::text)",
                ("f", farmId), ("a", from?.Date), ("b", to?.Date), ("c", customerId),
                ("s", Blank(status) ?? BalanceStatusFilters.All), ("m", minBalance), ("q", Blank(search)));
            return rows.Select(r => new PartyBalanceRow
            {
                PartyId = I(r, "customerid"),
                PartyName = S(r, "customername") ?? "",
                ContactPhone = S(r, "contactphone"),
                ContactEmail = S(r, "contactemail"),
                PaymentTermsDays = I(r, "paymenttermsdays"),
                TotalBalance = D(r, "totalbalance"),
                OpenDocumentCount = I(r, "opendocumentcount"),
                OldestDocumentDate = Dt(r, "oldestdocumentdate"),
                LatestDocumentDate = Dt(r, "latestdocumentdate"),
                LastPaymentDate = Dt(r, "lastpaymentdate"),
                OverdueAmount = D(r, "overdueamount"),
                TotalInvoiced = D(r, "totalinvoiced"),
                TotalPaid = D(r, "totalpaid"),
            }).ToList();
        }

        public async Task<BalanceSummary> SummaryAsync(string farmId)
        {
            var r = (await RowsAsync("SELECT * FROM sprestaurant_customerbalancesummary(p_farmid => @f::text)", ("f", farmId))).FirstOrDefault();
            if (r == null) return new BalanceSummary();
            return new BalanceSummary
            {
                TotalBalance = D(r, "totalbalance"),
                PartyCount = I(r, "partycount"),
                OverdueBalance = D(r, "overduebalance"),
                PaymentsToday = D(r, "paymentstoday"),
                LargestBalance = D(r, "largestbalance"),
                LargestBalanceParty = S(r, "largestbalanceparty"),
            };
        }

        public async Task<List<OpenDocumentRow>> OpenOrdersAsync(string farmId, int customerId, DateTime? from, DateTime? to, string? status)
        {
            var rows = await RowsAsync(
                "SELECT * FROM sprestaurant_customeropenorders(p_farmid => @f::text, p_customerid => @c::int, " +
                "p_from => @a::date, p_to => @b::date, p_status => @s::text)",
                ("f", farmId), ("c", customerId), ("a", from?.Date), ("b", to?.Date), ("s", Blank(status)));
            return rows.Select(r => new OpenDocumentRow
            {
                DocumentType = S(r, "documenttype") ?? "Order",
                DocumentId = I(r, "documentid"),
                Reference = S(r, "reference"),
                DocumentDate = Dt(r, "documentdate") ?? DateTime.MinValue,
                Label = S(r, "label"),
                Description = S(r, "description"),
                TotalAmount = D(r, "totalamount"),
                AmountPaid = D(r, "amountpaid"),
                Balance = D(r, "balance"),
                DueDate = Dt(r, "duedate"),
                AgeDays = I(r, "agedays"),
                Status = S(r, "status") ?? "",
                IsOverdue = r.TryGetValue("isoverdue", out var o) && o is bool b && b,
                CashAccountId = null,
            }).ToList();
        }

        public async Task<int> RecordAsync(RecordPaymentRequest r, string by)
        {
            var allocations = JsonSerializer.Serialize(r.Allocations.Select(a => new
            {
                documentId = a.DocumentId > 0 ? a.DocumentId : a.SaleId,
                amount = a.Amount,
            }));
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            await using var cmd = Command(conn,
                "SELECT sprestaurant_customerpayment_record(p_farmid => @f::text, p_customerid => @c::int, p_amount => @a::numeric, " +
                "p_paymentdate => @d::date, p_paymentmethod => @m::text, p_cashaccountid => @acc::int, p_reference => @ref::text, " +
                "p_notes => @n::text, p_sourcetype => @src::text, p_createdby => @by::text, p_allocations => @al)",
                ("f", r.FarmId), ("c", r.PartyId), ("a", r.Amount), ("d", r.PaymentDate?.Date), ("m", Blank(r.PaymentMethod) ?? "Cash"),
                ("acc", r.CashAccountId), ("ref", Blank(r.Reference)), ("n", Blank(r.Notes)),
                ("src", Blank(r.SourceType) ?? PaymentSourceTypes.CustomerBalances), ("by", by));
            cmd.Parameters.Add(new NpgsqlParameter("al", NpgsqlDbType.Jsonb) { Value = allocations });
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task<int> ReverseAsync(string farmId, string paymentId, string? reason, string by)
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            await using var cmd = Command(conn,
                "SELECT sprestaurant_customerpayment_reverse(p_farmid => @f::text, p_paymentid => @p::text, " +
                "p_reason => @r::text, p_reversedby => @by::text)",
                ("f", farmId), ("p", paymentId), ("r", Blank(reason)), ("by", by));
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task<List<PaymentHistoryRow>> HistoryAsync(string farmId, int? customerId, int? saleId, DateTime? from, DateTime? to)
        {
            var rows = await RowsAsync(
                "SELECT * FROM sprestaurant_customerpayment_history(p_farmid => @f::text, p_customerid => @c::int, " +
                "p_saleid => @s::int, p_from => @a::date, p_to => @b::date)",
                ("f", farmId), ("c", customerId), ("s", saleId), ("a", from?.Date), ("b", to?.Date));
            return rows.Select(r => new PaymentHistoryRow
            {
                PaymentId = S(r, "paymentid") ?? "",
                PaymentNumber = S(r, "paymentnumber"),
                PartyId = NI(r, "partyid"),
                PartyName = S(r, "partyname"),
                PaymentDate = Dt(r, "paymentdate") ?? DateTime.MinValue,
                TotalAmount = D(r, "totalamount"),
                PaymentMethod = S(r, "paymentmethod"),
                Reference = S(r, "reference"),
                Notes = S(r, "notes"),
                SourceType = S(r, "sourcetype"),
                Status = S(r, "status") ?? "Posted",
                AllocationCount = I(r, "allocationcount"),
                CashAccountId = NI(r, "cashaccountid"),
                CreatedBy = S(r, "createdby"),
                ReversedBy = S(r, "reversedby"),
                ReversedAt = Dt(r, "reversedat"),
                ReversalReason = S(r, "reversalreason"),
                SaleId = NI(r, "saleid"),
                SaleTotal = ND(r, "saletotal"),
                BalanceBefore = ND(r, "balancebefore"),
                AmountApplied = ND(r, "amountapplied"),
                BalanceAfter = ND(r, "balanceafter"),
                CreatedAt = Dt(r, "createdat"),
            }).ToList();
        }

        public async Task<List<PaymentAllocationRow>> AllocationsAsync(string farmId, string paymentId)
        {
            var rows = await RowsAsync("SELECT * FROM sprestaurant_customerpayment_allocations(p_farmid => @f::text, p_paymentid => @p::text)",
                                       ("f", farmId), ("p", paymentId));
            return rows.Select(r => new PaymentAllocationRow
            {
                AllocationId = I(r, "allocationid"),
                DocumentType = S(r, "documenttype") ?? "Order",
                DocumentId = I(r, "documentid"),
                Reference = S(r, "reference"),
                DocumentDate = Dt(r, "documentdate"),
                Label = S(r, "label"),
                DocumentTotal = D(r, "documenttotal"),
                AmountApplied = D(r, "amountapplied"),
                BalanceBefore = D(r, "balancebefore"),
                BalanceAfter = D(r, "balanceafter"),
                Status = S(r, "status") ?? "Posted",
            }).ToList();
        }

        public async Task<List<StatementLine>> StatementAsync(string farmId, int customerId, DateTime? from, DateTime? to)
        {
            var rows = await RowsAsync(
                "SELECT * FROM sprestaurant_customerstatement(p_farmid => @f::text, p_customerid => @c::int, p_from => @a::date, p_to => @b::date)",
                ("f", farmId), ("c", customerId), ("a", from?.Date), ("b", to?.Date));
            return rows.Select(r => new StatementLine
            {
                EntryDate = Dt(r, "entrydate"),
                EntryType = S(r, "entrytype") ?? "",
                Reference = S(r, "reference"),
                Description = S(r, "description"),
                Debit = D(r, "debit"),
                Credit = D(r, "credit"),
                RunningBalance = D(r, "runningbalance"),
                DocumentType = S(r, "documenttype"),
                DocumentId = NI(r, "documentid"),
                PaymentId = S(r, "paymentid"),
                AllocationCount = NI(r, "allocationcount"),
                SourceType = S(r, "sourcetype"),
            }).ToList();
        }

        public async Task<List<BalanceAuditRow>> AuditAsync(string farmId)
        {
            var rows = await RowsAsync("SELECT * FROM sprestaurant_customerbalance_audit(p_farmid => @f::text)", ("f", farmId));
            return rows.Select(r => new BalanceAuditRow
            {
                Side = S(r, "side") ?? "customer",
                DocumentType = S(r, "documenttype") ?? "Order",
                DocumentId = I(r, "documentid"),
                AmountPaid = D(r, "amountpaid"),
                Allocated = D(r, "allocated"),
                Difference = D(r, "difference"),
            }).ToList();
        }

        // ── Plumbing (same as RestaurantSupplierService) ──────────────────

        private static int I(Dictionary<string, object?> r, string k) => r.TryGetValue(k, out var v) && v != null ? Convert.ToInt32(v) : 0;
        private static int? NI(Dictionary<string, object?> r, string k) => r.TryGetValue(k, out var v) && v != null ? Convert.ToInt32(v) : null;
        private static decimal D(Dictionary<string, object?> r, string k) => r.TryGetValue(k, out var v) && v != null ? Convert.ToDecimal(v) : 0m;
        private static decimal? ND(Dictionary<string, object?> r, string k) => r.TryGetValue(k, out var v) && v != null ? Convert.ToDecimal(v) : null;
        private static string? S(Dictionary<string, object?> r, string k) => r.TryGetValue(k, out var v) && v != null ? v.ToString() : null;
        private static DateTime? Dt(Dictionary<string, object?> r, string k)
        {
            if (!r.TryGetValue(k, out var v) || v == null) return null;
            return v switch { DateOnly d => d.ToDateTime(TimeOnly.MinValue), DateTime t => t, _ => Convert.ToDateTime(v) };
        }

        private static NpgsqlCommand Command(NpgsqlConnection conn, string sql, params (string name, object? value)[] ps)
        {
            var cmd = new NpgsqlCommand(sql, conn);
            foreach (var (name, value) in ps) cmd.Parameters.AddWithValue("@" + name, value ?? DBNull.Value);
            return cmd;
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
            await using var rd = await cmd.ExecuteReaderAsync();
            var list = new List<Dictionary<string, object?>>();
            while (await rd.ReadAsync())
            {
                var d = new Dictionary<string, object?>(StringComparer.OrdinalIgnoreCase);
                for (var i = 0; i < rd.FieldCount; i++) d[rd.GetName(i)] = rd.IsDBNull(i) ? null : rd.GetValue(i);
                list.Add(d);
            }
            return list;
        }
    }
}
