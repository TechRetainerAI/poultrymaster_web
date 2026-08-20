using System.Data;
using Npgsql;
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
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwaterproduct_insert(p_farmid => @FarmId::text, p_name => @Name::text, p_sku => @Sku::text, p_sizeml => @SizeMl::int, p_unit => @Unit::text, p_unitprice => @UnitPrice::numeric, p_isactive => @IsActive::boolean, p_producttype => @ProductType::text, p_notes => @Notes::text, p_baseunit => @BaseUnit::text, p_sachetsperbag => @SachetsPerBag::int, p_bagprice => @BagPrice::numeric, p_sachetprice => @SachetPrice::numeric, p_issachetproduct => @IsSachetProduct::boolean, p_sizeunit => @SizeUnit::text, p_packagingunit => @PackagingUnit::text, p_defaultsalesunit => @DefaultSalesUnit::text, p_productcategory => @ProductCategory::text)", conn);
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
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwaterproduct_update(p_waterproductid => @WaterProductId::int, p_farmid => @FarmId::text, p_name => @Name::text, p_sku => @Sku::text, p_sizeml => @SizeMl::int, p_unit => @Unit::text, p_unitprice => @UnitPrice::numeric, p_isactive => @IsActive::boolean, p_producttype => @ProductType::text, p_notes => @Notes::text, p_baseunit => @BaseUnit::text, p_sachetsperbag => @SachetsPerBag::int, p_bagprice => @BagPrice::numeric, p_sachetprice => @SachetPrice::numeric, p_issachetproduct => @IsSachetProduct::boolean, p_sizeunit => @SizeUnit::text, p_packagingunit => @PackagingUnit::text, p_defaultsalesunit => @DefaultSalesUnit::text, p_productcategory => @ProductCategory::text)", conn);
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
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwaterproduct_getbyid(p_waterproductid => @WaterProductId::int, p_farmid => @FarmId::text)", conn);
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
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwaterproduct_getall(p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync()) list.Add(Read(reader));
            return list;
        }

        public async Task Delete(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwaterproduct_delete(p_waterproductid => @WaterProductId::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@WaterProductId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // Reconcile finished-product stock from the transaction ledger (in/out
        // breakdown). Read-only: water finished stock is derived, not stored.
        public async Task<List<ProductReconcileRow>> ReconcileStockAsync(string farmId, int? productId)
        {
            var list = new List<ProductReconcileRow>();
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwaterproduct_reconcilestock(p_farmid => @FarmId::text, p_waterproductid => @WaterProductId::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@WaterProductId", (object?)productId ?? DBNull.Value);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Add(new ProductReconcileRow
                {
                    ProductId = r.GetInt32(r.GetOrdinal("WaterProductId")),
                    Name = r.IsDBNull(r.GetOrdinal("Name")) ? null : r.GetString(r.GetOrdinal("Name")),
                    StockIn = r.GetDecimal(r.GetOrdinal("StockIn")),
                    StockOut = r.GetDecimal(r.GetOrdinal("StockOut")),
                    CurrentStock = r.GetDecimal(r.GetOrdinal("CurrentStock")),
                });
            return list;
        }

        public async Task<decimal> SetStockAsync(int productId, ProductSetStockRequest req)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwaterproduct_setstock(p_farmid => @FarmId::text, p_waterproductid => @WaterProductId::int, p_targetquantity => @TargetQuantity::numeric, p_note => @Note::text, p_createdby => @CreatedBy::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", req.FarmId);
            cmd.Parameters.AddWithValue("@WaterProductId", productId);
            cmd.Parameters.AddWithValue("@TargetQuantity", req.TargetQuantity);
            cmd.Parameters.AddWithValue("@Note", (object?)req.Note ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)req.CreatedBy ?? DBNull.Value);
            await conn.OpenAsync();
            var v = await cmd.ExecuteScalarAsync();
            return v is null || v == DBNull.Value ? 0 : Convert.ToDecimal(v);
        }

        private static WaterProductModel Read(NpgsqlDataReader r) => new()
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

        private static bool HasCol(NpgsqlDataReader r, string n)
        {
            for (int i = 0; i < r.FieldCount; i++)
                if (r.GetName(i).Equals(n, StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }
    }
}
