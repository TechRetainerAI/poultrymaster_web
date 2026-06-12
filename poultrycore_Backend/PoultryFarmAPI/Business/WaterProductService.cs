using System.Data;
using System.Data.SqlClient;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class WaterProductService : IWaterProductService
    {
        private readonly string _connectionString;

        public WaterProductService(string connectionString)
        {
            _connectionString = connectionString;
        }

        public async Task<int> Insert(WaterProductModel m)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spWaterProduct_Insert", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Name", m.Name);
            cmd.Parameters.AddWithValue("@Sku", (object?)m.Sku ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@SizeMl", (object?)m.SizeMl ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Unit", (object?)m.Unit ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@UnitPrice", m.UnitPrice);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            cmd.Parameters.AddWithValue("@ProductType", string.IsNullOrWhiteSpace(m.ProductType) ? "FinishedGood" : m.ProductType);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            // Migration 084 — sachet product fields. SP defaults handle older DBs.
            cmd.Parameters.AddWithValue("@BaseUnit",        (object?)m.BaseUnit        ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@SachetsPerBag",   (object?)m.SachetsPerBag   ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@BagPrice",        (object?)m.BagPrice        ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@SachetPrice",     (object?)m.SachetPrice     ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsSachetProduct", m.IsSachetProduct);
            // Migration 092 — Packaging & Pricing fields.
            cmd.Parameters.AddWithValue("@SizeUnit",         (object?)m.SizeUnit         ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PackagingUnit",    (object?)m.PackagingUnit    ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DefaultSalesUnit", (object?)m.DefaultSalesUnit ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ProductCategory",  (object?)m.ProductCategory  ?? DBNull.Value);

            await conn.OpenAsync();
            var result = await cmd.ExecuteScalarAsync();
            return Convert.ToInt32(result);
        }

        public async Task Update(WaterProductModel m)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spWaterProduct_Update", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterProductId", m.WaterProductId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Name", m.Name);
            cmd.Parameters.AddWithValue("@Sku", (object?)m.Sku ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@SizeMl", (object?)m.SizeMl ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Unit", (object?)m.Unit ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@UnitPrice", m.UnitPrice);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            cmd.Parameters.AddWithValue("@ProductType", string.IsNullOrWhiteSpace(m.ProductType) ? "FinishedGood" : m.ProductType);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            // Migration 084 — sachet product fields.
            cmd.Parameters.AddWithValue("@BaseUnit",        (object?)m.BaseUnit        ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@SachetsPerBag",   (object?)m.SachetsPerBag   ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@BagPrice",        (object?)m.BagPrice        ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@SachetPrice",     (object?)m.SachetPrice     ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsSachetProduct", m.IsSachetProduct);
            // Migration 092 — Packaging & Pricing fields.
            cmd.Parameters.AddWithValue("@SizeUnit",         (object?)m.SizeUnit         ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PackagingUnit",    (object?)m.PackagingUnit    ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DefaultSalesUnit", (object?)m.DefaultSalesUnit ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ProductCategory",  (object?)m.ProductCategory  ?? DBNull.Value);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<WaterProductModel?> GetById(int id, string farmId)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spWaterProduct_GetById", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterProductId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            if (await reader.ReadAsync()) return Read(reader);
            return null;
        }

        public async Task<List<WaterProductModel>> GetAll(string farmId)
        {
            var list = new List<WaterProductModel>();
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spWaterProduct_GetAll", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync()) list.Add(Read(reader));
            return list;
        }

        public async Task Delete(int id, string farmId)
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("spWaterProduct_Delete", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterProductId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static WaterProductModel Read(SqlDataReader r) => new()
        {
            WaterProductId = r.GetInt32(r.GetOrdinal("WaterProductId")),
            FarmId         = r.GetString(r.GetOrdinal("FarmId")),
            Name           = r.GetString(r.GetOrdinal("Name")),
            Sku            = r.IsDBNull(r.GetOrdinal("Sku")) ? null : r.GetString(r.GetOrdinal("Sku")),
            SizeMl         = r.IsDBNull(r.GetOrdinal("SizeMl")) ? null : r.GetInt32(r.GetOrdinal("SizeMl")),
            Unit           = r.IsDBNull(r.GetOrdinal("Unit")) ? null : r.GetString(r.GetOrdinal("Unit")),
            UnitPrice      = r.GetDecimal(r.GetOrdinal("UnitPrice")),
            IsActive       = r.GetBoolean(r.GetOrdinal("IsActive")),
            // ProductType column added in migration 063. Tolerate a DB that
            // hasn't been migrated yet by falling back to FinishedGood.
            ProductType    = HasCol(r, "ProductType") && !r.IsDBNull(r.GetOrdinal("ProductType"))
                                ? r.GetString(r.GetOrdinal("ProductType"))
                                : "FinishedGood",
            Notes          = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            CreatedDate    = r.GetDateTime(r.GetOrdinal("CreatedDate")),
            UpdatedDate    = r.IsDBNull(r.GetOrdinal("UpdatedDate")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedDate")),
            StockOnHand    = r.IsDBNull(r.GetOrdinal("StockOnHand")) ? 0 : Convert.ToInt32(r.GetValue(r.GetOrdinal("StockOnHand"))),
            // Migration 084 — sachet fields are nullable; absent in older DBs.
            BaseUnit       = HasCol(r, "BaseUnit")        && !r.IsDBNull(r.GetOrdinal("BaseUnit"))        ? r.GetString(r.GetOrdinal("BaseUnit"))                  : null,
            SachetsPerBag  = HasCol(r, "SachetsPerBag")   && !r.IsDBNull(r.GetOrdinal("SachetsPerBag"))   ? r.GetInt32(r.GetOrdinal("SachetsPerBag"))             : null,
            BagPrice       = HasCol(r, "BagPrice")        && !r.IsDBNull(r.GetOrdinal("BagPrice"))        ? r.GetDecimal(r.GetOrdinal("BagPrice"))                : null,
            SachetPrice    = HasCol(r, "SachetPrice")     && !r.IsDBNull(r.GetOrdinal("SachetPrice"))     ? r.GetDecimal(r.GetOrdinal("SachetPrice"))             : null,
            IsSachetProduct= HasCol(r, "IsSachetProduct") && r.GetBoolean(r.GetOrdinal("IsSachetProduct")),
            // Migration 092 — Packaging & Pricing fields.
            SizeUnit         = HasCol(r, "SizeUnit")         && !r.IsDBNull(r.GetOrdinal("SizeUnit"))         ? r.GetString(r.GetOrdinal("SizeUnit"))         : null,
            PackagingUnit    = HasCol(r, "PackagingUnit")    && !r.IsDBNull(r.GetOrdinal("PackagingUnit"))    ? r.GetString(r.GetOrdinal("PackagingUnit"))    : null,
            DefaultSalesUnit = HasCol(r, "DefaultSalesUnit") && !r.IsDBNull(r.GetOrdinal("DefaultSalesUnit")) ? r.GetString(r.GetOrdinal("DefaultSalesUnit")) : null,
            ProductCategory  = HasCol(r, "ProductCategory")  && !r.IsDBNull(r.GetOrdinal("ProductCategory"))  ? r.GetString(r.GetOrdinal("ProductCategory"))  : null,
        };

        private static bool HasCol(SqlDataReader r, string n)
        {
            for (int i = 0; i < r.FieldCount; i++)
                if (r.GetName(i).Equals(n, StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }
    }
}
