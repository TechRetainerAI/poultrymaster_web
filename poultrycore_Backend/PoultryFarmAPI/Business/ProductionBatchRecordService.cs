using PoultryFarmAPIWeb.Models;
using System.Data;
using System.Text.Json;
using Npgsql;
using NpgsqlTypes;

namespace PoultryFarmAPIWeb.Business
{
    /// <summary>
    /// ADO.NET service for the batch-level production + allocation workflow (migration 156).
    /// Mirrors the ProductionRecordService pattern: thin wrappers around stored procedures,
    /// child collections passed/returned as JSON columns.
    /// </summary>
    public class ProductionBatchRecordService : IProductionBatchRecordService
    {
        private readonly string _connectionString;
        private static readonly JsonSerializerOptions JsonOpts = new() { PropertyNameCaseInsensitive = true };

        public ProductionBatchRecordService(string connectionString)
        {
            _connectionString = connectionString;
        }

        // ---- JSON param builders (keys match the OPENJSON paths in migration 156) ----

        private static object BuildIncludedFlocksJson(ProductionBatchRecordModel m)
            => JsonSerializer.Serialize((m.IncludedFlocks ?? new())
                .Where(f => f.FlockId > 0)
                .Select(f => new { flockId = f.FlockId, flockName = f.FlockName, birdBatchId = f.BirdBatchId }));

        private static object BuildUsageJson(IEnumerable<ProductionBatchUsageLineModel>? lines)
            => JsonSerializer.Serialize((lines ?? Enumerable.Empty<ProductionBatchUsageLineModel>())
                .Where(l => l.ItemId > 0 && l.Qty > 0)
                .Select(l => new { itemId = l.ItemId, itemName = l.ItemName, qty = l.Qty, unitCost = l.UnitCost, totalCost = l.TotalCost, method = l.Method }));

        private static string BuildAllocationsJson(IEnumerable<ProductionBatchAllocationModel> allocations)
            => JsonSerializer.Serialize(allocations.Select(a => new
            {
                flockId = a.FlockId,
                flockName = a.FlockName,
                allocationMethod = a.AllocationMethod,
                ageInWeeks = a.AgeInWeeks,
                ageInDays = a.AgeInDays,
                birdsBefore = a.BirdsBefore,
                deaths = a.Deaths,
                birdsAfter = a.BirdsAfter,
                firstPickEggs = a.FirstPickEggs,
                secondPickEggs = a.SecondPickEggs,
                thirdPickEggs = a.ThirdPickEggs,
                fourthPickEggs = a.FourthPickEggs,
                brokenEggs = a.BrokenEggs,
                meatyEggs = a.MeatyEggs,
                softEggs = a.SoftEggs,
                lostEggs = a.LostEggs,
                totalEggs = a.TotalEggs,
                eggPercentage = a.EggPercentage,
                feedKg = a.FeedKg,
                totalFeedCost = a.TotalFeedCost,
                totalMedicationCost = a.TotalMedicationCost,
                totalCostOfProduction = a.TotalCostOfProduction,
                notes = a.Notes,
                feeds = (a.Feeds ?? new()).Where(f => f.ItemId > 0).Select(f => new
                {
                    batchUsageId = f.BatchUsageId,
                    itemId = f.ItemId,
                    itemName = f.ItemName,
                    qty = f.Qty,
                    unitCost = f.UnitCost,
                    totalCost = f.TotalCost
                }),
                medications = (a.Medications ?? new()).Where(f => f.ItemId > 0).Select(f => new
                {
                    batchUsageId = f.BatchUsageId,
                    itemId = f.ItemId,
                    itemName = f.ItemName,
                    qty = f.Qty,
                    unitCost = f.UnitCost,
                    totalCost = f.TotalCost
                })
            }));

        private static void AddHeaderParams(NpgsqlCommand cmd, ProductionBatchRecordModel m)
        {
            cmd.Parameters.AddWithValue("@BatchSelectionType", m.BatchSelectionType);
            cmd.Parameters.AddWithValue("@SelectedBirdBatchId", (object?)m.SelectedBirdBatchId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@BatchName", (object?)m.BatchName ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ProductionDate", m.ProductionDate);
            cmd.Parameters.AddWithValue("@AgeInWeeks", (object?)m.AgeInWeeks ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@AgeInDays", (object?)m.AgeInDays ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@AgeDisplay", (object?)m.AgeDisplay ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FirstPickCrates", (object?)m.FirstPickCrates ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FirstPickLooseEggs", (object?)m.FirstPickLooseEggs ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FirstPickTotal", m.FirstPickTotal);
            cmd.Parameters.AddWithValue("@SecondPickCrates", (object?)m.SecondPickCrates ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@SecondPickLooseEggs", (object?)m.SecondPickLooseEggs ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@SecondPickTotal", m.SecondPickTotal);
            cmd.Parameters.AddWithValue("@ThirdPickCrates", (object?)m.ThirdPickCrates ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ThirdPickLooseEggs", (object?)m.ThirdPickLooseEggs ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ThirdPickTotal", m.ThirdPickTotal);
            cmd.Parameters.AddWithValue("@FourthPickCrates", (object?)m.FourthPickCrates ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FourthPickLooseEggs", (object?)m.FourthPickLooseEggs ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FourthPickTotal", m.FourthPickTotal);
            cmd.Parameters.AddWithValue("@BrokenEggs", (object?)m.BrokenEggs ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@MeatyEggs", (object?)m.MeatyEggs ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@SoftEggs", (object?)m.SoftEggs ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@LostEggs", (object?)m.LostEggs ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@TotalEggs", m.TotalEggs);
            cmd.Parameters.AddWithValue("@FeedKg", (object?)m.FeedKg ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Deaths", m.Deaths);
            cmd.Parameters.AddWithValue("@BirdsLeft", (object?)m.BirdsLeft ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@EggGrade", (object?)m.EggGrade ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FeedType", (object?)m.FeedType ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Medication", (object?)m.Medication ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@TotalFeedCost", (object?)m.TotalFeedCost ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@TotalMedicationCost", (object?)m.TotalMedicationCost ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@TotalCostOfProduction", (object?)m.TotalCostOfProduction ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IncludedFlocksJson", BuildIncludedFlocksJson(m));
            cmd.Parameters.AddWithValue("@FeedsJson", BuildUsageJson(m.Feeds));
            cmd.Parameters.AddWithValue("@MedicationsJson", BuildUsageJson(m.Medications));
        }

        public async Task<int> Insert(ProductionBatchRecordModel model)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT spproductionbatchrecord_insert(p_farmid => @FarmId::text, p_userid => @UserId::text, p_createdby => @CreatedBy::text, p_batchselectiontype => @BatchSelectionType::text, p_selectedbirdbatchid => @SelectedBirdBatchId::int, p_batchname => @BatchName::text, p_productiondate => @ProductionDate::date, p_ageinweeks => @AgeInWeeks::int, p_ageindays => @AgeInDays::int, p_agedisplay => @AgeDisplay::text, p_firstpickcrates => @FirstPickCrates::int, p_firstpicklooseeggs => @FirstPickLooseEggs::int, p_firstpicktotal => @FirstPickTotal::int, p_secondpickcrates => @SecondPickCrates::int, p_secondpicklooseeggs => @SecondPickLooseEggs::int, p_secondpicktotal => @SecondPickTotal::int, p_thirdpickcrates => @ThirdPickCrates::int, p_thirdpicklooseeggs => @ThirdPickLooseEggs::int, p_thirdpicktotal => @ThirdPickTotal::int, p_fourthpickcrates => @FourthPickCrates::int, p_fourthpicklooseeggs => @FourthPickLooseEggs::int, p_fourthpicktotal => @FourthPickTotal::int, p_brokeneggs => @BrokenEggs::int, p_meatyeggs => @MeatyEggs::int, p_softeggs => @SoftEggs::int, p_losteggs => @LostEggs::int, p_totaleggs => @TotalEggs::int, p_feedkg => @FeedKg::numeric, p_deaths => @Deaths::int, p_birdsleft => @BirdsLeft::int, p_egggrade => @EggGrade::text, p_feedtype => @FeedType::text, p_medication => @Medication::text, p_totalfeedcost => @TotalFeedCost::numeric, p_totalmedicationcost => @TotalMedicationCost::numeric, p_totalcostofproduction => @TotalCostOfProduction::numeric, p_status => @Status::text, p_notes => @Notes::text, p_includedflocksjson => @IncludedFlocksJson::text, p_feedsjson => @FeedsJson::text, p_medicationsjson => @MedicationsJson::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", model.FarmId);
            cmd.Parameters.AddWithValue("@UserId", (object?)model.UserId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)model.CreatedBy ?? DBNull.Value);
            AddHeaderParams(cmd, model);
            cmd.Parameters.AddWithValue("@Status", string.IsNullOrWhiteSpace(model.Status) ? "PendingAllocation" : model.Status);
            var newIdParam = new NpgsqlParameter("@NewId", NpgsqlDbType.Integer) { Direction = ParameterDirection.Output };
            cmd.Parameters.Add(newIdParam);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
            return (int)newIdParam.Value;
        }

        public async Task Update(ProductionBatchRecordModel model)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spproductionbatchrecord_update(p_id => @Id::int, p_updatedby => @UpdatedBy::text, p_status => @Status::text, p_batchselectiontype => @BatchSelectionType::text, p_selectedbirdbatchid => @SelectedBirdBatchId::int, p_batchname => @BatchName::text, p_productiondate => @ProductionDate::date, p_ageinweeks => @AgeInWeeks::int, p_ageindays => @AgeInDays::int, p_agedisplay => @AgeDisplay::text, p_firstpickcrates => @FirstPickCrates::int, p_firstpicklooseeggs => @FirstPickLooseEggs::int, p_firstpicktotal => @FirstPickTotal::int, p_secondpickcrates => @SecondPickCrates::int, p_secondpicklooseeggs => @SecondPickLooseEggs::int, p_secondpicktotal => @SecondPickTotal::int, p_thirdpickcrates => @ThirdPickCrates::int, p_thirdpicklooseeggs => @ThirdPickLooseEggs::int, p_thirdpicktotal => @ThirdPickTotal::int, p_fourthpickcrates => @FourthPickCrates::int, p_fourthpicklooseeggs => @FourthPickLooseEggs::int, p_fourthpicktotal => @FourthPickTotal::int, p_brokeneggs => @BrokenEggs::int, p_meatyeggs => @MeatyEggs::int, p_softeggs => @SoftEggs::int, p_losteggs => @LostEggs::int, p_totaleggs => @TotalEggs::int, p_feedkg => @FeedKg::numeric, p_deaths => @Deaths::int, p_birdsleft => @BirdsLeft::int, p_egggrade => @EggGrade::text, p_feedtype => @FeedType::text, p_medication => @Medication::text, p_totalfeedcost => @TotalFeedCost::numeric, p_totalmedicationcost => @TotalMedicationCost::numeric, p_totalcostofproduction => @TotalCostOfProduction::numeric, p_notes => @Notes::text, p_includedflocksjson => @IncludedFlocksJson::text, p_feedsjson => @FeedsJson::text, p_medicationsjson => @MedicationsJson::text)", conn);
            cmd.Parameters.AddWithValue("@Id", model.Id);
            cmd.Parameters.AddWithValue("@UpdatedBy", (object?)model.UpdatedBy ?? DBNull.Value);
            AddHeaderParams(cmd, model);
            cmd.Parameters.AddWithValue("@Status", string.IsNullOrWhiteSpace(model.Status) ? (object)DBNull.Value : model.Status);

            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<ProductionBatchRecordModel?> GetById(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spproductionbatchrecord_getbyid(p_id => @Id::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            if (await reader.ReadAsync())
                return MapHeader(reader, includeAllocations: true);
            return null;
        }

        public async Task<List<ProductionBatchRecordModel>> GetAll(string userId, string farmId)
        {
            var list = new List<ProductionBatchRecordModel>();
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spproductionbatchrecord_getall(p_userid => @UserId::text, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@UserId", userId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
                list.Add(MapHeader(reader, includeAllocations: false));
            return list;
        }

        public async Task Delete(int id, string userId, string farmId)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spproductionbatchrecord_delete(p_id => @Id::int, p_userid => @UserId::text, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@UserId", userId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task SetStatus(int id, string farmId, string status, string? updatedBy)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spproductionbatchrecord_setstatus(p_id => @Id::int, p_farmid => @FarmId::text, p_status => @Status::text, p_updatedby => @UpdatedBy::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status", status);
            cmd.Parameters.AddWithValue("@UpdatedBy", (object?)updatedBy ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task SaveAllocation(int id, string farmId, string? updatedBy, string? status, List<ProductionBatchAllocationModel> allocations)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spproductionbatchrecord_saveallocation(p_id => @Id::int, p_farmid => @FarmId::text, p_updatedby => @UpdatedBy::text, p_allocationsjson => @AllocationsJson::text, p_status => @Status::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@UpdatedBy", (object?)updatedBy ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@AllocationsJson", BuildAllocationsJson(allocations ?? new()));
            cmd.Parameters.AddWithValue("@Status", string.IsNullOrWhiteSpace(status) ? "Allocated" : status);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task Post(int id, string farmId, string postedBy)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spproductionbatchrecord_post(p_id => @Id::int, p_farmid => @FarmId::text, p_postedby => @PostedBy::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@PostedBy", postedBy);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task Reverse(int id, string farmId, string reversedBy)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spproductionbatchrecord_reverse(p_id => @Id::int, p_farmid => @FarmId::text, p_reversedby => @ReversedBy::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ReversedBy", reversedBy);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteAllocation(int id, string farmId, string updatedBy)
        {
            using var conn = new NpgsqlConnection(_connectionString);
            using var cmd = new NpgsqlCommand("SELECT * FROM spproductionbatchrecord_deleteallocation(p_id => @Id::int, p_farmid => @FarmId::text, p_updatedby => @UpdatedBy::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@UpdatedBy", updatedBy);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // ---- Reading helpers ----

        private static ProductionBatchRecordModel MapHeader(NpgsqlDataReader reader, bool includeAllocations)
        {
            var m = new ProductionBatchRecordModel
            {
                Id = GetInt(reader, "Id") ?? 0,
                FarmId = reader.GetNullableStringIfPresent("FarmId") ?? string.Empty,
                UserId = reader.GetNullableStringIfPresent("UserId"),
                CreatedBy = reader.GetNullableStringIfPresent("CreatedBy"),
                UpdatedBy = reader.GetNullableStringIfPresent("UpdatedBy"),
                PostedBy = reader.GetNullableStringIfPresent("PostedBy"),
                BatchSelectionType = reader.GetNullableStringIfPresent("BatchSelectionType") ?? "AllBatches",
                SelectedBirdBatchId = GetInt(reader, "SelectedBirdBatchId"),
                BatchName = reader.GetNullableStringIfPresent("BatchName"),
                ProductionDate = reader.GetNullableDateTimeIfPresent("ProductionDate") ?? default,
                AgeInWeeks = GetInt(reader, "AgeInWeeks"),
                AgeInDays = GetInt(reader, "AgeInDays"),
                AgeDisplay = reader.GetNullableStringIfPresent("AgeDisplay"),
                FirstPickCrates = GetInt(reader, "FirstPickCrates"),
                FirstPickLooseEggs = GetInt(reader, "FirstPickLooseEggs"),
                FirstPickTotal = GetInt(reader, "FirstPickTotal") ?? 0,
                SecondPickCrates = GetInt(reader, "SecondPickCrates"),
                SecondPickLooseEggs = GetInt(reader, "SecondPickLooseEggs"),
                SecondPickTotal = GetInt(reader, "SecondPickTotal") ?? 0,
                ThirdPickCrates = GetInt(reader, "ThirdPickCrates"),
                ThirdPickLooseEggs = GetInt(reader, "ThirdPickLooseEggs"),
                ThirdPickTotal = GetInt(reader, "ThirdPickTotal") ?? 0,
                FourthPickCrates = GetInt(reader, "FourthPickCrates"),
                FourthPickLooseEggs = GetInt(reader, "FourthPickLooseEggs"),
                FourthPickTotal = GetInt(reader, "FourthPickTotal") ?? 0,
                BrokenEggs = GetInt(reader, "BrokenEggs"),
                MeatyEggs = GetInt(reader, "MeatyEggs"),
                SoftEggs = GetInt(reader, "SoftEggs"),
                LostEggs = GetInt(reader, "LostEggs"),
                TotalEggs = GetInt(reader, "TotalEggs") ?? 0,
                FeedKg = GetDecimal(reader, "FeedKg"),
                Deaths = GetInt(reader, "Deaths") ?? 0,
                BirdsLeft = GetInt(reader, "BirdsLeft"),
                EggGrade = reader.GetNullableStringIfPresent("EggGrade"),
                FeedType = reader.GetNullableStringIfPresent("FeedType"),
                Medication = reader.GetNullableStringIfPresent("Medication"),
                TotalFeedCost = GetDecimal(reader, "TotalFeedCost"),
                TotalMedicationCost = GetDecimal(reader, "TotalMedicationCost"),
                TotalCostOfProduction = GetDecimal(reader, "TotalCostOfProduction"),
                Status = reader.GetNullableStringIfPresent("Status") ?? "PendingAllocation",
                Notes = reader.GetNullableStringIfPresent("Notes"),
                CreatedDate = reader.GetNullableDateTimeIfPresent("CreatedDate") ?? default,
                UpdatedDate = reader.GetNullableDateTimeIfPresent("UpdatedDate"),
                PostedDate = reader.GetNullableDateTimeIfPresent("PostedDate"),
            };

            m.IncludedFlocks = Deserialize<List<ProductionBatchIncludedFlockModel>>(reader.GetNullableStringIfPresent("IncludedFlocksJson")) ?? new();
            m.Feeds = Deserialize<List<ProductionBatchUsageLineModel>>(reader.GetNullableStringIfPresent("FeedsJson")) ?? new();
            m.Medications = Deserialize<List<ProductionBatchUsageLineModel>>(reader.GetNullableStringIfPresent("MedicationsJson")) ?? new();
            if (includeAllocations)
                m.Allocations = Deserialize<List<ProductionBatchAllocationModel>>(reader.GetNullableStringIfPresent("AllocationsJson")) ?? new();
            return m;
        }

        private static T? Deserialize<T>(string? json)
        {
            if (string.IsNullOrWhiteSpace(json)) return default;
            try { return JsonSerializer.Deserialize<T>(json, JsonOpts); }
            catch { return default; }
        }

        private static int? GetInt(NpgsqlDataReader reader, string columnName)
        {
            for (var i = 0; i < reader.FieldCount; i++)
                if (string.Equals(reader.GetName(i), columnName, StringComparison.OrdinalIgnoreCase))
                    return reader.IsDBNull(i) ? (int?)null : Convert.ToInt32(reader.GetValue(i));
            return null;
        }

        private static decimal? GetDecimal(NpgsqlDataReader reader, string columnName)
        {
            for (var i = 0; i < reader.FieldCount; i++)
                if (string.Equals(reader.GetName(i), columnName, StringComparison.OrdinalIgnoreCase))
                    return reader.IsDBNull(i) ? (decimal?)null : Convert.ToDecimal(reader.GetValue(i));
            return null;
        }
    }
}
