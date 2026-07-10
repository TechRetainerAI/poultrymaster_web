using System.Data;
using Microsoft.Data.SqlClient;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    // =========================================================================
    // Poultry raw materials + inventory services (mirror the Water raw-material
    // services). Additive: new interfaces/classes only. Raw ADO.NET + spPoultry*.
    // =========================================================================

    public interface IPoultryRawMaterialItemService
    {
        Task<List<PoultryRawMaterialItemModel>> GetAllAsync(string farmId);
        Task<PoultryRawMaterialItemModel?> GetByIdAsync(int id, string farmId);
        Task<List<PoultryRawMaterialItemModel>> GetLowStockAsync(string farmId);
        Task<int> InsertAsync(PoultryRawMaterialItemModel m);
        Task UpdateAsync(PoultryRawMaterialItemModel m);
        Task DeleteAsync(int id, string farmId);
    }

    public interface IPoultryRawMaterialPurchaseService
    {
        Task<List<PoultryRawMaterialPurchaseModel>> GetAllAsync(string farmId, DateTime? fromDate, DateTime? toDate);
        Task<int> InsertAsync(PoultryRawMaterialPurchaseModel m);
        Task UpdateAsync(PoultryRawMaterialPurchaseModel m);
        Task DeleteAsync(int id, string farmId);
        Task<decimal> PayBalanceAsync(int id, string farmId, decimal amount, string? paymentMethod, DateTime? paymentDate, string? createdBy);
    }

    public interface IPoultryRawMaterialUsageService
    {
        Task<List<PoultryRawMaterialUsageModel>> GetHistoryAsync(string farmId, int? itemId, DateTime? fromDate, DateTime? toDate);
    }

    // -------------------------------------------------------------------------
    // Items
    // -------------------------------------------------------------------------
    public class PoultryRawMaterialItemService : IPoultryRawMaterialItemService
    {
        private readonly string _cs;
        public PoultryRawMaterialItemService(string cs) => _cs = cs;

        private static PoultryRawMaterialItemModel Map(SqlDataReader r) => new()
        {
            PoultryRawMaterialItemId = r.GetInt32(r.GetOrdinal("PoultryRawMaterialItemId")),
            FarmId = r.GetString(r.GetOrdinal("FarmId")),
            ItemName = r.GetString(r.GetOrdinal("ItemName")),
            Category = r.GetString(r.GetOrdinal("Category")),
            UnitOfMeasure = r.IsDBNull(r.GetOrdinal("UnitOfMeasure")) ? null : r.GetString(r.GetOrdinal("UnitOfMeasure")),
            MinimumStockAlert = r.GetDecimal(r.GetOrdinal("MinimumStockAlert")),
            CurrentQuantity = r.GetDecimal(r.GetOrdinal("CurrentQuantity")),
            IsActive = r.GetBoolean(r.GetOrdinal("IsActive")),
            IsLowStock = HasColumn(r, "IsLowStock") && !r.IsDBNull(r.GetOrdinal("IsLowStock")) && r.GetBoolean(r.GetOrdinal("IsLowStock")),
            Notes = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            UsageMethod = HasColumn(r, "UsageMethod") && !r.IsDBNull(r.GetOrdinal("UsageMethod")) ? r.GetString(r.GetOrdinal("UsageMethod")) : "FIFO",
            CreatedAt = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };

        private static bool HasColumn(SqlDataReader r, string name)
        {
            for (int i = 0; i < r.FieldCount; i++)
                if (string.Equals(r.GetName(i), name, StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }

        public async Task<List<PoultryRawMaterialItemModel>> GetAllAsync(string farmId)
        {
            var list = new List<PoultryRawMaterialItemModel>();
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spPoultryRawMaterialItem_GetAll", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(Map(r));
            return list;
        }

        public async Task<PoultryRawMaterialItemModel?> GetByIdAsync(int id, string farmId)
            => (await GetAllAsync(farmId)).FirstOrDefault(x => x.PoultryRawMaterialItemId == id);

        public async Task<List<PoultryRawMaterialItemModel>> GetLowStockAsync(string farmId)
            => (await GetAllAsync(farmId)).Where(x => x.IsActive && x.IsLowStock).ToList();

        public async Task<int> InsertAsync(PoultryRawMaterialItemModel m)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spPoultryRawMaterialItem_Insert", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@ItemName", m.ItemName);
            cmd.Parameters.AddWithValue("@Category", m.Category);
            cmd.Parameters.AddWithValue("@UnitOfMeasure", (object?)m.UnitOfMeasure ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@MinimumStockAlert", m.MinimumStockAlert);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@UsageMethod", string.IsNullOrWhiteSpace(m.UsageMethod) ? "FIFO" : m.UsageMethod);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateAsync(PoultryRawMaterialItemModel m)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spPoultryRawMaterialItem_Update", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@PoultryRawMaterialItemId", m.PoultryRawMaterialItemId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@ItemName", m.ItemName);
            cmd.Parameters.AddWithValue("@Category", m.Category);
            cmd.Parameters.AddWithValue("@UnitOfMeasure", (object?)m.UnitOfMeasure ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@MinimumStockAlert", m.MinimumStockAlert);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@UsageMethod", string.IsNullOrWhiteSpace(m.UsageMethod) ? "FIFO" : m.UsageMethod);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteAsync(int id, string farmId)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spPoultryRawMaterialItem_Delete", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@PoultryRawMaterialItemId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }
    }

    // -------------------------------------------------------------------------
    // Purchases
    // -------------------------------------------------------------------------
    public class PoultryRawMaterialPurchaseService : IPoultryRawMaterialPurchaseService
    {
        private readonly string _cs;
        public PoultryRawMaterialPurchaseService(string cs) => _cs = cs;

        private static decimal? GetNullableDecimal(SqlDataReader r, string col)
        {
            int i = r.GetOrdinal(col);
            return r.IsDBNull(i) ? (decimal?)null : r.GetDecimal(i);
        }

        private static bool HasColumn(SqlDataReader r, string name)
        {
            for (int i = 0; i < r.FieldCount; i++)
                if (string.Equals(r.GetName(i), name, StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }

        private static PoultryRawMaterialPurchaseModel Map(SqlDataReader r) => new()
        {
            PoultryRawMaterialPurchaseId = r.GetInt32(r.GetOrdinal("PoultryRawMaterialPurchaseId")),
            FarmId = r.GetString(r.GetOrdinal("FarmId")),
            PoultryRawMaterialItemId = r.GetInt32(r.GetOrdinal("PoultryRawMaterialItemId")),
            ItemName = r.IsDBNull(r.GetOrdinal("ItemName")) ? null : r.GetString(r.GetOrdinal("ItemName")),
            Category = r.IsDBNull(r.GetOrdinal("Category")) ? null : r.GetString(r.GetOrdinal("Category")),
            UnitOfMeasure = r.IsDBNull(r.GetOrdinal("UnitOfMeasure")) ? null : r.GetString(r.GetOrdinal("UnitOfMeasure")),
            SupplierName = r.IsDBNull(r.GetOrdinal("SupplierName")) ? null : r.GetString(r.GetOrdinal("SupplierName")),
            SupplierId = r.IsDBNull(r.GetOrdinal("SupplierId")) ? null : r.GetInt32(r.GetOrdinal("SupplierId")),
            PurchaseDate = r.GetDateTime(r.GetOrdinal("PurchaseDate")),
            Quantity = r.GetDecimal(r.GetOrdinal("Quantity")),
            UnitCost = r.GetDecimal(r.GetOrdinal("UnitCost")),
            TotalCost = r.GetDecimal(r.GetOrdinal("TotalCost")),
            RemainingQuantity = HasColumn(r, "RemainingQuantity") && !r.IsDBNull(r.GetOrdinal("RemainingQuantity")) ? r.GetDecimal(r.GetOrdinal("RemainingQuantity")) : r.GetDecimal(r.GetOrdinal("Quantity")),
            ProductionUnit = r.IsDBNull(r.GetOrdinal("ProductionUnit")) ? null : r.GetString(r.GetOrdinal("ProductionUnit")),
            ProductionUnitsPerPurchaseUnit = GetNullableDecimal(r, "ProductionUnitsPerPurchaseUnit"),
            ProductionQuantity = GetNullableDecimal(r, "ProductionQuantity"),
            ProductionUnitCost = GetNullableDecimal(r, "ProductionUnitCost"),
            PaymentMethod = r.IsDBNull(r.GetOrdinal("PaymentMethod")) ? null : r.GetString(r.GetOrdinal("PaymentMethod")),
            PoultryCashAccountId = r.IsDBNull(r.GetOrdinal("PoultryCashAccountId")) ? (int?)null : r.GetInt32(r.GetOrdinal("PoultryCashAccountId")),
            AmountPaid = r.GetDecimal(r.GetOrdinal("AmountPaid")),
            Balance = r.GetDecimal(r.GetOrdinal("Balance")),
            ReceiptUrl = r.IsDBNull(r.GetOrdinal("ReceiptUrl")) ? null : r.GetString(r.GetOrdinal("ReceiptUrl")),
            Notes = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            CreatedBy = r.IsDBNull(r.GetOrdinal("CreatedBy")) ? null : r.GetString(r.GetOrdinal("CreatedBy")),
            CreatedAt = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };

        public async Task<List<PoultryRawMaterialPurchaseModel>> GetAllAsync(string farmId, DateTime? fromDate, DateTime? toDate)
        {
            var list = new List<PoultryRawMaterialPurchaseModel>();
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spPoultryRawMaterialPurchase_GetAll", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ToDate", (object?)toDate ?? DBNull.Value);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(Map(r));
            return list;
        }

        public async Task<int> InsertAsync(PoultryRawMaterialPurchaseModel m)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spPoultryRawMaterialPurchase_Insert", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@PoultryRawMaterialItemId", m.PoultryRawMaterialItemId);
            cmd.Parameters.AddWithValue("@SupplierName", (object?)m.SupplierName ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@SupplierId", (object?)m.SupplierId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PurchaseDate", (object?)m.PurchaseDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Quantity", m.Quantity);
            cmd.Parameters.AddWithValue("@UnitCost", m.UnitCost);
            cmd.Parameters.AddWithValue("@TotalCost", m.TotalCost > 0 ? m.TotalCost : (object)DBNull.Value);
            cmd.Parameters.AddWithValue("@ProductionUnit", (object?)m.ProductionUnit ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ProductionUnitsPerPurchaseUnit", (object?)m.ProductionUnitsPerPurchaseUnit ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PaymentMethod", (object?)m.PaymentMethod ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@AmountPaid", m.AmountPaid);
            cmd.Parameters.AddWithValue("@ReceiptUrl", (object?)m.ReceiptUrl ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)m.CreatedBy ?? DBNull.Value);
            await conn.OpenAsync();
            var newId = Convert.ToInt32(await cmd.ExecuteScalarAsync());
            conn.Close();
            await SyncCashAsync(m.FarmId, newId, m.PoultryCashAccountId, setAccount: true, createdBy: m.CreatedBy);
            return newId;
        }

        // Posts / reverses the purchase's cash-out on the chosen PoultryCashAccount.
        // The SP reads the current AmountPaid + account from the row, so callers
        // just say whether to (re)set the account.
        private async Task SyncCashAsync(string farmId, int purchaseId, int? cashAccountId, bool setAccount, string? createdBy)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spPoultryRawMaterialPurchaseCash_Sync", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@PoultryRawMaterialPurchaseId", purchaseId);
            cmd.Parameters.AddWithValue("@PoultryCashAccountId", (object?)cashAccountId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@SetAccount", setAccount);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)createdBy ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task UpdateAsync(PoultryRawMaterialPurchaseModel m)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spPoultryRawMaterialPurchase_Update", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@PoultryRawMaterialPurchaseId", m.PoultryRawMaterialPurchaseId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@SupplierName", (object?)m.SupplierName ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@SupplierId", (object?)m.SupplierId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PurchaseDate", (object?)m.PurchaseDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Quantity", m.Quantity);
            cmd.Parameters.AddWithValue("@UnitCost", m.UnitCost);
            cmd.Parameters.AddWithValue("@TotalCost", m.TotalCost > 0 ? m.TotalCost : (object)DBNull.Value);
            cmd.Parameters.AddWithValue("@ProductionUnit", (object?)m.ProductionUnit ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ProductionUnitsPerPurchaseUnit", (object?)m.ProductionUnitsPerPurchaseUnit ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PaymentMethod", (object?)m.PaymentMethod ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@AmountPaid", m.AmountPaid);
            cmd.Parameters.AddWithValue("@ReceiptUrl", (object?)m.ReceiptUrl ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
            conn.Close();
            await SyncCashAsync(m.FarmId, m.PoultryRawMaterialPurchaseId, m.PoultryCashAccountId, setAccount: true, createdBy: m.CreatedBy);
        }

        public async Task DeleteAsync(int id, string farmId)
        {
            using (var conn = new SqlConnection(_cs))
            using (var cmd = new SqlCommand("spPoultryRawMaterialPurchase_Delete", conn) { CommandType = CommandType.StoredProcedure })
            {
                cmd.Parameters.AddWithValue("@PoultryRawMaterialPurchaseId", id);
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                await conn.OpenAsync();
                await cmd.ExecuteNonQueryAsync();
            }
            // Row is gone now → reverse-only (no repost).
            await SyncCashAsync(farmId, id, null, setAccount: false, createdBy: null);
        }

        public async Task<decimal> PayBalanceAsync(int id, string farmId, decimal amount, string? paymentMethod, DateTime? paymentDate, string? createdBy)
        {
            decimal balance;
            using (var conn = new SqlConnection(_cs))
            using (var cmd = new SqlCommand("spPoultryRawMaterialPurchase_PayBalance", conn) { CommandType = CommandType.StoredProcedure })
            {
                cmd.Parameters.AddWithValue("@PoultryRawMaterialPurchaseId", id);
                cmd.Parameters.AddWithValue("@FarmId", farmId);
                cmd.Parameters.AddWithValue("@Amount", amount);
                cmd.Parameters.AddWithValue("@PaymentMethod", (object?)paymentMethod ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@PaymentDate", (object?)paymentDate ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@CreatedBy", (object?)createdBy ?? DBNull.Value);
                await conn.OpenAsync();
                var result = await cmd.ExecuteScalarAsync();
                balance = result is null || result == DBNull.Value ? 0m : Convert.ToDecimal(result);
            }
            // Re-sync the purchase's cash-out to the new total paid (keep its account).
            await SyncCashAsync(farmId, id, null, setAccount: false, createdBy: createdBy);
            return balance;
        }
    }

    // -------------------------------------------------------------------------
    // Usage history
    // -------------------------------------------------------------------------
    public class PoultryRawMaterialUsageService : IPoultryRawMaterialUsageService
    {
        private readonly string _cs;
        public PoultryRawMaterialUsageService(string cs) => _cs = cs;

        public async Task<List<PoultryRawMaterialUsageModel>> GetHistoryAsync(string farmId, int? itemId, DateTime? fromDate, DateTime? toDate)
        {
            var list = new List<PoultryRawMaterialUsageModel>();
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spPoultryRawMaterialUsage_GetHistory", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@PoultryRawMaterialItemId", (object?)itemId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ToDate", (object?)toDate ?? DBNull.Value);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                list.Add(new PoultryRawMaterialUsageModel
                {
                    PoultryRawMaterialUsageId = r.GetInt32(r.GetOrdinal("PoultryRawMaterialUsageId")),
                    FarmId = r.GetString(r.GetOrdinal("FarmId")),
                    PoultryRawMaterialItemId = r.GetInt32(r.GetOrdinal("PoultryRawMaterialItemId")),
                    ItemName = r.IsDBNull(r.GetOrdinal("ItemName")) ? null : r.GetString(r.GetOrdinal("ItemName")),
                    UnitOfMeasure = r.IsDBNull(r.GetOrdinal("UnitOfMeasure")) ? null : r.GetString(r.GetOrdinal("UnitOfMeasure")),
                    PoultryProductionBatchId = r.IsDBNull(r.GetOrdinal("PoultryProductionBatchId")) ? null : r.GetInt32(r.GetOrdinal("PoultryProductionBatchId")),
                    UsedDate = r.GetDateTime(r.GetOrdinal("UsedDate")),
                    QuantityUsed = r.GetDecimal(r.GetOrdinal("QuantityUsed")),
                    ExpectedQuantityUsed = r.IsDBNull(r.GetOrdinal("ExpectedQuantityUsed")) ? null : r.GetDecimal(r.GetOrdinal("ExpectedQuantityUsed")),
                    Variance = r.GetDecimal(r.GetOrdinal("Variance")),
                    VarianceReason = r.IsDBNull(r.GetOrdinal("VarianceReason")) ? null : r.GetString(r.GetOrdinal("VarianceReason")),
                    UsedByStaffId = r.IsDBNull(r.GetOrdinal("UsedByStaffId")) ? null : r.GetInt32(r.GetOrdinal("UsedByStaffId")),
                    Notes = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
                    CreatedBy = r.IsDBNull(r.GetOrdinal("CreatedBy")) ? null : r.GetString(r.GetOrdinal("CreatedBy")),
                    CreatedAt = r.GetDateTime(r.GetOrdinal("CreatedAt")),
                });
            }
            return list;
        }
    }
}
