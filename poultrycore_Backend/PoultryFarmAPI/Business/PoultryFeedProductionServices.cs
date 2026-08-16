using System.Data;
using System.Text.Json;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    // Feed Production module services. Raw ADO.NET + spPoultryFeed* procedures.
    // Reuses the PoultryRdr reader helpers defined in PoultryProductionServices.cs
    // (same namespace). Additive; a dedicated module.

    internal static class FeedJson
    {
        public static readonly JsonSerializerOptions Camel = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };
    }

    // ============================ Feed Formulas ============================
    public interface IPoultryFeedFormulaService
    {
        Task<List<PoultryFeedFormulaModel>> GetAllAsync(string farmId);
        Task<PoultryFeedFormulaModel?> GetByIdAsync(string farmId, int id);
        Task<int> UpsertAsync(PoultryFeedFormulaUpsertRequest req);
        Task DeleteAsync(string farmId, int id);
    }

    public class PoultryFeedFormulaService : IPoultryFeedFormulaService
    {
        private readonly string _cs; public PoultryFeedFormulaService(string cs) => _cs = cs;

        private static PoultryFeedFormulaModel MapHeader(NpgsqlDataReader r) => new()
        {
            PoultryFeedFormulaId = r.Int("PoultryFeedFormulaId"),
            FarmId = r.Str("FarmId"),
            FormulaName = r.Str("FormulaName"),
            FinishedFeedItemId = r.IntN("FinishedFeedItemId"),
            FinishedFeedItemName = r.Has("FinishedFeedItemName") ? r.StrN("FinishedFeedItemName") : null,
            FinishedFeedUnit = r.Has("FinishedFeedUnit") ? r.StrN("FinishedFeedUnit") : null,
            DefaultOutputUnit = r.StrN("DefaultOutputUnit"),
            Notes = r.StrN("Notes"),
            IsActive = r.Bool("IsActive"),
            CreatedBy = r.StrN("CreatedBy"),
            CreatedAt = r.DateN("CreatedAt"),
            UpdatedAt = r.DateN("UpdatedAt"),
            LineCount = r.Has("LineCount") ? r.Int("LineCount") : 0,
            PercentageTotal = r.Has("PercentageTotal") ? r.Dec("PercentageTotal") : 0,
        };

        private static PoultryFeedFormulaLineModel MapLine(NpgsqlDataReader r) => new()
        {
            PoultryFeedFormulaLineId = r.Int("PoultryFeedFormulaLineId"),
            PoultryFeedFormulaId = r.Int("PoultryFeedFormulaId"),
            IngredientItemId = r.Int("IngredientItemId"),
            IngredientName = r.Has("IngredientName") ? r.StrN("IngredientName") : null,
            IngredientUnit = r.Has("IngredientUnit") ? r.StrN("IngredientUnit") : null,
            AvailableStock = r.Has("AvailableStock") ? r.Dec("AvailableStock") : 0,
            LatestUnitCost = r.Has("LatestUnitCost") ? r.Dec("LatestUnitCost") : 0,
            QuantityMode = r.Str("QuantityMode"),
            Percentage = r.DecN("Percentage"),
            FixedQuantity = r.DecN("FixedQuantity"),
            UnitOfMeasure = r.StrN("UnitOfMeasure"),
            SortOrder = r.Int("SortOrder"),
            Notes = r.StrN("Notes"),
        };

        public async Task<List<PoultryFeedFormulaModel>> GetAllAsync(string farmId)
        {
            var list = new List<PoultryFeedFormulaModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryfeedformula_getall(p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(MapHeader(r));
            return list;
        }

        public async Task<PoultryFeedFormulaModel?> GetByIdAsync(string farmId, int id)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryfeedformula_getbyid_rs1(p_farmid => @FarmId::text, p_poultryfeedformulaid => @PoultryFeedFormulaId::int); SELECT * FROM sppoultryfeedformula_getbyid_rs2(p_farmid => @FarmId::text, p_poultryfeedformulaid => @PoultryFeedFormulaId::int)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@PoultryFeedFormulaId", id);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            PoultryFeedFormulaModel? formula = null;
            if (await r.ReadAsync()) formula = MapHeader(r);
            if (formula != null && await r.NextResultAsync())
                while (await r.ReadAsync()) formula.Lines.Add(MapLine(r));
            return formula;
        }

        public async Task<int> UpsertAsync(PoultryFeedFormulaUpsertRequest req)
        {
            var linesJson = JsonSerializer.Serialize(req.Lines ?? new(), FeedJson.Camel);
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryfeedformula_upsert(p_farmid => @FarmId::text, p_poultryfeedformulaid => @PoultryFeedFormulaId::int, p_formulaname => @FormulaName::text, p_finishedfeeditemid => @FinishedFeedItemId::int, p_defaultoutputunit => @DefaultOutputUnit::text, p_notes => @Notes::text, p_isactive => @IsActive::boolean, p_userid => @UserId::text, p_linesjson => @LinesJson::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", req.FarmId);
            cmd.Parameters.AddWithValue("@PoultryFeedFormulaId", (object?)req.PoultryFeedFormulaId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FormulaName", req.FormulaName);
            cmd.Parameters.AddWithValue("@FinishedFeedItemId", (object?)req.FinishedFeedItemId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DefaultOutputUnit", (object?)req.DefaultOutputUnit ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)req.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", req.IsActive);
            cmd.Parameters.AddWithValue("@UserId", (object?)req.UserId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@LinesJson", (object?)linesJson ?? DBNull.Value);
            await c.OpenAsync();
            var result = await cmd.ExecuteScalarAsync();
            return Convert.ToInt32(result);
        }

        public async Task DeleteAsync(string farmId, int id)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryfeedformula_delete(p_farmid => @FarmId::text, p_poultryfeedformulaid => @PoultryFeedFormulaId::int)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@PoultryFeedFormulaId", id);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }
    }

    // ======================= Feed Production Batches =======================
    public interface IPoultryFeedProductionBatchService
    {
        Task<List<PoultryFeedProductionBatchModel>> GetAllAsync(string farmId, DateTime? fromDate, DateTime? toDate, string? status);
        Task<PoultryFeedProductionBatchModel?> GetByIdAsync(string farmId, int id);
        Task<int> SaveAsync(PoultryFeedProductionBatchSaveRequest req);
        Task DeleteAsync(string farmId, int id);
        Task<List<PoultryFeedProductionBatchItemModel>> GetBatchItemsAsync(string farmId);
        Task PostAsync(string farmId, int id, string? postedBy);
        Task ReverseAsync(string farmId, int id, string? reversedBy, string? reason);
        Task<List<PoultryFeedIngredientUsageRow>> GetIngredientUsageReportAsync(string farmId, DateTime? fromDate, DateTime? toDate);
        Task<List<PoultryFeedTraceabilityRow>> GetTraceabilityAsync(string farmId, int batchId);
    }

    public class PoultryFeedProductionBatchService : IPoultryFeedProductionBatchService
    {
        private readonly string _cs; public PoultryFeedProductionBatchService(string cs) => _cs = cs;

        private static PoultryFeedProductionBatchModel MapHeader(NpgsqlDataReader r) => new()
        {
            PoultryFeedProductionBatchId = r.Int("PoultryFeedProductionBatchId"),
            FarmId = r.Str("FarmId"),
            BatchNumber = r.StrN("BatchNumber"),
            ProductionDate = r.DateN("ProductionDate"),
            FinishedFeedItemId = r.Int("FinishedFeedItemId"),
            FinishedFeedItemName = r.Has("FinishedFeedItemName") ? r.StrN("FinishedFeedItemName") : null,
            FinishedFeedUnit = r.Has("FinishedFeedUnit") ? r.StrN("FinishedFeedUnit") : null,
            FormulaId = r.IntN("FormulaId"),
            FormulaName = r.Has("FormulaName") ? r.StrN("FormulaName") : null,
            QuantityProduced = r.Dec("QuantityProduced"),
            OutputUnit = r.StrN("OutputUnit"),
            TotalIngredientCost = r.Dec("TotalIngredientCost"),
            TotalAdditionalCost = r.Dec("TotalAdditionalCost"),
            TotalProductionCost = r.Dec("TotalProductionCost"),
            CostPerOutputUnit = r.Dec("CostPerOutputUnit"),
            Status = r.Str("Status"),
            Notes = r.StrN("Notes"),
            CreatedBy = r.StrN("CreatedBy"),
            CreatedAt = r.DateN("CreatedAt"),
            UpdatedAt = r.DateN("UpdatedAt"),
            PostedBy = r.StrN("PostedBy"),
            PostedAt = r.DateN("PostedAt"),
            ReversedBy = r.StrN("ReversedBy"),
            ReversedAt = r.DateN("ReversedAt"),
            ReversalReason = r.StrN("ReversalReason"),
        };

        private static PoultryFeedProductionBatchLineModel MapLine(NpgsqlDataReader r) => new()
        {
            PoultryFeedProductionBatchLineId = r.Int("PoultryFeedProductionBatchLineId"),
            PoultryFeedProductionBatchId = r.Int("PoultryFeedProductionBatchId"),
            IngredientItemId = r.Int("IngredientItemId"),
            IngredientName = r.Has("IngredientName") ? r.StrN("IngredientName") : null,
            AvailableStock = r.Has("AvailableStock") ? r.Dec("AvailableStock") : 0,
            SourceType = r.Str("SourceType"),
            QuantityUsed = r.Dec("QuantityUsed"),
            UnitOfMeasure = r.StrN("UnitOfMeasure"),
            // Guarded: migration 184 adds these, so an API running against a
            // database that hasn't caught up still serves batches.
            QuantityMode = r.Has("QuantityMode") ? (r.StrN("QuantityMode") ?? "Quantity") : "Quantity",
            FixedQuantity = r.Has("FixedQuantity") ? r.DecN("FixedQuantity") : null,
            InventoryQuantityUsed = r.DecN("InventoryQuantityUsed"),
            PurchasedQuantityUsed = r.DecN("PurchasedQuantityUsed"),
            InventoryUnitCost = r.DecN("InventoryUnitCost"),
            PurchasedUnitCost = r.DecN("PurchasedUnitCost"),
            UnitCost = r.Dec("UnitCost"),
            TotalCost = r.Dec("TotalCost"),
            SupplierId = r.IntN("SupplierId"),
            SupplierName = r.StrN("SupplierName"),
            PurchaseReference = r.StrN("PurchaseReference"),
            PaymentStatus = r.StrN("PaymentStatus"),
            AmountPaid = r.DecN("AmountPaid"),
            PaidFromCashAccountId = r.IntN("PaidFromCashAccountId"),
            PaymentMethod = r.StrN("PaymentMethod"),
            SortOrder = r.Int("SortOrder"),
            Notes = r.StrN("Notes"),
        };

        private static PoultryFeedProductionAdditionalCostModel MapCost(NpgsqlDataReader r) => new()
        {
            PoultryFeedProductionAdditionalCostId = r.Int("PoultryFeedProductionAdditionalCostId"),
            PoultryFeedProductionBatchId = r.Int("PoultryFeedProductionBatchId"),
            CostType = r.Str("CostType"),
            Amount = r.Dec("Amount"),
            PaymentStatus = r.StrN("PaymentStatus"),
            AmountPaid = r.DecN("AmountPaid"),
            PaidFromCashAccountId = r.IntN("PaidFromCashAccountId"),
            PaymentMethod = r.StrN("PaymentMethod"),
            SupplierId = r.IntN("SupplierId"),
            PayeeName = r.StrN("PayeeName"),
            SortOrder = r.Int("SortOrder"),
            Notes = r.StrN("Notes"),
        };

        public async Task<List<PoultryFeedProductionBatchModel>> GetAllAsync(string farmId, DateTime? fromDate, DateTime? toDate, string? status)
        {
            var list = new List<PoultryFeedProductionBatchModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryfeedproductionbatch_getall(p_farmid => @FarmId::text, p_fromdate => @FromDate::timestamp, p_todate => @ToDate::timestamp, p_status => @Status::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ToDate", (object?)toDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(MapHeader(r));
            return list;
        }

        public async Task<PoultryFeedProductionBatchModel?> GetByIdAsync(string farmId, int id)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryfeedproductionbatch_getbyid_rs1(p_farmid => @FarmId::text, p_poultryfeedproductionbatchid => @PoultryFeedProductionBatchId::int); SELECT * FROM sppoultryfeedproductionbatch_getbyid_rs2(p_farmid => @FarmId::text, p_poultryfeedproductionbatchid => @PoultryFeedProductionBatchId::int); SELECT * FROM sppoultryfeedproductionbatch_getbyid_rs3(p_farmid => @FarmId::text, p_poultryfeedproductionbatchid => @PoultryFeedProductionBatchId::int)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@PoultryFeedProductionBatchId", id);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            PoultryFeedProductionBatchModel? batch = null;
            if (await r.ReadAsync()) batch = MapHeader(r);
            if (batch == null) return null;
            if (await r.NextResultAsync())
                while (await r.ReadAsync()) batch.Lines.Add(MapLine(r));
            if (await r.NextResultAsync())
                while (await r.ReadAsync()) batch.AdditionalCosts.Add(MapCost(r));
            return batch;
        }

        public async Task<int> SaveAsync(PoultryFeedProductionBatchSaveRequest req)
        {
            var linesJson = JsonSerializer.Serialize(req.Lines ?? new(), FeedJson.Camel);
            var costsJson = JsonSerializer.Serialize(req.AdditionalCosts ?? new(), FeedJson.Camel);
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryfeedproductionbatch_save(p_farmid => @FarmId::text, p_poultryfeedproductionbatchid => @PoultryFeedProductionBatchId::int, p_batchnumber => @BatchNumber::text, p_productiondate => @ProductionDate::timestamp, p_finishedfeeditemid => @FinishedFeedItemId::int, p_formulaid => @FormulaId::int, p_quantityproduced => @QuantityProduced::numeric, p_outputunit => @OutputUnit::text, p_notes => @Notes::text, p_userid => @UserId::text, p_linesjson => @LinesJson::text, p_costsjson => @CostsJson::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", req.FarmId);
            cmd.Parameters.AddWithValue("@PoultryFeedProductionBatchId", (object?)req.PoultryFeedProductionBatchId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@BatchNumber", (object?)req.BatchNumber ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ProductionDate", (object?)req.ProductionDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FinishedFeedItemId", req.FinishedFeedItemId);
            cmd.Parameters.AddWithValue("@FormulaId", (object?)req.FormulaId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@QuantityProduced", req.QuantityProduced);
            cmd.Parameters.AddWithValue("@OutputUnit", (object?)req.OutputUnit ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)req.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@UserId", (object?)req.UserId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@LinesJson", (object?)linesJson ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CostsJson", (object?)costsJson ?? DBNull.Value);
            await c.OpenAsync();
            var result = await cmd.ExecuteScalarAsync();
            return Convert.ToInt32(result);
        }

        public async Task DeleteAsync(string farmId, int id)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryfeedproductionbatch_delete(p_farmid => @FarmId::text, p_poultryfeedproductionbatchid => @PoultryFeedProductionBatchId::int)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@PoultryFeedProductionBatchId", id);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task PostAsync(string farmId, int id, string? postedBy)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryfeedproductionbatch_post(p_farmid => @FarmId::text, p_poultryfeedproductionbatchid => @PoultryFeedProductionBatchId::int, p_postedby => @PostedBy::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@PoultryFeedProductionBatchId", id);
            cmd.Parameters.AddWithValue("@PostedBy", (object?)postedBy ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task ReverseAsync(string farmId, int id, string? reversedBy, string? reason)
        {
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryfeedproductionbatch_reverse(p_farmid => @FarmId::text, p_poultryfeedproductionbatchid => @PoultryFeedProductionBatchId::int, p_reversedby => @ReversedBy::text, p_reversalreason => @ReversalReason::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@PoultryFeedProductionBatchId", id);
            cmd.Parameters.AddWithValue("@ReversedBy", (object?)reversedBy ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ReversalReason", (object?)reason ?? DBNull.Value);
            await c.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<List<PoultryFeedIngredientUsageRow>> GetIngredientUsageReportAsync(string farmId, DateTime? fromDate, DateTime? toDate)
        {
            var list = new List<PoultryFeedIngredientUsageRow>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryfeedproductionreport_ingredientusage(p_farmid => @FarmId::text, p_fromdate => @FromDate::timestamp, p_todate => @ToDate::timestamp)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ToDate", (object?)toDate ?? DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(new PoultryFeedIngredientUsageRow
            {
                IngredientItemId = r.Int("IngredientItemId"),
                IngredientName = r.StrN("IngredientName"),
                UnitOfMeasure = r.StrN("UnitOfMeasure"),
                TotalQuantityUsed = r.Dec("TotalQuantityUsed"),
                TotalCost = r.Dec("TotalCost"),
                FromInventoryQuantity = r.Dec("FromInventoryQuantity"),
                PurchasedQuantity = r.Dec("PurchasedQuantity"),
                BatchCount = r.Int("BatchCount"),
            });
            return list;
        }

        public async Task<List<PoultryFeedTraceabilityRow>> GetTraceabilityAsync(string farmId, int batchId)
        {
            var list = new List<PoultryFeedTraceabilityRow>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryfeedproductionreport_traceability(p_farmid => @FarmId::text, p_poultryfeedproductionbatchid => @PoultryFeedProductionBatchId::int)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@PoultryFeedProductionBatchId", batchId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(new PoultryFeedTraceabilityRow
            {
                PoultryFeedProductionBatchId = r.Int("PoultryFeedProductionBatchId"),
                BatchNumber = r.StrN("BatchNumber"),
                FinishedFeedItemId = r.Int("FinishedFeedItemId"),
                FinishedFeedName = r.StrN("FinishedFeedName"),
                PoultryRawMaterialUsageId = r.Int("PoultryRawMaterialUsageId"),
                ProductionRecordId = r.IntN("ProductionRecordId"),
                QuantityUsed = r.Dec("QuantityUsed"),
                QuantityDrawn = r.Dec("QuantityDrawn"),
                UnitCostAtDraw = r.Dec("UnitCostAtDraw"),
                UsedDate = r.DateN("UsedDate"),
            });
            return list;
        }

        public async Task<List<PoultryFeedProductionBatchItemModel>> GetBatchItemsAsync(string farmId)
        {
            var list = new List<PoultryFeedProductionBatchItemModel>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryfeedproduction_getbatchitems(p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(new PoultryFeedProductionBatchItemModel
            {
                PoultryRawMaterialItemId = r.Int("PoultryRawMaterialItemId"),
                ItemName = r.Str("ItemName"),
                Category = r.Str("Category"),
                UnitOfMeasure = r.StrN("UnitOfMeasure"),
                CurrentQuantity = r.Dec("CurrentQuantity"),
                IsActive = r.Bool("IsActive"),
                LatestUnitCost = r.Dec("LatestUnitCost"),
                AvailableFromLots = r.Dec("AvailableFromLots"),
            });
            return list;
        }
    }
}
