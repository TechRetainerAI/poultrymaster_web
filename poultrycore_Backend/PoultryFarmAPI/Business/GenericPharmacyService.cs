// Generic Pharmacy (migration 511). Thin: every rule (class A/B/C, pack sizes, batch
// quantities, first-expiry-first-out, write-off limits, prescription checks) is in the
// SQL functions. The list functions return JSON built in SQL, which is passed straight
// through, so the C# layer has no row mapping to keep in step with the SQL.

using System.Text.Json;
using Npgsql;
using NpgsqlTypes;

namespace PoultryFarmAPIWeb.Business
{
    public interface IGenericPharmacyService
    {
        Task<string> GetSettingsAsync(string farmId);
        Task SaveSettingsAsync(string farmId, string shopType, bool requirePrescriptionClassA, int expiryWarningDays, string? by);
        Task<string> GetMedicinesAsync(string farmId);
        Task SaveMedicineAsync(string farmId, int productId, JsonElement data, string? by);
        Task<string> GetBatchesAsync(string farmId, int? productId);
        Task<int> AddBatchAsync(string farmId, int productId, string? batchNumber, DateTime? expiryDate, decimal quantity,
                                decimal? unitCost, DateTime? receivedDate, string? notes, string? by);
        Task UpdateBatchAsync(string farmId, int batchId, string? batchNumber, DateTime? expiryDate, string? notes);
        Task DeleteBatchAsync(string farmId, int batchId);
        Task<int> WriteOffBatchAsync(string farmId, int batchId, decimal quantity, string? reason, string? by);
        Task<string> GetPurchaseBatchesAsync(string farmId, int purchaseId);
        Task SetPurchaseBatchesAsync(string farmId, int purchaseId, JsonElement lines);
        Task<string> GetPrescriptionsAsync(string farmId, DateTime? from, DateTime? to);
        Task<int> CreatePrescriptionAsync(string farmId, JsonElement data, string? by);
        Task<string> GetReportAsync(string farmId, DateTime from, DateTime to, int expiryDays);
    }

    public class GenericPharmacyService : IGenericPharmacyService
    {
        private readonly string _cs;
        public GenericPharmacyService(string cs) => _cs = cs;

        private static object Db(object? v) => v ?? DBNull.Value;
        private static object DbDate(DateTime? v) => v.HasValue ? v.Value.Date : DBNull.Value;

        private async Task<object?> ScalarAsync(string sql, params (string name, object value, NpgsqlDbType? type)[] ps)
        {
            await using var c = new NpgsqlConnection(_cs);
            await using var cmd = new NpgsqlCommand(sql, c);
            foreach (var (name, value, type) in ps)
            {
                if (type.HasValue) cmd.Parameters.Add(new NpgsqlParameter(name, type.Value) { Value = value });
                else cmd.Parameters.AddWithValue(name, value);
            }
            await c.OpenAsync();
            return await cmd.ExecuteScalarAsync();
        }

        private async Task<string> JsonAsync(string sql, params (string, object, NpgsqlDbType?)[] ps)
        {
            var v = await ScalarAsync(sql, ps);
            return v is null || v is DBNull ? "[]" : v.ToString()!;
        }

        private static (string, object, NpgsqlDbType?) P(string n, object? v, NpgsqlDbType? t = null) => (n, Db(v), t);

        public Task<string> GetSettingsAsync(string farmId) =>
            JsonAsync("SELECT spgenericpharmacy_settings_get(@f::text)", P("f", farmId));

        public async Task SaveSettingsAsync(string farmId, string shopType, bool requirePrescriptionClassA, int expiryWarningDays, string? by) =>
            await ScalarAsync("SELECT spgenericpharmacy_settings_save(@f::text, @t::text, @r::boolean, @d::int, @b::text)",
                P("f", farmId), P("t", shopType), P("r", requirePrescriptionClassA), P("d", expiryWarningDays), P("b", by));

        public Task<string> GetMedicinesAsync(string farmId) =>
            JsonAsync("SELECT spgenericmedicine_list(@f::text)", P("f", farmId));

        public async Task SaveMedicineAsync(string farmId, int productId, JsonElement data, string? by) =>
            await ScalarAsync("SELECT spgenericmedicine_save(@f::text, @p::int, @d, @b::text)",
                P("f", farmId), P("p", productId), P("d", data.GetRawText(), NpgsqlDbType.Jsonb), P("b", by));

        public Task<string> GetBatchesAsync(string farmId, int? productId) =>
            JsonAsync("SELECT spgenericproductbatch_list(@f::text, @p::int)", P("f", farmId), P("p", productId));

        public async Task<int> AddBatchAsync(string farmId, int productId, string? batchNumber, DateTime? expiryDate, decimal quantity,
                                             decimal? unitCost, DateTime? receivedDate, string? notes, string? by) =>
            Convert.ToInt32(await ScalarAsync(
                "SELECT spgenericproductbatch_add(@f::text, @p::int, @n::text, @e::date, @q::numeric, @c::numeric, @r::date, @x::text, @b::text)",
                P("f", farmId), P("p", productId), P("n", batchNumber), ("e", DbDate(expiryDate), null), P("q", quantity),
                P("c", unitCost), ("r", DbDate(receivedDate), null), P("x", notes), P("b", by)));

        public async Task UpdateBatchAsync(string farmId, int batchId, string? batchNumber, DateTime? expiryDate, string? notes) =>
            await ScalarAsync("SELECT spgenericproductbatch_update(@f::text, @i::int, @n::text, @e::date, @x::text)",
                P("f", farmId), P("i", batchId), P("n", batchNumber), ("e", DbDate(expiryDate), null), P("x", notes));

        public async Task DeleteBatchAsync(string farmId, int batchId) =>
            await ScalarAsync("SELECT spgenericproductbatch_delete(@f::text, @i::int)", P("f", farmId), P("i", batchId));

        public async Task<int> WriteOffBatchAsync(string farmId, int batchId, decimal quantity, string? reason, string? by) =>
            Convert.ToInt32(await ScalarAsync("SELECT spgenericproductbatch_writeoff(@f::text, @i::int, @q::numeric, @r::text, @b::text)",
                P("f", farmId), P("i", batchId), P("q", quantity), P("r", reason), P("b", by)));

        public Task<string> GetPurchaseBatchesAsync(string farmId, int purchaseId) =>
            JsonAsync("SELECT spgenericpurchase_getbatches(@f::text, @i::int)", P("f", farmId), P("i", purchaseId));

        public async Task SetPurchaseBatchesAsync(string farmId, int purchaseId, JsonElement lines) =>
            await ScalarAsync("SELECT spgenericpurchase_setbatches(@f::text, @i::int, @l)",
                P("f", farmId), P("i", purchaseId), P("l", lines.GetRawText(), NpgsqlDbType.Jsonb));

        public Task<string> GetPrescriptionsAsync(string farmId, DateTime? from, DateTime? to) =>
            JsonAsync("SELECT spgenericprescription_list(@f::text, @a::date, @z::date)",
                P("f", farmId), ("a", DbDate(from), null), ("z", DbDate(to), null));

        public async Task<int> CreatePrescriptionAsync(string farmId, JsonElement data, string? by) =>
            Convert.ToInt32(await ScalarAsync("SELECT spgenericprescription_create(@f::text, @d, @b::text)",
                P("f", farmId), P("d", data.GetRawText(), NpgsqlDbType.Jsonb), P("b", by)));

        public Task<string> GetReportAsync(string farmId, DateTime from, DateTime to, int expiryDays) =>
            JsonAsync("SELECT spgenericpharmacy_report(@f::text, @a::date, @z::date, @d::int)",
                P("f", farmId), ("a", from.Date, null), ("z", to.Date, null), P("d", expiryDays));
    }
}
