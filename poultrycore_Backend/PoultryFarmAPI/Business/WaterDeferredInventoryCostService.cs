// Water deferred inventory costs (migration 281).
//
// Reads only. Every number is decided in SQL -- what counts as recognised, what
// counts as an Exception, which lots a scope includes -- so this file maps rows
// and nothing else. There is no arithmetic here on purpose: a total recomputed
// in C# would be a second answer to a question 281 has already answered.
//
// The list and its summary go out as ONE batch for the same reason the poultry
// twin batches them: a card that disagreed with the table under it, because a
// purchase landed between two round trips, is worse than a slower page.
//
// TWO DIFFERENCES FROM THE POULTRY TWIN
// -------------------------------------
// 1. Every water lot is bought. There is no feed production and no produced
//    raw-material lot, so the provenance columns poultry carries for a lot made
//    out of other lots have no water equivalent and are not read.
// 2. A water consumption belongs to a WATER PRODUCTION BATCH -- the run that
//    made the sachets -- not to a flock or a production record. So the cost
//    breakdown is keyed on the batch id, and the history names the batch.

using Npgsql;
using NpgsqlTypes;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface IWaterDeferredInventoryCostService
    {
        Task<WaterDeferredCostResponse> GetAsync(
            string farmId, string? scope, int? itemId, int? supplierId,
            string? category, DateTime? fromDate, DateTime? toDate, string? search);

        Task<List<WaterDeferredRecognitionModel>> GetHistoryAsync(string farmId, int purchaseId);

        Task<List<WaterConsumptionCostLayerModel>> GetCostBreakdownAsync(string farmId, int productionBatchId);
    }

    public class WaterDeferredInventoryCostService : IWaterDeferredInventoryCostService
    {
        private readonly string _cs;
        public WaterDeferredInventoryCostService(string cs) => _cs = cs;

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
        // named-argument bind resolves to the one overload 281 defines.
        private static void AddN(NpgsqlCommand cmd, string name, NpgsqlDbType type, object? value)
            => cmd.Parameters.Add(new NpgsqlParameter(name, type) { Value = value ?? DBNull.Value });

        public async Task<WaterDeferredCostResponse> GetAsync(
            string farmId, string? scope, int? itemId, int? supplierId,
            string? category, DateTime? fromDate, DateTime? toDate, string? search)
        {
            var res = new WaterDeferredCostResponse();

            // The scope is normalised here rather than trusted: 281 falls back to
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
                $"SELECT * FROM spwaterdeferredpurchase_summary({args}); " +
                $"SELECT * FROM spwaterdeferredpurchase_getall({args})", conn);

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
                res.Summary = new WaterDeferredCostSummaryModel
                {
                    RemainingDeferredCost = Dec(r, "remainingdeferredcost"),
                    RecognizedCost = Dec(r, "recognizedcost"),
                    DeferredBasis = Dec(r, "deferredbasis"),
                    OperationalCost = Dec(r, "operationalcost"),
                    PurchaseCount = Int(r, "purchasecount"),
                    DeferredPurchases = Int(r, "deferredpurchases"),
                    FullyRecognized = Int(r, "fullyrecognized"),
                    NotRecognized = Int(r, "notrecognized"),
                    Exceptions = Int(r, "exceptions"),
                    ExceptionDrift = Dec(r, "exceptiondrift"),
                    RecognitionPercent = Dec(r, "recognitionpercent"),
                    BlockedPurchases = Int(r, "blockedpurchases"),
                    BlockedCost = Dec(r, "blockedcost"),
                };
            }

            if (await r.NextResultAsync())
            {
                while (await r.ReadAsync())
                {
                    res.Purchases.Add(new WaterDeferredPurchaseModel
                    {
                        WaterRawMaterialPurchaseId = Int(r, "waterrawmaterialpurchaseid"),
                        PurchaseDate = Dt(r, "purchasedate"),
                        WaterRawMaterialItemId = Int(r, "waterrawmaterialitemid"),
                        ItemName = StrN(r, "itemname"),
                        Category = StrN(r, "category"),
                        UnitOfMeasure = StrN(r, "unitofmeasure"),
                        ProductionUnit = StrN(r, "productionunit"),
                        SupplierId = IntN(r, "supplierid"),
                        SupplierName = StrN(r, "suppliername"),
                        PurchasedQuantity = Dec(r, "purchasedquantity"),
                        ConsumedQuantity = Dec(r, "consumedquantity"),
                        RemainingQuantity = Dec(r, "remainingquantity"),
                        OperationalCost = Dec(r, "operationalcost"),
                        DeferredTotalCost = Dec(r, "deferredtotalcost"),
                        RecognizedCost = Dec(r, "recognizedcost"),
                        DeferredRemainingCost = Dec(r, "deferredremainingcost"),
                        RecognitionPercent = Dec(r, "recognitionpercent"),
                        AllocatedRecognizedCost = Dec(r, "allocatedrecognizedcost"),
                        RecognitionDrift = Dec(r, "recognitiondrift"),
                        CostRecognitionMethod = StrN(r, "costrecognitionmethod"),
                        RecognitionMethodLabel = StrN(r, "recognitionmethodlabel"),
                        Status = StrN(r, "status"),
                        ExceptionReason = StrN(r, "exceptionreason"),
                        RecognitionEvents = Int(r, "recognitionevents"),
                        LastRecognitionDate = DtN(r, "lastrecognitiondate"),
                        CostingMethod = StrN(r, "costingmethod"),
                        QueuePosition = IntN(r, "queueposition"),
                        QuantityAheadInQueue = DecN(r, "quantityaheadinqueue"),
                    });
                }
            }

            return res;
        }

        public async Task<List<WaterDeferredRecognitionModel>> GetHistoryAsync(string farmId, int purchaseId)
        {
            var list = new List<WaterDeferredRecognitionModel>();

            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spwaterdeferredpurchase_history(" +
                "p_farmid => @FarmId::text, p_purchaseid => @PurchaseId::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@PurchaseId", purchaseId);

            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                list.Add(new WaterDeferredRecognitionModel
                {
                    WaterRawMaterialUsageId = Int(r, "waterrawmaterialusageid"),
                    UsedDate = Dt(r, "useddate"),
                    SourceType = StrN(r, "sourcetype"),
                    SourceLabel = StrN(r, "sourcelabel"),
                    WaterProductionBatchId = IntN(r, "waterproductionbatchid"),
                    // 281 spells these columns `productionbatchnumber` and
                    // `productname`; the properties carry the names the page
                    // reads, batchNumber and productName.
                    BatchNumber = StrN(r, "productionbatchnumber"),
                    ProductName = StrN(r, "productname"),
                    ItemName = StrN(r, "itemname"),
                    ProductionUnit = StrN(r, "productionunit"),
                    QuantityDrawn = Dec(r, "quantitydrawn"),
                    UnitCostAtDraw = Dec(r, "unitcostatdraw"),
                    OperationalCost = Dec(r, "operationalcost"),
                    RecognizedCost = Dec(r, "recognizedcost"),
                    RecognitionOutcome = StrN(r, "recognitionoutcome"),
                    IsReversed = Bool(r, "isreversed"),
                    ReversedAt = DtN(r, "reversedat"),
                    // 281's column is `expenseid`; the JSON the page reads is
                    // waterExpenseId.
                    WaterExpenseId = IntN(r, "expenseid"),
                    ExpenseAmount = DecN(r, "expenseamount"),
                    ExpenseStatus = StrN(r, "expensestatus"),
                });
            }
            return list;
        }

        public async Task<List<WaterConsumptionCostLayerModel>> GetCostBreakdownAsync(string farmId, int productionBatchId)
        {
            var list = new List<WaterConsumptionCostLayerModel>();

            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spwaterconsumption_costbreakdown(" +
                "p_farmid => @FarmId::text, p_waterproductionbatchid => @WaterProductionBatchId::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@WaterProductionBatchId", productionBatchId);

            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                list.Add(new WaterConsumptionCostLayerModel
                {
                    WaterRawMaterialUsageId = Int(r, "waterrawmaterialusageid"),
                    WaterRawMaterialItemId = Int(r, "waterrawmaterialitemid"),
                    ItemName = StrN(r, "itemname"),
                    Category = StrN(r, "category"),
                    UsedDate = Dt(r, "useddate"),
                    TotalQuantityUsed = Dec(r, "totalquantityused"),
                    ProductionUnit = StrN(r, "productionunit"),
                    WaterRawMaterialPurchaseId = Int(r, "waterrawmaterialpurchaseid"),
                    PurchaseDate = Dt(r, "purchasedate"),
                    SupplierName = StrN(r, "suppliername"),
                    QuantityDrawn = Dec(r, "quantitydrawn"),
                    UnitCostAtDraw = Dec(r, "unitcostatdraw"),
                    OperationalCost = Dec(r, "operationalcost"),
                    RecognizedCost = Dec(r, "recognizedcost"),
                    LotRecognitionMethod = StrN(r, "lotrecognitionmethod"),
                    RecognitionLabel = StrN(r, "recognitionlabel"),
                    IsReversed = Bool(r, "isreversed"),
                });
            }
            return list;
        }
    }
}
