// =============================================================================
// Restaurant Capital Investments/Assets (migration 328).
//
// Every rule lives in the sprestaurant_capitalasset_* / _assetdepreciation_*
// functions, each one database transaction: a purchase's cost row and its
// ledger posting, a reversal's refund, a disposal's proceeds all commit together
// or not at all. This class only passes parameters and reads rows back by column
// NAME. Refusals (P0001) become a 400 through RestaurantBusinessRuleFilter.
// =============================================================================

using System.Reflection;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IRestaurantCapitalAssetService
    {
        Task<List<RestaurantAssetCategory>> CategoriesAsync(string farmId);
        Task<int> UpsertCategoryAsync(string farmId, RestaurantAssetCategoryRequest req, string by);
        Task<List<RestaurantCapitalAsset>> ListAsync(string farmId, string? status, int? categoryId);
        Task<RestaurantCapitalAsset?> GetAsync(string farmId, int assetId);
        Task<RestaurantCapitalAssetSummary> SummaryAsync(string farmId, DateTime? from, DateTime? to);
        Task<List<RestaurantCapitalAssetPayable>> PayablesAsync(string farmId);
        Task<int> CreateAsync(string farmId, RestaurantCapitalAssetCreateRequest req, string by);
        Task UpdateAsync(string farmId, int assetId, RestaurantCapitalAssetUpdateRequest req, string by);
        Task<int> AddCostAsync(string farmId, int assetId, RestaurantCapitalAssetCostRequest req, string by);
        Task<int> CorrectOriginalCostAsync(string farmId, int assetId, RestaurantCapitalAssetCorrectCostRequest req, string by);
        Task ReverseCostAsync(string farmId, int assetId, int costId, string? reason, string by);
        Task DisposeAsync(string farmId, int assetId, RestaurantCapitalAssetDisposeRequest req, string by);
        Task ReverseAsync(string farmId, int assetId, string? reason, string by);

        Task<List<RestaurantAssetDepreciation>> DepreciationAsync(string farmId, int? assetId, DateTime? from, DateTime? to);
        Task<List<RestaurantAssetDepreciationDue>> DueAsync(string farmId, DateTime? throughDate);
        Task<RestaurantAssetDepreciationRun> GenerateAsync(string farmId, RestaurantDepreciationGenerateRequest req, string by);
        Task ReverseDepreciationAsync(string farmId, int entryId, string? reason, string by);
        Task<int> AdjustDepreciationAsync(string farmId, RestaurantDepreciationAdjustRequest req, string by);
    }

    public class RestaurantCapitalAssetService : IRestaurantCapitalAssetService
    {
        private readonly string _cs;
        public RestaurantCapitalAssetService(string connectionString) { _cs = connectionString; }

        private static string? Blank(string? s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();

        // ── Categories ─────────────────────────────────────────────────────

        public Task<List<RestaurantAssetCategory>> CategoriesAsync(string farmId) =>
            QueryAsync<RestaurantAssetCategory>("SELECT * FROM sprestaurant_assetcategory_list(p_farmid => @f::text)", ("f", farmId));

        public Task<int> UpsertCategoryAsync(string farmId, RestaurantAssetCategoryRequest req, string by) =>
            ScalarIntAsync(
                "SELECT sprestaurant_assetcategory_upsert(p_farmid => @f::text, p_assetcategoryid => @id::int, " +
                "p_categoryname => @n::text, p_defaultusefullifemonths => @l::int, p_isactive => @a::boolean, p_createdby => @by::text)",
                ("f", farmId), ("id", req.AssetCategoryId), ("n", req.CategoryName), ("l", req.DefaultUsefulLifeMonths),
                ("a", req.IsActive ?? true), ("by", by));

        // ── Register ───────────────────────────────────────────────────────

        public Task<List<RestaurantCapitalAsset>> ListAsync(string farmId, string? status, int? categoryId) =>
            QueryAsync<RestaurantCapitalAsset>(
                "SELECT * FROM sprestaurant_capitalasset_list(p_farmid => @f::text, p_status => @s::text, p_categoryid => @c::int)",
                ("f", farmId), ("s", Blank(status)), ("c", categoryId));

        public async Task<RestaurantCapitalAsset?> GetAsync(string farmId, int assetId)
        {
            var asset = (await QueryAsync<RestaurantCapitalAsset>(
                "SELECT * FROM sprestaurant_capitalasset_list(p_farmid => @f::text, p_assetid => @a::int)",
                ("f", farmId), ("a", assetId))).FirstOrDefault();
            if (asset == null) return null;
            asset.Costs = await QueryAsync<RestaurantCapitalAssetCost>(
                "SELECT * FROM sprestaurant_capitalasset_costs(p_farmid => @f::text, p_assetid => @a::int)",
                ("f", farmId), ("a", assetId));
            asset.Depreciation = await DepreciationAsync(farmId, assetId, null, null);
            return asset;
        }

        public async Task<RestaurantCapitalAssetSummary> SummaryAsync(string farmId, DateTime? from, DateTime? to) =>
            (await QueryAsync<RestaurantCapitalAssetSummary>(
                "SELECT * FROM sprestaurant_capitalasset_summary(p_farmid => @f::text, p_from => @a::date, p_to => @b::date)",
                ("f", farmId), ("a", from?.Date), ("b", to?.Date))).FirstOrDefault() ?? new();

        public Task<List<RestaurantCapitalAssetPayable>> PayablesAsync(string farmId) =>
            QueryAsync<RestaurantCapitalAssetPayable>("SELECT * FROM sprestaurant_capitalasset_payables(p_farmid => @f::text)", ("f", farmId));

        public Task<int> CreateAsync(string farmId, RestaurantCapitalAssetCreateRequest req, string by) =>
            ScalarIntAsync(
                "SELECT sprestaurant_capitalasset_create(p_farmid => @f::text, p_assetname => @n::text, " +
                "p_assetcategoryid => @cat::int, p_description => @d::text, p_acquisitiondate => @acq::date, " +
                "p_inservicedate => @ins::date, p_amount => @amt::numeric, p_residualvalue => @res::numeric, " +
                "p_usefullifemonths => @life::int, p_suppliername => @sup::text, p_supplierid => @supid::int, " +
                "p_paymentmethod => @m::text, p_amountpaid => @paid::numeric, p_duedate => @due::date, " +
                "p_cashaccountid => @acc::int, p_location => @loc::text, p_serialnumber => @sn::text, " +
                "p_notes => @notes::text, p_createdby => @by::text)",
                ("f", farmId), ("n", req.AssetName), ("cat", req.AssetCategoryId), ("d", Blank(req.Description)),
                ("acq", req.AcquisitionDate?.Date), ("ins", req.InServiceDate?.Date), ("amt", req.Amount),
                ("res", req.ResidualValue ?? 0m), ("life", req.UsefulLifeMonths), ("sup", Blank(req.Supplier)),
                ("supid", req.SupplierId), ("m", Blank(req.PaymentMethod) ?? "Cash"), ("paid", req.AmountPaid),
                ("due", req.DueDate?.Date), ("acc", req.CashAccountId), ("loc", Blank(req.Location)),
                ("sn", Blank(req.SerialNumber)), ("notes", Blank(req.Notes)), ("by", by));

        public Task UpdateAsync(string farmId, int assetId, RestaurantCapitalAssetUpdateRequest req, string by) =>
            ExecAsync(
                "SELECT sprestaurant_capitalasset_update(p_farmid => @f::text, p_assetid => @a::int, p_assetname => @n::text, " +
                "p_assetcategoryid => @cat::int, p_description => @d::text, p_location => @loc::text, " +
                "p_serialnumber => @sn::text, p_notes => @notes::text, p_inservicedate => @ins::date, " +
                "p_usefullifemonths => @life::int, p_residualvalue => @res::numeric, p_setfinancials => @set::boolean, " +
                "p_updatedby => @by::text)",
                ("f", farmId), ("a", assetId), ("n", Blank(req.AssetName)), ("cat", req.AssetCategoryId),
                ("d", Blank(req.Description)), ("loc", Blank(req.Location)), ("sn", Blank(req.SerialNumber)),
                ("notes", Blank(req.Notes)), ("ins", req.InServiceDate?.Date), ("life", req.UsefulLifeMonths),
                ("res", req.ResidualValue), ("set", req.SetFinancials), ("by", by));

        public Task<int> AddCostAsync(string farmId, int assetId, RestaurantCapitalAssetCostRequest req, string by) =>
            ScalarIntAsync(
                "SELECT sprestaurant_capitalasset_addcost(p_farmid => @f::text, p_assetid => @a::int, p_costdate => @dt::date, " +
                "p_description => @d::text, p_costcategory => @cc::text, p_amount => @amt::numeric, " +
                "p_suppliername => @sup::text, p_supplierid => @supid::int, p_paymentmethod => @m::text, " +
                "p_amountpaid => @paid::numeric, p_duedate => @due::date, p_cashaccountid => @acc::int, p_createdby => @by::text)",
                ("f", farmId), ("a", assetId), ("dt", req.CostDate?.Date), ("d", Blank(req.Description)),
                ("cc", Blank(req.CostCategory)), ("amt", req.Amount), ("sup", Blank(req.Supplier)), ("supid", req.SupplierId),
                ("m", Blank(req.PaymentMethod) ?? "Cash"), ("paid", req.AmountPaid), ("due", req.DueDate?.Date),
                ("acc", req.CashAccountId), ("by", by));

        public Task<int> CorrectOriginalCostAsync(string farmId, int assetId, RestaurantCapitalAssetCorrectCostRequest req, string by) =>
            ScalarIntAsync(
                "SELECT sprestaurant_capitalasset_correctoriginalcost(p_farmid => @f::text, p_assetid => @a::int, " +
                "p_newamount => @amt::numeric, p_effectivedate => @dt::date, p_reason => @r::text, p_createdby => @by::text)",
                ("f", farmId), ("a", assetId), ("amt", req.NewAmount), ("dt", req.EffectiveDate?.Date),
                ("r", Blank(req.Reason)), ("by", by));

        public Task ReverseCostAsync(string farmId, int assetId, int costId, string? reason, string by) =>
            ExecAsync(
                "SELECT sprestaurant_capitalasset_cost_reverse(p_farmid => @f::text, p_costid => @c::int, p_reason => @r::text, " +
                "p_createdby => @by::text, p_assetid => @a::int)",
                ("f", farmId), ("c", costId), ("r", Blank(reason)), ("by", by), ("a", assetId));

        public Task DisposeAsync(string farmId, int assetId, RestaurantCapitalAssetDisposeRequest req, string by) =>
            ExecAsync(
                "SELECT sprestaurant_capitalasset_dispose(p_farmid => @f::text, p_assetid => @a::int, p_disposaldate => @dt::date, " +
                "p_proceeds => @p::numeric, p_cashaccountid => @acc::int, p_notes => @n::text, p_createdby => @by::text)",
                ("f", farmId), ("a", assetId), ("dt", req.DisposalDate?.Date), ("p", req.Proceeds),
                ("acc", req.CashAccountId), ("n", Blank(req.Notes)), ("by", by));

        public Task ReverseAsync(string farmId, int assetId, string? reason, string by) =>
            ExecAsync(
                "SELECT sprestaurant_capitalasset_reverse(p_farmid => @f::text, p_assetid => @a::int, p_reason => @r::text, p_createdby => @by::text)",
                ("f", farmId), ("a", assetId), ("r", Blank(reason)), ("by", by));

        // ── Depreciation ───────────────────────────────────────────────────

        public Task<List<RestaurantAssetDepreciation>> DepreciationAsync(string farmId, int? assetId, DateTime? from, DateTime? to) =>
            QueryAsync<RestaurantAssetDepreciation>(
                "SELECT * FROM sprestaurant_assetdepreciation_list(p_farmid => @f::text, p_assetid => @a::int, " +
                "p_from => @x::date, p_to => @y::date)",
                ("f", farmId), ("a", assetId), ("x", from?.Date), ("y", to?.Date));

        public Task<List<RestaurantAssetDepreciationDue>> DueAsync(string farmId, DateTime? throughDate) =>
            QueryAsync<RestaurantAssetDepreciationDue>(
                "SELECT * FROM sprestaurant_assetdepreciation_due(p_farmid => @f::text, p_throughdate => @t::date)",
                ("f", farmId), ("t", throughDate?.Date));

        public async Task<RestaurantAssetDepreciationRun> GenerateAsync(string farmId, RestaurantDepreciationGenerateRequest req, string by) =>
            (await QueryAsync<RestaurantAssetDepreciationRun>(
                "SELECT * FROM sprestaurant_assetdepreciation_generate(p_farmid => @f::text, p_throughdate => @t::date, " +
                "p_assetid => @a::int, p_createdby => @by::text)",
                ("f", farmId), ("t", req.ThroughDate?.Date), ("a", req.AssetId), ("by", by))).FirstOrDefault() ?? new();

        public Task ReverseDepreciationAsync(string farmId, int entryId, string? reason, string by) =>
            ExecAsync(
                "SELECT sprestaurant_assetdepreciation_reverse(p_farmid => @f::text, p_entryid => @e::int, p_reason => @r::text, p_createdby => @by::text)",
                ("f", farmId), ("e", entryId), ("r", Blank(reason)), ("by", by));

        public Task<int> AdjustDepreciationAsync(string farmId, RestaurantDepreciationAdjustRequest req, string by) =>
            ScalarIntAsync(
                "SELECT sprestaurant_assetdepreciation_adjust(p_farmid => @f::text, p_assetid => @a::int, " +
                "p_periodstart => @p::date, p_amount => @amt::numeric, p_reason => @r::text, p_createdby => @by::text)",
                ("f", farmId), ("a", req.AssetId), ("p", req.PeriodStart.Date), ("amt", req.Amount),
                ("r", Blank(req.Reason)), ("by", by));

        // ── Plumbing (same as RestaurantPayrollService) ───────────────────

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

        private async Task<List<T>> QueryAsync<T>(string sql, params (string, object?)[] ps) where T : new()
        {
            await using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            await using var cmd = Command(conn, sql, ps);
            await using var r = await cmd.ExecuteReaderAsync();
            var props = typeof(T).GetProperties(BindingFlags.Public | BindingFlags.Instance)
                .Where(p => p.CanWrite)
                .ToDictionary(p => p.Name, StringComparer.OrdinalIgnoreCase);
            var map = new List<(int ordinal, PropertyInfo prop)>();
            for (var i = 0; i < r.FieldCount; i++)
                if (props.TryGetValue(r.GetName(i), out var p)) map.Add((i, p));
            var list = new List<T>();
            while (await r.ReadAsync())
            {
                var item = new T();
                foreach (var (i, p) in map)
                {
                    if (r.IsDBNull(i)) continue;
                    p.SetValue(item, ConvertTo(r.GetValue(i), p.PropertyType));
                }
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
