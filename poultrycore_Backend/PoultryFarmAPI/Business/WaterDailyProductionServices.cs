using System.Data;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    // =========================================================================
    // WaterDailyProductionService (migration 193)
    //
    // Thin ADO.NET wrapper over spWaterDailyProduction_*. Two things to know:
    //  * The child sets come back as FOR JSON PATH columns, which are NULL (not
    //    "[]") when the sub-select is empty — every deserialize is guarded.
    //  * Post/Reverse use ExecuteNonQueryAsync deliberately:
    //    spWaterProductionBatch_Approve emits a trailing result set per call
    //    (188:498-500), and ExecuteNonQuery discards them.
    // =========================================================================
    public class WaterDailyProductionService : IWaterDailyProductionService
    {
        private readonly string _cs;
        public WaterDailyProductionService(string cs) => _cs = cs;

        private static readonly JsonSerializerOptions JsonOpts = new()
        {
            PropertyNameCaseInsensitive = true,
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        };

        // ---------------------------------------------------------------- read
        public async Task<List<WaterDailyProductionModel>> GetAllAsync(string farmId, string? status, DateTime? fromDate, DateTime? toDate)
        {
            var list = new List<WaterDailyProductionModel>();
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterDailyProduction_GetAll", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ToDate", (object?)toDate ?? DBNull.Value);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(MapHeader(r));
            return list;
        }

        public async Task<WaterDailyProductionModel?> GetByIdAsync(int id, string farmId)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterDailyProduction_GetById", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterDailyProductionId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? MapHeader(r) : null;
        }

        // --------------------------------------------------------------- write
        public async Task<int> InsertAsync(WaterDailyProductionModel m)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterDailyProduction_Insert", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@UserId", (object?)m.UserId ?? DBNull.Value);
            AddHeaderParams(cmd, m);
            cmd.Parameters.AddWithValue("@Status", m.Status);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)(m.CreatedBy ?? m.UserId) ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@MachinesJson", (object?)BuildMachinesJson(m.Machines) ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@MaterialsJson", (object?)BuildMaterialsJson(m.Materials) ?? DBNull.Value);

            var outId = new SqlParameter("@NewId", SqlDbType.Int) { Direction = ParameterDirection.Output };
            cmd.Parameters.Add(outId);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
            return outId.Value == DBNull.Value ? 0 : (int)outId.Value;
        }

        public async Task UpdateAsync(WaterDailyProductionModel m)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterDailyProduction_Update", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterDailyProductionId", m.WaterDailyProductionId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            AddHeaderParams(cmd, m);
            cmd.Parameters.AddWithValue("@Status", (object?)m.Status ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@UpdatedBy", (object?)(m.UpdatedBy ?? m.UserId) ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@MachinesJson", (object?)BuildMachinesJson(m.Machines) ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@MaterialsJson", (object?)BuildMaterialsJson(m.Materials) ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteAsync(int id, string farmId, string? userId)
            => await ExecAsync("spWaterDailyProduction_Delete", id, farmId, ("@UserId", userId));

        public async Task SetStatusAsync(int id, string farmId, string status, string? updatedBy)
            => await ExecAsync("spWaterDailyProduction_SetStatus", id, farmId, ("@Status", status), ("@UpdatedBy", updatedBy));

        public async Task DeleteAllocationAsync(int id, string farmId, string? updatedBy)
            => await ExecAsync("spWaterDailyProduction_DeleteAllocation", id, farmId, ("@UpdatedBy", updatedBy));

        public async Task PostAsync(int id, string farmId, string? postedBy)
            => await ExecAsync("spWaterDailyProduction_Post", id, farmId, ("@PostedBy", postedBy));

        public async Task ReverseAsync(int id, string farmId, string? reversedBy)
            => await ExecAsync("spWaterDailyProduction_Reverse", id, farmId, ("@ReversedBy", reversedBy));

        public async Task SaveAllocationAsync(int id, string farmId, string? updatedBy, string? status,
                                              List<WaterDailyProductionAllocationModel> allocations)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand("spWaterDailyProduction_SaveAllocation", conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterDailyProductionId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@AllocationsJson", BuildAllocationsJson(allocations));
            cmd.Parameters.AddWithValue("@Status", (object?)status ?? WaterDailyProductionStatus.Allocated);
            cmd.Parameters.AddWithValue("@UpdatedBy", (object?)updatedBy ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private async Task ExecAsync(string sp, int id, string farmId, params (string Name, object? Value)[] extra)
        {
            using var conn = new SqlConnection(_cs);
            using var cmd = new SqlCommand(sp, conn) { CommandType = CommandType.StoredProcedure };
            cmd.Parameters.AddWithValue("@WaterDailyProductionId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            foreach (var (name, value) in extra) cmd.Parameters.AddWithValue(name, value ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static void AddHeaderParams(SqlCommand cmd, WaterDailyProductionModel m)
        {
            cmd.Parameters.AddWithValue("@ProductionNumber", (object?)m.ProductionNumber ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ProductionDate", m.ProductionDate.Date);
            cmd.Parameters.AddWithValue("@Shift", (object?)m.Shift ?? "FullDay");
            cmd.Parameters.AddWithValue("@MachineSelectionType", (object?)m.MachineSelectionType ?? "AllMachines");
            cmd.Parameters.AddWithValue("@WaterProductId", m.WaterProductId);
            cmd.Parameters.AddWithValue("@WaterBoreholeId", (object?)m.WaterBoreholeId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@OperatorStaffId", (object?)m.OperatorStaffId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@StartTime", (object?)m.StartTime ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@EndTime", (object?)m.EndTime ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@BagsProduced", m.BagsProduced);
            cmd.Parameters.AddWithValue("@SachetsPerBag", m.SachetsPerBag <= 0 ? 30 : m.SachetsPerBag);
            cmd.Parameters.AddWithValue("@LooseSachetsProduced", m.LooseSachetsProduced);
            cmd.Parameters.AddWithValue("@RejectedSachets", m.RejectedSachets);
            cmd.Parameters.AddWithValue("@DamagedBags", m.DamagedBags);
            cmd.Parameters.AddWithValue("@PackagingRollsUsed", m.PackagingRollsUsed);
            cmd.Parameters.AddWithValue("@EstimatedWaterUsedLitres", (object?)m.EstimatedWaterUsedLitres ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ElectricityCost", m.ElectricityCost);
            cmd.Parameters.AddWithValue("@FuelCost", m.FuelCost);
            cmd.Parameters.AddWithValue("@LaborCost", m.LaborCost);
            cmd.Parameters.AddWithValue("@OtherProductionCost", m.OtherProductionCost);
            cmd.Parameters.AddWithValue("@RawMaterialCost", m.RawMaterialCost);
            cmd.Parameters.AddWithValue("@QualityStatus", (object?)m.QualityStatus ?? "Pending");
            cmd.Parameters.AddWithValue("@QualityPHLevel", (object?)m.QualityPHLevel ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@QualityChlorinePpm", (object?)m.QualityChlorinePpm ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@QualityTurbidity", (object?)m.QualityTurbidity ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@QualityTDS", (object?)m.QualityTDS ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@QualityNotes", (object?)m.QualityNotes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
        }

        // ------------------------------------------------------- JSON builders
        // Keys are camelCase to match the OPENJSON paths in migration 193.
        private static string? BuildMachinesJson(List<WaterDailyProductionMachineModel>? rows)
        {
            if (rows is null) return null;
            return JsonSerializer.Serialize(rows.Where(x => x.WaterMachineId > 0).Select(x => new
            {
                waterMachineId = x.WaterMachineId,
                machineName = x.MachineName,
                machineNumber = x.MachineNumber,
                capacityPerHour = x.CapacityPerHour,
                operatorStaffId = x.OperatorStaffId,
            }));
        }

        private static string? BuildMaterialsJson(List<WaterDailyProductionMaterialModel>? rows)
        {
            if (rows is null) return null;
            return JsonSerializer.Serialize(rows
                .Where(x => x.WaterRawMaterialItemId > 0 && x.QuantityUsed > 0)
                .Select(x => new
                {
                    waterRawMaterialItemId = x.WaterRawMaterialItemId,
                    itemName = x.ItemName,
                    unitOfMeasure = x.UnitOfMeasure,
                    quantityUsed = x.QuantityUsed,
                    expectedQuantityUsed = x.ExpectedQuantityUsed,
                    unitCost = x.UnitCost,
                    varianceReason = x.VarianceReason,
                    notes = x.Notes,
                }));
        }

        private static string BuildAllocationsJson(List<WaterDailyProductionAllocationModel>? rows)
        {
            if (rows is null) return "[]";
            return JsonSerializer.Serialize(rows.Where(x => x.WaterMachineId > 0).Select(x => new
            {
                waterMachineId = x.WaterMachineId,
                machineName = x.MachineName,
                allocationMethod = x.AllocationMethod,
                shift = x.Shift,
                operatorStaffId = x.OperatorStaffId,
                startTime = x.StartTime,
                endTime = x.EndTime,
                bagsProduced = x.BagsProduced,
                looseSachetsProduced = x.LooseSachetsProduced,
                rejectedSachets = x.RejectedSachets,
                damagedBags = x.DamagedBags,
                packagingRollsUsed = x.PackagingRollsUsed,
                estimatedWaterUsedLitres = x.EstimatedWaterUsedLitres,
                electricityCost = x.ElectricityCost,
                fuelCost = x.FuelCost,
                laborCost = x.LaborCost,
                otherProductionCost = x.OtherProductionCost,
                rawMaterialCost = x.RawMaterialCost,
                notes = x.Notes,
                materials = (x.Materials ?? new()).Where(mm => mm.WaterRawMaterialItemId > 0 && mm.QuantityAllocated > 0)
                    .Select(mm => new
                    {
                        waterDailyProductionMaterialId = mm.WaterDailyProductionMaterialId,
                        waterRawMaterialItemId = mm.WaterRawMaterialItemId,
                        itemName = mm.ItemName,
                        quantityAllocated = mm.QuantityAllocated,
                        expectedQuantityAllocated = mm.ExpectedQuantityAllocated,
                        unitCost = mm.UnitCost,
                    }),
            }));
        }

        // ------------------------------------------------------------- mapping
        private static WaterDailyProductionModel MapHeader(SqlDataReader r)
        {
            var m = new WaterDailyProductionModel
            {
                WaterDailyProductionId = GetInt(r, "WaterDailyProductionId"),
                FarmId = GetStr(r, "FarmId") ?? string.Empty,
                UserId = GetStr(r, "UserId"),
                ProductionNumber = GetStr(r, "ProductionNumber"),
                ProductionDate = GetDate(r, "ProductionDate") ?? default,
                Shift = GetStr(r, "Shift") ?? "FullDay",
                MachineSelectionType = GetStr(r, "MachineSelectionType") ?? "AllMachines",
                WaterProductId = GetInt(r, "WaterProductId"),
                WaterBoreholeId = GetIntN(r, "WaterBoreholeId"),
                OperatorStaffId = GetIntN(r, "OperatorStaffId"),
                StartTime = GetDate(r, "StartTime"),
                EndTime = GetDate(r, "EndTime"),
                BagsProduced = GetInt(r, "BagsProduced"),
                SachetsPerBag = GetInt(r, "SachetsPerBag"),
                LooseSachetsProduced = GetInt(r, "LooseSachetsProduced"),
                RejectedSachets = GetInt(r, "RejectedSachets"),
                DamagedBags = GetInt(r, "DamagedBags"),
                PackagingRollsUsed = GetInt(r, "PackagingRollsUsed"),
                EstimatedWaterUsedLitres = GetIntN(r, "EstimatedWaterUsedLitres"),
                ElectricityCost = GetDec(r, "ElectricityCost"),
                FuelCost = GetDec(r, "FuelCost"),
                LaborCost = GetDec(r, "LaborCost"),
                OtherProductionCost = GetDec(r, "OtherProductionCost"),
                TotalProductionCost = GetDec(r, "TotalProductionCost"),
                RawMaterialCost = GetDec(r, "RawMaterialCost"),
                QualityStatus = GetStr(r, "QualityStatus") ?? "Pending",
                QualityPHLevel = GetDecN(r, "QualityPHLevel"),
                QualityChlorinePpm = GetDecN(r, "QualityChlorinePpm"),
                QualityTurbidity = GetDecN(r, "QualityTurbidity"),
                QualityTDS = GetIntN(r, "QualityTDS"),
                QualityNotes = GetStr(r, "QualityNotes"),
                Status = GetStr(r, "Status") ?? WaterDailyProductionStatus.PendingAllocation,
                PostingVersion = GetInt(r, "PostingVersion"),
                Notes = GetStr(r, "Notes"),
                CreatedBy = GetStr(r, "CreatedBy"),
                CreatedAt = GetDate(r, "CreatedAt"),
                UpdatedBy = GetStr(r, "UpdatedBy"),
                UpdatedAt = GetDate(r, "UpdatedAt"),
                PostedBy = GetStr(r, "PostedBy"),
                PostedAt = GetDate(r, "PostedAt"),
                ReversedBy = GetStr(r, "ReversedBy"),
                ReversedAt = GetDate(r, "ReversedAt"),
                ProductName = GetStr(r, "ProductName"),
                BoreholeName = GetStr(r, "BoreholeName"),
                GoodBags = GetInt(r, "GoodBags"),
                AllInCost = GetDec(r, "AllInCost"),
                CostPerBag = GetDec(r, "CostPerBag"),
                ProductionEfficiencyPercent = GetDec(r, "ProductionEfficiencyPercent"),
                MachineCount = GetInt(r, "MachineCount"),
                AllocationCount = GetInt(r, "AllocationCount"),
            };

            m.Machines = Deserialize<WaterDailyProductionMachineModel>(GetStr(r, "MachinesJson"));
            m.Materials = Deserialize<WaterDailyProductionMaterialModel>(GetStr(r, "MaterialsJson"));
            m.Allocations = Deserialize<WaterDailyProductionAllocationModel>(GetStr(r, "AllocationsJson"));
            m.Postings = Deserialize<WaterDailyProductionPostingModel>(GetStr(r, "PostingsJson"));
            return m;
        }

        // FOR JSON PATH yields NULL, not "[]", when the sub-select is empty.
        private static List<T> Deserialize<T>(string? json)
        {
            if (string.IsNullOrWhiteSpace(json)) return new List<T>();
            try { return JsonSerializer.Deserialize<List<T>>(json, JsonOpts) ?? new List<T>(); }
            catch (JsonException) { return new List<T>(); }
        }

        // Column lookups are tolerant: _GetAll and _GetById return different
        // enrichment columns, and both feed this one mapper.
        private static int Ord(SqlDataReader r, string n)
        {
            for (int i = 0; i < r.FieldCount; i++)
                if (r.GetName(i).Equals(n, StringComparison.OrdinalIgnoreCase)) return i;
            return -1;
        }
        private static string? GetStr(SqlDataReader r, string n)
        { var i = Ord(r, n); return i < 0 || r.IsDBNull(i) ? null : r.GetValue(i)?.ToString(); }
        private static int GetInt(SqlDataReader r, string n)
        { var i = Ord(r, n); return i < 0 || r.IsDBNull(i) ? 0 : Convert.ToInt32(r.GetValue(i)); }
        private static int? GetIntN(SqlDataReader r, string n)
        { var i = Ord(r, n); return i < 0 || r.IsDBNull(i) ? null : Convert.ToInt32(r.GetValue(i)); }
        private static decimal GetDec(SqlDataReader r, string n)
        { var i = Ord(r, n); return i < 0 || r.IsDBNull(i) ? 0m : Convert.ToDecimal(r.GetValue(i)); }
        private static decimal? GetDecN(SqlDataReader r, string n)
        { var i = Ord(r, n); return i < 0 || r.IsDBNull(i) ? null : Convert.ToDecimal(r.GetValue(i)); }
        private static DateTime? GetDate(SqlDataReader r, string n)
        { var i = Ord(r, n); return i < 0 || r.IsDBNull(i) ? null : Convert.ToDateTime(r.GetValue(i)); }
    }
}
