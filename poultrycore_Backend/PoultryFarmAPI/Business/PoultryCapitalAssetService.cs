// Poultry capital assets and depreciation (migrations 270, 271).
//
// Thin, like every other service here: it sends parameters and maps rows.
// Everything that decides what an asset costs, what it is worth, whether it can
// be reversed and how much depreciation is due lives in the stored procedures,
// so there is exactly one definition of each and this file cannot drift from it.
//
// In particular NOTHING here computes book value. fnpoultrycapitalasset_financials
// does, once, and the register, the detail page and the depreciation engine all
// read that same function.

using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IPoultryCapitalAssetService
    {
        Task<List<PoultryAssetCategoryModel>> GetCategoriesAsync(string farmId);
        Task<int> UpsertCategoryAsync(string farmId, PoultryAssetCategoryModel m, string? userId);

        Task<List<PoultryCapitalAssetModel>> GetAllAsync(string farmId, string? status, int? categoryId);
        /// <summary>Header, capitalised costs and depreciation history in one round trip.</summary>
        Task<PoultryCapitalAssetModel?> GetByIdAsync(string farmId, int id);
        Task<PoultryCapitalAssetSummaryModel> GetSummaryAsync(string farmId, DateTime? from, DateTime? to);

        Task<int> CreateAsync(PoultryCapitalAssetCreateRequest r);
        Task UpdateAsync(int id, PoultryCapitalAssetUpdateRequest r);
        Task<int> AddCostAsync(int assetId, PoultryCapitalAssetCostRequest r);
        Task DisposeAsync(int id, PoultryCapitalAssetDisposeRequest r);
        Task ReverseAsync(int id, PoultryReversalRequest r);

        Task<List<PoultryAssetDepreciationModel>> GetDepreciationAsync(string farmId, int? assetId, DateTime? from, DateTime? to);
        Task<List<PoultryAssetDepreciationDueModel>> GetDueAsync(string farmId, DateTime? throughDate);
        Task<PoultryAssetDepreciationRunResult> GenerateDepreciationAsync(PoultryDepreciationGenerateRequest r);
        Task ReverseDepreciationAsync(int entryId, PoultryReversalRequest r);
        Task<int> AdjustDepreciationAsync(PoultryDepreciationAdjustRequest r);
    }

    public class PoultryCapitalAssetService : IPoultryCapitalAssetService
    {
        private readonly string _cs;
        public PoultryCapitalAssetService(string cs) => _cs = cs;

        // ---- reader helpers -------------------------------------------------
        private static string? StrN(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? null : r.GetString(i); }
        private static string Str(NpgsqlDataReader r, string c) => StrN(r, c) ?? string.Empty;
        private static int Int(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? 0 : r.GetInt32(i); }
        private static int? IntN(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? (int?)null : r.GetInt32(i); }
        private static decimal Dec(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? 0m : r.GetDecimal(i); }
        private static decimal? DecN(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? (decimal?)null : r.GetDecimal(i); }
        private static DateTime? DateN(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? (DateTime?)null : r.GetDateTime(i); }
        private static DateTime Date(NpgsqlDataReader r, string c) => DateN(r, c) ?? default;
        private static bool Bool(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return !r.IsDBNull(i) && r.GetBoolean(i); }

        private static object N(object? v) => v ?? DBNull.Value;

        // ---- categories -----------------------------------------------------

        public async Task<List<PoultryAssetCategoryModel>> GetCategoriesAsync(string farmId)
        {
            var list = new List<PoultryAssetCategoryModel>();
            using var conn = new NpgsqlConnection(_cs);
            // The SP seeds the thirteen defaults on first read and is idempotent,
            // so a farm never has to be told to "set up asset categories".
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryassetcategory_getall(p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                list.Add(new PoultryAssetCategoryModel
                {
                    PoultryAssetCategoryId = Int(r, "PoultryAssetCategoryId"),
                    FarmId = StrN(r, "FarmId"),
                    CategoryName = Str(r, "CategoryName"),
                    DefaultUsefulLifeMonths = IntN(r, "DefaultUsefulLifeMonths"),
                    SortOrder = Int(r, "SortOrder"),
                    IsActive = Bool(r, "IsActive"),
                    AssetCount = Int(r, "AssetCount"),
                });
            }
            return list;
        }

        public async Task<int> UpsertCategoryAsync(string farmId, PoultryAssetCategoryModel m, string? userId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryassetcategory_upsert(p_farmid => @FarmId::text, " +
                "p_poultryassetcategoryid => @Id::int, p_categoryname => @Name::text, " +
                "p_defaultusefullifemonths => @Life::int, p_isactive => @IsActive::boolean, " +
                "p_createdby => @By::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Id", m.PoultryAssetCategoryId > 0 ? m.PoultryAssetCategoryId : (object)DBNull.Value);
            cmd.Parameters.AddWithValue("@Name", m.CategoryName);
            cmd.Parameters.AddWithValue("@Life", N(m.DefaultUsefulLifeMonths));
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            cmd.Parameters.AddWithValue("@By", N(userId));
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        // ---- assets ---------------------------------------------------------

        private static PoultryCapitalAssetModel MapAsset(NpgsqlDataReader r) => new()
        {
            PoultryCapitalAssetId = Int(r, "PoultryCapitalAssetId"),
            FarmId = StrN(r, "FarmId"),
            AssetNumber = StrN(r, "AssetNumber"),
            AssetName = Str(r, "AssetName"),
            PoultryAssetCategoryId = IntN(r, "PoultryAssetCategoryId"),
            CategoryName = StrN(r, "CategoryName"),
            Description = StrN(r, "Description"),
            AcquisitionDate = Date(r, "AcquisitionDate"),
            InServiceDate = DateN(r, "InServiceDate"),
            Location = StrN(r, "Location"),
            SerialNumber = StrN(r, "SerialNumber"),
            SupplierId = IntN(r, "SupplierId"),
            SupplierName = StrN(r, "SupplierName"),
            Status = Str(r, "Status"),
            Notes = StrN(r, "Notes"),
            OriginalCost = Dec(r, "OriginalCost"),
            ResidualValue = Dec(r, "ResidualValue"),
            DepreciableAmount = Dec(r, "DepreciableAmount"),
            UsefulLifeMonths = IntN(r, "UsefulLifeMonths"),
            MonthlyDepreciation = DecN(r, "MonthlyDepreciation"),
            AccumulatedDepreciation = Dec(r, "AccumulatedDepreciation"),
            CurrentBookValue = Dec(r, "CurrentBookValue"),
            RemainingDepreciable = Dec(r, "RemainingDepreciable"),
            IsFullyDepreciated = Bool(r, "IsFullyDepreciated"),
            CostEntries = Int(r, "CostEntries"),
            DepreciationEntries = Int(r, "DepreciationEntries"),
            DisposalDate = DateN(r, "DisposalDate"),
            DisposalProceeds = DecN(r, "DisposalProceeds"),
            CreatedBy = StrN(r, "CreatedBy"),
            CreatedAt = DateN(r, "CreatedAt"),
            UpdatedAt = DateN(r, "UpdatedAt"),
            ReversedBy = StrN(r, "ReversedBy"),
            ReversedAt = DateN(r, "ReversedAt"),
            ReversalReason = StrN(r, "ReversalReason"),
        };

        private static PoultryCapitalAssetCostModel MapCost(NpgsqlDataReader r) => new()
        {
            PoultryCapitalAssetCostId = Int(r, "PoultryCapitalAssetCostId"),
            PoultryCapitalAssetId = Int(r, "PoultryCapitalAssetId"),
            CostDate = Date(r, "CostDate"),
            Description = StrN(r, "Description"),
            CostCategory = StrN(r, "CostCategory"),
            Amount = Dec(r, "Amount"),
            SourceType = StrN(r, "SourceType"),
            ExpenseId = IntN(r, "ExpenseId"),
            SupplierId = IntN(r, "SupplierId"),
            SupplierName = StrN(r, "SupplierName"),
            PaymentStatus = StrN(r, "PaymentStatus"),
            AmountPaid = DecN(r, "AmountPaid"),
            Balance = DecN(r, "Balance"),
            Status = Str(r, "Status"),
            CreatedBy = StrN(r, "CreatedBy"),
            CreatedAt = DateN(r, "CreatedAt"),
            ReversedBy = StrN(r, "ReversedBy"),
            ReversedAt = DateN(r, "ReversedAt"),
            ReversalReason = StrN(r, "ReversalReason"),
        };

        private static PoultryAssetDepreciationModel MapDep(NpgsqlDataReader r) => new()
        {
            PoultryAssetDepreciationId = Int(r, "PoultryAssetDepreciationId"),
            PoultryCapitalAssetId = Int(r, "PoultryCapitalAssetId"),
            AssetNumber = StrN(r, "AssetNumber"),
            AssetName = StrN(r, "AssetName"),
            CategoryName = StrN(r, "CategoryName"),
            PeriodStart = Date(r, "PeriodStart"),
            PeriodEnd = Date(r, "PeriodEnd"),
            DepreciationDate = DateN(r, "DepreciationDate"),
            Amount = Dec(r, "Amount"),
            DepreciationMethod = StrN(r, "DepreciationMethod"),
            SourceType = StrN(r, "SourceType"),
            Status = StrN(r, "Status"),
            ExpenseId = IntN(r, "ExpenseId"),
            ReversalOfId = IntN(r, "ReversalOfId"),
            OriginalCost = DecN(r, "OriginalCost"),
            MonthlyDepreciation = DecN(r, "MonthlyDepreciation"),
            AccumulatedAfter = DecN(r, "AccumulatedAfter"),
            BookValueAfter = DecN(r, "BookValueAfter"),
            CreatedBy = StrN(r, "CreatedBy"),
            CreatedAt = DateN(r, "CreatedAt"),
            ReversedBy = StrN(r, "ReversedBy"),
            ReversedAt = DateN(r, "ReversedAt"),
            ReversalReason = StrN(r, "ReversalReason"),
        };

        public async Task<List<PoultryCapitalAssetModel>> GetAllAsync(string farmId, string? status, int? categoryId)
        {
            var list = new List<PoultryCapitalAssetModel>();
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultrycapitalasset_getall(p_farmid => @FarmId::text, " +
                "p_status => @Status::text, p_categoryid => @CategoryId::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status", N(string.IsNullOrWhiteSpace(status) ? null : status));
            cmd.Parameters.AddWithValue("@CategoryId", N(categoryId));
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(MapAsset(r));
            return list;
        }

        public async Task<PoultryCapitalAssetModel?> GetByIdAsync(string farmId, int id)
        {
            using var conn = new NpgsqlConnection(_cs);
            // One batch: a detail page that fetched three times could show a
            // header and a cost list that disagree, if a cost landed between them.
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultrycapitalasset_getall(p_farmid => @FarmId::text, p_status => NULL, p_categoryid => NULL) g " +
                "WHERE g.poultrycapitalassetid = @Id::int; " +
                "SELECT * FROM sppoultrycapitalassetcost_getall(p_farmid => @FarmId::text, p_assetid => @Id::int); " +
                "SELECT * FROM sppoultryassetdepreciation_getall(p_farmid => @FarmId::text, p_assetid => @Id::int, " +
                "p_fromdate => NULL, p_todate => NULL)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Id", id);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();

            PoultryCapitalAssetModel? asset = null;
            if (await r.ReadAsync()) asset = MapAsset(r);
            if (asset == null) return null;
            if (await r.NextResultAsync())
                while (await r.ReadAsync()) asset.Costs.Add(MapCost(r));
            if (await r.NextResultAsync())
                while (await r.ReadAsync()) asset.Depreciation.Add(MapDep(r));
            return asset;
        }

        public async Task<PoultryCapitalAssetSummaryModel> GetSummaryAsync(string farmId, DateTime? from, DateTime? to)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultrycapitalasset_summary(p_farmid => @FarmId::text, " +
                "p_fromdate => @From::date, p_todate => @To::date)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@From", N(from?.Date));
            cmd.Parameters.AddWithValue("@To", N(to?.Date));
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            if (!await r.ReadAsync()) return new PoultryCapitalAssetSummaryModel();
            return new PoultryCapitalAssetSummaryModel
            {
                TotalAssets = Int(r, "TotalAssets"),
                ActiveAssets = Int(r, "ActiveAssets"),
                DraftAssets = Int(r, "DraftAssets"),
                DisposedAssets = Int(r, "DisposedAssets"),
                FullyDepreciated = Int(r, "FullyDepreciated"),
                TotalAssetCost = Dec(r, "TotalAssetCost"),
                AccumulatedDepreciation = Dec(r, "AccumulatedDepreciation"),
                CurrentBookValue = Dec(r, "CurrentBookValue"),
                AddedInPeriod = Dec(r, "AddedInPeriod"),
                AddedCount = Int(r, "AddedCount"),
            };
        }

        public async Task<int> CreateAsync(PoultryCapitalAssetCreateRequest q)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultrycapitalasset_create(p_farmid => @FarmId::text, " +
                "p_assetname => @Name::text, p_assetcategoryid => @CategoryId::int, " +
                "p_description => @Description::text, p_acquisitiondate => @AcqDate::date, " +
                "p_inservicedate => @InService::date, p_amount => @Amount::numeric, " +
                "p_residualvalue => @Residual::numeric, p_usefullifemonths => @Life::int, " +
                "p_supplier => @Supplier::text, p_supplierid => @SupplierId::int, " +
                "p_paymentmethod => @PaymentMethod::text, p_amountpaid => @AmountPaid::numeric, " +
                "p_duedate => @DueDate::date, p_cashaccountid => @CashAccountId::int, " +
                "p_expensecategory => @ExpenseCategory::text, p_location => @Location::text, " +
                "p_serialnumber => @Serial::text, p_notes => @Notes::text, p_createdby => @By::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", q.FarmId ?? string.Empty);
            cmd.Parameters.AddWithValue("@Name", q.AssetName);
            cmd.Parameters.AddWithValue("@CategoryId", N(q.AssetCategoryId));
            cmd.Parameters.AddWithValue("@Description", N(q.Description));
            cmd.Parameters.AddWithValue("@AcqDate", N(q.AcquisitionDate?.Date));
            cmd.Parameters.AddWithValue("@InService", N(q.InServiceDate?.Date));
            cmd.Parameters.AddWithValue("@Amount", N(q.Amount));
            cmd.Parameters.AddWithValue("@Residual", q.ResidualValue ?? 0m);
            cmd.Parameters.AddWithValue("@Life", N(q.UsefulLifeMonths));
            cmd.Parameters.AddWithValue("@Supplier", N(q.Supplier));
            cmd.Parameters.AddWithValue("@SupplierId", N(q.SupplierId));
            cmd.Parameters.AddWithValue("@PaymentMethod", N(q.PaymentMethod ?? "Cash"));
            cmd.Parameters.AddWithValue("@AmountPaid", N(q.AmountPaid));
            cmd.Parameters.AddWithValue("@DueDate", N(q.DueDate?.Date));
            cmd.Parameters.AddWithValue("@CashAccountId", N(q.CashAccountId));
            cmd.Parameters.AddWithValue("@ExpenseCategory", N(q.ExpenseCategory));
            cmd.Parameters.AddWithValue("@Location", N(q.Location));
            cmd.Parameters.AddWithValue("@Serial", N(q.SerialNumber));
            cmd.Parameters.AddWithValue("@Notes", N(q.Notes));
            cmd.Parameters.AddWithValue("@By", N(q.CreatedBy));
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateAsync(int id, PoultryCapitalAssetUpdateRequest q)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultrycapitalasset_update(p_farmid => @FarmId::text, p_assetid => @Id::int, " +
                "p_assetname => @Name::text, p_assetcategoryid => @CategoryId::int, " +
                "p_description => @Description::text, p_location => @Location::text, " +
                "p_serialnumber => @Serial::text, p_notes => @Notes::text, " +
                "p_inservicedate => @InService::date, p_usefullifemonths => @Life::int, " +
                "p_residualvalue => @Residual::numeric, p_setfinancials => @SetFinancials::boolean, " +
                "p_updatedby => @By::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", q.FarmId ?? string.Empty);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@Name", N(q.AssetName));
            cmd.Parameters.AddWithValue("@CategoryId", N(q.AssetCategoryId));
            cmd.Parameters.AddWithValue("@Description", N(q.Description));
            cmd.Parameters.AddWithValue("@Location", N(q.Location));
            cmd.Parameters.AddWithValue("@Serial", N(q.SerialNumber));
            cmd.Parameters.AddWithValue("@Notes", N(q.Notes));
            cmd.Parameters.AddWithValue("@InService", N(q.InServiceDate?.Date));
            cmd.Parameters.AddWithValue("@Life", N(q.UsefulLifeMonths));
            cmd.Parameters.AddWithValue("@Residual", N(q.ResidualValue));
            cmd.Parameters.AddWithValue("@SetFinancials", q.SetFinancials);
            cmd.Parameters.AddWithValue("@By", N(q.UpdatedBy));
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<int> AddCostAsync(int assetId, PoultryCapitalAssetCostRequest q)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultrycapitalassetcost_add(p_farmid => @FarmId::text, p_assetid => @Id::int, " +
                "p_costdate => @CostDate::date, p_description => @Description::text, " +
                "p_costcategory => @CostCategory::text, p_amount => @Amount::numeric, " +
                "p_supplier => @Supplier::text, p_supplierid => @SupplierId::int, " +
                "p_paymentmethod => @PaymentMethod::text, p_amountpaid => @AmountPaid::numeric, " +
                "p_duedate => @DueDate::date, p_cashaccountid => @CashAccountId::int, " +
                "p_expensecategory => @ExpenseCategory::text, p_createdby => @By::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", q.FarmId ?? string.Empty);
            cmd.Parameters.AddWithValue("@Id", assetId);
            cmd.Parameters.AddWithValue("@CostDate", N(q.CostDate?.Date));
            cmd.Parameters.AddWithValue("@Description", N(q.Description));
            cmd.Parameters.AddWithValue("@CostCategory", N(q.CostCategory));
            cmd.Parameters.AddWithValue("@Amount", q.Amount);
            cmd.Parameters.AddWithValue("@Supplier", N(q.Supplier));
            cmd.Parameters.AddWithValue("@SupplierId", N(q.SupplierId));
            cmd.Parameters.AddWithValue("@PaymentMethod", N(q.PaymentMethod ?? "Cash"));
            cmd.Parameters.AddWithValue("@AmountPaid", N(q.AmountPaid));
            cmd.Parameters.AddWithValue("@DueDate", N(q.DueDate?.Date));
            cmd.Parameters.AddWithValue("@CashAccountId", N(q.CashAccountId));
            cmd.Parameters.AddWithValue("@ExpenseCategory", N(q.ExpenseCategory));
            cmd.Parameters.AddWithValue("@By", N(q.CreatedBy));
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task DisposeAsync(int id, PoultryCapitalAssetDisposeRequest q)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultrycapitalasset_dispose(p_farmid => @FarmId::text, p_assetid => @Id::int, " +
                "p_disposaldate => @Date::date, p_proceeds => @Proceeds::numeric, " +
                "p_cashaccountid => @CashAccountId::int, p_notes => @Notes::text, p_createdby => @By::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", q.FarmId ?? string.Empty);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@Date", N(q.DisposalDate?.Date));
            cmd.Parameters.AddWithValue("@Proceeds", N(q.Proceeds));
            cmd.Parameters.AddWithValue("@CashAccountId", N(q.CashAccountId));
            cmd.Parameters.AddWithValue("@Notes", N(q.Notes));
            cmd.Parameters.AddWithValue("@By", N(q.CreatedBy));
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task ReverseAsync(int id, PoultryReversalRequest q)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultrycapitalasset_reverse(p_farmid => @FarmId::text, p_assetid => @Id::int, " +
                "p_reason => @Reason::text, p_createdby => @By::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", q.FarmId ?? string.Empty);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@Reason", q.Reason);
            cmd.Parameters.AddWithValue("@By", N(q.CreatedBy));
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // ---- depreciation ---------------------------------------------------

        public async Task<List<PoultryAssetDepreciationModel>> GetDepreciationAsync(
            string farmId, int? assetId, DateTime? from, DateTime? to)
        {
            var list = new List<PoultryAssetDepreciationModel>();
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryassetdepreciation_getall(p_farmid => @FarmId::text, " +
                "p_assetid => @AssetId::int, p_fromdate => @From::date, p_todate => @To::date)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@AssetId", N(assetId));
            cmd.Parameters.AddWithValue("@From", N(from?.Date));
            cmd.Parameters.AddWithValue("@To", N(to?.Date));
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(MapDep(r));
            return list;
        }

        public async Task<List<PoultryAssetDepreciationDueModel>> GetDueAsync(string farmId, DateTime? throughDate)
        {
            var list = new List<PoultryAssetDepreciationDueModel>();
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryassetdepreciation_due(p_farmid => @FarmId::text, " +
                "p_throughdate => @Through::date)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Through", N(throughDate?.Date));
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                list.Add(new PoultryAssetDepreciationDueModel
                {
                    PoultryCapitalAssetId = Int(r, "PoultryCapitalAssetId"),
                    AssetNumber = StrN(r, "AssetNumber"),
                    AssetName = StrN(r, "AssetName"),
                    MonthsDue = Int(r, "MonthsDue"),
                    AmountDue = Dec(r, "AmountDue"),
                    MonthlyDepreciation = DecN(r, "MonthlyDepreciation"),
                    NextPeriod = DateN(r, "NextPeriod"),
                });
            }
            return list;
        }

        public async Task<PoultryAssetDepreciationRunResult> GenerateDepreciationAsync(PoultryDepreciationGenerateRequest q)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryassetdepreciation_generate(p_farmid => @FarmId::text, " +
                "p_throughdate => @Through::date, p_assetid => @AssetId::int, p_createdby => @By::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", q.FarmId ?? string.Empty);
            cmd.Parameters.AddWithValue("@Through", N(q.ThroughDate?.Date));
            cmd.Parameters.AddWithValue("@AssetId", N(q.AssetId));
            cmd.Parameters.AddWithValue("@By", N(q.CreatedBy));
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            if (!await r.ReadAsync()) return new PoultryAssetDepreciationRunResult();
            return new PoultryAssetDepreciationRunResult
            {
                AssetsProcessed = Int(r, "AssetsProcessed"),
                EntriesCreated = Int(r, "EntriesCreated"),
                TotalAmount = Dec(r, "TotalAmount"),
            };
        }

        public async Task ReverseDepreciationAsync(int entryId, PoultryReversalRequest q)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryassetdepreciation_reverse(p_farmid => @FarmId::text, " +
                "p_entryid => @Id::int, p_reason => @Reason::text, p_createdby => @By::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", q.FarmId ?? string.Empty);
            cmd.Parameters.AddWithValue("@Id", entryId);
            cmd.Parameters.AddWithValue("@Reason", q.Reason);
            cmd.Parameters.AddWithValue("@By", N(q.CreatedBy));
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<int> AdjustDepreciationAsync(PoultryDepreciationAdjustRequest q)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryassetdepreciation_adjust(p_farmid => @FarmId::text, " +
                "p_assetid => @AssetId::int, p_periodstart => @Period::date, p_amount => @Amount::numeric, " +
                "p_reason => @Reason::text, p_createdby => @By::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", q.FarmId ?? string.Empty);
            cmd.Parameters.AddWithValue("@AssetId", q.AssetId);
            cmd.Parameters.AddWithValue("@Period", q.PeriodStart.Date);
            cmd.Parameters.AddWithValue("@Amount", q.Amount);
            cmd.Parameters.AddWithValue("@Reason", q.Reason);
            cmd.Parameters.AddWithValue("@By", N(q.CreatedBy));
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }
    }
}
