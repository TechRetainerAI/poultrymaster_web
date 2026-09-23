using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class HotelCapitalAssetService : IHotelCapitalAssetService
    {
        private readonly string _cs;
        public HotelCapitalAssetService(string connectionString) { _cs = connectionString; }

        private static string? StrN(NpgsqlDataReader r, string col) { var o = r.GetOrdinal(col); return r.IsDBNull(o) ? null : r.GetString(o); }
        private static string Str(NpgsqlDataReader r, string col) => r.GetString(r.GetOrdinal(col));
        private static int Int(NpgsqlDataReader r, string col) => r.GetInt32(r.GetOrdinal(col));
        private static int? IntN(NpgsqlDataReader r, string col) { var o = r.GetOrdinal(col); return r.IsDBNull(o) ? null : r.GetInt32(o); }
        private static decimal Dec(NpgsqlDataReader r, string col) => r.GetDecimal(r.GetOrdinal(col));
        private static bool Bool(NpgsqlDataReader r, string col) => r.GetBoolean(r.GetOrdinal(col));
        private static DateTime Dt(NpgsqlDataReader r, string col) => r.GetDateTime(r.GetOrdinal(col));
        private static DateTime? DtN(NpgsqlDataReader r, string col) { var o = r.GetOrdinal(col); return r.IsDBNull(o) ? null : r.GetDateTime(o); }

        public async Task<List<HotelAssetCategoryModel>> GetCategoriesAsync(string farmId)
        {
            var list = new List<HotelAssetCategoryModel>();
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM sphotelassetcategory_getall(@f)", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(new HotelAssetCategoryModel { HotelAssetCategoryId = Int(r,"hotelassetcategoryid"), FarmId = Str(r,"farmid"), CategoryName = Str(r,"categoryname"), DefaultUsefulLifeMonths = Int(r,"defaultusefullifemonths"), SortOrder = Int(r,"sortorder"), IsActive = Bool(r,"isactive") });
            return list;
        }

        public async Task<int> UpsertCategoryAsync(string farmId, HotelAssetCategoryModel m)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT sphotelassetcategory_upsert(@f,@id,@n,@life,@sort)", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            cmd.Parameters.AddWithValue("@id", m.HotelAssetCategoryId > 0 ? (object)m.HotelAssetCategoryId : DBNull.Value);
            cmd.Parameters.AddWithValue("@n", m.CategoryName);
            cmd.Parameters.AddWithValue("@life", m.DefaultUsefulLifeMonths);
            cmd.Parameters.AddWithValue("@sort", m.SortOrder);
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task<List<HotelCapitalAssetModel>> GetAllAsync(string farmId, string? status, int? categoryId)
        {
            var list = new List<HotelCapitalAssetModel>();
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM sphotelcapitalasset_getall(@f,@s,@c)", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            cmd.Parameters.AddWithValue("@s", (object?)status ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@c", (object?)(categoryId.HasValue ? (object)categoryId.Value : null) ?? DBNull.Value);
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(MapAsset(r, false));
            return list;
        }

        public async Task<HotelCapitalAssetModel?> GetByIdAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM sphotelcapitalasset_getbyid(@id,@f)", conn);
            cmd.Parameters.AddWithValue("@id", id); cmd.Parameters.AddWithValue("@f", farmId);
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? MapAsset(r, true) : null;
        }

        public async Task<HotelCapitalAssetSummaryModel> GetSummaryAsync(string farmId)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM sphotelcapitalasset_summary(@f)", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            using var r = await cmd.ExecuteReaderAsync();
            if (await r.ReadAsync()) return new HotelCapitalAssetSummaryModel { TotalAssets = Int(r,"totalassets"), ActiveAssets = Int(r,"activeassets"), DraftAssets = Int(r,"draftassets"), TotalAssetCost = Dec(r,"totalassetcost"), AccumulatedDepreciation = Dec(r,"accumulateddepreciation"), CurrentBookValue = Dec(r,"currentbookvalue") };
            return new HotelCapitalAssetSummaryModel();
        }

        public async Task<int> CreateAsync(HotelCapitalAssetCreateRequest req, string? createdBy)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT sphotelcapitalasset_create(@f,@n,@cat,@acqd,@ind,@res,@life,@amt,@sup,@loc,@sn,@notes,@by)", conn);
            cmd.Parameters.AddWithValue("@f", req.FarmId); cmd.Parameters.AddWithValue("@n", req.AssetName);
            cmd.Parameters.AddWithValue("@cat", (object?)req.HotelAssetCategoryId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@acqd", string.IsNullOrEmpty(req.AcquisitionDate) ? DBNull.Value : (object)DateTime.Parse(req.AcquisitionDate));
            cmd.Parameters.AddWithValue("@ind", string.IsNullOrEmpty(req.InServiceDate) ? DBNull.Value : (object)DateTime.Parse(req.InServiceDate));
            cmd.Parameters.AddWithValue("@res", req.ResidualValue); cmd.Parameters.AddWithValue("@life", req.UsefulLifeMonths);
            cmd.Parameters.AddWithValue("@amt", req.Amount);
            cmd.Parameters.AddWithValue("@sup", (object?)req.Supplier ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@loc", (object?)req.Location ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@sn", (object?)req.SerialNumber ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@notes", (object?)req.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@by", (object?)createdBy ?? DBNull.Value);
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateAsync(int id, HotelCapitalAssetUpdateRequest req)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT sphotelcapitalasset_update(@id,@f,@n,@cat,@acqd,@ind,@res,@life,@sup,@loc,@sn,@notes)", conn);
            cmd.Parameters.AddWithValue("@id", id); cmd.Parameters.AddWithValue("@f", req.FarmId);
            cmd.Parameters.AddWithValue("@n", req.AssetName);
            cmd.Parameters.AddWithValue("@cat", (object?)req.HotelAssetCategoryId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@acqd", string.IsNullOrEmpty(req.AcquisitionDate) ? DBNull.Value : (object)DateTime.Parse(req.AcquisitionDate));
            cmd.Parameters.AddWithValue("@ind", string.IsNullOrEmpty(req.InServiceDate) ? DBNull.Value : (object)DateTime.Parse(req.InServiceDate));
            cmd.Parameters.AddWithValue("@res", req.ResidualValue); cmd.Parameters.AddWithValue("@life", req.UsefulLifeMonths);
            cmd.Parameters.AddWithValue("@sup", (object?)req.Supplier ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@loc", (object?)req.Location ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@sn", (object?)req.SerialNumber ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@notes", (object?)req.Notes ?? DBNull.Value);
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task ActivateAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT sphotelcapitalasset_activate(@id,@f)", conn);
            cmd.Parameters.AddWithValue("@id", id); cmd.Parameters.AddWithValue("@f", farmId);
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<int> AddCostAsync(int assetId, string farmId, decimal amount, string? description, DateTime? costDate, string? createdBy)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT sphotelcapitalasset_addcost(@aid,@f,@amt,@desc,@date,@by)", conn);
            cmd.Parameters.AddWithValue("@aid", assetId); cmd.Parameters.AddWithValue("@f", farmId);
            cmd.Parameters.AddWithValue("@amt", amount);
            cmd.Parameters.AddWithValue("@desc", (object?)description ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@date", (object?)costDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@by", (object?)createdBy ?? DBNull.Value);
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task ReverseCostAsync(int costId, int assetId, string farmId, string? reason, string? by)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT sphotelcapitalasset_reversecost(@cid,@aid,@f,@reason,@by)", conn);
            cmd.Parameters.AddWithValue("@cid", costId); cmd.Parameters.AddWithValue("@aid", assetId);
            cmd.Parameters.AddWithValue("@f", farmId);
            cmd.Parameters.AddWithValue("@reason", (object?)reason ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@by", (object?)by ?? DBNull.Value);
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DisposeAsync(int id, string farmId, DateTime? disposalDate, string? reason, string? by)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT sphotelcapitalasset_dispose(@id,@f,@date,@reason,@by)", conn);
            cmd.Parameters.AddWithValue("@id", id); cmd.Parameters.AddWithValue("@f", farmId);
            cmd.Parameters.AddWithValue("@date", (object?)disposalDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@reason", (object?)reason ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@by", (object?)by ?? DBNull.Value);
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task ReverseAsync(int id, string farmId, string? reason, string? by)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT sphotelcapitalasset_reverse(@id,@f,@reason,@by)", conn);
            cmd.Parameters.AddWithValue("@id", id); cmd.Parameters.AddWithValue("@f", farmId);
            cmd.Parameters.AddWithValue("@reason", (object?)reason ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@by", (object?)by ?? DBNull.Value);
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<List<HotelCapitalAssetCostModel>> GetCostsAsync(int assetId, string farmId)
        {
            var list = new List<HotelCapitalAssetCostModel>();
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM sphotelcapitalassetcost_getall(@aid,@f)", conn);
            cmd.Parameters.AddWithValue("@aid", assetId); cmd.Parameters.AddWithValue("@f", farmId);
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(new HotelCapitalAssetCostModel { HotelCapitalAssetCostId = Int(r,"hotelcapitalassetcostid"), FarmId = Str(r,"farmid"), HotelCapitalAssetId = Int(r,"hotelcapitalassetid"), Amount = Dec(r,"amount"), SourceType = Str(r,"sourcetype"), Description = StrN(r,"description"), CostDate = DtN(r,"costdate"), Status = Str(r,"status"), CreatedBy = StrN(r,"createdby"), CreatedAt = Dt(r,"createdat") });
            return list;
        }

        public async Task<List<HotelAssetDepreciationModel>> GetDepreciationAsync(string farmId, int? assetId)
        {
            var list = new List<HotelAssetDepreciationModel>();
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM sphotelassetdepreciation_getall(@f,@aid)", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            cmd.Parameters.AddWithValue("@aid", (object?)(assetId.HasValue ? (object)assetId.Value : null) ?? DBNull.Value);
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(new HotelAssetDepreciationModel { HotelAssetDepreciationId = Int(r,"hotelassetdepreciationid"), FarmId = Str(r,"farmid"), HotelCapitalAssetId = Int(r,"hotelcapitalassetid"), AssetName = StrN(r,"assetname"), PeriodStart = Dt(r,"periodstart"), Amount = Dec(r,"amount"), AccumulatedAfter = Dec(r,"accumulatedafter"), BookValueAfter = Dec(r,"bookvalueafter"), DepreciationMethod = Str(r,"depreciationmethod"), SourceType = Str(r,"sourcetype"), Reason = StrN(r,"reason"), Status = Str(r,"status"), CreatedBy = StrN(r,"createdby"), CreatedAt = Dt(r,"createdat") });
            return list;
        }

        public async Task<HotelDepreciationRunResult> GenerateDepreciationAsync(string farmId, DateTime? throughDate, int? assetId, string? createdBy)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM sphotelassetdepreciation_generate(@f,@td,@aid,@by)", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            cmd.Parameters.AddWithValue("@td", (object?)throughDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@aid", (object?)(assetId.HasValue ? (object)assetId.Value : null) ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@by", (object?)createdBy ?? DBNull.Value);
            using var r = await cmd.ExecuteReaderAsync();
            if (await r.ReadAsync()) return new HotelDepreciationRunResult { AssetsProcessed = Int(r,"assetsprocessed"), EntriesCreated = Int(r,"entriescreated"), TotalAmount = Dec(r,"totalamount") };
            return new HotelDepreciationRunResult();
        }

        public async Task ReverseDepreciationAsync(int entryId, string farmId, string? reason, string? by)
        {
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT sphotelassetdepreciation_reverse(@id,@f,@reason,@by)", conn);
            cmd.Parameters.AddWithValue("@id", entryId); cmd.Parameters.AddWithValue("@f", farmId);
            cmd.Parameters.AddWithValue("@reason", (object?)reason ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@by", (object?)by ?? DBNull.Value);
            await cmd.ExecuteNonQueryAsync();
        }

        private static HotelCapitalAssetModel MapAsset(NpgsqlDataReader r, bool includeReversal)
        {
            var m = new HotelCapitalAssetModel
            {
                HotelCapitalAssetId = Int(r,"hotelcapitalassetid"), FarmId = Str(r,"farmid"),
                AssetName = Str(r,"assetname"), AssetNumber = StrN(r,"assetnumber"),
                HotelAssetCategoryId = IntN(r,"hotelassetcategoryid"), CategoryName = StrN(r,"categoryname"),
                Status = Str(r,"status"), AcquisitionDate = DtN(r,"acquisitiondate"),
                InServiceDate = DtN(r,"inservicedate"), DisposalDate = DtN(r,"disposaldate"),
                AcquisitionCost = Dec(r,"acquisitioncost"), AdditionalCost = Dec(r,"additionalcost"),
                TotalCapitalizedCost = Dec(r,"totalcapitalizedcost"), ResidualValue = Dec(r,"residualvalue"),
                UsefulLifeMonths = Int(r,"usefullifemonths"), DepreciationMethod = Str(r,"depreciationmethod"),
                AccumulatedDepreciation = Dec(r,"accumulateddepreciation"), CurrentBookValue = Dec(r,"currentbookvalue"),
                Supplier = StrN(r,"supplier"), Location = StrN(r,"location"), SerialNumber = StrN(r,"serialnumber"),
                Notes = StrN(r,"notes"), CreatedBy = StrN(r,"createdby"),
                CreatedAt = Dt(r,"createdat"), UpdatedAt = DtN(r,"updatedat"),
            };
            if (includeReversal) { m.ReversedBy = StrN(r,"reversedby"); m.ReversedReason = StrN(r,"reversedreason"); m.ReversedAt = DtN(r,"reversedat"); }
            return m;
        }
    }
}
