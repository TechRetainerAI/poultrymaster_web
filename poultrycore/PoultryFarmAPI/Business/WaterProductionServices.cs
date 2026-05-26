using System.Data;
using System.Data.SqlClient;
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
