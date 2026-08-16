using System.Data;
using System.Text.Json;
using Npgsql;
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
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwaterdailyproduction_getall(p_farmid => @FarmId::text, p_status => @Status::text, p_fromdate => @FromDate::date, p_todate => @ToDate::date)", conn);
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
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwaterdailyproduction_getbyid(p_waterdailyproductionid => @WaterDailyProductionId::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@WaterDailyProductionId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? MapHeader(r) : null;
        }

        // --------------------------------------------------------------- write
        public async Task<int> InsertAsync(WaterDailyProductionModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwaterdailyproduction_insert(p_farmid => @FarmId::text, p_userid => @UserId::text, p_status => @Status::text, p_createdby => @CreatedBy::text, p_machinesjson => @MachinesJson::text, p_materialsjson => @MaterialsJson::text, p_productionnumber => @ProductionNumber::text, p_productiondate => @ProductionDate::date, p_shift => @Shift::text, p_machineselectiontype => @MachineSelectionType::text, p_waterproductid => @WaterProductId::int, p_waterboreholeid => @WaterBoreholeId::int, p_operatorstaffid => @OperatorStaffId::int, p_starttime => @StartTime::timestamp, p_endtime => @EndTime::timestamp, p_bagsproduced => @BagsProduced::int, p_sachetsperbag => @SachetsPerBag::int, p_loosesachetsproduced => @LooseSachetsProduced::int, p_rejectedsachets => @RejectedSachets::int, p_damagedbags => @DamagedBags::int, p_packagingrollsused => @PackagingRollsUsed::int, p_estimatedwaterusedlitres => @EstimatedWaterUsedLitres::int, p_electricitycost => @ElectricityCost::numeric, p_fuelcost => @FuelCost::numeric, p_laborcost => @LaborCost::numeric, p_otherproductioncost => @OtherProductionCost::numeric, p_rawmaterialcost => @RawMaterialCost::numeric, p_qualitystatus => @QualityStatus::text, p_qualityphlevel => @QualityPHLevel::numeric, p_qualitychlorineppm => @QualityChlorinePpm::numeric, p_qualityturbidity => @QualityTurbidity::numeric, p_qualitytds => @QualityTDS::int, p_qualitynotes => @QualityNotes::text, p_notes => @Notes::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@UserId", (object?)m.UserId ?? DBNull.Value);
            AddHeaderParams(cmd, m);
            cmd.Parameters.AddWithValue("@Status", m.Status);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)(m.CreatedBy ?? m.UserId) ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@MachinesJson", (object?)BuildMachinesJson(m.Machines) ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@MaterialsJson", (object?)BuildMaterialsJson(m.Materials) ?? DBNull.Value);

            // The PG function returns the new id directly (the T-SQL used an
            // @NewId OUTPUT parameter). Call text is built from the parameters
            // actually on the command, since AddHeaderParams adds several.
            await conn.OpenAsync();
            cmd.CommandText = await PgCallText.ForAsync("spWaterDailyProduction_Insert", cmd);
            var scalar = await cmd.ExecuteScalarAsync();
            return scalar is null || scalar == DBNull.Value ? 0 : Convert.ToInt32(scalar);
        }

        public async Task UpdateAsync(WaterDailyProductionModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwaterdailyproduction_update(p_waterdailyproductionid => @WaterDailyProductionId::int, p_farmid => @FarmId::text, p_status => @Status::text, p_updatedby => @UpdatedBy::text, p_machinesjson => @MachinesJson::text, p_materialsjson => @MaterialsJson::text, p_productionnumber => @ProductionNumber::text, p_productiondate => @ProductionDate::date, p_shift => @Shift::text, p_machineselectiontype => @MachineSelectionType::text, p_waterproductid => @WaterProductId::int, p_waterboreholeid => @WaterBoreholeId::int, p_operatorstaffid => @OperatorStaffId::int, p_starttime => @StartTime::timestamp, p_endtime => @EndTime::timestamp, p_bagsproduced => @BagsProduced::int, p_sachetsperbag => @SachetsPerBag::int, p_loosesachetsproduced => @LooseSachetsProduced::int, p_rejectedsachets => @RejectedSachets::int, p_damagedbags => @DamagedBags::int, p_packagingrollsused => @PackagingRollsUsed::int, p_estimatedwaterusedlitres => @EstimatedWaterUsedLitres::int, p_electricitycost => @ElectricityCost::numeric, p_fuelcost => @FuelCost::numeric, p_laborcost => @LaborCost::numeric, p_otherproductioncost => @OtherProductionCost::numeric, p_rawmaterialcost => @RawMaterialCost::numeric, p_qualitystatus => @QualityStatus::text, p_qualityphlevel => @QualityPHLevel::numeric, p_qualitychlorineppm => @QualityChlorinePpm::numeric, p_qualityturbidity => @QualityTurbidity::numeric, p_qualitytds => @QualityTDS::int, p_qualitynotes => @QualityNotes::text, p_notes => @Notes::text)", conn);
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
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spwaterdailyproduction_saveallocation(p_waterdailyproductionid => @WaterDailyProductionId::int, p_farmid => @FarmId::text, p_allocationsjson => @AllocationsJson::text, p_status => @Status::text, p_updatedby => @UpdatedBy::text)", conn);
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
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("", conn);
            cmd.Parameters.AddWithValue("@WaterDailyProductionId", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            foreach (var (name, value) in extra) cmd.Parameters.AddWithValue(name, value ?? DBNull.Value);
            await conn.OpenAsync();
            cmd.CommandText = await PgCallText.ForAsync(sp, cmd);
            await cmd.ExecuteNonQueryAsync();
        }

        private static void AddHeaderParams(NpgsqlCommand cmd, WaterDailyProductionModel m)
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
        private static WaterDailyProductionModel MapHeader(NpgsqlDataReader r)
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
        private static int Ord(NpgsqlDataReader r, string n)
        {
            for (int i = 0; i < r.FieldCount; i++)
                if (r.GetName(i).Equals(n, StringComparison.OrdinalIgnoreCase)) return i;
            return -1;
        }
        private static string? GetStr(NpgsqlDataReader r, string n)
        { var i = Ord(r, n); return i < 0 || r.IsDBNull(i) ? null : r.GetValue(i)?.ToString(); }
        private static int GetInt(NpgsqlDataReader r, string n)
        { var i = Ord(r, n); return i < 0 || r.IsDBNull(i) ? 0 : Convert.ToInt32(r.GetValue(i)); }
        private static int? GetIntN(NpgsqlDataReader r, string n)
        { var i = Ord(r, n); return i < 0 || r.IsDBNull(i) ? null : Convert.ToInt32(r.GetValue(i)); }
        private static decimal GetDec(NpgsqlDataReader r, string n)
        { var i = Ord(r, n); return i < 0 || r.IsDBNull(i) ? 0m : Convert.ToDecimal(r.GetValue(i)); }
        private static decimal? GetDecN(NpgsqlDataReader r, string n)
        { var i = Ord(r, n); return i < 0 || r.IsDBNull(i) ? null : Convert.ToDecimal(r.GetValue(i)); }
        private static DateTime? GetDate(NpgsqlDataReader r, string n)
        { var i = Ord(r, n); return i < 0 || r.IsDBNull(i) ? null : Convert.ToDateTime(r.GetValue(i)); }
    }
}
