using System.Data;
using Microsoft.Data.SqlClient;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    // =========================================================================
    // Interfaces
    // =========================================================================
    public interface IWaterRawMaterialItemService
    {
        Task<List<WaterRawMaterialItemModel>> GetAllAsync(string farmId);
        Task<WaterRawMaterialItemModel?> GetByIdAsync(int id, string farmId);
        Task<int> InsertAsync(WaterRawMaterialItemModel m);
        Task UpdateAsync(WaterRawMaterialItemModel m);
        Task DeleteAsync(int id, string farmId);
        Task<List<WaterRawMaterialItemModel>> GetLowStockAsync(string farmId);
    }

    public interface IWaterRawMaterialPurchaseService
    {
        Task<List<WaterRawMaterialPurchaseModel>> GetAllAsync(string farmId, DateTime? fromDate, DateTime? toDate);
        Task<int> InsertAsync(WaterRawMaterialPurchaseModel m);
        Task UpdateAsync(WaterRawMaterialPurchaseModel m);
        Task DeleteAsync(int id, string farmId);
        Task<decimal> PayBalanceAsync(int id, string farmId, decimal amount, string? paymentMethod, DateTime? paymentDate, string? createdBy);
    }

    public interface IWaterRawMaterialUsageService
    {
        Task<List<WaterRawMaterialUsageModel>> GetAllAsync(string farmId, int? batchId, DateTime? fromDate, DateTime? toDate);
        Task<int> InsertAsync(WaterRawMaterialUsageModel m);
    }

    public interface IWaterLossRecordService
    {
        Task<List<WaterLossRecordModel>> GetAllAsync(string farmId, string? lossType, DateTime? fromDate, DateTime? toDate);
        Task<int> InsertAsync(WaterLossRecordModel m);
        Task ApproveAsync(int id, string farmId, string? approvedBy);
        // Migration 068: Pending → editable; Approved → Unapprove with reason.
        Task UpdateAsync(WaterLossRecordModel m);
        Task UnapproveAsync(int id, string farmId, string? unapprovedBy, string? reason);
    }

    public interface IWaterDailyClosingService
    {
        Task<List<WaterDailyClosingModel>> GetAllAsync(string farmId, string? status, DateTime? fromDate, DateTime? toDate);
        Task<WaterDailyClosingModel?> GetByIdAsync(int id, string farmId);
        Task<int> InsertAsync(WaterDailyClosingModel m);
        Task<WaterDailyClosingModel?> SubmitAsync(int id, string farmId, WaterDailyClosingSubmitRequest req, string? submittedBy);
        Task ApproveAsync(int id, string farmId, string? approvedBy);
        Task RejectAsync(int id, string farmId, string rejectionReason, string? approvedBy);
        /// <summary>Hard-deletes a Draft or Rejected closing. Returns true if a row was removed; false if the closing
        /// was Submitted/Approved (SP guards against it) or didn't exist.</summary>
        Task<bool> DeleteAsync(int id, string farmId);
        /// <summary>Updates ManagerNotes on a Draft or Rejected closing. Same false-on-immutable contract as DeleteAsync.</summary>
        Task<bool> UpdateNotesAsync(int id, string farmId, string? managerNotes);
        // Migration 068: Reopen an active closing + link a new submission as its superseder.
        Task ReopenAsync(int id, string farmId, string? reopenedBy, string? reason);
        Task LinkSupersededAsync(int newClosingId, string farmId, int previousClosingId);
        // Migration 079: Reopen-then-Insert in one call. Returns new draft id.
        Task<int> RecreateAsync(string farmId, DateTime closingDate, int predecessorClosingId,
                                string? createdBy, decimal actualCashCounted,
                                string? managerNotes, string? differenceReason);
    }

    public interface IWaterReportService
    {
        Task<WaterPeriodPnLModel?> GetPeriodPnLAsync(string farmId, DateTime fromDate, DateTime toDate);
        Task<List<WaterRouteProfitabilityRow>> GetRouteProfitabilityAsync(string farmId, DateTime fromDate, DateTime toDate);
        Task<List<WaterDriverReconciliationRow>> GetDriverReconciliationAsync(string farmId, DateTime fromDate, DateTime toDate);
        Task<List<WaterRawMaterialVarianceRow>> GetRawMaterialVarianceAsync(string farmId, DateTime fromDate, DateTime toDate);
        // Migration 066: Driver Collection Report (Prompt 2 #16)
        Task<WaterDriverCollectionReport> GetDriverCollectionAsync(string farmId, DateTime fromDate, DateTime toDate, int? waterDriverId);
        Task<WaterDashboardExtendedModel> GetDashboardExtendedAsync(string farmId);
        // Migration 057: dashboard intelligence (gap #7)
        Task<List<WaterExpenseByCategoryRow>> GetExpenseByCategoryAsync(string farmId, DateTime fromDate, DateTime toDate);
        Task<List<WaterTopCustomerRow>> GetTopCustomersAsync(string farmId, DateTime fromDate, DateTime toDate, int topN);
        // Migration 081: per-supplier purchase + expense rollup ("Supplier Report").
        Task<List<WaterSupplierActivityRow>> GetSupplierActivityAsync(string farmId, DateTime? fromDate, DateTime? toDate);
    }

    // =========================================================================
    // WaterRawMaterialItemService
    // =========================================================================
    public class WaterRawMaterialItemService : IWaterRawMaterialItemService
    {
        private readonly string _cs;
        public WaterRawMaterialItemService(string cs) => _cs = cs;

        public async Task<List<WaterRawMaterialItemModel>> GetAllAsync(string farmId)
            => await ReadList("spWaterRawMaterialItem_GetAll", _cs, c => c.Parameters.AddWithValue("@FarmId", farmId), Read);

        public async Task<WaterRawMaterialItemModel?> GetByIdAsync(int id, string farmId)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterRawMaterialItem_GetById", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterRawMaterialItemId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Read(r) : null;
        }

        public async Task<int> InsertAsync(WaterRawMaterialItemModel m)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterRawMaterialItem_Insert", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@ItemName", m.ItemName);
            cmd.Parameters.AddWithValue("@Category", m.Category);
            cmd.Parameters.AddWithValue("@UnitOfMeasure", (object?)m.UnitOfMeasure ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@MinimumStockAlert", m.MinimumStockAlert);
            cmd.Parameters.AddWithValue("@CurrentQuantity", m.CurrentQuantity);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateAsync(WaterRawMaterialItemModel m)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterRawMaterialItem_Update", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterRawMaterialItemId", m.WaterRawMaterialItemId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@ItemName", m.ItemName);
            cmd.Parameters.AddWithValue("@Category", m.Category);
            cmd.Parameters.AddWithValue("@UnitOfMeasure", (object?)m.UnitOfMeasure ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@MinimumStockAlert", m.MinimumStockAlert);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteAsync(int id, string farmId)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterRawMaterialItem_Delete", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterRawMaterialItemId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<List<WaterRawMaterialItemModel>> GetLowStockAsync(string farmId)
            => await ReadList("spWaterRawMaterialItem_GetLowStock", _cs, c => c.Parameters.AddWithValue("@FarmId", farmId), Read);

        internal static WaterRawMaterialItemModel Read(SqlDataReader r) => new()
        {
            WaterRawMaterialItemId = r.GetInt32(r.GetOrdinal("WaterRawMaterialItemId")),
            FarmId            = r.GetString(r.GetOrdinal("FarmId")),
            ItemName          = r.GetString(r.GetOrdinal("ItemName")),
            Category          = r.GetString(r.GetOrdinal("Category")),
            UnitOfMeasure     = r.IsDBNull(r.GetOrdinal("UnitOfMeasure")) ? null : r.GetString(r.GetOrdinal("UnitOfMeasure")),
            MinimumStockAlert = r.GetDecimal(r.GetOrdinal("MinimumStockAlert")),
            CurrentQuantity   = r.GetDecimal(r.GetOrdinal("CurrentQuantity")),
            IsActive          = r.GetBoolean(r.GetOrdinal("IsActive")),
            Notes             = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            CreatedAt         = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt         = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };

        internal static async Task<List<T>> ReadList<T>(string sp, string cs, Action<SqlCommand> setParams, Func<SqlDataReader, T> reader)
        {
            var list = new List<T>();
            using var conn = new SqlConnection(cs);
            using var cmd = new SqlCommand(sp, conn) { CommandType = CommandType.StoredProcedure };
            setParams(cmd);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(reader(r));
            return list;
        }

        internal static bool HasCol(SqlDataReader r, string n)
        {
            for (int i = 0; i < r.FieldCount; i++)
                if (r.GetName(i).Equals(n, StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }
    }

    // =========================================================================
    // WaterRawMaterialPurchaseService
    // =========================================================================
    public class WaterRawMaterialPurchaseService : IWaterRawMaterialPurchaseService
    {
        private readonly string _cs;
        public WaterRawMaterialPurchaseService(string cs) => _cs = cs;

        public async Task<List<WaterRawMaterialPurchaseModel>> GetAllAsync(string farmId, DateTime? fromDate, DateTime? toDate)
        {
            return await WaterRawMaterialItemService.ReadList("spWaterRawMaterialPurchase_GetAll", _cs, c =>
            {
                c.Parameters.AddWithValue("@FarmId", farmId);
                c.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value);
                c.Parameters.AddWithValue("@ToDate", (object?)toDate ?? DBNull.Value);
            }, Read);
        }

        public async Task<int> InsertAsync(WaterRawMaterialPurchaseModel m)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterRawMaterialPurchase_Insert", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@WaterRawMaterialItemId", m.WaterRawMaterialItemId);
            cmd.Parameters.AddWithValue("@SupplierName", (object?)m.SupplierName ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PurchaseDate", m.PurchaseDate == default ? (object)DBNull.Value : m.PurchaseDate);
            cmd.Parameters.AddWithValue("@Quantity", m.Quantity);
            cmd.Parameters.AddWithValue("@UnitCost", m.UnitCost);
            cmd.Parameters.AddWithValue("@PaymentMethod", (object?)m.PaymentMethod ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@AmountPaid", m.AmountPaid);
            cmd.Parameters.AddWithValue("@ReceiptUrl", (object?)m.ReceiptUrl ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ReceivedByStaffId", (object?)m.ReceivedByStaffId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)m.CreatedBy ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@SupplierId", (object?)m.SupplierId ?? DBNull.Value);
            // N2: exact total the operator entered (SP falls back to Qty*UnitCost if 0).
            cmd.Parameters.AddWithValue("@TotalCost", m.TotalCost > 0 ? m.TotalCost : (object)DBNull.Value);
            // Caller-chosen cash account for the auto-posted expense; NULL => first active.
            cmd.Parameters.AddWithValue("@WaterCashAccountId", (object?)m.WaterCashAccountId ?? DBNull.Value);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateAsync(WaterRawMaterialPurchaseModel m)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterRawMaterialPurchase_Update", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterRawMaterialPurchaseId", m.WaterRawMaterialPurchaseId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@SupplierName", (object?)m.SupplierName ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PurchaseDate", m.PurchaseDate == default ? (object)DBNull.Value : m.PurchaseDate);
            cmd.Parameters.AddWithValue("@Quantity", m.Quantity);
            cmd.Parameters.AddWithValue("@UnitCost", m.UnitCost);
            cmd.Parameters.AddWithValue("@PaymentMethod", (object?)m.PaymentMethod ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@AmountPaid", m.AmountPaid);
            cmd.Parameters.AddWithValue("@ReceiptUrl", (object?)m.ReceiptUrl ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@SupplierId", (object?)m.SupplierId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@TotalCost", m.TotalCost > 0 ? m.TotalCost : (object)DBNull.Value);
            // Caller-chosen cash account; the Update SP re-points the linked expense to it.
            cmd.Parameters.AddWithValue("@WaterCashAccountId", (object?)m.WaterCashAccountId ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteAsync(int id, string farmId)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterRawMaterialPurchase_Delete", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterRawMaterialPurchaseId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<decimal> PayBalanceAsync(int id, string farmId, decimal amount, string? paymentMethod, DateTime? paymentDate, string? createdBy)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterRawMaterialPurchase_PayBalance", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterRawMaterialPurchaseId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Amount", amount);
            cmd.Parameters.AddWithValue("@PaymentMethod", (object?)paymentMethod ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PaymentDate", (object?)paymentDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)createdBy ?? DBNull.Value);
            await conn.OpenAsync();
            var result = await cmd.ExecuteScalarAsync();
            return result is null || result is DBNull ? 0m : Convert.ToDecimal(result);
        }

        private static WaterRawMaterialPurchaseModel Read(SqlDataReader r) => new()
        {
            WaterRawMaterialPurchaseId = r.GetInt32(r.GetOrdinal("WaterRawMaterialPurchaseId")),
            FarmId                     = r.GetString(r.GetOrdinal("FarmId")),
            WaterRawMaterialItemId     = r.GetInt32(r.GetOrdinal("WaterRawMaterialItemId")),
            ItemName                   = WaterRawMaterialItemService.HasCol(r, "ItemName") && !r.IsDBNull(r.GetOrdinal("ItemName")) ? r.GetString(r.GetOrdinal("ItemName")) : null,
            Category                   = WaterRawMaterialItemService.HasCol(r, "Category") && !r.IsDBNull(r.GetOrdinal("Category")) ? r.GetString(r.GetOrdinal("Category")) : null,
            UnitOfMeasure              = WaterRawMaterialItemService.HasCol(r, "UnitOfMeasure") && !r.IsDBNull(r.GetOrdinal("UnitOfMeasure")) ? r.GetString(r.GetOrdinal("UnitOfMeasure")) : null,
            SupplierName               = r.IsDBNull(r.GetOrdinal("SupplierName")) ? null : r.GetString(r.GetOrdinal("SupplierName")),
            SupplierId                 = WaterRawMaterialItemService.HasCol(r, "SupplierId") && !r.IsDBNull(r.GetOrdinal("SupplierId")) ? r.GetInt32(r.GetOrdinal("SupplierId")) : (int?)null,
            PurchaseDate               = r.GetDateTime(r.GetOrdinal("PurchaseDate")),
            Quantity                   = r.GetDecimal(r.GetOrdinal("Quantity")),
            UnitCost                   = r.GetDecimal(r.GetOrdinal("UnitCost")),
            TotalCost                  = r.GetDecimal(r.GetOrdinal("TotalCost")),
            PaymentMethod              = r.IsDBNull(r.GetOrdinal("PaymentMethod")) ? null : r.GetString(r.GetOrdinal("PaymentMethod")),
            AmountPaid                 = r.GetDecimal(r.GetOrdinal("AmountPaid")),
            // Balance comes from migration 087's altered GetAll SP. Guarded with
            // HasCol so older deployments still read without throwing — they'll
            // just report Balance = 0 (same as before this fix).
            Balance                    = WaterRawMaterialItemService.HasCol(r, "Balance") && !r.IsDBNull(r.GetOrdinal("Balance")) ? r.GetDecimal(r.GetOrdinal("Balance")) : 0m,
            ReceiptUrl                 = r.IsDBNull(r.GetOrdinal("ReceiptUrl")) ? null : r.GetString(r.GetOrdinal("ReceiptUrl")),
            ReceivedByStaffId          = r.IsDBNull(r.GetOrdinal("ReceivedByStaffId")) ? null : r.GetInt32(r.GetOrdinal("ReceivedByStaffId")),
            Notes                      = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            CreatedBy                  = r.IsDBNull(r.GetOrdinal("CreatedBy")) ? null : r.GetString(r.GetOrdinal("CreatedBy")),
            CreatedAt                  = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt                  = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };
    }

    // =========================================================================
    // WaterRawMaterialUsageService
    // =========================================================================
    public class WaterRawMaterialUsageService : IWaterRawMaterialUsageService
    {
        private readonly string _cs;
        public WaterRawMaterialUsageService(string cs) => _cs = cs;

        public async Task<List<WaterRawMaterialUsageModel>> GetAllAsync(string farmId, int? batchId, DateTime? fromDate, DateTime? toDate)
        {
            return await WaterRawMaterialItemService.ReadList("spWaterRawMaterialUsage_GetAll", _cs, c =>
            {
                c.Parameters.AddWithValue("@FarmId", farmId);
                c.Parameters.AddWithValue("@BatchId", (object?)batchId ?? DBNull.Value);
                c.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value);
                c.Parameters.AddWithValue("@ToDate", (object?)toDate ?? DBNull.Value);
            }, Read);
        }

        public async Task<int> InsertAsync(WaterRawMaterialUsageModel m)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterRawMaterialUsage_Insert", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@WaterRawMaterialItemId", m.WaterRawMaterialItemId);
            cmd.Parameters.AddWithValue("@WaterProductionBatchId", (object?)m.WaterProductionBatchId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@UsedDate", m.UsedDate == default ? (object)DBNull.Value : m.UsedDate);
            cmd.Parameters.AddWithValue("@QuantityUsed", m.QuantityUsed);
            cmd.Parameters.AddWithValue("@ExpectedQuantityUsed", (object?)m.ExpectedQuantityUsed ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@VarianceReason", (object?)m.VarianceReason ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@UsedByStaffId", (object?)m.UsedByStaffId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)m.CreatedBy ?? DBNull.Value);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        private static WaterRawMaterialUsageModel Read(SqlDataReader r) => new()
        {
            WaterRawMaterialUsageId = r.GetInt32(r.GetOrdinal("WaterRawMaterialUsageId")),
            FarmId                  = r.GetString(r.GetOrdinal("FarmId")),
            WaterRawMaterialItemId  = r.GetInt32(r.GetOrdinal("WaterRawMaterialItemId")),
            ItemName                = WaterRawMaterialItemService.HasCol(r, "ItemName") && !r.IsDBNull(r.GetOrdinal("ItemName")) ? r.GetString(r.GetOrdinal("ItemName")) : null,
            Category                = WaterRawMaterialItemService.HasCol(r, "Category") && !r.IsDBNull(r.GetOrdinal("Category")) ? r.GetString(r.GetOrdinal("Category")) : null,
            UnitOfMeasure           = WaterRawMaterialItemService.HasCol(r, "UnitOfMeasure") && !r.IsDBNull(r.GetOrdinal("UnitOfMeasure")) ? r.GetString(r.GetOrdinal("UnitOfMeasure")) : null,
            WaterProductionBatchId  = r.IsDBNull(r.GetOrdinal("WaterProductionBatchId")) ? null : r.GetInt32(r.GetOrdinal("WaterProductionBatchId")),
            BatchNumber             = WaterRawMaterialItemService.HasCol(r, "BatchNumber") && !r.IsDBNull(r.GetOrdinal("BatchNumber")) ? r.GetString(r.GetOrdinal("BatchNumber")) : null,
            UsedDate                = r.GetDateTime(r.GetOrdinal("UsedDate")),
            QuantityUsed            = r.GetDecimal(r.GetOrdinal("QuantityUsed")),
            ExpectedQuantityUsed    = r.IsDBNull(r.GetOrdinal("ExpectedQuantityUsed")) ? null : r.GetDecimal(r.GetOrdinal("ExpectedQuantityUsed")),
            Variance                = r.GetDecimal(r.GetOrdinal("Variance")),
            VarianceReason          = r.IsDBNull(r.GetOrdinal("VarianceReason")) ? null : r.GetString(r.GetOrdinal("VarianceReason")),
            UsedByStaffId           = r.IsDBNull(r.GetOrdinal("UsedByStaffId")) ? null : r.GetInt32(r.GetOrdinal("UsedByStaffId")),
            Notes                   = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            CreatedBy               = r.IsDBNull(r.GetOrdinal("CreatedBy")) ? null : r.GetString(r.GetOrdinal("CreatedBy")),
            CreatedAt               = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt               = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };
    }

    // =========================================================================
    // WaterLossRecordService
    // =========================================================================
    public class WaterLossRecordService : IWaterLossRecordService
    {
        private readonly string _cs;
        public WaterLossRecordService(string cs) => _cs = cs;

        public async Task<List<WaterLossRecordModel>> GetAllAsync(string farmId, string? lossType, DateTime? fromDate, DateTime? toDate)
        {
            return await WaterRawMaterialItemService.ReadList("spWaterLossRecord_GetAll", _cs, c =>
            {
                c.Parameters.AddWithValue("@FarmId", farmId);
                c.Parameters.AddWithValue("@LossType", (object?)lossType ?? DBNull.Value);
                c.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value);
                c.Parameters.AddWithValue("@ToDate", (object?)toDate ?? DBNull.Value);
            }, Read);
        }

        public async Task<int> InsertAsync(WaterLossRecordModel m)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterLossRecord_Insert", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@LossDate", m.LossDate == default ? (object)DBNull.Value : m.LossDate);
            cmd.Parameters.AddWithValue("@LossType", m.LossType);
            cmd.Parameters.AddWithValue("@WaterProductId", (object?)m.WaterProductId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@QuantityBags", (object?)m.QuantityBags ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@QuantitySachets", (object?)m.QuantitySachets ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@EstimatedValue", (object?)m.EstimatedValue ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ResponsibleStaffId", (object?)m.ResponsibleStaffId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Reason", (object?)m.Reason ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)m.CreatedBy ?? DBNull.Value);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task ApproveAsync(int id, string farmId, string? approvedBy)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterLossRecord_Approve", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterLossRecordId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // Migration 068 — Pending records can be edited inline.
        public async Task UpdateAsync(WaterLossRecordModel m)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterLossRecord_Update", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterLossRecordId", m.WaterLossRecordId);
            cmd.Parameters.AddWithValue("@FarmId",              m.FarmId);
            cmd.Parameters.AddWithValue("@LossDate",            m.LossDate);
            cmd.Parameters.AddWithValue("@LossType",            m.LossType);
            cmd.Parameters.AddWithValue("@WaterProductId",      (object?)m.WaterProductId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@QuantityBags",        (object?)m.QuantityBags ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@QuantitySachets",     (object?)m.QuantitySachets ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@EstimatedValue",      (object?)m.EstimatedValue ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ResponsibleStaffId",  (object?)m.ResponsibleStaffId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Reason",              (object?)m.Reason ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes",               (object?)m.Notes ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // Migration 068 — Approved → Reopened (Pending). Cash impact reversed
        // by the SP if any. After this the user can edit and Approve again.
        public async Task UnapproveAsync(int id, string farmId, string? unapprovedBy, string? reason)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterLossRecord_Unapprove", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterLossRecordId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@UnapprovedBy", (object?)unapprovedBy ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Reason",       (object?)reason       ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static WaterLossRecordModel Read(SqlDataReader r) => new()
        {
            WaterLossRecordId   = r.GetInt32(r.GetOrdinal("WaterLossRecordId")),
            FarmId              = r.GetString(r.GetOrdinal("FarmId")),
            LossDate            = r.GetDateTime(r.GetOrdinal("LossDate")),
            LossType            = r.GetString(r.GetOrdinal("LossType")),
            WaterProductId      = r.IsDBNull(r.GetOrdinal("WaterProductId")) ? null : r.GetInt32(r.GetOrdinal("WaterProductId")),
            ProductName         = WaterRawMaterialItemService.HasCol(r, "ProductName") && !r.IsDBNull(r.GetOrdinal("ProductName")) ? r.GetString(r.GetOrdinal("ProductName")) : null,
            QuantityBags        = r.IsDBNull(r.GetOrdinal("QuantityBags")) ? null : r.GetDecimal(r.GetOrdinal("QuantityBags")),
            QuantitySachets     = r.IsDBNull(r.GetOrdinal("QuantitySachets")) ? null : r.GetDecimal(r.GetOrdinal("QuantitySachets")),
            EstimatedValue      = r.IsDBNull(r.GetOrdinal("EstimatedValue")) ? null : r.GetDecimal(r.GetOrdinal("EstimatedValue")),
            ResponsibleStaffId  = r.IsDBNull(r.GetOrdinal("ResponsibleStaffId")) ? null : r.GetInt32(r.GetOrdinal("ResponsibleStaffId")),
            Reason              = r.IsDBNull(r.GetOrdinal("Reason")) ? null : r.GetString(r.GetOrdinal("Reason")),
            Status              = r.GetString(r.GetOrdinal("Status")),
            ApprovedBy          = r.IsDBNull(r.GetOrdinal("ApprovedBy")) ? null : r.GetString(r.GetOrdinal("ApprovedBy")),
            Notes               = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            CreatedBy           = r.IsDBNull(r.GetOrdinal("CreatedBy")) ? null : r.GetString(r.GetOrdinal("CreatedBy")),
            CreatedAt           = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt           = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };
    }

    // =========================================================================
    // WaterDailyClosingService
    // =========================================================================
    public class WaterDailyClosingService : IWaterDailyClosingService
    {
        private readonly string _cs;
        public WaterDailyClosingService(string cs) => _cs = cs;

        public async Task<List<WaterDailyClosingModel>> GetAllAsync(string farmId, string? status, DateTime? fromDate, DateTime? toDate)
        {
            return await WaterRawMaterialItemService.ReadList("spWaterDailyClosing_GetAll", _cs, c =>
            {
                c.Parameters.AddWithValue("@FarmId", farmId);
                c.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);
                c.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value);
                c.Parameters.AddWithValue("@ToDate", (object?)toDate ?? DBNull.Value);
            }, Read);
        }

        public async Task<WaterDailyClosingModel?> GetByIdAsync(int id, string farmId)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterDailyClosing_GetById", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterDailyClosingId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Read(r) : null;
        }

        public async Task<int> InsertAsync(WaterDailyClosingModel m)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterDailyClosing_Insert", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@ClosingDate", m.ClosingDate);
            cmd.Parameters.AddWithValue("@ActualCashCounted", m.ActualCashCounted);
            cmd.Parameters.AddWithValue("@ManagerNotes", (object?)m.ManagerNotes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DifferenceReason", (object?)m.DifferenceReason ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)m.CreatedBy ?? DBNull.Value);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task<WaterDailyClosingModel?> SubmitAsync(int id, string farmId, WaterDailyClosingSubmitRequest req, string? submittedBy)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterDailyClosing_Submit", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterDailyClosingId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ActualCashCounted", (object?)req.ActualCashCounted ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ManagerNotes", (object?)req.ManagerNotes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DifferenceReason", (object?)req.DifferenceReason ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@SubmittedBy", (object?)submittedBy ?? DBNull.Value);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Read(r) : null;
        }

        public async Task ApproveAsync(int id, string farmId, string? approvedBy)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterDailyClosing_Approve", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterDailyClosingId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task RejectAsync(int id, string farmId, string rejectionReason, string? approvedBy)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterDailyClosing_Reject", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterDailyClosingId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@RejectionReason", rejectionReason);
            cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<bool> DeleteAsync(int id, string farmId)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterDailyClosing_Delete", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterDailyClosingId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            // SP returns RowsDeleted scalar; 0 means the SP's WHERE rejected it (not Draft/Rejected, or wrong farm).
            var result = await cmd.ExecuteScalarAsync();
            return Convert.ToInt32(result ?? 0) > 0;
        }

        public async Task<bool> UpdateNotesAsync(int id, string farmId, string? managerNotes)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterDailyClosing_UpdateNotes", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterDailyClosingId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ManagerNotes", (object?)managerNotes ?? DBNull.Value);
            await conn.OpenAsync();
            var result = await cmd.ExecuteScalarAsync();
            return Convert.ToInt32(result ?? 0) > 0;
        }

        // Migration 068 — Reopen an active closing (marks IsActive=0, Status='Reopened')
        // and link a new closing as its successor (SupersededByClosingId).
        public async Task ReopenAsync(int id, string farmId, string? reopenedBy, string? reason)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterDailyClosing_Reopen", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterDailyClosingId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ReopenedBy", (object?)reopenedBy ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Reason",     (object?)reason     ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task LinkSupersededAsync(int newClosingId, string farmId, int previousClosingId)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterDailyClosing_LinkSuperseded", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterDailyClosingId", previousClosingId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@SupersededByClosingId", newClosingId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // Migration 079 — single-shot Recreate. The SP validates the predecessor
        // is IsActive=0, creates a fresh Draft, and links them via SupersededByClosingId.
        public async Task<int> RecreateAsync(string farmId, DateTime closingDate, int predecessorClosingId,
                                             string? createdBy, decimal actualCashCounted,
                                             string? managerNotes, string? differenceReason)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterDailyClosing_Recreate", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ClosingDate", closingDate.Date);
            cmd.Parameters.AddWithValue("@PredecessorClosingId", predecessorClosingId);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)createdBy ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ActualCashCounted", actualCashCounted);
            cmd.Parameters.AddWithValue("@ManagerNotes", (object?)managerNotes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DifferenceReason", (object?)differenceReason ?? DBNull.Value);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        private static WaterDailyClosingModel Read(SqlDataReader r) => new()
        {
            WaterDailyClosingId  = r.GetInt32(r.GetOrdinal("WaterDailyClosingId")),
            FarmId               = r.GetString(r.GetOrdinal("FarmId")),
            ClosingDate          = r.GetDateTime(r.GetOrdinal("ClosingDate")),
            OpeningStockBags     = r.GetDecimal(r.GetOrdinal("OpeningStockBags")),
            BagsProduced         = r.GetDecimal(r.GetOrdinal("BagsProduced")),
            BagsSold             = r.GetDecimal(r.GetOrdinal("BagsSold")),
            BagsReturned         = r.GetDecimal(r.GetOrdinal("BagsReturned")),
            BagsDamaged          = r.GetDecimal(r.GetOrdinal("BagsDamaged")),
            ClosingStockBags     = r.GetDecimal(r.GetOrdinal("ClosingStockBags")),
            TotalIncome          = r.GetDecimal(r.GetOrdinal("TotalIncome")),
            TotalExpenses        = r.GetDecimal(r.GetOrdinal("TotalExpenses")),
            TotalProductionCost  = r.GetDecimal(r.GetOrdinal("TotalProductionCost")),
            CashAtHand           = r.GetDecimal(r.GetOrdinal("CashAtHand")),
            ActualCashCounted    = r.GetDecimal(r.GetOrdinal("ActualCashCounted")),
            CashDifference       = r.GetDecimal(r.GetOrdinal("CashDifference")),
            CreditSales          = r.GetDecimal(r.GetOrdinal("CreditSales")),
            CustomerCollections  = r.GetDecimal(r.GetOrdinal("CustomerCollections")),
            DriverShortagesTotal = r.GetDecimal(r.GetOrdinal("DriverShortagesTotal")),
            MoMoBalance          = WaterRawMaterialItemService.HasCol(r, "MoMoBalance") && !r.IsDBNull(r.GetOrdinal("MoMoBalance")) ? r.GetDecimal(r.GetOrdinal("MoMoBalance")) : 0m,
            BankBalance          = WaterRawMaterialItemService.HasCol(r, "BankBalance") && !r.IsDBNull(r.GetOrdinal("BankBalance")) ? r.GetDecimal(r.GetOrdinal("BankBalance")) : 0m,
            ManagerNotes         = r.IsDBNull(r.GetOrdinal("ManagerNotes")) ? null : r.GetString(r.GetOrdinal("ManagerNotes")),
            DifferenceReason     = r.IsDBNull(r.GetOrdinal("DifferenceReason")) ? null : r.GetString(r.GetOrdinal("DifferenceReason")),
            Status               = r.GetString(r.GetOrdinal("Status")),
            CreatedBy            = r.IsDBNull(r.GetOrdinal("CreatedBy")) ? null : r.GetString(r.GetOrdinal("CreatedBy")),
            SubmittedBy          = r.IsDBNull(r.GetOrdinal("SubmittedBy")) ? null : r.GetString(r.GetOrdinal("SubmittedBy")),
            SubmittedAt          = r.IsDBNull(r.GetOrdinal("SubmittedAt")) ? null : r.GetDateTime(r.GetOrdinal("SubmittedAt")),
            ApprovedBy           = r.IsDBNull(r.GetOrdinal("ApprovedBy")) ? null : r.GetString(r.GetOrdinal("ApprovedBy")),
            ApprovedAt           = r.IsDBNull(r.GetOrdinal("ApprovedAt")) ? null : r.GetDateTime(r.GetOrdinal("ApprovedAt")),
            RejectionReason      = r.IsDBNull(r.GetOrdinal("RejectionReason")) ? null : r.GetString(r.GetOrdinal("RejectionReason")),
            CreatedAt            = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt            = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
            // Migration 068 — reopen/resubmit support. HasCol guards keep the
            // Read working on databases that haven't applied 068 yet.
            IsActive              = WaterRawMaterialItemService.HasCol(r, "IsActive") && !r.IsDBNull(r.GetOrdinal("IsActive")) ? r.GetBoolean(r.GetOrdinal("IsActive")) : true,
            SupersededByClosingId = WaterRawMaterialItemService.HasCol(r, "SupersededByClosingId") && !r.IsDBNull(r.GetOrdinal("SupersededByClosingId")) ? r.GetInt32(r.GetOrdinal("SupersededByClosingId")) : (int?)null,
            ReopenedBy            = WaterRawMaterialItemService.HasCol(r, "ReopenedBy") && !r.IsDBNull(r.GetOrdinal("ReopenedBy")) ? r.GetString(r.GetOrdinal("ReopenedBy")) : null,
            ReopenedAt            = WaterRawMaterialItemService.HasCol(r, "ReopenedAt") && !r.IsDBNull(r.GetOrdinal("ReopenedAt")) ? r.GetDateTime(r.GetOrdinal("ReopenedAt")) : (DateTime?)null,
            ReopenReason          = WaterRawMaterialItemService.HasCol(r, "ReopenReason") && !r.IsDBNull(r.GetOrdinal("ReopenReason")) ? r.GetString(r.GetOrdinal("ReopenReason")) : null,
        };
    }

    // =========================================================================
    // WaterReportService
    // =========================================================================
    public class WaterReportService : IWaterReportService
    {
        private readonly string _cs;
        public WaterReportService(string cs) => _cs = cs;

        // Reads a numeric column as decimal regardless of whether SQL Server
        // returned it as Int32 (e.g. SUM of INT columns) or Decimal. r.GetDecimal
        // throws "Unable to cast Int32 to Decimal" on integer columns.
        private static decimal Dec(SqlDataReader r, string col)
        {
            var o = r.GetOrdinal(col);
            return r.IsDBNull(o) ? 0m : Convert.ToDecimal(r.GetValue(o));
        }

        public async Task<WaterPeriodPnLModel?> GetPeriodPnLAsync(string farmId, DateTime fromDate, DateTime toDate)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterReport_PeriodPnL", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@FromDate", fromDate);
            cmd.Parameters.AddWithValue("@ToDate", toDate);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            if (!await r.ReadAsync()) return null;
            return new WaterPeriodPnLModel
            {
                PeriodStart      = r.GetDateTime(r.GetOrdinal("PeriodStart")),
                PeriodEnd        = r.GetDateTime(r.GetOrdinal("PeriodEnd")),
                TotalIncome      = r.GetDecimal(r.GetOrdinal("TotalIncome")),
                TotalExpenses    = r.GetDecimal(r.GetOrdinal("TotalExpenses")),
                RawMaterialCost  = r.GetDecimal(r.GetOrdinal("RawMaterialCost")),
                ProductionCost   = r.GetDecimal(r.GetOrdinal("ProductionCost")),
                TotalLosses      = r.GetDecimal(r.GetOrdinal("TotalLosses")),
                NetProfit        = r.GetDecimal(r.GetOrdinal("NetProfit")),
                ProfitMarginPct  = r.GetDecimal(r.GetOrdinal("ProfitMarginPct")),
                BagsProduced     = r.GetInt32(r.GetOrdinal("BagsProduced")),
                BagsSold         = r.GetInt32(r.GetOrdinal("BagsSold")),
                AvgProfitPerBag  = r.GetDecimal(r.GetOrdinal("AvgProfitPerBag")),
            };
        }

        public async Task<List<WaterRouteProfitabilityRow>> GetRouteProfitabilityAsync(string farmId, DateTime fromDate, DateTime toDate)
        {
            return await WaterRawMaterialItemService.ReadList("spWaterReport_RouteProfitability", _cs, c =>
            {
                c.Parameters.AddWithValue("@FarmId", farmId);
                c.Parameters.AddWithValue("@FromDate", fromDate);
                c.Parameters.AddWithValue("@ToDate", toDate);
            }, r => new WaterRouteProfitabilityRow
            {
                WaterRouteId      = r.GetInt32(r.GetOrdinal("WaterRouteId")),
                RouteName         = r.GetString(r.GetOrdinal("RouteName")),
                // The bag columns are SUM()s of INT columns, so SQL Server returns
                // them as Int32 — r.GetDecimal() throws "Unable to cast Int32 to
                // Decimal". Convert.ToDecimal tolerates both int and decimal.
                TotalBagsLoaded   = Dec(r, "TotalBagsLoaded"),
                TotalBagsSold     = Dec(r, "TotalBagsSold"),
                TotalBagsReturned = Dec(r, "TotalBagsReturned"),
                TotalBagsLost     = Dec(r, "TotalBagsLost"),
                TotalRevenue      = Dec(r, "TotalRevenue"),
                TotalShortages    = Dec(r, "TotalShortages"),
                TotalOverages     = Dec(r, "TotalOverages"),
                NetRouteIncome    = Dec(r, "NetRouteIncome"),
            });
        }

        public async Task<List<WaterDriverReconciliationRow>> GetDriverReconciliationAsync(string farmId, DateTime fromDate, DateTime toDate)
        {
            return await WaterRawMaterialItemService.ReadList("spWaterReport_DriverReconciliation", _cs, c =>
            {
                c.Parameters.AddWithValue("@FarmId", farmId);
                c.Parameters.AddWithValue("@FromDate", fromDate);
                c.Parameters.AddWithValue("@ToDate", toDate);
            }, r => new WaterDriverReconciliationRow
            {
                WaterDriverId       = r.GetInt32(r.GetOrdinal("WaterDriverId")),
                DriverName          = r.GetString(r.GetOrdinal("DriverName")),
                PhoneNumber         = r.IsDBNull(r.GetOrdinal("PhoneNumber")) ? null : r.GetString(r.GetOrdinal("PhoneNumber")),
                TotalBagsLoaded     = r.GetDecimal(r.GetOrdinal("TotalBagsLoaded")),
                TotalBagsSold       = r.GetDecimal(r.GetOrdinal("TotalBagsSold")),
                TotalBagsReturned   = r.GetDecimal(r.GetOrdinal("TotalBagsReturned")),
                TotalBagsLost       = r.GetDecimal(r.GetOrdinal("TotalBagsLost")),
                ExpectedRevenue     = r.GetDecimal(r.GetOrdinal("ExpectedRevenue")),
                ActualAccountedFor  = r.GetDecimal(r.GetOrdinal("ActualAccountedFor")),
                TotalShortages      = r.GetDecimal(r.GetOrdinal("TotalShortages")),
                ShortageOccurrences = r.GetInt32(r.GetOrdinal("ShortageOccurrences")),
            });
        }

        public async Task<List<WaterRawMaterialVarianceRow>> GetRawMaterialVarianceAsync(string farmId, DateTime fromDate, DateTime toDate)
        {
            return await WaterRawMaterialItemService.ReadList("spWaterReport_RawMaterialVariance", _cs, c =>
            {
                c.Parameters.AddWithValue("@FarmId", farmId);
                c.Parameters.AddWithValue("@FromDate", fromDate);
                c.Parameters.AddWithValue("@ToDate", toDate);
            }, r => new WaterRawMaterialVarianceRow
            {
                WaterRawMaterialItemId = r.GetInt32(r.GetOrdinal("WaterRawMaterialItemId")),
                ItemName               = r.GetString(r.GetOrdinal("ItemName")),
                Category               = r.GetString(r.GetOrdinal("Category")),
                UnitOfMeasure          = r.IsDBNull(r.GetOrdinal("UnitOfMeasure")) ? null : r.GetString(r.GetOrdinal("UnitOfMeasure")),
                TotalExpected          = r.GetDecimal(r.GetOrdinal("TotalExpected")),
                TotalActual            = r.GetDecimal(r.GetOrdinal("TotalActual")),
                TotalVariance          = r.GetDecimal(r.GetOrdinal("TotalVariance")),
                UsageCount             = r.GetInt32(r.GetOrdinal("UsageCount")),
            });
        }

        public async Task<WaterDriverCollectionReport> GetDriverCollectionAsync(string farmId, DateTime fromDate, DateTime toDate, int? waterDriverId)
        {
            var report = new WaterDriverCollectionReport();
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterReport_DriverCollection", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@FromDate", fromDate);
            cmd.Parameters.AddWithValue("@ToDate", toDate);
            cmd.Parameters.AddWithValue("@WaterDriverId", (object?)waterDriverId ?? DBNull.Value);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();

            while (await r.ReadAsync())
            {
                report.Detail.Add(new WaterDriverCollectionDetailRow
                {
                    WaterDriverId   = r.IsDBNull(r.GetOrdinal("WaterDriverId")) ? null : r.GetInt32(r.GetOrdinal("WaterDriverId")),
                    DriverName      = r.IsDBNull(r.GetOrdinal("DriverName")) ? null : r.GetString(r.GetOrdinal("DriverName")),
                    WaterProductId  = r.GetInt32(r.GetOrdinal("WaterProductId")),
                    ProductName     = r.IsDBNull(r.GetOrdinal("ProductName")) ? null : r.GetString(r.GetOrdinal("ProductName")),
                    BagsLoaded      = r.GetInt32(r.GetOrdinal("BagsLoaded")),
                    BagsSold        = r.GetInt32(r.GetOrdinal("BagsSold")),
                    BagsReturned    = r.GetInt32(r.GetOrdinal("BagsReturned")),
                    BagsDamaged     = r.GetInt32(r.GetOrdinal("BagsDamaged")),
                    ExpectedCash    = r.GetDecimal(r.GetOrdinal("ExpectedCash")),
                    SalesValue      = r.GetDecimal(r.GetOrdinal("SalesValue")),
                });
            }
            if (await r.NextResultAsync())
            {
                while (await r.ReadAsync())
                {
                    report.Totals.Add(new WaterDriverCollectionTotalsRow
                    {
                        WaterDriverId   = r.IsDBNull(r.GetOrdinal("WaterDriverId")) ? null : r.GetInt32(r.GetOrdinal("WaterDriverId")),
                        DriverName      = r.IsDBNull(r.GetOrdinal("DriverName")) ? null : r.GetString(r.GetOrdinal("DriverName")),
                        DeliveryRuns    = r.GetInt32(r.GetOrdinal("DeliveryRuns")),
                        ReconciledRuns  = r.GetInt32(r.GetOrdinal("ReconciledRuns")),
                        CashCollected   = r.GetDecimal(r.GetOrdinal("CashCollected")),
                        MoMoCollected   = r.GetDecimal(r.GetOrdinal("MoMoCollected")),
                        BankCollected   = r.GetDecimal(r.GetOrdinal("BankCollected")),
                        CreditSales     = r.GetDecimal(r.GetOrdinal("CreditSales")),
                        Shortage        = r.GetDecimal(r.GetOrdinal("Shortage")),
                        Overage         = r.GetDecimal(r.GetOrdinal("Overage")),
                    });
                }
            }
            return report;
        }

        public async Task<WaterDashboardExtendedModel> GetDashboardExtendedAsync(string farmId)
        {
            var model = new WaterDashboardExtendedModel();
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterReport_DashboardExtended", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            if (await r.ReadAsync())
            {
                model.Today = new WaterDashboardExtendedToday
                {
                    TodayBagsProduced      = r.GetDecimal(r.GetOrdinal("TodayBagsProduced")),
                    TodayBagsSold          = r.GetDecimal(r.GetOrdinal("TodayBagsSold")),
                    TodayRevenue           = r.GetDecimal(r.GetOrdinal("TodayRevenue")),
                    TodayProductionCost    = r.GetDecimal(r.GetOrdinal("TodayProductionCost")),
                    BagsOnHand             = r.GetDecimal(r.GetOrdinal("BagsOnHand")),
                    TotalCustomerDebt      = r.GetDecimal(r.GetOrdinal("TotalCustomerDebt")),
                    PendingDriverShortages = r.GetDecimal(r.GetOrdinal("PendingDriverShortages")),
                };
            }
            if (await r.NextResultAsync() && await r.ReadAsync())
            {
                model.Alerts = new WaterDashboardExtendedAlerts
                {
                    LowRawMaterialCount         = r.GetInt32(r.GetOrdinal("LowRawMaterialCount")),
                    PendingShortagesCount       = r.GetInt32(r.GetOrdinal("PendingShortagesCount")),
                    DraftBatchesCount           = r.GetInt32(r.GetOrdinal("DraftBatchesCount")),
                    LoadingsAwaitingReturnCount = r.GetInt32(r.GetOrdinal("LoadingsAwaitingReturnCount")),
                    DraftReturnsCount           = r.GetInt32(r.GetOrdinal("DraftReturnsCount")),
                    MachinesDownCount           = r.GetInt32(r.GetOrdinal("MachinesDownCount")),
                    VehiclesDownCount           = r.GetInt32(r.GetOrdinal("VehiclesDownCount")),
                };
            }
            return model;
        }

        // Migration 057: dashboard intelligence (gap #7 — owner-intelligence cards)

        public async Task<List<WaterExpenseByCategoryRow>> GetExpenseByCategoryAsync(string farmId, DateTime fromDate, DateTime toDate)
        {
            return await WaterRawMaterialItemService.ReadList("spWaterReport_ExpenseByCategory", _cs, c =>
            {
                c.Parameters.AddWithValue("@FarmId", farmId);
                c.Parameters.AddWithValue("@FromDate", fromDate);
                c.Parameters.AddWithValue("@ToDate", toDate);
            }, r => new WaterExpenseByCategoryRow
            {
                WaterExpenseCategoryId = r.GetInt32(r.GetOrdinal("WaterExpenseCategoryId")),
                CategoryName           = r.GetString(r.GetOrdinal("CategoryName")),
                ExpenseCount           = r.GetInt32(r.GetOrdinal("ExpenseCount")),
                TotalAmount            = r.GetDecimal(r.GetOrdinal("TotalAmount")),
            });
        }

        public async Task<List<WaterSupplierActivityRow>> GetSupplierActivityAsync(string farmId, DateTime? fromDate, DateTime? toDate)
        {
            return await WaterRawMaterialItemService.ReadList("spWaterReport_SupplierActivity", _cs, c =>
            {
                c.Parameters.AddWithValue("@FarmId", farmId);
                c.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value);
                c.Parameters.AddWithValue("@ToDate",   (object?)toDate   ?? DBNull.Value);
            }, r => new WaterSupplierActivityRow
            {
                WaterSupplierId     = r.GetInt32(r.GetOrdinal("WaterSupplierId")),
                SupplierName        = r.GetString(r.GetOrdinal("SupplierName")),
                SupplierType        = r.IsDBNull(r.GetOrdinal("SupplierType"))   ? null : r.GetString(r.GetOrdinal("SupplierType")),
                ContactPerson       = r.IsDBNull(r.GetOrdinal("ContactPerson"))  ? null : r.GetString(r.GetOrdinal("ContactPerson")),
                Phone               = r.IsDBNull(r.GetOrdinal("Phone"))          ? null : r.GetString(r.GetOrdinal("Phone")),
                Email               = r.IsDBNull(r.GetOrdinal("Email"))          ? null : r.GetString(r.GetOrdinal("Email")),
                TotalPurchaseAmount = r.GetDecimal(r.GetOrdinal("TotalPurchaseAmount")),
                PurchaseCount       = r.GetInt32(r.GetOrdinal("PurchaseCount")),
                LastPurchaseDate    = r.IsDBNull(r.GetOrdinal("LastPurchaseDate")) ? null : r.GetDateTime(r.GetOrdinal("LastPurchaseDate")),
                TotalExpenseAmount  = r.GetDecimal(r.GetOrdinal("TotalExpenseAmount")),
                ExpenseCount        = r.GetInt32(r.GetOrdinal("ExpenseCount")),
                LastExpenseDate     = r.IsDBNull(r.GetOrdinal("LastExpenseDate")) ? null : r.GetDateTime(r.GetOrdinal("LastExpenseDate")),
                OutstandingBalance  = r.GetDecimal(r.GetOrdinal("OutstandingBalance")),
            });
        }

        public async Task<List<WaterTopCustomerRow>> GetTopCustomersAsync(string farmId, DateTime fromDate, DateTime toDate, int topN)
        {
            return await WaterRawMaterialItemService.ReadList("spWaterReport_TopCustomers", _cs, c =>
            {
                c.Parameters.AddWithValue("@FarmId", farmId);
                c.Parameters.AddWithValue("@FromDate", fromDate);
                c.Parameters.AddWithValue("@ToDate", toDate);
                c.Parameters.AddWithValue("@TopN", topN);
            }, r => new WaterTopCustomerRow
            {
                WaterCustomerId    = r.GetInt32(r.GetOrdinal("WaterCustomerId")),
                CustomerName       = r.GetString(r.GetOrdinal("CustomerName")),
                PhoneNumber        = r.IsDBNull(r.GetOrdinal("PhoneNumber")) ? null : r.GetString(r.GetOrdinal("PhoneNumber")),
                SalesCount         = r.GetInt32(r.GetOrdinal("SalesCount")),
                TotalSales         = r.GetDecimal(r.GetOrdinal("TotalSales")),
                TotalPaid          = r.GetDecimal(r.GetOrdinal("TotalPaid")),
                OutstandingBalance = r.GetDecimal(r.GetOrdinal("OutstandingBalance")),
            });
        }
    }
}
