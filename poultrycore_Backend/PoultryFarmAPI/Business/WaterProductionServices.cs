using System.Data;
using System.Data.SqlClient;
using System.Text.Json;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    // =========================================================================
    // WaterBoreholeService
    // =========================================================================
    public class WaterBoreholeService : IWaterBoreholeService
    {
        private readonly string _cs;
        public WaterBoreholeService(string cs) => _cs = cs;

        public async Task<List<WaterBoreholeModel>> GetAllAsync(string farmId)
        {
            var list = new List<WaterBoreholeModel>();
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterBorehole_GetAll", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(Read(r));
            return list;
        }

        public async Task<WaterBoreholeModel?> GetByIdAsync(int id, string farmId)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterBorehole_GetById", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterBoreholeId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Read(r) : null;
        }

        public async Task<int> InsertAsync(WaterBoreholeModel m)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterBorehole_Insert", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@BoreholeName", m.BoreholeName);
            cmd.Parameters.AddWithValue("@Location", (object?)m.Location ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PumpType", (object?)m.PumpType ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PumpCapacity", (object?)m.PumpCapacity ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@TankCapacity", (object?)m.TankCapacity ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@WaterTreatmentMethod", (object?)m.WaterTreatmentMethod ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FiltrationSystem", (object?)m.FiltrationSystem ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@UVSterilizationAvailable", m.UVSterilizationAvailable);
            cmd.Parameters.AddWithValue("@MaintenanceFrequencyDays", (object?)m.MaintenanceFrequencyDays ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@LastMaintenanceDate", (object?)m.LastMaintenanceDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@NextMaintenanceDate", (object?)m.NextMaintenanceDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@WaterQualityTestDueDate", (object?)m.WaterQualityTestDueDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Status", m.Status);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateAsync(WaterBoreholeModel m)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterBorehole_Update", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterBoreholeId", m.WaterBoreholeId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@BoreholeName", m.BoreholeName);
            cmd.Parameters.AddWithValue("@Location", (object?)m.Location ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PumpType", (object?)m.PumpType ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PumpCapacity", (object?)m.PumpCapacity ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@TankCapacity", (object?)m.TankCapacity ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@WaterTreatmentMethod", (object?)m.WaterTreatmentMethod ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FiltrationSystem", (object?)m.FiltrationSystem ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@UVSterilizationAvailable", m.UVSterilizationAvailable);
            cmd.Parameters.AddWithValue("@MaintenanceFrequencyDays", (object?)m.MaintenanceFrequencyDays ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@LastMaintenanceDate", (object?)m.LastMaintenanceDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@NextMaintenanceDate", (object?)m.NextMaintenanceDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@WaterQualityTestDueDate", (object?)m.WaterQualityTestDueDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Status", m.Status);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteAsync(int id, string farmId)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterBorehole_Delete", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterBoreholeId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static WaterBoreholeModel Read(SqlDataReader r) => new()
        {
            WaterBoreholeId          = r.GetInt32(r.GetOrdinal("WaterBoreholeId")),
            FarmId                   = r.GetString(r.GetOrdinal("FarmId")),
            BoreholeName             = r.GetString(r.GetOrdinal("BoreholeName")),
            Location                 = r.IsDBNull(r.GetOrdinal("Location")) ? null : r.GetString(r.GetOrdinal("Location")),
            PumpType                 = r.IsDBNull(r.GetOrdinal("PumpType")) ? null : r.GetString(r.GetOrdinal("PumpType")),
            PumpCapacity             = r.IsDBNull(r.GetOrdinal("PumpCapacity")) ? null : r.GetString(r.GetOrdinal("PumpCapacity")),
            TankCapacity             = r.IsDBNull(r.GetOrdinal("TankCapacity")) ? null : r.GetString(r.GetOrdinal("TankCapacity")),
            WaterTreatmentMethod     = r.IsDBNull(r.GetOrdinal("WaterTreatmentMethod")) ? null : r.GetString(r.GetOrdinal("WaterTreatmentMethod")),
            FiltrationSystem         = r.IsDBNull(r.GetOrdinal("FiltrationSystem")) ? null : r.GetString(r.GetOrdinal("FiltrationSystem")),
            UVSterilizationAvailable = r.GetBoolean(r.GetOrdinal("UVSterilizationAvailable")),
            MaintenanceFrequencyDays = r.IsDBNull(r.GetOrdinal("MaintenanceFrequencyDays")) ? null : r.GetInt32(r.GetOrdinal("MaintenanceFrequencyDays")),
            LastMaintenanceDate      = r.IsDBNull(r.GetOrdinal("LastMaintenanceDate")) ? null : r.GetDateTime(r.GetOrdinal("LastMaintenanceDate")),
            NextMaintenanceDate      = r.IsDBNull(r.GetOrdinal("NextMaintenanceDate")) ? null : r.GetDateTime(r.GetOrdinal("NextMaintenanceDate")),
            WaterQualityTestDueDate  = r.IsDBNull(r.GetOrdinal("WaterQualityTestDueDate")) ? null : r.GetDateTime(r.GetOrdinal("WaterQualityTestDueDate")),
            Status                   = r.GetString(r.GetOrdinal("Status")),
            Notes                    = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            CreatedAt                = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt                = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };
    }

    // =========================================================================
    // WaterMachineService
    // =========================================================================
    public class WaterMachineService : IWaterMachineService
    {
        private readonly string _cs;
        public WaterMachineService(string cs) => _cs = cs;

        public async Task<List<WaterMachineModel>> GetAllAsync(string farmId)
        {
            var list = new List<WaterMachineModel>();
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterMachine_GetAll", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(Read(r));
            return list;
        }

        public async Task<WaterMachineModel?> GetByIdAsync(int id, string farmId)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterMachine_GetById", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterMachineId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Read(r) : null;
        }

        public async Task<int> InsertAsync(WaterMachineModel m)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterMachine_Insert", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@MachineName", m.MachineName);
            cmd.Parameters.AddWithValue("@MachineNumber", (object?)m.MachineNumber ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@MachineType", (object?)m.MachineType ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Manufacturer", (object?)m.Manufacturer ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PurchaseDate", (object?)m.PurchaseDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CapacityPerHour", (object?)m.CapacityPerHour ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@AssignedOperatorStaffId", (object?)m.AssignedOperatorStaffId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@MaintenanceFrequencyDays", (object?)m.MaintenanceFrequencyDays ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@LastMaintenanceDate", (object?)m.LastMaintenanceDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@NextMaintenanceDate", (object?)m.NextMaintenanceDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Status", m.Status);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateAsync(WaterMachineModel m)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterMachine_Update", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterMachineId", m.WaterMachineId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@MachineName", m.MachineName);
            cmd.Parameters.AddWithValue("@MachineNumber", (object?)m.MachineNumber ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@MachineType", (object?)m.MachineType ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Manufacturer", (object?)m.Manufacturer ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PurchaseDate", (object?)m.PurchaseDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CapacityPerHour", (object?)m.CapacityPerHour ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@AssignedOperatorStaffId", (object?)m.AssignedOperatorStaffId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@MaintenanceFrequencyDays", (object?)m.MaintenanceFrequencyDays ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@LastMaintenanceDate", (object?)m.LastMaintenanceDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@NextMaintenanceDate", (object?)m.NextMaintenanceDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Status", m.Status);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteAsync(int id, string farmId)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterMachine_Delete", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterMachineId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static WaterMachineModel Read(SqlDataReader r) => new()
        {
            WaterMachineId           = r.GetInt32(r.GetOrdinal("WaterMachineId")),
            FarmId                   = r.GetString(r.GetOrdinal("FarmId")),
            MachineName              = r.GetString(r.GetOrdinal("MachineName")),
            MachineNumber            = r.IsDBNull(r.GetOrdinal("MachineNumber")) ? null : r.GetString(r.GetOrdinal("MachineNumber")),
            MachineType              = r.IsDBNull(r.GetOrdinal("MachineType")) ? null : r.GetString(r.GetOrdinal("MachineType")),
            Manufacturer             = r.IsDBNull(r.GetOrdinal("Manufacturer")) ? null : r.GetString(r.GetOrdinal("Manufacturer")),
            PurchaseDate             = r.IsDBNull(r.GetOrdinal("PurchaseDate")) ? null : r.GetDateTime(r.GetOrdinal("PurchaseDate")),
            CapacityPerHour          = r.IsDBNull(r.GetOrdinal("CapacityPerHour")) ? null : r.GetInt32(r.GetOrdinal("CapacityPerHour")),
            AssignedOperatorStaffId  = r.IsDBNull(r.GetOrdinal("AssignedOperatorStaffId")) ? null : r.GetInt32(r.GetOrdinal("AssignedOperatorStaffId")),
            MaintenanceFrequencyDays = r.IsDBNull(r.GetOrdinal("MaintenanceFrequencyDays")) ? null : r.GetInt32(r.GetOrdinal("MaintenanceFrequencyDays")),
            LastMaintenanceDate      = r.IsDBNull(r.GetOrdinal("LastMaintenanceDate")) ? null : r.GetDateTime(r.GetOrdinal("LastMaintenanceDate")),
            NextMaintenanceDate      = r.IsDBNull(r.GetOrdinal("NextMaintenanceDate")) ? null : r.GetDateTime(r.GetOrdinal("NextMaintenanceDate")),
            Status                   = r.GetString(r.GetOrdinal("Status")),
            Notes                    = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            CreatedAt                = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt                = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };
    }

    // =========================================================================
    // WaterProductionBatchService
    // =========================================================================
    public class WaterProductionBatchService : IWaterProductionBatchService
    {
        private readonly string _cs;
        public WaterProductionBatchService(string cs) => _cs = cs;

        public async Task<List<WaterProductionBatchModel>> GetAllAsync(string farmId, string? status, DateTime? fromDate, DateTime? toDate)
        {
            var list = new List<WaterProductionBatchModel>();
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterProductionBatch_GetAll", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ToDate", (object?)toDate ?? DBNull.Value);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(Read(r));
            return list;
        }

        public async Task<WaterProductionBatchModel?> GetByIdAsync(int id, string farmId)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterProductionBatch_GetById", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterProductionBatchId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Read(r) : null;
        }

        public async Task<int> InsertAsync(WaterProductionBatchModel m)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterProductionBatch_Insert", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@BatchNumber", m.BatchNumber);
            cmd.Parameters.AddWithValue("@ProductionDate", m.ProductionDate);
            cmd.Parameters.AddWithValue("@Shift", m.Shift);
            cmd.Parameters.AddWithValue("@WaterMachineId", (object?)m.WaterMachineId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@WaterBoreholeId", (object?)m.WaterBoreholeId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@OperatorStaffId", (object?)m.OperatorStaffId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@StartTime", (object?)m.StartTime ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@EndTime", (object?)m.EndTime ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@WaterProductId", m.WaterProductId);
            cmd.Parameters.AddWithValue("@BagsProduced", m.BagsProduced);
            cmd.Parameters.AddWithValue("@SachetsPerBag", m.SachetsPerBag);
            cmd.Parameters.AddWithValue("@LooseSachetsProduced", m.LooseSachetsProduced);
            cmd.Parameters.AddWithValue("@RejectedSachets", m.RejectedSachets);
            cmd.Parameters.AddWithValue("@DamagedBags", m.DamagedBags);
            cmd.Parameters.AddWithValue("@PackagingRollsUsed", m.PackagingRollsUsed);
            cmd.Parameters.AddWithValue("@EstimatedWaterUsedLitres", (object?)m.EstimatedWaterUsedLitres ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ElectricityCost", m.ElectricityCost);
            cmd.Parameters.AddWithValue("@FuelCost", m.FuelCost);
            cmd.Parameters.AddWithValue("@LaborCost", m.LaborCost);
            cmd.Parameters.AddWithValue("@OtherProductionCost", m.OtherProductionCost);
            cmd.Parameters.AddWithValue("@QualityStatus", m.QualityStatus);
            cmd.Parameters.AddWithValue("@QualityPHLevel", (object?)m.QualityPHLevel ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@QualityChlorinePpm", (object?)m.QualityChlorinePpm ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@QualityTurbidity", (object?)m.QualityTurbidity ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@QualityTDS", (object?)m.QualityTDS ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@QualityNotes", (object?)m.QualityNotes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)m.CreatedBy ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@MaterialsUsedJson", (object?)SerializeMaterials(m.MaterialsUsed) ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@MachineScope",
                string.IsNullOrWhiteSpace(m.MachineScope) ? "SingleMachine" : m.MachineScope);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateAsync(WaterProductionBatchModel m)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterProductionBatch_Update", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterProductionBatchId", m.WaterProductionBatchId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@BatchNumber", m.BatchNumber);
            cmd.Parameters.AddWithValue("@ProductionDate", m.ProductionDate);
            cmd.Parameters.AddWithValue("@Shift", m.Shift);
            cmd.Parameters.AddWithValue("@WaterMachineId", (object?)m.WaterMachineId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@WaterBoreholeId", (object?)m.WaterBoreholeId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@OperatorStaffId", (object?)m.OperatorStaffId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@StartTime", (object?)m.StartTime ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@EndTime", (object?)m.EndTime ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@WaterProductId", m.WaterProductId);
            cmd.Parameters.AddWithValue("@BagsProduced", m.BagsProduced);
            cmd.Parameters.AddWithValue("@SachetsPerBag", m.SachetsPerBag);
            cmd.Parameters.AddWithValue("@LooseSachetsProduced", m.LooseSachetsProduced);
            cmd.Parameters.AddWithValue("@RejectedSachets", m.RejectedSachets);
            cmd.Parameters.AddWithValue("@DamagedBags", m.DamagedBags);
            cmd.Parameters.AddWithValue("@PackagingRollsUsed", m.PackagingRollsUsed);
            cmd.Parameters.AddWithValue("@EstimatedWaterUsedLitres", (object?)m.EstimatedWaterUsedLitres ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ElectricityCost", m.ElectricityCost);
            cmd.Parameters.AddWithValue("@FuelCost", m.FuelCost);
            cmd.Parameters.AddWithValue("@LaborCost", m.LaborCost);
            cmd.Parameters.AddWithValue("@OtherProductionCost", m.OtherProductionCost);
            cmd.Parameters.AddWithValue("@QualityStatus", m.QualityStatus);
            cmd.Parameters.AddWithValue("@QualityPHLevel", (object?)m.QualityPHLevel ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@QualityChlorinePpm", (object?)m.QualityChlorinePpm ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@QualityTurbidity", (object?)m.QualityTurbidity ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@QualityTDS", (object?)m.QualityTDS ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@QualityNotes", (object?)m.QualityNotes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            // NULL = leave existing usage rows untouched; non-null replaces them.
            cmd.Parameters.AddWithValue("@MaterialsUsedJson", (object?)SerializeMaterials(m.MaterialsUsed) ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@MachineScope",
                string.IsNullOrWhiteSpace(m.MachineScope) ? "SingleMachine" : m.MachineScope);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task ApproveAsync(int id, string farmId, string? approvedBy)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterProductionBatch_Approve", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterProductionBatchId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task CancelAsync(int id, string farmId)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterProductionBatch_Cancel", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterProductionBatchId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task ReopenAsync(int id, string farmId, string? reopenedBy)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterProductionBatch_Reopen", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterProductionBatchId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ReopenedBy", (object?)reopenedBy ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static WaterProductionBatchModel Read(SqlDataReader r) => new()
        {
            WaterProductionBatchId   = r.GetInt32(r.GetOrdinal("WaterProductionBatchId")),
            FarmId                   = r.GetString(r.GetOrdinal("FarmId")),
            BatchNumber              = r.GetString(r.GetOrdinal("BatchNumber")),
            ProductionDate           = r.GetDateTime(r.GetOrdinal("ProductionDate")),
            Shift                    = r.GetString(r.GetOrdinal("Shift")),
            WaterMachineId           = r.IsDBNull(r.GetOrdinal("WaterMachineId")) ? null : r.GetInt32(r.GetOrdinal("WaterMachineId")),
            MachineName              = HasCol(r, "MachineName")  && !r.IsDBNull(r.GetOrdinal("MachineName")) ? r.GetString(r.GetOrdinal("MachineName"))  : null,
            WaterBoreholeId          = r.IsDBNull(r.GetOrdinal("WaterBoreholeId")) ? null : r.GetInt32(r.GetOrdinal("WaterBoreholeId")),
            BoreholeName             = HasCol(r, "BoreholeName") && !r.IsDBNull(r.GetOrdinal("BoreholeName")) ? r.GetString(r.GetOrdinal("BoreholeName")) : null,
            OperatorStaffId          = r.IsDBNull(r.GetOrdinal("OperatorStaffId")) ? null : r.GetInt32(r.GetOrdinal("OperatorStaffId")),
            StartTime                = r.IsDBNull(r.GetOrdinal("StartTime")) ? null : r.GetDateTime(r.GetOrdinal("StartTime")),
            EndTime                  = r.IsDBNull(r.GetOrdinal("EndTime")) ? null : r.GetDateTime(r.GetOrdinal("EndTime")),
            WaterProductId           = r.GetInt32(r.GetOrdinal("WaterProductId")),
            ProductName              = HasCol(r, "ProductName") && !r.IsDBNull(r.GetOrdinal("ProductName")) ? r.GetString(r.GetOrdinal("ProductName")) : null,
            BagsProduced             = r.GetInt32(r.GetOrdinal("BagsProduced")),
            SachetsPerBag            = r.GetInt32(r.GetOrdinal("SachetsPerBag")),
            LooseSachetsProduced     = r.GetInt32(r.GetOrdinal("LooseSachetsProduced")),
            RejectedSachets          = r.GetInt32(r.GetOrdinal("RejectedSachets")),
            DamagedBags              = r.GetInt32(r.GetOrdinal("DamagedBags")),
            PackagingRollsUsed       = r.GetInt32(r.GetOrdinal("PackagingRollsUsed")),
            EstimatedWaterUsedLitres = r.IsDBNull(r.GetOrdinal("EstimatedWaterUsedLitres")) ? null : r.GetInt32(r.GetOrdinal("EstimatedWaterUsedLitres")),
            ElectricityCost          = r.GetDecimal(r.GetOrdinal("ElectricityCost")),
            FuelCost                 = r.GetDecimal(r.GetOrdinal("FuelCost")),
            LaborCost                = r.GetDecimal(r.GetOrdinal("LaborCost")),
            OtherProductionCost      = r.GetDecimal(r.GetOrdinal("OtherProductionCost")),
            TotalProductionCost      = r.GetDecimal(r.GetOrdinal("TotalProductionCost")),
            RawMaterialCost          = HasCol(r, "RawMaterialCost") && !r.IsDBNull(r.GetOrdinal("RawMaterialCost")) ? r.GetDecimal(r.GetOrdinal("RawMaterialCost")) : 0m,
            // Migration 067: server-derived costing + machine scope.
            GoodBags                 = HasCol(r, "GoodBags")    && !r.IsDBNull(r.GetOrdinal("GoodBags"))    ? r.GetInt32(r.GetOrdinal("GoodBags"))    : 0,
            AllInCost                = HasCol(r, "AllInCost")   && !r.IsDBNull(r.GetOrdinal("AllInCost"))   ? r.GetDecimal(r.GetOrdinal("AllInCost"))  : 0m,
            CostPerBag               = HasCol(r, "CostPerBag")  && !r.IsDBNull(r.GetOrdinal("CostPerBag"))  ? r.GetDecimal(r.GetOrdinal("CostPerBag")) : 0m,
            ProductionEfficiencyPercent = HasCol(r, "ProductionEfficiencyPercent") && !r.IsDBNull(r.GetOrdinal("ProductionEfficiencyPercent")) ? r.GetDecimal(r.GetOrdinal("ProductionEfficiencyPercent")) : 0m,
            MachineScope             = HasCol(r, "MachineScope") && !r.IsDBNull(r.GetOrdinal("MachineScope")) ? r.GetString(r.GetOrdinal("MachineScope")) : "SingleMachine",
            QualityStatus            = r.GetString(r.GetOrdinal("QualityStatus")),
            QualityPHLevel           = r.IsDBNull(r.GetOrdinal("QualityPHLevel")) ? null : r.GetDecimal(r.GetOrdinal("QualityPHLevel")),
            QualityChlorinePpm       = r.IsDBNull(r.GetOrdinal("QualityChlorinePpm")) ? null : r.GetDecimal(r.GetOrdinal("QualityChlorinePpm")),
            QualityTurbidity         = r.IsDBNull(r.GetOrdinal("QualityTurbidity")) ? null : r.GetDecimal(r.GetOrdinal("QualityTurbidity")),
            QualityTDS               = r.IsDBNull(r.GetOrdinal("QualityTDS")) ? null : r.GetInt32(r.GetOrdinal("QualityTDS")),
            QualityNotes             = r.IsDBNull(r.GetOrdinal("QualityNotes")) ? null : r.GetString(r.GetOrdinal("QualityNotes")),
            Notes                    = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            Status                   = r.GetString(r.GetOrdinal("Status")),
            CreatedBy                = r.IsDBNull(r.GetOrdinal("CreatedBy")) ? null : r.GetString(r.GetOrdinal("CreatedBy")),
            ApprovedBy               = r.IsDBNull(r.GetOrdinal("ApprovedBy")) ? null : r.GetString(r.GetOrdinal("ApprovedBy")),
            ApprovedAt               = r.IsDBNull(r.GetOrdinal("ApprovedAt")) ? null : r.GetDateTime(r.GetOrdinal("ApprovedAt")),
            CreatedAt                = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt                = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
            IsDeleted                = r.GetBoolean(r.GetOrdinal("IsDeleted")),
        };

        private static bool HasCol(SqlDataReader r, string n)
        {
            for (int i = 0; i < r.FieldCount; i++)
                if (r.GetName(i).Equals(n, StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }

        // Serializer for the @MaterialsUsedJson SP parameter. Returns null when
        // the caller didn't supply a list — the SP treats NULL as "leave usage
        // rows alone", which preserves legacy behavior for older clients.
        private static string? SerializeMaterials(List<WaterProductionMaterialUsageInput>? mats)
        {
            if (mats is null) return null;
            // An empty array still means "replace with no rows" — caller is
            // explicitly clearing the recipe. Serialize as "[]".
            return JsonSerializer.Serialize(mats, new JsonSerializerOptions
            {
                PropertyNamingPolicy = JsonNamingPolicy.CamelCase
            });
        }

        public async Task<List<WaterProductionMaterialUsageRow>> GetMaterialsUsedAsync(int batchId, string farmId)
        {
            var list = new List<WaterProductionMaterialUsageRow>();
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterRawMaterialUsage_GetByBatch", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@WaterProductionBatchId", batchId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                list.Add(new WaterProductionMaterialUsageRow
                {
                    WaterRawMaterialUsageId = r.GetInt32(r.GetOrdinal("WaterRawMaterialUsageId")),
                    FarmId                  = r.GetString(r.GetOrdinal("FarmId")),
                    WaterRawMaterialItemId  = r.GetInt32(r.GetOrdinal("WaterRawMaterialItemId")),
                    ItemName                = r.IsDBNull(r.GetOrdinal("ItemName")) ? null : r.GetString(r.GetOrdinal("ItemName")),
                    UnitOfMeasure           = r.IsDBNull(r.GetOrdinal("UnitOfMeasure")) ? null : r.GetString(r.GetOrdinal("UnitOfMeasure")),
                    CurrentStock            = r.IsDBNull(r.GetOrdinal("CurrentStock")) ? null : r.GetDecimal(r.GetOrdinal("CurrentStock")),
                    WaterProductionBatchId  = r.IsDBNull(r.GetOrdinal("WaterProductionBatchId")) ? null : r.GetInt32(r.GetOrdinal("WaterProductionBatchId")),
                    BatchNumber             = r.IsDBNull(r.GetOrdinal("BatchNumber")) ? null : r.GetString(r.GetOrdinal("BatchNumber")),
                    FinishedProductName     = r.IsDBNull(r.GetOrdinal("FinishedProductName")) ? null : r.GetString(r.GetOrdinal("FinishedProductName")),
                    UsedDate                = r.GetDateTime(r.GetOrdinal("UsedDate")),
                    QuantityUsed            = r.GetDecimal(r.GetOrdinal("QuantityUsed")),
                    ExpectedQuantityUsed    = r.IsDBNull(r.GetOrdinal("ExpectedQuantityUsed")) ? null : r.GetDecimal(r.GetOrdinal("ExpectedQuantityUsed")),
                    Variance                = r.IsDBNull(r.GetOrdinal("Variance")) ? 0m : r.GetDecimal(r.GetOrdinal("Variance")),
                    VarianceReason          = r.IsDBNull(r.GetOrdinal("VarianceReason")) ? null : r.GetString(r.GetOrdinal("VarianceReason")),
                    UnitCost                = r.IsDBNull(r.GetOrdinal("UnitCost")) ? null : r.GetDecimal(r.GetOrdinal("UnitCost")),
                    TotalCost               = r.IsDBNull(r.GetOrdinal("TotalCost")) ? null : r.GetDecimal(r.GetOrdinal("TotalCost")),
                    UsedByStaffId           = r.IsDBNull(r.GetOrdinal("UsedByStaffId")) ? null : r.GetInt32(r.GetOrdinal("UsedByStaffId")),
                    Notes                   = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
                    CreatedAt               = r.GetDateTime(r.GetOrdinal("CreatedAt")),
                });
            }
            return list;
        }

        // -----------------------------------------------------------------
        // Migration 067 — read-side helpers for the Details view.
        // -----------------------------------------------------------------
        public async Task<List<WaterProductionLossModel>> GetLinkedLossesAsync(int batchId, string farmId)
        {
            var list = new List<WaterProductionLossModel>();
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterProductionLoss_GetByBatch", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@WaterProductionBatchId", batchId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(ReadLoss(r));
            return list;
        }

        public async Task<List<WaterProductionLinkedExpenseRow>> GetLinkedExpensesAsync(int batchId, string farmId)
        {
            var list = new List<WaterProductionLinkedExpenseRow>();
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterProductionBatch_GetLinkedExpenses", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@WaterProductionBatchId", batchId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                list.Add(new WaterProductionLinkedExpenseRow
                {
                    WaterExpenseId               = r.GetInt32(r.GetOrdinal("WaterExpenseId")),
                    FarmId                       = r.GetString(r.GetOrdinal("FarmId")),
                    ExpenseDate                  = r.GetDateTime(r.GetOrdinal("ExpenseDate")),
                    WaterExpenseCategoryId       = r.GetInt32(r.GetOrdinal("WaterExpenseCategoryId")),
                    CategoryName                 = r.IsDBNull(r.GetOrdinal("CategoryName")) ? null : r.GetString(r.GetOrdinal("CategoryName")),
                    Description                  = r.IsDBNull(r.GetOrdinal("Description")) ? null : r.GetString(r.GetOrdinal("Description")),
                    Amount                       = r.GetDecimal(r.GetOrdinal("Amount")),
                    PaidTo                       = r.IsDBNull(r.GetOrdinal("PaidTo")) ? null : r.GetString(r.GetOrdinal("PaidTo")),
                    PaymentMethod                = r.IsDBNull(r.GetOrdinal("PaymentMethod")) ? null : r.GetString(r.GetOrdinal("PaymentMethod")),
                    WaterCashAccountId           = r.IsDBNull(r.GetOrdinal("WaterCashAccountId")) ? null : r.GetInt32(r.GetOrdinal("WaterCashAccountId")),
                    CashAccountName              = r.IsDBNull(r.GetOrdinal("CashAccountName")) ? null : r.GetString(r.GetOrdinal("CashAccountName")),
                    LinkedWaterProductionBatchId = r.IsDBNull(r.GetOrdinal("LinkedWaterProductionBatchId")) ? null : r.GetInt32(r.GetOrdinal("LinkedWaterProductionBatchId")),
                    Status                       = r.IsDBNull(r.GetOrdinal("Status")) ? null : r.GetString(r.GetOrdinal("Status")),
                    Notes                        = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
                    CreatedBy                    = r.IsDBNull(r.GetOrdinal("CreatedBy")) ? null : r.GetString(r.GetOrdinal("CreatedBy")),
                    ApprovedBy                   = r.IsDBNull(r.GetOrdinal("ApprovedBy")) ? null : r.GetString(r.GetOrdinal("ApprovedBy")),
                    ApprovedAt                   = r.IsDBNull(r.GetOrdinal("ApprovedAt")) ? null : r.GetDateTime(r.GetOrdinal("ApprovedAt")),
                    CreatedAt                    = r.GetDateTime(r.GetOrdinal("CreatedAt")),
                });
            }
            return list;
        }

        public async Task<List<WaterProductionLinkedStockTxnRow>> GetLinkedStockTxnsAsync(int batchId, string farmId)
        {
            var list = new List<WaterProductionLinkedStockTxnRow>();
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterProductionBatch_GetLinkedStockTxns", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@WaterProductionBatchId", batchId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                list.Add(new WaterProductionLinkedStockTxnRow
                {
                    WaterStockTransactionId = r.GetInt32(r.GetOrdinal("WaterStockTransactionId")),
                    WaterProductId          = r.GetInt32(r.GetOrdinal("WaterProductId")),
                    ProductName             = r.IsDBNull(r.GetOrdinal("ProductName")) ? null : r.GetString(r.GetOrdinal("ProductName")),
                    TxnType                 = r.IsDBNull(r.GetOrdinal("TxnType")) ? null : r.GetString(r.GetOrdinal("TxnType")),
                    Quantity                = r.GetInt32(r.GetOrdinal("Quantity")),
                    UnitCost                = r.IsDBNull(r.GetOrdinal("UnitCost")) ? null : r.GetDecimal(r.GetOrdinal("UnitCost")),
                    Note                    = r.IsDBNull(r.GetOrdinal("Note")) ? null : r.GetString(r.GetOrdinal("Note")),
                    CreatedAt               = r.GetDateTime(r.GetOrdinal("CreatedAt")),
                });
            }
            return list;
        }

        internal static WaterProductionLossModel ReadLoss(SqlDataReader r) => new()
        {
            WaterProductionLossId = r.GetInt32(r.GetOrdinal("WaterProductionLossId")),
            FarmId                = r.GetString(r.GetOrdinal("FarmId")),
            LossDate              = r.GetDateTime(r.GetOrdinal("LossDate")),
            LossType              = r.IsDBNull(r.GetOrdinal("LossType")) ? "ProductionDamage" : r.GetString(r.GetOrdinal("LossType")),
            SourceType            = r.IsDBNull(r.GetOrdinal("SourceType")) ? "ProductionBatch" : r.GetString(r.GetOrdinal("SourceType")),
            SourceId              = r.IsDBNull(r.GetOrdinal("SourceId")) ? null : r.GetInt32(r.GetOrdinal("SourceId")),
            WaterProductId        = r.IsDBNull(r.GetOrdinal("WaterProductId")) ? null : r.GetInt32(r.GetOrdinal("WaterProductId")),
            ProductName           = HasCol(r, "ProductName") && !r.IsDBNull(r.GetOrdinal("ProductName")) ? r.GetString(r.GetOrdinal("ProductName")) : null,
            BatchNumber           = HasCol(r, "BatchNumber") && !r.IsDBNull(r.GetOrdinal("BatchNumber")) ? r.GetString(r.GetOrdinal("BatchNumber")) : null,
            BagsLost              = r.GetInt32(r.GetOrdinal("BagsLost")),
            SachetsLost           = r.GetInt32(r.GetOrdinal("SachetsLost")),
            SachetsPerBag         = r.GetInt32(r.GetOrdinal("SachetsPerBag")),
            CostPerBag            = r.GetDecimal(r.GetOrdinal("CostPerBag")),
            BagsLossValue         = r.GetDecimal(r.GetOrdinal("BagsLossValue")),
            SachetsLossValue      = r.GetDecimal(r.GetOrdinal("SachetsLossValue")),
            TotalValue            = r.GetDecimal(r.GetOrdinal("TotalValue")),
            Reason                = r.IsDBNull(r.GetOrdinal("Reason")) ? null : r.GetString(r.GetOrdinal("Reason")),
            Status                = r.IsDBNull(r.GetOrdinal("Status")) ? "Approved" : r.GetString(r.GetOrdinal("Status")),
            Notes                 = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            CreatedBy             = r.IsDBNull(r.GetOrdinal("CreatedBy")) ? null : r.GetString(r.GetOrdinal("CreatedBy")),
            CreatedAt             = r.GetDateTime(r.GetOrdinal("CreatedAt")),
        };
    }

    // =========================================================================
    // WaterProductionLossService (Migration 067) — standalone Loss page.
    // =========================================================================
    public class WaterProductionLossService : IWaterProductionLossService
    {
        private readonly string _cs;
        public WaterProductionLossService(string cs) => _cs = cs;

        public async Task<List<WaterProductionLossModel>> GetAllAsync(string farmId, DateTime? fromDate, DateTime? toDate, string? status)
        {
            var list = new List<WaterProductionLossModel>();
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterProductionLoss_GetAll", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ToDate",   (object?)toDate   ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Status",   (object?)status   ?? DBNull.Value);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(WaterProductionBatchService.ReadLoss(r));
            return list;
        }
    }

    // =========================================================================
    // WaterProductionRecipeService — Production Recipe per finished product.
    // =========================================================================
    public class WaterProductionRecipeService : IWaterProductionRecipeService
    {
        private readonly string _cs;
        public WaterProductionRecipeService(string cs) => _cs = cs;

        public async Task<WaterProductionRecipeModel?> GetByProductAsync(string farmId, int waterProductId)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterProductionRecipe_GetByProduct", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@WaterProductId", waterProductId);
            await conn.OpenAsync();

            using var r = await cmd.ExecuteReaderAsync();

            WaterProductionRecipeModel? recipe = null;
            if (await r.ReadAsync())
            {
                recipe = new WaterProductionRecipeModel
                {
                    WaterProductionRecipeId = r.GetInt32(r.GetOrdinal("WaterProductionRecipeId")),
                    FarmId                  = r.GetString(r.GetOrdinal("FarmId")),
                    WaterProductId          = r.GetInt32(r.GetOrdinal("WaterProductId")),
                    RecipeName              = r.GetString(r.GetOrdinal("RecipeName")),
                    IsDefault               = r.GetBoolean(r.GetOrdinal("IsDefault")),
                    IsActive                = r.GetBoolean(r.GetOrdinal("IsActive")),
                    Notes                   = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
                    CreatedBy               = r.IsDBNull(r.GetOrdinal("CreatedBy")) ? null : r.GetString(r.GetOrdinal("CreatedBy")),
                    CreatedAt               = r.GetDateTime(r.GetOrdinal("CreatedAt")),
                    UpdatedBy               = r.IsDBNull(r.GetOrdinal("UpdatedBy")) ? null : r.GetString(r.GetOrdinal("UpdatedBy")),
                    UpdatedAt               = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
                };
            }

            // Second result set = items (always read, even when header is null
            // so callers can detect "no recipe yet" vs "empty recipe").
            if (await r.NextResultAsync())
            {
                while (await r.ReadAsync())
                {
                    var item = new WaterProductionRecipeItemModel
                    {
                        WaterProductionRecipeItemId = r.GetInt32(r.GetOrdinal("WaterProductionRecipeItemId")),
                        WaterProductionRecipeId     = r.GetInt32(r.GetOrdinal("WaterProductionRecipeId")),
                        WaterRawMaterialItemId      = r.GetInt32(r.GetOrdinal("WaterRawMaterialItemId")),
                        RawMaterialName             = r.IsDBNull(r.GetOrdinal("RawMaterialName")) ? null : r.GetString(r.GetOrdinal("RawMaterialName")),
                        RawMaterialUnit             = r.IsDBNull(r.GetOrdinal("RawMaterialUnit")) ? null : r.GetString(r.GetOrdinal("RawMaterialUnit")),
                        RawMaterialStock            = r.IsDBNull(r.GetOrdinal("RawMaterialStock")) ? null : r.GetDecimal(r.GetOrdinal("RawMaterialStock")),
                        QuantityPerOutputUnit       = r.GetDecimal(r.GetOrdinal("QuantityPerOutputUnit")),
                        OutputUnit                  = r.GetString(r.GetOrdinal("OutputUnit")),
                        WasteAllowancePercent       = r.GetDecimal(r.GetOrdinal("WasteAllowancePercent")),
                        IsOptional                  = r.GetBoolean(r.GetOrdinal("IsOptional")),
                        DisplayOrder                = r.GetInt32(r.GetOrdinal("DisplayOrder")),
                        Notes                       = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
                        LatestUnitCost              = r.IsDBNull(r.GetOrdinal("LatestUnitCost")) ? null : r.GetDecimal(r.GetOrdinal("LatestUnitCost")),
                        CreatedAt                   = r.GetDateTime(r.GetOrdinal("CreatedAt")),
                        UpdatedAt                   = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
                    };

                    if (recipe is null)
                    {
                        // Defensive: shouldn't happen because the SP only emits
                        // items when a recipe row exists, but materialize an
                        // empty one so we can return the items.
                        recipe = new WaterProductionRecipeModel { FarmId = farmId, WaterProductId = waterProductId };
                    }
                    recipe.Items.Add(item);
                }
            }
            return recipe;
        }

        public async Task<int> UpsertAsync(string farmId, int waterProductId, WaterProductionRecipeUpsertRequest req, string? updatedBy)
        {
            var itemsJson = JsonSerializer.Serialize(req.Items, new JsonSerializerOptions
            {
                PropertyNamingPolicy = JsonNamingPolicy.CamelCase
            });

            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterProductionRecipe_Upsert", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@WaterProductId", waterProductId);
            cmd.Parameters.AddWithValue("@RecipeName", string.IsNullOrWhiteSpace(req.RecipeName) ? "Default" : req.RecipeName);
            cmd.Parameters.AddWithValue("@Notes", (object?)req.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ItemsJson", itemsJson);
            cmd.Parameters.AddWithValue("@UpdatedBy", (object?)updatedBy ?? DBNull.Value);

            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task DeleteAsync(string farmId, int recipeId)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterProductionRecipe_Delete", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@WaterProductionRecipeId", recipeId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<List<WaterProductionMaterialUsageRow>> GetUsageHistoryAsync(string farmId, int? rawMaterialItemId, DateTime? fromDate, DateTime? toDate)
        {
            var list = new List<WaterProductionMaterialUsageRow>();
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterRawMaterialUsage_GetHistory", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@WaterRawMaterialItemId", (object?)rawMaterialItemId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ToDate",   (object?)toDate   ?? DBNull.Value);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                list.Add(new WaterProductionMaterialUsageRow
                {
                    WaterRawMaterialUsageId = r.GetInt32(r.GetOrdinal("WaterRawMaterialUsageId")),
                    FarmId                  = r.GetString(r.GetOrdinal("FarmId")),
                    WaterRawMaterialItemId  = r.GetInt32(r.GetOrdinal("WaterRawMaterialItemId")),
                    ItemName                = r.IsDBNull(r.GetOrdinal("ItemName")) ? null : r.GetString(r.GetOrdinal("ItemName")),
                    UnitOfMeasure           = r.IsDBNull(r.GetOrdinal("UnitOfMeasure")) ? null : r.GetString(r.GetOrdinal("UnitOfMeasure")),
                    WaterProductionBatchId  = r.IsDBNull(r.GetOrdinal("WaterProductionBatchId")) ? null : r.GetInt32(r.GetOrdinal("WaterProductionBatchId")),
                    BatchNumber             = r.IsDBNull(r.GetOrdinal("BatchNumber")) ? null : r.GetString(r.GetOrdinal("BatchNumber")),
                    FinishedProductName     = r.IsDBNull(r.GetOrdinal("FinishedProductName")) ? null : r.GetString(r.GetOrdinal("FinishedProductName")),
                    UsedDate                = r.GetDateTime(r.GetOrdinal("UsedDate")),
                    QuantityUsed            = r.GetDecimal(r.GetOrdinal("QuantityUsed")),
                    ExpectedQuantityUsed    = r.IsDBNull(r.GetOrdinal("ExpectedQuantityUsed")) ? null : r.GetDecimal(r.GetOrdinal("ExpectedQuantityUsed")),
                    Variance                = r.IsDBNull(r.GetOrdinal("Variance")) ? 0m : r.GetDecimal(r.GetOrdinal("Variance")),
                    UnitCost                = r.IsDBNull(r.GetOrdinal("UnitCost")) ? null : r.GetDecimal(r.GetOrdinal("UnitCost")),
                    TotalCost               = r.IsDBNull(r.GetOrdinal("TotalCost")) ? null : r.GetDecimal(r.GetOrdinal("TotalCost")),
                    Notes                   = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
                    CreatedAt               = r.GetDateTime(r.GetOrdinal("CreatedAt")),
                });
            }
            return list;
        }
    }

    // =========================================================================
    // WaterQualityTestService
    // =========================================================================
    public class WaterQualityTestService : IWaterQualityTestService
    {
        private readonly string _cs;
        public WaterQualityTestService(string cs) => _cs = cs;

        public async Task<List<WaterQualityTestModel>> GetAllAsync(string farmId, int? boreholeId, int? batchId)
        {
            var list = new List<WaterQualityTestModel>();
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterQualityTest_GetAll", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@BoreholeId", (object?)boreholeId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@BatchId", (object?)batchId ?? DBNull.Value);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                list.Add(new WaterQualityTestModel
                {
                    WaterQualityTestId     = r.GetInt32(r.GetOrdinal("WaterQualityTestId")),
                    FarmId                 = r.GetString(r.GetOrdinal("FarmId")),
                    WaterBoreholeId        = r.IsDBNull(r.GetOrdinal("WaterBoreholeId")) ? null : r.GetInt32(r.GetOrdinal("WaterBoreholeId")),
                    BoreholeName           = r.IsDBNull(r.GetOrdinal("BoreholeName")) ? null : r.GetString(r.GetOrdinal("BoreholeName")),
                    WaterProductionBatchId = r.IsDBNull(r.GetOrdinal("WaterProductionBatchId")) ? null : r.GetInt32(r.GetOrdinal("WaterProductionBatchId")),
                    BatchNumber            = r.IsDBNull(r.GetOrdinal("BatchNumber")) ? null : r.GetString(r.GetOrdinal("BatchNumber")),
                    TestDate               = r.GetDateTime(r.GetOrdinal("TestDate")),
                    TestType               = r.IsDBNull(r.GetOrdinal("TestType")) ? null : r.GetString(r.GetOrdinal("TestType")),
                    PHLevel                = r.IsDBNull(r.GetOrdinal("PHLevel")) ? null : r.GetDecimal(r.GetOrdinal("PHLevel")),
                    TDS                    = r.IsDBNull(r.GetOrdinal("TDS")) ? null : r.GetInt32(r.GetOrdinal("TDS")),
                    Turbidity              = r.IsDBNull(r.GetOrdinal("Turbidity")) ? null : r.GetDecimal(r.GetOrdinal("Turbidity")),
                    ChlorineLevel          = r.IsDBNull(r.GetOrdinal("ChlorineLevel")) ? null : r.GetDecimal(r.GetOrdinal("ChlorineLevel")),
                    Result                 = r.GetString(r.GetOrdinal("Result")),
                    TestedBy               = r.IsDBNull(r.GetOrdinal("TestedBy")) ? null : r.GetString(r.GetOrdinal("TestedBy")),
                    LabName                = r.IsDBNull(r.GetOrdinal("LabName")) ? null : r.GetString(r.GetOrdinal("LabName")),
                    AttachmentUrl          = r.IsDBNull(r.GetOrdinal("AttachmentUrl")) ? null : r.GetString(r.GetOrdinal("AttachmentUrl")),
                    NextTestDate           = r.IsDBNull(r.GetOrdinal("NextTestDate")) ? null : r.GetDateTime(r.GetOrdinal("NextTestDate")),
                    Notes                  = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
                    CreatedBy              = r.IsDBNull(r.GetOrdinal("CreatedBy")) ? null : r.GetString(r.GetOrdinal("CreatedBy")),
                    CreatedAt              = r.GetDateTime(r.GetOrdinal("CreatedAt")),
                    UpdatedAt              = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
                });
            }
            return list;
        }

        public async Task<int> InsertAsync(WaterQualityTestModel m)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterQualityTest_Insert", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@WaterBoreholeId", (object?)m.WaterBoreholeId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@WaterProductionBatchId", (object?)m.WaterProductionBatchId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@TestDate", (object?)m.TestDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@TestType", (object?)m.TestType ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PHLevel", (object?)m.PHLevel ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@TDS", (object?)m.TDS ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Turbidity", (object?)m.Turbidity ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ChlorineLevel", (object?)m.ChlorineLevel ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Result", m.Result);
            cmd.Parameters.AddWithValue("@TestedBy", (object?)m.TestedBy ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@LabName", (object?)m.LabName ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@AttachmentUrl", (object?)m.AttachmentUrl ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@NextTestDate", (object?)m.NextTestDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)m.CreatedBy ?? DBNull.Value);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }
    }

    // =========================================================================
    // WaterDailyPumpingLogService (light)
    // =========================================================================
    public class WaterDailyPumpingLogService : IWaterDailyPumpingLogService
    {
        private readonly string _cs;
        public WaterDailyPumpingLogService(string cs) => _cs = cs;

        public async Task<List<WaterDailyPumpingLogModel>> GetAllAsync(string farmId, DateTime? fromDate, DateTime? toDate)
        {
            var list = new List<WaterDailyPumpingLogModel>();
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterDailyPumpingLog_GetAll", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ToDate", (object?)toDate ?? DBNull.Value);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                list.Add(new WaterDailyPumpingLogModel
                {
                    WaterDailyPumpingLogId = r.GetInt32(r.GetOrdinal("WaterDailyPumpingLogId")),
                    FarmId                 = r.GetString(r.GetOrdinal("FarmId")),
                    WaterBoreholeId        = r.GetInt32(r.GetOrdinal("WaterBoreholeId")),
                    BoreholeName           = r.IsDBNull(r.GetOrdinal("BoreholeName")) ? null : r.GetString(r.GetOrdinal("BoreholeName")),
                    LogDate                = r.GetDateTime(r.GetOrdinal("LogDate")),
                    OpeningTankLevel       = r.IsDBNull(r.GetOrdinal("OpeningTankLevel")) ? null : r.GetInt32(r.GetOrdinal("OpeningTankLevel")),
                    ClosingTankLevel       = r.IsDBNull(r.GetOrdinal("ClosingTankLevel")) ? null : r.GetInt32(r.GetOrdinal("ClosingTankLevel")),
                    EstimatedLitresPumped  = r.IsDBNull(r.GetOrdinal("EstimatedLitresPumped")) ? null : r.GetInt32(r.GetOrdinal("EstimatedLitresPumped")),
                    PumpStartTime          = r.IsDBNull(r.GetOrdinal("PumpStartTime")) ? null : r.GetDateTime(r.GetOrdinal("PumpStartTime")),
                    PumpEndTime            = r.IsDBNull(r.GetOrdinal("PumpEndTime")) ? null : r.GetDateTime(r.GetOrdinal("PumpEndTime")),
                    ElectricityUsed        = r.IsDBNull(r.GetOrdinal("ElectricityUsed")) ? null : r.GetDecimal(r.GetOrdinal("ElectricityUsed")),
                    FuelUsed               = r.IsDBNull(r.GetOrdinal("FuelUsed")) ? null : r.GetDecimal(r.GetOrdinal("FuelUsed")),
                    OperatorStaffId        = r.IsDBNull(r.GetOrdinal("OperatorStaffId")) ? null : r.GetInt32(r.GetOrdinal("OperatorStaffId")),
                    Notes                  = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
                    CreatedAt              = r.GetDateTime(r.GetOrdinal("CreatedAt")),
                    UpdatedAt              = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
                });
            }
            return list;
        }

        public async Task<int> InsertAsync(WaterDailyPumpingLogModel m)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterDailyPumpingLog_Insert", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@WaterBoreholeId", m.WaterBoreholeId);
            cmd.Parameters.AddWithValue("@LogDate", m.LogDate);
            cmd.Parameters.AddWithValue("@OpeningTankLevel", (object?)m.OpeningTankLevel ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ClosingTankLevel", (object?)m.ClosingTankLevel ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@EstimatedLitresPumped", (object?)m.EstimatedLitresPumped ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PumpStartTime", (object?)m.PumpStartTime ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PumpEndTime", (object?)m.PumpEndTime ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ElectricityUsed", (object?)m.ElectricityUsed ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FuelUsed", (object?)m.FuelUsed ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@OperatorStaffId", (object?)m.OperatorStaffId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }
    }
}
