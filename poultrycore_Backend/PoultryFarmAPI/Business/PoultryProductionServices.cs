using System.Data;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    // Poultry products/stock/recipes/batches/losses/daily-closing services (slices 2-6).
    // Additive; mirrors the Water production services. Raw ADO.NET + spPoultry*.

    internal static class PoultryRdr
    {
        public static bool Has(this SqlDataReader r, string n)
        {
            for (int i = 0; i < r.FieldCount; i++) if (string.Equals(r.GetName(i), n, StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }
        public static string Str(this SqlDataReader r, string n) => r.GetString(r.GetOrdinal(n));
        public static string? StrN(this SqlDataReader r, string n) { int i = r.GetOrdinal(n); return r.IsDBNull(i) ? null : r.GetString(i); }
        public static int Int(this SqlDataReader r, string n) => r.GetInt32(r.GetOrdinal(n));
        public static int? IntN(this SqlDataReader r, string n) { int i = r.GetOrdinal(n); return r.IsDBNull(i) ? (int?)null : r.GetInt32(i); }
        public static decimal Dec(this SqlDataReader r, string n) => r.GetDecimal(r.GetOrdinal(n));
        public static decimal? DecN(this SqlDataReader r, string n) { int i = r.GetOrdinal(n); return r.IsDBNull(i) ? (decimal?)null : r.GetDecimal(i); }
        public static bool Bool(this SqlDataReader r, string n) => r.GetBoolean(r.GetOrdinal(n));
        public static DateTime Date(this SqlDataReader r, string n) => r.GetDateTime(r.GetOrdinal(n));
        public static DateTime? DateN(this SqlDataReader r, string n) { int i = r.GetOrdinal(n); return r.IsDBNull(i) ? (DateTime?)null : r.GetDateTime(i); }
    }

    // ============================ Products ============================
    public interface IPoultryProductService
    {
        Task<List<PoultryProductModel>> GetAllAsync(string farmId);
        Task<PoultryProductModel?> GetByIdAsync(int id, string farmId);
        Task<int> InsertAsync(PoultryProductModel m);
        Task UpdateAsync(PoultryProductModel m);
        Task DeleteAsync(int id, string farmId);
    }

    public class PoultryProductService : IPoultryProductService
    {
        private readonly string _cs; public PoultryProductService(string cs) => _cs = cs;
        private static PoultryProductModel Map(SqlDataReader r) => new()
        {
            PoultryProductId = r.Int("PoultryProductId"), FarmId = r.Str("FarmId"), Name = r.Str("Name"),
            Sku = r.StrN("Sku"), Unit = r.StrN("Unit"), UnitPrice = r.Dec("UnitPrice"), ProductType = r.Str("ProductType"),
            IsActive = r.Bool("IsActive"), Notes = r.StrN("Notes"),
            StockOnHand = r.Has("StockOnHand") ? r.Dec("StockOnHand") : 0,
            CreatedDate = r.Date("CreatedDate"), UpdatedDate = r.DateN("UpdatedDate"),
        };
        public async Task<List<PoultryProductModel>> GetAllAsync(string farmId)
        {
            var list = new List<PoultryProductModel>();
            using var c = new SqlConnection(_cs); using var cmd = new SqlCommand("spPoultryProduct_GetAll", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId); await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync(); while (await r.ReadAsync()) list.Add(Map(r));
            return list;
        }
        public async Task<PoultryProductModel?> GetByIdAsync(int id, string farmId)
            => (await GetAllAsync(farmId)).FirstOrDefault(x => x.PoultryProductId == id);
        public async Task<int> InsertAsync(PoultryProductModel m)
        {
            using var c = new SqlConnection(_cs); using var cmd = new SqlCommand("spPoultryProduct_Insert", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId); cmd.Parameters.AddWithValue("@Name", m.Name);
            cmd.Parameters.AddWithValue("@Sku", (object?)m.Sku ?? DBNull.Value); cmd.Parameters.AddWithValue("@Unit", (object?)m.Unit ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@UnitPrice", m.UnitPrice); cmd.Parameters.AddWithValue("@ProductType", m.ProductType ?? "FinishedGood");
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            await c.OpenAsync(); return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }
        public async Task UpdateAsync(PoultryProductModel m)
        {
            using var c = new SqlConnection(_cs); using var cmd = new SqlCommand("spPoultryProduct_Update", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@PoultryProductId", m.PoultryProductId); cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Name", m.Name); cmd.Parameters.AddWithValue("@Sku", (object?)m.Sku ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Unit", (object?)m.Unit ?? DBNull.Value); cmd.Parameters.AddWithValue("@UnitPrice", m.UnitPrice);
            cmd.Parameters.AddWithValue("@ProductType", m.ProductType ?? "FinishedGood"); cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }
        public async Task DeleteAsync(int id, string farmId)
        {
            using var c = new SqlConnection(_cs); using var cmd = new SqlCommand("spPoultryProduct_Delete", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@PoultryProductId", id); cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }
    }

    // ============================ Stock ============================
    public interface IPoultryStockService
    {
        Task<List<PoultryStockTransactionModel>> GetTransactionsAsync(string farmId, int? productId);
        Task<int> AddTransactionAsync(PoultryStockTransactionModel m);
    }
    public class PoultryStockService : IPoultryStockService
    {
        private readonly string _cs; public PoultryStockService(string cs) => _cs = cs;
        public async Task<List<PoultryStockTransactionModel>> GetTransactionsAsync(string farmId, int? productId)
        {
            var list = new List<PoultryStockTransactionModel>();
            using var c = new SqlConnection(_cs); using var cmd = new SqlCommand("spPoultryStock_GetTransactions", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId); cmd.Parameters.AddWithValue("@PoultryProductId", (object?)productId ?? DBNull.Value);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(new PoultryStockTransactionModel
            {
                PoultryStockTransactionId = r.Int("PoultryStockTransactionId"), FarmId = r.Str("FarmId"),
                PoultryProductId = r.Int("PoultryProductId"), ProductName = r.StrN("ProductName"), TxnType = r.Str("TxnType"),
                Quantity = r.Dec("Quantity"), UnitCost = r.DecN("UnitCost"), RelatedId = r.IntN("RelatedId"),
                Note = r.StrN("Note"), CreatedDate = r.Date("CreatedDate"), CreatedBy = r.StrN("CreatedBy"),
            });
            return list;
        }
        public async Task<int> AddTransactionAsync(PoultryStockTransactionModel m)
        {
            using var c = new SqlConnection(_cs); using var cmd = new SqlCommand("spPoultryStock_AddTransaction", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId); cmd.Parameters.AddWithValue("@PoultryProductId", m.PoultryProductId);
            cmd.Parameters.AddWithValue("@TxnType", m.TxnType); cmd.Parameters.AddWithValue("@Quantity", m.Quantity);
            cmd.Parameters.AddWithValue("@UnitCost", (object?)m.UnitCost ?? DBNull.Value); cmd.Parameters.AddWithValue("@RelatedId", (object?)m.RelatedId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Note", (object?)m.Note ?? DBNull.Value); cmd.Parameters.AddWithValue("@CreatedBy", (object?)m.CreatedBy ?? DBNull.Value);
            await c.OpenAsync(); return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }
    }

    // ============================ Recipes ============================
    public interface IPoultryProductionRecipeService
    {
        Task<PoultryProductionRecipeModel?> GetByProductAsync(string farmId, int productId);
        Task<int> UpsertAsync(string farmId, int productId, PoultryProductionRecipeUpsertRequest req);
        Task DeleteAsync(string farmId, int recipeId);
    }
    public class PoultryProductionRecipeService : IPoultryProductionRecipeService
    {
        private readonly string _cs; public PoultryProductionRecipeService(string cs) => _cs = cs;
        public async Task<PoultryProductionRecipeModel?> GetByProductAsync(string farmId, int productId)
        {
            using var c = new SqlConnection(_cs); using var cmd = new SqlCommand("spPoultryProductionRecipe_GetByProduct", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId); cmd.Parameters.AddWithValue("@PoultryProductId", productId);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            PoultryProductionRecipeModel? recipe = null;
            if (await r.ReadAsync()) recipe = new PoultryProductionRecipeModel
            {
                PoultryProductionRecipeId = r.Int("PoultryProductionRecipeId"), FarmId = r.Str("FarmId"),
                PoultryProductId = r.Int("PoultryProductId"), RecipeName = r.StrN("RecipeName"), IsActive = r.Bool("IsActive"), Notes = r.StrN("Notes"),
            };
            if (recipe == null) return null;
            if (await r.NextResultAsync())
                while (await r.ReadAsync()) recipe.Items.Add(new PoultryProductionRecipeItemModel
                {
                    PoultryProductionRecipeItemId = r.Int("PoultryProductionRecipeItemId"), PoultryProductionRecipeId = r.Int("PoultryProductionRecipeId"),
                    PoultryRawMaterialItemId = r.Int("PoultryRawMaterialItemId"), ItemName = r.StrN("ItemName"), UnitOfMeasure = r.StrN("UnitOfMeasure"),
                    AvailableStock = r.Has("AvailableStock") ? r.Dec("AvailableStock") : 0, LatestUnitCost = r.Has("LatestUnitCost") ? r.Dec("LatestUnitCost") : 0,
                    QuantityPerOutputUnit = r.Dec("QuantityPerOutputUnit"), WasteAllowancePercent = r.Dec("WasteAllowancePercent"),
                    IsOptional = r.Bool("IsOptional"), DisplayOrder = r.Int("DisplayOrder"), Notes = r.StrN("Notes"),
                });
            return recipe;
        }
        public async Task<int> UpsertAsync(string farmId, int productId, PoultryProductionRecipeUpsertRequest req)
        {
            var itemsJson = JsonSerializer.Serialize(req.Items, new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase });
            using var c = new SqlConnection(_cs); using var cmd = new SqlCommand("spPoultryProductionRecipe_Upsert", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId); cmd.Parameters.AddWithValue("@PoultryProductId", productId);
            cmd.Parameters.AddWithValue("@RecipeName", (object?)req.RecipeName ?? DBNull.Value); cmd.Parameters.AddWithValue("@Notes", (object?)req.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ItemsJson", (object?)itemsJson ?? DBNull.Value); cmd.Parameters.AddWithValue("@UpdatedBy", (object?)req.UpdatedBy ?? DBNull.Value);
            await c.OpenAsync(); return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }
        public async Task DeleteAsync(string farmId, int recipeId)
        {
            using var c = new SqlConnection(_cs); using var cmd = new SqlCommand("spPoultryProductionRecipe_Delete", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId); cmd.Parameters.AddWithValue("@PoultryProductionRecipeId", recipeId);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }
    }

    // ============================ Batches + Production loss ============================
    public interface IPoultryProductionBatchService
    {
        Task<List<PoultryProductionBatchModel>> GetAllAsync(string farmId, string? status, DateTime? fromDate, DateTime? toDate);
        Task<List<PoultryProductionMaterialUsageInput>> GetMaterialsAsync(string farmId, int batchId);
        Task<int> InsertAsync(PoultryProductionBatchModel m);
        Task UpdateAsync(PoultryProductionBatchModel m);
        Task ApproveAsync(int id, string farmId, string? approvedBy);
        Task CancelAsync(int id, string farmId);
        Task<List<PoultryProductionLossModel>> GetProductionLossesAsync(string farmId, DateTime? fromDate, DateTime? toDate);
    }
    public class PoultryProductionBatchService : IPoultryProductionBatchService
    {
        private readonly string _cs; public PoultryProductionBatchService(string cs) => _cs = cs;
        private static string MaterialsJson(List<PoultryProductionMaterialUsageInput> m)
            => JsonSerializer.Serialize(m ?? new(), new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase });
        private static PoultryProductionBatchModel Map(SqlDataReader r) => new()
        {
            PoultryProductionBatchId = r.Int("PoultryProductionBatchId"), FarmId = r.Str("FarmId"), BatchNumber = r.Str("BatchNumber"),
            ProductionDate = r.Date("ProductionDate"), PoultryProductId = r.Int("PoultryProductId"), ProductName = r.StrN("ProductName"),
            QuantityProduced = r.Dec("QuantityProduced"), Unit = r.StrN("Unit"), DamagedQuantity = r.Dec("DamagedQuantity"),
            LaborCost = r.Dec("LaborCost"), OtherCost = r.Dec("OtherCost"), MaterialsCost = r.Dec("MaterialsCost"),
            TotalCost = r.Dec("TotalCost"), CostPerUnit = r.Dec("CostPerUnit"), Status = r.Str("Status"), Notes = r.StrN("Notes"),
            CreatedBy = r.StrN("CreatedBy"), ApprovedBy = r.StrN("ApprovedBy"), ApprovedAt = r.DateN("ApprovedAt"),
            CreatedAt = r.Date("CreatedAt"), UpdatedAt = r.DateN("UpdatedAt"),
        };
        public async Task<List<PoultryProductionBatchModel>> GetAllAsync(string farmId, string? status, DateTime? fromDate, DateTime? toDate)
        {
            var list = new List<PoultryProductionBatchModel>();
            using var c = new SqlConnection(_cs); using var cmd = new SqlCommand("spPoultryProductionBatch_GetAll", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId); cmd.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value); cmd.Parameters.AddWithValue("@ToDate", (object?)toDate ?? DBNull.Value);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync(); while (await r.ReadAsync()) list.Add(Map(r));
            return list;
        }
        public async Task<List<PoultryProductionMaterialUsageInput>> GetMaterialsAsync(string farmId, int batchId)
        {
            var list = new List<PoultryProductionMaterialUsageInput>();
            using var c = new SqlConnection(_cs); using var cmd = new SqlCommand("spPoultryProductionBatch_GetMaterials", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId); cmd.Parameters.AddWithValue("@PoultryProductionBatchId", batchId);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(new PoultryProductionMaterialUsageInput
            {
                PoultryRawMaterialItemId = r.Int("PoultryRawMaterialItemId"), QuantityUsed = r.Dec("QuantityUsed"),
                ExpectedQuantityUsed = r.DecN("ExpectedQuantityUsed"), UnitCost = r.DecN("UnitCost"),
            });
            return list;
        }
        public async Task<int> InsertAsync(PoultryProductionBatchModel m)
        {
            using var c = new SqlConnection(_cs); using var cmd = new SqlCommand("spPoultryProductionBatch_Insert", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId); cmd.Parameters.AddWithValue("@BatchNumber", m.BatchNumber);
            cmd.Parameters.AddWithValue("@ProductionDate", (object?)m.ProductionDate ?? DBNull.Value); cmd.Parameters.AddWithValue("@PoultryProductId", m.PoultryProductId);
            cmd.Parameters.AddWithValue("@QuantityProduced", m.QuantityProduced); cmd.Parameters.AddWithValue("@Unit", (object?)m.Unit ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DamagedQuantity", m.DamagedQuantity); cmd.Parameters.AddWithValue("@LaborCost", m.LaborCost);
            cmd.Parameters.AddWithValue("@OtherCost", m.OtherCost); cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)m.CreatedBy ?? DBNull.Value); cmd.Parameters.AddWithValue("@MaterialsUsedJson", MaterialsJson(m.MaterialsUsed));
            await c.OpenAsync(); return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }
        public async Task UpdateAsync(PoultryProductionBatchModel m)
        {
            using var c = new SqlConnection(_cs); using var cmd = new SqlCommand("spPoultryProductionBatch_Update", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@PoultryProductionBatchId", m.PoultryProductionBatchId); cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@BatchNumber", m.BatchNumber); cmd.Parameters.AddWithValue("@ProductionDate", (object?)m.ProductionDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PoultryProductId", m.PoultryProductId); cmd.Parameters.AddWithValue("@QuantityProduced", m.QuantityProduced);
            cmd.Parameters.AddWithValue("@Unit", (object?)m.Unit ?? DBNull.Value); cmd.Parameters.AddWithValue("@DamagedQuantity", m.DamagedQuantity);
            cmd.Parameters.AddWithValue("@LaborCost", m.LaborCost); cmd.Parameters.AddWithValue("@OtherCost", m.OtherCost);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value); cmd.Parameters.AddWithValue("@MaterialsUsedJson", MaterialsJson(m.MaterialsUsed));
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }
        public async Task ApproveAsync(int id, string farmId, string? approvedBy)
        {
            using var c = new SqlConnection(_cs); using var cmd = new SqlCommand("spPoultryProductionBatch_Approve", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@PoultryProductionBatchId", id); cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }
        public async Task CancelAsync(int id, string farmId)
        {
            using var c = new SqlConnection(_cs); using var cmd = new SqlCommand("spPoultryProductionBatch_Cancel", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@PoultryProductionBatchId", id); cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }
        public async Task<List<PoultryProductionLossModel>> GetProductionLossesAsync(string farmId, DateTime? fromDate, DateTime? toDate)
        {
            var list = new List<PoultryProductionLossModel>();
            using var c = new SqlConnection(_cs); using var cmd = new SqlCommand("spPoultryProductionLoss_GetAll", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId); cmd.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value); cmd.Parameters.AddWithValue("@ToDate", (object?)toDate ?? DBNull.Value);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(new PoultryProductionLossModel
            {
                PoultryProductionLossId = r.Int("PoultryProductionLossId"), FarmId = r.Str("FarmId"), SourceType = r.Str("SourceType"),
                SourceId = r.IntN("SourceId"), LossDate = r.Date("LossDate"), PoultryProductId = r.IntN("PoultryProductId"),
                ProductName = r.StrN("ProductName"), QuantityLost = r.Dec("QuantityLost"), EstimatedValue = r.DecN("EstimatedValue"),
                Reason = r.StrN("Reason"), CreatedAt = r.Date("CreatedAt"),
            });
            return list;
        }
    }

    // ============================ Manual loss records ============================
    public interface IPoultryLossRecordService
    {
        Task<List<PoultryLossRecordModel>> GetAllAsync(string farmId, string? lossType, DateTime? fromDate, DateTime? toDate);
        Task<int> InsertAsync(PoultryLossRecordModel m);
        Task UpdateAsync(PoultryLossRecordModel m);
        Task ApproveAsync(int id, string farmId, string? approvedBy);
        Task UnapproveAsync(int id, string farmId);
        Task DeleteAsync(int id, string farmId);
    }
    public class PoultryLossRecordService : IPoultryLossRecordService
    {
        private readonly string _cs; public PoultryLossRecordService(string cs) => _cs = cs;
        public async Task<List<PoultryLossRecordModel>> GetAllAsync(string farmId, string? lossType, DateTime? fromDate, DateTime? toDate)
        {
            var list = new List<PoultryLossRecordModel>();
            using var c = new SqlConnection(_cs); using var cmd = new SqlCommand("spPoultryLossRecord_GetAll", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId); cmd.Parameters.AddWithValue("@LossType", (object?)lossType ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value); cmd.Parameters.AddWithValue("@ToDate", (object?)toDate ?? DBNull.Value);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(new PoultryLossRecordModel
            {
                PoultryLossRecordId = r.Int("PoultryLossRecordId"), FarmId = r.Str("FarmId"), LossDate = r.Date("LossDate"), LossType = r.Str("LossType"),
                PoultryProductId = r.IntN("PoultryProductId"), ProductName = r.StrN("ProductName"), Quantity = r.DecN("Quantity"),
                EstimatedValue = r.DecN("EstimatedValue"), ResponsibleStaffId = r.IntN("ResponsibleStaffId"), Reason = r.StrN("Reason"),
                Status = r.Str("Status"), ApprovedBy = r.StrN("ApprovedBy"), ApprovedAt = r.DateN("ApprovedAt"), Notes = r.StrN("Notes"),
                CreatedBy = r.StrN("CreatedBy"), CreatedAt = r.Date("CreatedAt"), UpdatedAt = r.DateN("UpdatedAt"),
            });
            return list;
        }
        public async Task<int> InsertAsync(PoultryLossRecordModel m)
        {
            using var c = new SqlConnection(_cs); using var cmd = new SqlCommand("spPoultryLossRecord_Insert", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId); cmd.Parameters.AddWithValue("@LossDate", (object?)m.LossDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@LossType", m.LossType); cmd.Parameters.AddWithValue("@PoultryProductId", (object?)m.PoultryProductId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Quantity", (object?)m.Quantity ?? DBNull.Value); cmd.Parameters.AddWithValue("@EstimatedValue", (object?)m.EstimatedValue ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ResponsibleStaffId", (object?)m.ResponsibleStaffId ?? DBNull.Value); cmd.Parameters.AddWithValue("@Reason", (object?)m.Reason ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value); cmd.Parameters.AddWithValue("@CreatedBy", (object?)m.CreatedBy ?? DBNull.Value);
            await c.OpenAsync(); return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }
        public async Task UpdateAsync(PoultryLossRecordModel m)
        {
            using var c = new SqlConnection(_cs); using var cmd = new SqlCommand("spPoultryLossRecord_Update", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@PoultryLossRecordId", m.PoultryLossRecordId); cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@LossDate", (object?)m.LossDate ?? DBNull.Value); cmd.Parameters.AddWithValue("@LossType", m.LossType);
            cmd.Parameters.AddWithValue("@PoultryProductId", (object?)m.PoultryProductId ?? DBNull.Value); cmd.Parameters.AddWithValue("@Quantity", (object?)m.Quantity ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@EstimatedValue", (object?)m.EstimatedValue ?? DBNull.Value); cmd.Parameters.AddWithValue("@ResponsibleStaffId", (object?)m.ResponsibleStaffId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Reason", (object?)m.Reason ?? DBNull.Value); cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }
        public async Task ApproveAsync(int id, string farmId, string? approvedBy)
        {
            using var c = new SqlConnection(_cs); using var cmd = new SqlCommand("spPoultryLossRecord_Approve", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@PoultryLossRecordId", id); cmd.Parameters.AddWithValue("@FarmId", farmId); cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }
        public async Task UnapproveAsync(int id, string farmId)
        {
            using var c = new SqlConnection(_cs); using var cmd = new SqlCommand("spPoultryLossRecord_Unapprove", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@PoultryLossRecordId", id); cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }
        public async Task DeleteAsync(int id, string farmId)
        {
            using var c = new SqlConnection(_cs); using var cmd = new SqlCommand("spPoultryLossRecord_Delete", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@PoultryLossRecordId", id); cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }
    }

    // ============================ Daily closing ============================
    public interface IPoultryDailyClosingService
    {
        Task<List<PoultryDailyClosingModel>> GetAllAsync(string farmId, string? status, DateTime? fromDate, DateTime? toDate);
        Task<PoultryDailyClosingModel?> GetByIdAsync(int id, string farmId);
        Task<int> InsertAsync(string farmId, DateTime closingDate, string? managerNotes, string? createdBy);
        Task SubmitAsync(int id, PoultryDailyClosingSubmitRequest req);
        Task ApproveAsync(int id, string farmId, string? approvedBy);
        Task RejectAsync(int id, string farmId, string? reason);
        Task DeleteAsync(int id, string farmId);
    }
    public class PoultryDailyClosingService : IPoultryDailyClosingService
    {
        private readonly string _cs; public PoultryDailyClosingService(string cs) => _cs = cs;
        private static PoultryDailyClosingModel Map(SqlDataReader r) => new()
        {
            PoultryDailyClosingId = r.Int("PoultryDailyClosingId"), FarmId = r.Str("FarmId"), ClosingDate = r.Date("ClosingDate"),
            QuantityProduced = r.Dec("QuantityProduced"), QuantityDamaged = r.Dec("QuantityDamaged"), TotalProductionCost = r.Dec("TotalProductionCost"),
            ClosingStock = r.Dec("ClosingStock"), CashAtHand = r.Dec("CashAtHand"), ActualCashCounted = r.Dec("ActualCashCounted"),
            CashDifference = r.Dec("CashDifference"), ManagerNotes = r.StrN("ManagerNotes"), Status = r.Str("Status"), RejectionReason = r.StrN("RejectionReason"),
            CreatedBy = r.StrN("CreatedBy"), SubmittedBy = r.StrN("SubmittedBy"), SubmittedAt = r.DateN("SubmittedAt"),
            ApprovedBy = r.StrN("ApprovedBy"), ApprovedAt = r.DateN("ApprovedAt"), CreatedAt = r.Date("CreatedAt"), UpdatedAt = r.DateN("UpdatedAt"),
        };
        public async Task<List<PoultryDailyClosingModel>> GetAllAsync(string farmId, string? status, DateTime? fromDate, DateTime? toDate)
        {
            var list = new List<PoultryDailyClosingModel>();
            using var c = new SqlConnection(_cs); using var cmd = new SqlCommand("spPoultryDailyClosing_GetAll", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId); cmd.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value); cmd.Parameters.AddWithValue("@ToDate", (object?)toDate ?? DBNull.Value);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync(); while (await r.ReadAsync()) list.Add(Map(r));
            return list;
        }
        public async Task<PoultryDailyClosingModel?> GetByIdAsync(int id, string farmId)
        {
            using var c = new SqlConnection(_cs); using var cmd = new SqlCommand("spPoultryDailyClosing_GetById", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@PoultryDailyClosingId", id); cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync(); return await r.ReadAsync() ? Map(r) : null;
        }
        public async Task<int> InsertAsync(string farmId, DateTime closingDate, string? managerNotes, string? createdBy)
        {
            using var c = new SqlConnection(_cs); using var cmd = new SqlCommand("spPoultryDailyClosing_Insert", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId); cmd.Parameters.AddWithValue("@ClosingDate", closingDate.Date);
            cmd.Parameters.AddWithValue("@ManagerNotes", (object?)managerNotes ?? DBNull.Value); cmd.Parameters.AddWithValue("@CreatedBy", (object?)createdBy ?? DBNull.Value);
            await c.OpenAsync(); return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }
        public async Task SubmitAsync(int id, PoultryDailyClosingSubmitRequest req)
        {
            using var c = new SqlConnection(_cs); using var cmd = new SqlCommand("spPoultryDailyClosing_Submit", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@PoultryDailyClosingId", id); cmd.Parameters.AddWithValue("@FarmId", req.FarmId);
            cmd.Parameters.AddWithValue("@ActualCashCounted", req.ActualCashCounted); cmd.Parameters.AddWithValue("@ManagerNotes", (object?)req.ManagerNotes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@SubmittedBy", (object?)req.SubmittedBy ?? DBNull.Value);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }
        public async Task ApproveAsync(int id, string farmId, string? approvedBy)
        {
            using var c = new SqlConnection(_cs); using var cmd = new SqlCommand("spPoultryDailyClosing_Approve", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@PoultryDailyClosingId", id); cmd.Parameters.AddWithValue("@FarmId", farmId); cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }
        public async Task RejectAsync(int id, string farmId, string? reason)
        {
            using var c = new SqlConnection(_cs); using var cmd = new SqlCommand("spPoultryDailyClosing_Reject", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@PoultryDailyClosingId", id); cmd.Parameters.AddWithValue("@FarmId", farmId); cmd.Parameters.AddWithValue("@RejectionReason", (object?)reason ?? DBNull.Value);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }
        public async Task DeleteAsync(int id, string farmId)
        {
            using var c = new SqlConnection(_cs); using var cmd = new SqlCommand("spPoultryDailyClosing_Delete", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@PoultryDailyClosingId", id); cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }
    }
}
