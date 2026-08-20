using System.Data;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class GenericProductService : IGenericProductService
    {
        private readonly string _connectionString;
        public GenericProductService(string connectionString) => _connectionString = connectionString;

        // ====================================================================
        // Product categories
        // ====================================================================
        public async Task<List<GenericProductCategoryModel>> GetCategoriesAsync(string farmId)
        {
            var list = new List<GenericProductCategoryModel>();
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericproductcategory_getall(p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync()) list.Add(ReadCategory(reader));
            return list;
        }

        public async Task<int> InsertCategoryAsync(GenericProductCategoryModel m)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericproductcategory_insert(p_farmid => @FarmId::text, p_name => @Name::text, p_description => @Description::text, p_isactive => @IsActive::boolean)", conn);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Name", m.Name);
            cmd.Parameters.AddWithValue("@Description", (object?)m.Description ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);

            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateCategoryAsync(GenericProductCategoryModel m)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericproductcategory_update(p_genericproductcategoryid => @GenericProductCategoryId::int, p_farmid => @FarmId::text, p_name => @Name::text, p_description => @Description::text, p_isactive => @IsActive::boolean)", conn);
            cmd.Parameters.AddWithValue("@GenericProductCategoryId", m.GenericProductCategoryId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Name", m.Name);
            cmd.Parameters.AddWithValue("@Description", (object?)m.Description ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteCategoryAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericproductcategory_delete(p_genericproductcategoryid => @GenericProductCategoryId::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@GenericProductCategoryId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // ====================================================================
        // Products
        // ====================================================================
        public async Task<List<GenericProductModel>> GetAllAsync(string farmId)
        {
            var list = new List<GenericProductModel>();
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericproduct_getall(p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync()) list.Add(ReadProduct(reader));
            return list;
        }

        public async Task<GenericProductModel?> GetByIdAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericproduct_getbyid(p_genericproductid => @GenericProductId::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@GenericProductId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            return await reader.ReadAsync() ? ReadProduct(reader) : null;
        }

        public async Task<int> InsertAsync(GenericProductModel m)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericproduct_insert(p_farmid => @FarmId::text, p_genericproductcategoryid => @GenericProductCategoryId::int, p_productname => @ProductName::text, p_sku => @SKU::text, p_barcode => @Barcode::text, p_unitofmeasure => @UnitOfMeasure::text, p_costprice => @CostPrice::numeric, p_sellingprice => @SellingPrice::numeric, p_wholesaleprice => @WholesalePrice::numeric, p_retailprice => @RetailPrice::numeric, p_openingstock => @OpeningStock::numeric, p_minimumstockalert => @MinimumStockAlert::numeric, p_trackinventory => @TrackInventory::boolean, p_supplierid => @SupplierId::int, p_isactive => @IsActive::boolean, p_notes => @Notes::text, p_createdby => @CreatedBy::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@GenericProductCategoryId", (object?)m.GenericProductCategoryId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ProductName", m.ProductName);
            cmd.Parameters.AddWithValue("@SKU", (object?)m.SKU ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Barcode", (object?)m.Barcode ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@UnitOfMeasure", (object?)m.UnitOfMeasure ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CostPrice", m.CostPrice);
            cmd.Parameters.AddWithValue("@SellingPrice", m.SellingPrice);
            cmd.Parameters.AddWithValue("@WholesalePrice", (object?)m.WholesalePrice ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@RetailPrice", (object?)m.RetailPrice ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@OpeningStock", m.OpeningStock);
            cmd.Parameters.AddWithValue("@MinimumStockAlert", m.MinimumStockAlert);
            cmd.Parameters.AddWithValue("@TrackInventory", m.TrackInventory);
            cmd.Parameters.AddWithValue("@SupplierId", (object?)m.SupplierId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)m.CreatedBy ?? DBNull.Value);

            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateAsync(GenericProductModel m)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericproduct_update(p_genericproductid => @GenericProductId::int, p_farmid => @FarmId::text, p_genericproductcategoryid => @GenericProductCategoryId::int, p_productname => @ProductName::text, p_sku => @SKU::text, p_barcode => @Barcode::text, p_unitofmeasure => @UnitOfMeasure::text, p_costprice => @CostPrice::numeric, p_sellingprice => @SellingPrice::numeric, p_wholesaleprice => @WholesalePrice::numeric, p_retailprice => @RetailPrice::numeric, p_minimumstockalert => @MinimumStockAlert::numeric, p_trackinventory => @TrackInventory::boolean, p_supplierid => @SupplierId::int, p_isactive => @IsActive::boolean, p_notes => @Notes::text)", conn);
            cmd.Parameters.AddWithValue("@GenericProductId", m.GenericProductId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@GenericProductCategoryId", (object?)m.GenericProductCategoryId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ProductName", m.ProductName);
            cmd.Parameters.AddWithValue("@SKU", (object?)m.SKU ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Barcode", (object?)m.Barcode ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@UnitOfMeasure", (object?)m.UnitOfMeasure ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CostPrice", m.CostPrice);
            cmd.Parameters.AddWithValue("@SellingPrice", m.SellingPrice);
            cmd.Parameters.AddWithValue("@WholesalePrice", (object?)m.WholesalePrice ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@RetailPrice", (object?)m.RetailPrice ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@MinimumStockAlert", m.MinimumStockAlert);
            cmd.Parameters.AddWithValue("@TrackInventory", m.TrackInventory);
            cmd.Parameters.AddWithValue("@SupplierId", (object?)m.SupplierId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericproduct_delete(p_genericproductid => @GenericProductId::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@GenericProductId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<List<GenericProductLowStockRowModel>> GetLowStockAsync(string farmId)
        {
            var list = new List<GenericProductLowStockRowModel>();
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericproduct_getlowstock(p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                list.Add(new GenericProductLowStockRowModel
                {
                    GenericProductId  = reader.GetInt32(reader.GetOrdinal("GenericProductId")),
                    FarmId            = reader.GetString(reader.GetOrdinal("FarmId")),
                    ProductName       = reader.GetString(reader.GetOrdinal("ProductName")),
                    SKU               = reader.IsDBNull(reader.GetOrdinal("SKU")) ? null : reader.GetString(reader.GetOrdinal("SKU")),
                    UnitOfMeasure     = reader.IsDBNull(reader.GetOrdinal("UnitOfMeasure")) ? null : reader.GetString(reader.GetOrdinal("UnitOfMeasure")),
                    CurrentStock      = reader.GetDecimal(reader.GetOrdinal("CurrentStock")),
                    MinimumStockAlert = reader.GetDecimal(reader.GetOrdinal("MinimumStockAlert")),
                    Shortfall         = reader.GetDecimal(reader.GetOrdinal("Shortfall")),
                });
            }
            return list;
        }

        public async Task ReconcileStockAsync(string farmId)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericproduct_reconcilestock(p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // ====================================================================
        // Helpers
        // ====================================================================
        private static GenericProductCategoryModel ReadCategory(NpgsqlDataReader r) => new()
        {
            GenericProductCategoryId = r.GetInt32(r.GetOrdinal("GenericProductCategoryId")),
            FarmId                   = r.GetString(r.GetOrdinal("FarmId")),
            Name                     = r.GetString(r.GetOrdinal("Name")),
            Description              = r.IsDBNull(r.GetOrdinal("Description")) ? null : r.GetString(r.GetOrdinal("Description")),
            IsActive                 = r.GetBoolean(r.GetOrdinal("IsActive")),
            IsDeleted                = r.GetBoolean(r.GetOrdinal("IsDeleted")),
            CreatedAt                = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt                = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };

        private static GenericProductModel ReadProduct(NpgsqlDataReader r) => new()
        {
            GenericProductId         = r.GetInt32(r.GetOrdinal("GenericProductId")),
            FarmId                   = r.GetString(r.GetOrdinal("FarmId")),
            GenericProductCategoryId = r.IsDBNull(r.GetOrdinal("GenericProductCategoryId")) ? null : r.GetInt32(r.GetOrdinal("GenericProductCategoryId")),
            CategoryName             = r.IsDBNull(r.GetOrdinal("CategoryName")) ? null : r.GetString(r.GetOrdinal("CategoryName")),
            ProductName              = r.GetString(r.GetOrdinal("ProductName")),
            SKU                      = r.IsDBNull(r.GetOrdinal("SKU")) ? null : r.GetString(r.GetOrdinal("SKU")),
            Barcode                  = r.IsDBNull(r.GetOrdinal("Barcode")) ? null : r.GetString(r.GetOrdinal("Barcode")),
            UnitOfMeasure            = r.IsDBNull(r.GetOrdinal("UnitOfMeasure")) ? null : r.GetString(r.GetOrdinal("UnitOfMeasure")),
            CostPrice                = r.GetDecimal(r.GetOrdinal("CostPrice")),
            SellingPrice             = r.GetDecimal(r.GetOrdinal("SellingPrice")),
            WholesalePrice           = r.IsDBNull(r.GetOrdinal("WholesalePrice")) ? null : r.GetDecimal(r.GetOrdinal("WholesalePrice")),
            RetailPrice              = r.IsDBNull(r.GetOrdinal("RetailPrice")) ? null : r.GetDecimal(r.GetOrdinal("RetailPrice")),
            OpeningStock             = r.GetDecimal(r.GetOrdinal("OpeningStock")),
            CurrentStock             = r.GetDecimal(r.GetOrdinal("CurrentStock")),
            MinimumStockAlert        = r.GetDecimal(r.GetOrdinal("MinimumStockAlert")),
            TrackInventory           = r.GetBoolean(r.GetOrdinal("TrackInventory")),
            SupplierId               = r.IsDBNull(r.GetOrdinal("SupplierId")) ? null : r.GetInt32(r.GetOrdinal("SupplierId")),
            IsActive                 = r.GetBoolean(r.GetOrdinal("IsActive")),
            IsDeleted                = r.GetBoolean(r.GetOrdinal("IsDeleted")),
            Notes                    = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            CreatedAt                = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt                = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };
    }
}
