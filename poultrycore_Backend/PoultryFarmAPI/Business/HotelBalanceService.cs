// =============================================================================
// Hotel Sales, Payments, Customer Balances, Supplier Balances, Supplier
// Payments (migration 332).
//
// A thin caller of the 332 Postgres functions: every money movement happens in
// one of them, in one transaction, through fnhotelcash_post. Rows are read by
// column NAME into the shared BalanceModels DTOs (the functions return columns
// named after the DTO properties), so components/balances and
// components/payments work unchanged. Refusals (P0001) become a 400 via
// HotelBusinessRuleFilter.
//
// Customer party ids: a guest is its hotelguestid, a corporate account is
// MINUS its hotelcustomerid.
// =============================================================================

using System.Reflection;
using System.Text.Json;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class HotelSaleRow
    {
        public string DocumentType { get; set; } = "";
        public int DocumentId { get; set; }
        public int? PartyId { get; set; }
        public string? PartyName { get; set; }
        public DateTime DocDate { get; set; }
        public DateTime? DueDate { get; set; }
        public string? Reference { get; set; }
        public string? Label { get; set; }
        public decimal TotalAmount { get; set; }
        public decimal AmountPaid { get; set; }
        public decimal Balance { get; set; }
        public string PaymentStatus { get; set; } = "";
        public string? BookingStatus { get; set; }
        public int? Nights { get; set; }
        public string? RoomNumber { get; set; }
        public string? PaymentMethod { get; set; }
        public bool BilledToAccount { get; set; }
        public bool IsOwing { get; set; }
        public bool IsOverdue { get; set; }
    }

    public interface IHotelBalanceService
    {
        Task<List<HotelSaleRow>> SalesAsync(string farmId, DateTime? from, DateTime? to);
        Task<int> BillToAccountAsync(string farmId, int bookingId, int customerId, string by);

        Task<List<PartyBalanceRow>> BalancesAsync(string side, string farmId, DateTime? from, DateTime? to, int? partyId,
                                                  string? status, decimal? minBalance, string? search);
        Task<BalanceSummary> SummaryAsync(string side, string farmId);
        Task<List<OpenDocumentRow>> OpenDocumentsAsync(string side, string farmId, int partyId, DateTime? from, DateTime? to, string? status);
        Task<string> RecordAsync(string side, RecordPaymentRequest r, string by);
        Task<int> ReverseAsync(string side, string farmId, string paymentId, string? reason, string by);
        Task<List<PaymentHistoryRow>> HistoryAsync(string side, string farmId, int? partyId, string? documentType, int? documentId,
                                                   DateTime? from, DateTime? to);
        Task<List<PaymentAllocationRow>> AllocationsAsync(string side, string farmId, string paymentId);
        Task<List<StatementLine>> StatementAsync(string side, string farmId, int partyId, DateTime? from, DateTime? to);
        Task<List<BalanceAuditRow>> AuditAsync(string farmId);
    }

    public class HotelBalanceService : IHotelBalanceService
    {
        private readonly string _cs;
        public HotelBalanceService(string connectionString) { _cs = connectionString; }

        private static bool Customer(string side) => side == "customer";
        private static object Db(object? v) => v ?? DBNull.Value;

        // Reads every row into T, matching column names to property names
        // case-insensitively. Unknown columns are ignored.
        private async Task<List<T>> RowsAsync<T>(string sql, params (string n, object? v)[] ps) where T : new()
        {
            var props = typeof(T).GetProperties(BindingFlags.Public | BindingFlags.Instance)
                .ToDictionary(p => p.Name.ToLowerInvariant(), p => p);
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            await using var cmd = new NpgsqlCommand(sql, conn);
            foreach (var (n, v) in ps) cmd.Parameters.AddWithValue(n, Db(v));
            await using var r = await cmd.ExecuteReaderAsync();
            var list = new List<T>();
            while (await r.ReadAsync())
            {
                var t = new T();
                for (var i = 0; i < r.FieldCount; i++)
                {
                    if (r.IsDBNull(i) || !props.TryGetValue(r.GetName(i).ToLowerInvariant(), out var p)) continue;
                    var val = r.GetValue(i);
                    var target = Nullable.GetUnderlyingType(p.PropertyType) ?? p.PropertyType;
                    if (val is DateOnly d) val = d.ToDateTime(TimeOnly.MinValue);
                    else if (val is DateTimeOffset dto) val = dto.UtcDateTime;
                    else if (val is Guid g) val = g.ToString();
                    p.SetValue(t, target == val.GetType() ? val : Convert.ChangeType(val, target));
                }
                list.Add(t);
            }
            return list;
        }

        private async Task<object?> ScalarAsync(string sql, params (string n, object? v)[] ps)
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            await using var cmd = new NpgsqlCommand(sql, conn);
            foreach (var (n, v) in ps) cmd.Parameters.AddWithValue(n, Db(v));
            return await cmd.ExecuteScalarAsync();
        }

        // ── Sales ─────────────────────────────────────────────────────────────
        public Task<List<HotelSaleRow>> SalesAsync(string farmId, DateTime? from, DateTime? to) =>
            RowsAsync<HotelSaleRow>("SELECT * FROM sphotelsale_list(p_farmid => @f::text, p_from => @a::date, p_to => @b::date)",
                ("f", farmId), ("a", from?.Date), ("b", to?.Date));

        public async Task<int> BillToAccountAsync(string farmId, int bookingId, int customerId, string by) =>
            Convert.ToInt32(await ScalarAsync(
                "SELECT sphotelsale_billto(p_farmid => @f::text, p_bookingid => @b::int, p_customerid => @c::int, p_by => @by::text)",
                ("f", farmId), ("b", bookingId), ("c", customerId), ("by", by)));

        // ── Balances ─────────────────────────────────────────────────────────
        public Task<List<PartyBalanceRow>> BalancesAsync(string side, string farmId, DateTime? from, DateTime? to, int? partyId,
                                                         string? status, decimal? minBalance, string? search) =>
            RowsAsync<PartyBalanceRow>(
                $"SELECT * FROM {(Customer(side) ? "sphotelcustomerbalances" : "sphotelsupplierbalances")}(" +
                "@f::text, @a::date, @b::date, @p::int, @s::text, @m::numeric, @q::text)",
                ("f", farmId), ("a", from?.Date), ("b", to?.Date), ("p", partyId), ("s", status ?? "All"),
                ("m", minBalance), ("q", search));

        public async Task<BalanceSummary> SummaryAsync(string side, string farmId) =>
            (await RowsAsync<BalanceSummary>(
                $"SELECT * FROM {(Customer(side) ? "sphotelcustomerbalancesummary" : "sphotelsupplierbalancesummary")}(@f::text)",
                ("f", farmId))).FirstOrDefault() ?? new BalanceSummary();

        public Task<List<OpenDocumentRow>> OpenDocumentsAsync(string side, string farmId, int partyId, DateTime? from, DateTime? to, string? status) =>
            RowsAsync<OpenDocumentRow>(
                $"SELECT * FROM {(Customer(side) ? "sphotelcustomeropendocs" : "sphotelsupplieropenpurchases")}(" +
                "@f::text, @p::int, @a::date, @b::date, @s::text)",
                ("f", farmId), ("p", partyId), ("a", from?.Date), ("b", to?.Date), ("s", status ?? "All"));

        public async Task<string> RecordAsync(string side, RecordPaymentRequest r, string by)
        {
            var allocs = JsonSerializer.Serialize(r.Allocations.Select(a => new
            {
                documenttype = string.IsNullOrWhiteSpace(a.DocumentType) ? (Customer(side) ? "Stay" : null) : a.DocumentType,
                documentid = a.DocumentId != 0 ? a.DocumentId : a.SaleId,
                amount = a.Amount,
            }));
            var fn = Customer(side) ? "sphotelcustomerpayment_record" : "sphotelsupplierpayment_record";
            var res = await ScalarAsync(
                $"SELECT {fn}(@f::text, @p::int, @amt::numeric, @al::jsonb, @m::text, @d::timestamp, @ca::int, @ref::text, " +
                "@n::text, @src::text, @by::text)",
                ("f", r.FarmId), ("p", r.PartyId), ("amt", r.Amount), ("al", allocs), ("m", r.PaymentMethod),
                ("d", r.PaymentDate), ("ca", r.CashAccountId), ("ref", r.Reference), ("n", r.Notes),
                ("src", string.IsNullOrWhiteSpace(r.SourceType) ? (Customer(side) ? "CustomerBalances" : "SupplierBalances") : r.SourceType),
                ("by", by));
            return res?.ToString() ?? "";
        }

        public async Task<int> ReverseAsync(string side, string farmId, string paymentId, string? reason, string by)
        {
            object? res;
            if (Customer(side))
            {
                if (!Guid.TryParse(paymentId, out var g)) throw new ArgumentException("Payment not found for this company.");
                res = await ScalarAsync("SELECT sphotelcustomerpayment_reverse(@f::text, @g::uuid, @r::text, @by::text)",
                    ("f", farmId), ("g", g), ("r", reason), ("by", by));
            }
            else
            {
                if (!int.TryParse(paymentId, out var id)) throw new ArgumentException("Payment not found for this company.");
                res = await ScalarAsync("SELECT sphotelsupplierpayment_reverse(@f::text, @i::int, @r::text, @by::text)",
                    ("f", farmId), ("i", id), ("r", reason), ("by", by));
            }
            return Convert.ToInt32(res ?? 0);
        }

        public Task<List<PaymentHistoryRow>> HistoryAsync(string side, string farmId, int? partyId, string? documentType, int? documentId,
                                                          DateTime? from, DateTime? to) =>
            Customer(side)
                ? RowsAsync<PaymentHistoryRow>("SELECT * FROM sphotelcustomerpayment_history(@f::text, @p::int, @s::int, @a::date, @b::date)",
                    ("f", farmId), ("p", partyId), ("s", documentId), ("a", from?.Date), ("b", to?.Date))
                : RowsAsync<PaymentHistoryRow>("SELECT * FROM sphotelsupplierpayment_history(@f::text, @p::int, @t::text, @d::int, @a::date, @b::date)",
                    ("f", farmId), ("p", partyId), ("t", documentType), ("d", documentId), ("a", from?.Date), ("b", to?.Date));

        public Task<List<PaymentAllocationRow>> AllocationsAsync(string side, string farmId, string paymentId)
        {
            if (Customer(side))
                return Guid.TryParse(paymentId, out var g)
                    ? RowsAsync<PaymentAllocationRow>("SELECT * FROM sphotelcustomerpayment_allocations(@f::text, @g::uuid)", ("f", farmId), ("g", g))
                    : Task.FromResult(new List<PaymentAllocationRow>());
            return int.TryParse(paymentId, out var id)
                ? RowsAsync<PaymentAllocationRow>("SELECT * FROM sphotelsupplierpayment_allocations(@f::text, @i::int)", ("f", farmId), ("i", id))
                : Task.FromResult(new List<PaymentAllocationRow>());
        }

        public Task<List<StatementLine>> StatementAsync(string side, string farmId, int partyId, DateTime? from, DateTime? to) =>
            RowsAsync<StatementLine>(
                $"SELECT * FROM {(Customer(side) ? "sphotelcustomerstatement" : "sphotelsupplierstatement")}(@f::text, @p::int, @a::date, @b::date)",
                ("f", farmId), ("p", partyId), ("a", from?.Date), ("b", to?.Date));

        public Task<List<BalanceAuditRow>> AuditAsync(string farmId) =>
            RowsAsync<BalanceAuditRow>("SELECT * FROM sphotelbalanceaudit(@f::text)", ("f", farmId));
    }
}
