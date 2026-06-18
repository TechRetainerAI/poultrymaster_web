using System.Data;
using Microsoft.Data.SqlClient;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IWaterMaintenanceLogService
    {
        Task<List<WaterMaintenanceLogModel>> GetAllAsync(
            string farmId, string? status, string? assetType, DateTime? fromDate, DateTime? toDate);
        Task<WaterMaintenanceLogModel?> GetByIdAsync(int id, string farmId);
        Task<int> InsertAsync(WaterMaintenanceLogModel m);
        Task UpdateAsync(WaterMaintenanceLogModel m);
        Task CompleteAsync(int id, string farmId, string? completedBy, DateTime? completedDate, int? cashAccountId);
        Task DeleteAsync(int id, string farmId);
        Task<List<WaterMaintenanceLogAlertModel>> GetDueAlertsAsync(string farmId);
    }

    public class WaterMaintenanceLogService : IWaterMaintenanceLogService
    {
        private readonly string _cs;
        public WaterMaintenanceLogService(string cs) => _cs = cs;

        public async Task<List<WaterMaintenanceLogModel>> GetAllAsync(
            string farmId, string? status, string? assetType, DateTime? fromDate, DateTime? toDate)
        {
            var list = new List<WaterMaintenanceLogModel>();
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterMaintenanceLog_GetAll", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status",    (object?)status    ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@AssetType", (object?)assetType ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FromDate",  (object?)fromDate  ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ToDate",    (object?)toDate    ?? DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(Read(r));
            return list;
        }

        public async Task<WaterMaintenanceLogModel?> GetByIdAsync(int id, string farmId)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterMaintenanceLog_GetById", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterMaintenanceLogId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Read(r) : null;
        }

        public async Task<int> InsertAsync(WaterMaintenanceLogModel m)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterMaintenanceLog_Insert", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@AssetType", m.AssetType);
            cmd.Parameters.AddWithValue("@AssetId",    (object?)m.AssetId    ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@AssetLabel", (object?)m.AssetLabel ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IssueDate",
                m.IssueDate == default ? (object)DBNull.Value : m.IssueDate);
            cmd.Parameters.AddWithValue("@IssueDescription", m.IssueDescription);
            cmd.Parameters.AddWithValue("@ReportedByWaterStaffId", (object?)m.ReportedByWaterStaffId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@TechnicianName",         (object?)m.TechnicianName         ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@RepairCost", m.RepairCost);
            cmd.Parameters.AddWithValue("@PartsReplaced", (object?)m.PartsReplaced ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DowntimeHours", (object?)m.DowntimeHours ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes",         (object?)m.Notes         ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy",     (object?)m.CreatedBy     ?? DBNull.Value);
            await c.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateAsync(WaterMaintenanceLogModel m)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterMaintenanceLog_Update", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterMaintenanceLogId", m.WaterMaintenanceLogId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@AssetType", m.AssetType);
            cmd.Parameters.AddWithValue("@AssetId",    (object?)m.AssetId    ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@AssetLabel", (object?)m.AssetLabel ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IssueDescription", m.IssueDescription);
            cmd.Parameters.AddWithValue("@ReportedByWaterStaffId", (object?)m.ReportedByWaterStaffId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@TechnicianName",         (object?)m.TechnicianName         ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@RepairCost", m.RepairCost);
            cmd.Parameters.AddWithValue("@PartsReplaced", (object?)m.PartsReplaced ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DowntimeHours", (object?)m.DowntimeHours ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Status", m.Status);
            cmd.Parameters.AddWithValue("@Notes",  (object?)m.Notes ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task CompleteAsync(int id, string farmId, string? completedBy, DateTime? completedDate, int? cashAccountId)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterMaintenanceLog_Complete", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterMaintenanceLogId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@CompletedBy",   (object?)completedBy   ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CompletedDate", (object?)completedDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@WaterCashAccountId", (object?)cashAccountId ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteAsync(int id, string farmId)
        {
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterMaintenanceLog_Delete", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterMaintenanceLogId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<List<WaterMaintenanceLogAlertModel>> GetDueAlertsAsync(string farmId)
        {
            var list = new List<WaterMaintenanceLogAlertModel>();
            using var c = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterMaintenanceLog_DueAlerts", c) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                list.Add(new WaterMaintenanceLogAlertModel
                {
                    AssetType    = r.GetString(r.GetOrdinal("AssetType")),
                    AssetId      = r.GetInt32(r.GetOrdinal("AssetId")),
                    AssetLabel   = r.IsDBNull(r.GetOrdinal("AssetLabel")) ? string.Empty : r.GetString(r.GetOrdinal("AssetLabel")),
                    NextDueDate  = r.GetDateTime(r.GetOrdinal("NextDueDate")),
                    DaysUntilDue = r.GetInt32(r.GetOrdinal("DaysUntilDue")),
                    Severity     = r.GetString(r.GetOrdinal("Severity")),
                });
            }
            return list;
        }

        private static WaterMaintenanceLogModel Read(SqlDataReader r) => new()
        {
            WaterMaintenanceLogId  = r.GetInt32(r.GetOrdinal("WaterMaintenanceLogId")),
            FarmId                 = r.GetString(r.GetOrdinal("FarmId")),
            AssetType              = r.GetString(r.GetOrdinal("AssetType")),
            AssetId                = r.IsDBNull(r.GetOrdinal("AssetId")) ? null : r.GetInt32(r.GetOrdinal("AssetId")),
            AssetLabel             = r.IsDBNull(r.GetOrdinal("AssetLabel")) ? null : r.GetString(r.GetOrdinal("AssetLabel")),
            IssueDate              = r.GetDateTime(r.GetOrdinal("IssueDate")),
            IssueDescription       = r.GetString(r.GetOrdinal("IssueDescription")),
            ReportedByWaterStaffId = r.IsDBNull(r.GetOrdinal("ReportedByWaterStaffId")) ? null : r.GetInt32(r.GetOrdinal("ReportedByWaterStaffId")),
            TechnicianName         = r.IsDBNull(r.GetOrdinal("TechnicianName")) ? null : r.GetString(r.GetOrdinal("TechnicianName")),
            RepairCost             = r.GetDecimal(r.GetOrdinal("RepairCost")),
            PartsReplaced          = r.IsDBNull(r.GetOrdinal("PartsReplaced")) ? null : r.GetString(r.GetOrdinal("PartsReplaced")),
            DowntimeHours          = r.IsDBNull(r.GetOrdinal("DowntimeHours")) ? null : r.GetDecimal(r.GetOrdinal("DowntimeHours")),
            Status                 = r.GetString(r.GetOrdinal("Status")),
            CompletedDate          = r.IsDBNull(r.GetOrdinal("CompletedDate")) ? null : r.GetDateTime(r.GetOrdinal("CompletedDate")),
            WaterCashAccountId     = r.IsDBNull(r.GetOrdinal("WaterCashAccountId")) ? null : r.GetInt32(r.GetOrdinal("WaterCashAccountId")),
            CashAccountName        = r.IsDBNull(r.GetOrdinal("CashAccountName")) ? null : r.GetString(r.GetOrdinal("CashAccountName")),
            CashTransactionWritten = r.GetBoolean(r.GetOrdinal("CashTransactionWritten")),
            Notes                  = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            CreatedBy              = r.IsDBNull(r.GetOrdinal("CreatedBy")) ? null : r.GetString(r.GetOrdinal("CreatedBy")),
            CreatedAt              = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt              = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };
    }
}
