// Poultry deferred inventory costs (migration 288).
//
// Reads only. Every number is decided in SQL -- what counts as recognised, what
// counts as an Exception, which lots a scope includes -- so this file maps rows
// and nothing else. There is no arithmetic here on purpose: a total recomputed
// in C# would be a second answer to a question 288 has already answered.
//
// The list and its summary go out as ONE batch for the same reason the valuation
// service batches its three reads: a card that disagreed with the table under it,
// because a purchase landed between two round trips, is worse than a slower page.

using Npgsql;
using NpgsqlTypes;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IPoultryDeferredInventoryCostService
    {
        Task<PoultryDeferredCostResponse> GetAsync(
            string farmId, string? scope, int? itemId, int? supplierId,
            string? category, DateTime? fromDate, DateTime? toDate, string? search);

        Task<List<PoultryDeferredRecognitionModel>> GetHistoryAsync(string farmId, int purchaseId);

        Task<List<PoultryConsumptionCostLayerModel>> GetCostBreakdownAsync(string farmId, int productionRecordId);
    }

    public class PoultryDeferredInventoryCostService : IPoultryDeferredInventoryCostService
    {
        private readonly string _cs;
        public PoultryDeferredInventoryCostService(string cs) => _cs = cs;

        private static string? StrN(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? null : r.GetString(i); }

        private static int? IntN(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? (int?)null : r.GetInt32(i); }

        private static decimal? DecN(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? (decimal?)null : r.GetDecimal(i); }

        private static DateTime? DtN(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? (DateTime?)null : r.GetDateTime(i); }

        private static decimal Dec(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? 0m : r.GetDecimal(i); }

        private static int Int(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? 0 : r.GetInt32(i); }

        private static DateTime Dt(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? default : r.GetDateTime(i); }

        private static bool Bool(NpgsqlDataReader r, string c)
        { var i = r.GetOrdinal(c); return !r.IsDBNull(i) && r.GetBoolean(i); }

        // Npgsql will not infer the type of a null, and every one of these
        // filters is usually null. Each is added with its type stated so the
        // named-argument bind resolves to the one overload 288 defines.
        private static void AddN(NpgsqlCommand cmd, string name, NpgsqlDbType type, object? value)
            => cmd.Parameters.Add(new NpgsqlParameter(name, type) { Value = value ?? DBNull.Value });

        public async Task<PoultryDeferredCostResponse> GetAsync(
            string farmId, string? scope, int? itemId, int? supplierId,
            string? category, DateTime? fromDate, DateTime? toDate, string? search)
        {
            var res = new PoultryDeferredCostResponse();

            // The scope is normalised here rather than trusted: 288 falls back to
            // DEFERRED for anything it does not recognise, but sending a stray
            // value would make the summary and the list disagree if the two ever
            // fell back differently.
            var s = (scope ?? "DEFERRED").Trim().ToUpperInvariant();
            if (s != "DEFERRED" && s != "RECOGNIZED" && s != "EXCEPTION" && s != "ALL")
                s = "DEFERRED";

            const string args =
                "p_farmid => @FarmId::text, p_scope => @Scope::text, " +
                "p_itemid => @ItemId::int, p_supplierid => @SupplierId::int, " +
                "p_category => @Category::text, p_fromdate => @FromDate::date, " +
                "p_todate => @ToDate::date, p_search => @Search::text";

            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                $"SELECT * FROM sppoultrydeferredpurchase_summary({args}); " +
                $"SELECT * FROM sppoultrydeferredpurchase_getall({args})", conn);

            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Scope", s);
            AddN(cmd, "@ItemId", NpgsqlDbType.Integer, itemId);
            AddN(cmd, "@SupplierId", NpgsqlDbType.Integer, supplierId);
            AddN(cmd, "@Category", NpgsqlDbType.Text, string.IsNullOrWhiteSpace(category) ? null : category);
            AddN(cmd, "@FromDate", NpgsqlDbType.Date, fromDate);
            AddN(cmd, "@ToDate", NpgsqlDbType.Date, toDate);
            AddN(cmd, "@Search", NpgsqlDbType.Text, string.IsNullOrWhiteSpace(search) ? null : search);

            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();

            if (await r.ReadAsync())
            {
                res.Summary = new PoultryDeferredCostSummaryModel
                {
                    RemainingDeferredCost = Dec(r, "RemainingDeferredCost"),
                    RecognizedCost = Dec(r, "RecognizedCost"),
                    DeferredBasis = Dec(r, "DeferredBasis"),
                    OperationalCost = Dec(r, "OperationalCost"),
                    PurchaseCount = Int(r, "PurchaseCount"),
                    DeferredPurchases = Int(r, "DeferredPurchases"),
                    FullyRecognized = Int(r, "FullyRecognized"),
                    NotRecognized = Int(r, "NotRecognized"),
                    Exceptions = Int(r, "Exceptions"),
                    ExceptionDrift = Dec(r, "ExceptionDrift"),
                    RecognitionPercent = Dec(r, "RecognitionPercent"),
                    BlockedPurchases = Int(r, "BlockedPurchases"),
                    BlockedCost = Dec(r, "BlockedCost"),
                };
            }

            if (await r.NextResultAsync())
            {
                while (await r.ReadAsync())
                {
                    res.Purchases.Add(new PoultryDeferredPurchaseModel
                    {
                        PoultryRawMaterialPurchaseId = Int(r, "PoultryRawMaterialPurchaseId"),
                        PurchaseDate = Dt(r, "PurchaseDate"),
                        PoultryRawMaterialItemId = Int(r, "PoultryRawMaterialItemId"),
                        ItemName = StrN(r, "ItemName"),
                        Category = StrN(r, "Category"),
                        UnitOfMeasure = StrN(r, "UnitOfMeasure"),
                        ProductionUnit = StrN(r, "ProductionUnit"),
                        SupplierId = IntN(r, "SupplierId"),
                        SupplierName = StrN(r, "SupplierName"),
                        PurchasedQuantity = Dec(r, "PurchasedQuantity"),
                        ConsumedQuantity = Dec(r, "ConsumedQuantity"),
                        RemainingQuantity = Dec(r, "RemainingQuantity"),
                        OperationalCost = Dec(r, "OperationalCost"),
                        DeferredTotalCost = Dec(r, "DeferredTotalCost"),
                        RecognizedCost = Dec(r, "RecognizedCost"),
                        DeferredRemainingCost = Dec(r, "DeferredRemainingCost"),
                        RecognitionPercent = Dec(r, "RecognitionPercent"),
                        AllocatedRecognizedCost = Dec(r, "AllocatedRecognizedCost"),
                        RecognitionDrift = Dec(r, "RecognitionDrift"),
                        CostRecognitionMethod = StrN(r, "CostRecognitionMethod"),
                        RecognitionMethodLabel = StrN(r, "RecognitionMethodLabel"),
                        Status = StrN(r, "Status"),
                        ExceptionReason = StrN(r, "ExceptionReason"),
                        SourceFeedProductionBatchId = IntN(r, "SourceFeedProductionBatchId"),
                        FeedProductionBatchNumber = StrN(r, "FeedProductionBatchNumber"),
                        IsLotProduced = Bool(r, "IsLotProduced"),
                        RecognitionEvents = Int(r, "RecognitionEvents"),
                        LastRecognitionDate = DtN(r, "LastRecognitionDate"),
                        CostingMethod = StrN(r, "CostingMethod"),
                        QueuePosition = IntN(r, "QueuePosition"),
                        QuantityAheadInQueue = DecN(r, "QuantityAheadInQueue"),
                    });
                }
            }

            return res;
        }

        public async Task<List<PoultryDeferredRecognitionModel>> GetHistoryAsync(string farmId, int purchaseId)
        {
            var list = new List<PoultryDeferredRecognitionModel>();

            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultrydeferredpurchase_history(" +
                "p_farmid => @FarmId::text, p_purchaseid => @PurchaseId::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@PurchaseId", purchaseId);

            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                list.Add(new PoultryDeferredRecognitionModel
                {
                    PoultryRawMaterialUsageId = Int(r, "PoultryRawMaterialUsageId"),
                    UsedDate = Dt(r, "UsedDate"),
                    SourceType = StrN(r, "SourceType"),
                    SourceLabel = StrN(r, "SourceLabel"),
                    ProductionRecordId = IntN(r, "ProductionRecordId"),
                    PoultryProductionBatchId = IntN(r, "PoultryProductionBatchId"),
                    ProductionBatchNumber = StrN(r, "ProductionBatchNumber"),
                    FlockId = IntN(r, "FlockId"),
                    FlockName = StrN(r, "FlockName"),
                    PoultryFeedProductionBatchId = IntN(r, "PoultryFeedProductionBatchId"),
                    FeedProductionBatchNumber = StrN(r, "FeedProductionBatchNumber"),
                    ItemName = StrN(r, "ItemName"),
                    ProductionUnit = StrN(r, "ProductionUnit"),
                    QuantityDrawn = Dec(r, "QuantityDrawn"),
                    UnitCostAtDraw = Dec(r, "UnitCostAtDraw"),
                    OperationalCost = Dec(r, "OperationalCost"),
                    RecognizedCost = Dec(r, "RecognizedCost"),
                    RecognitionOutcome = StrN(r, "RecognitionOutcome"),
                    IsReversed = Bool(r, "IsReversed"),
                    ReversedAt = DtN(r, "ReversedAt"),
                    ExpenseId = IntN(r, "ExpenseId"),
                    ExpenseAmount = DecN(r, "ExpenseAmount"),
                    ExpenseStatus = StrN(r, "ExpenseStatus"),
                });
            }
            return list;
        }

        public async Task<List<PoultryConsumptionCostLayerModel>> GetCostBreakdownAsync(string farmId, int productionRecordId)
        {
            var list = new List<PoultryConsumptionCostLayerModel>();

            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryconsumption_costbreakdown(" +
                "p_farmid => @FarmId::text, p_productionrecordid => @ProductionRecordId::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ProductionRecordId", productionRecordId);

            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                list.Add(new PoultryConsumptionCostLayerModel
                {
                    PoultryRawMaterialUsageId = Int(r, "PoultryRawMaterialUsageId"),
                    PoultryRawMaterialItemId = Int(r, "PoultryRawMaterialItemId"),
                    ItemName = StrN(r, "ItemName"),
                    Category = StrN(r, "Category"),
                    UsedDate = Dt(r, "UsedDate"),
                    TotalQuantityUsed = Dec(r, "TotalQuantityUsed"),
                    ProductionUnit = StrN(r, "ProductionUnit"),
                    PoultryRawMaterialPurchaseId = Int(r, "PoultryRawMaterialPurchaseId"),
                    PurchaseDate = Dt(r, "PurchaseDate"),
                    SupplierName = StrN(r, "SupplierName"),
                    SourceFeedProductionBatchId = IntN(r, "SourceFeedProductionBatchId"),
                    FeedProductionBatchNumber = StrN(r, "FeedProductionBatchNumber"),
                    QuantityDrawn = Dec(r, "QuantityDrawn"),
                    UnitCostAtDraw = Dec(r, "UnitCostAtDraw"),
                    OperationalCost = Dec(r, "OperationalCost"),
                    RecognizedCost = Dec(r, "RecognizedCost"),
                    LotRecognitionMethod = StrN(r, "LotRecognitionMethod"),
                    RecognitionLabel = StrN(r, "RecognitionLabel"),
                    IsReversed = Bool(r, "IsReversed"),
                });
            }
            return list;
        }
    }
}
