using Npgsql;

namespace PoultryFarmAPIWeb.Business
{
    // Generic Deferred inventory cost, purchase by purchase (migration 452,
    // Report 40 Part 6). The Poultry/Water page's shapes; the lots are derived
    // from genericstockmovements (FIFO), read-only.
    public class GenericDeferredLot
    {
        public int? GenericPurchaseId { get; set; }
        public int LotId { get; set; }
        public DateTime PurchaseDate { get; set; }
        public int GenericProductId { get; set; }
        public string? ItemName { get; set; }
        public string? Category { get; set; }
        public string? UnitOfMeasure { get; set; }
        public string? ProductionUnit { get; set; }
        public int? SupplierId { get; set; }
        public string? SupplierName { get; set; }
        public string? LotSource { get; set; }
        public decimal PurchasedQuantity { get; set; }
        public decimal ConsumedQuantity { get; set; }
        public decimal RemainingQuantity { get; set; }
        public decimal OperationalCost { get; set; }
        public decimal DeferredTotalCost { get; set; }
        public decimal RecognizedCost { get; set; }
        public decimal DeferredRemainingCost { get; set; }
        public decimal RecognitionPercent { get; set; }
        public decimal AllocatedRecognizedCost { get; set; }
        public decimal RecognitionDrift { get; set; }
        public string? CostRecognitionMethod { get; set; } = "OnConsumption";
        public string? RecognitionMethodLabel { get; set; } = "Expensed when sold or used";
        public string? Status { get; set; }
        public string? ExceptionReason { get; set; }
        public int RecognitionEvents { get; set; }
        public DateTime? LastRecognitionDate { get; set; }
        public string? CostingMethod { get; set; } = "FIFO";
        public int? QueuePosition { get; set; }
        public decimal? QuantityAheadInQueue { get; set; }
    }

    public class GenericDeferredSummary
    {
        public decimal RemainingDeferredCost { get; set; }
        public decimal RecognizedCost { get; set; }
        public decimal DeferredBasis { get; set; }
        public decimal OperationalCost { get; set; }
        public int PurchaseCount { get; set; }
        public int DeferredPurchases { get; set; }
        public int FullyRecognized { get; set; }
        public int NotRecognized { get; set; }
        public int Exceptions { get; set; }
        public decimal ExceptionDrift { get; set; }
        public decimal RecognitionPercent { get; set; }
        public int BlockedPurchases { get; set; }
        public decimal BlockedCost { get; set; }
    }

    public class GenericDeferredResponse
    {
        public GenericDeferredSummary Summary { get; set; } = new();
        public List<GenericDeferredLot> Purchases { get; set; } = new();
    }

    public class GenericDeferredDraw
    {
        public int GenericStockMovementId { get; set; }
        public DateTime UsedDate { get; set; }
        public string? SourceType { get; set; }
        public string? SourceLabel { get; set; }
        public int? ReferenceId { get; set; }
        public string? ItemName { get; set; }
        public string? ProductionUnit { get; set; }
        public decimal QuantityDrawn { get; set; }
        public decimal UnitCostAtDraw { get; set; }
        public decimal OperationalCost { get; set; }
        public decimal RecognizedCost { get; set; }
        public string? RecognitionOutcome { get; set; }
        public bool IsReversed { get; set; }
    }

    public interface IGenericDeferredInventoryCostService
    {
        Task<GenericDeferredResponse> GetAsync(string farmId, string? scope, int? itemId, int? supplierId,
            string? category, DateTime? fromDate, DateTime? toDate, string? search);
        Task<List<GenericDeferredDraw>> GetHistoryAsync(string farmId, int lotId);
    }

    public class GenericDeferredInventoryCostService : IGenericDeferredInventoryCostService
    {
        private readonly string _cs;
        public GenericDeferredInventoryCostService(string cs) => _cs = cs;

        private static object Db(object? v) => v ?? DBNull.Value;
        private static decimal Dec(NpgsqlDataReader r, string c) { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? 0m : r.GetDecimal(i); }
        private static int? IntN(NpgsqlDataReader r, string c) { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? null : r.GetInt32(i); }
        private static string? Str(NpgsqlDataReader r, string c) { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? null : r.GetString(i); }
        private static DateTime? DateN(NpgsqlDataReader r, string c) { var i = r.GetOrdinal(c); return r.IsDBNull(i) ? null : r.GetDateTime(i); }

        private async Task<List<GenericDeferredLot>> LotsAsync(string farmId, string scope, int? itemId, int? supplierId,
            string? category, DateTime? fromDate, DateTime? toDate, string? search)
        {
            var list = new List<GenericDeferredLot>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM spgenericdeferredcost_lots(p_farmid => @F::text, p_scope => @S::text, p_productid => @P::int, " +
                "p_supplierid => @Sup::int, p_category => @C::text, p_fromdate => @From::timestamp, p_todate => @To::timestamp, " +
                "p_search => @Q::text)", c);
            cmd.Parameters.AddWithValue("@F", farmId);
            cmd.Parameters.AddWithValue("@S", scope);
            cmd.Parameters.AddWithValue("@P", Db(itemId));
            cmd.Parameters.AddWithValue("@Sup", Db(supplierId));
            cmd.Parameters.AddWithValue("@C", Db(string.IsNullOrWhiteSpace(category) ? null : category));
            cmd.Parameters.AddWithValue("@From", Db(fromDate));
            cmd.Parameters.AddWithValue("@To", Db(toDate));
            cmd.Parameters.AddWithValue("@Q", Db(string.IsNullOrWhiteSpace(search) ? null : search.Trim()));
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
            {
                var lot = new GenericDeferredLot
                {
                    GenericPurchaseId = IntN(r, "genericpurchaseid"),
                    LotId = r.GetInt32(r.GetOrdinal("lotid")),
                    PurchaseDate = r.GetDateTime(r.GetOrdinal("purchasedate")),
                    GenericProductId = r.GetInt32(r.GetOrdinal("genericproductid")),
                    ItemName = Str(r, "itemname"),
                    Category = Str(r, "category"),
                    UnitOfMeasure = Str(r, "unitofmeasure"),
                    SupplierId = IntN(r, "supplierid"),
                    SupplierName = Str(r, "suppliername"),
                    LotSource = Str(r, "lotsource"),
                    PurchasedQuantity = Dec(r, "purchasedquantity"),
                    ConsumedQuantity = Dec(r, "consumedquantity"),
                    RemainingQuantity = Dec(r, "remainingquantity"),
                    OperationalCost = Dec(r, "operationalcost"),
                    RecognizedCost = Dec(r, "recognizedcost"),
                    DeferredRemainingCost = Dec(r, "deferredremainingcost"),
                    RecognitionPercent = Dec(r, "recognitionpercent"),
                    Status = Str(r, "status"),
                    RecognitionEvents = r.GetInt32(r.GetOrdinal("recognitionevents")),
                    LastRecognitionDate = DateN(r, "lastrecognitiondate"),
                    QueuePosition = IntN(r, "queueposition"),
                    QuantityAheadInQueue = r.IsDBNull(r.GetOrdinal("quantityaheadinqueue")) ? null : Dec(r, "quantityaheadinqueue"),
                };
                lot.ProductionUnit = lot.UnitOfMeasure;
                lot.DeferredTotalCost = lot.OperationalCost;       // Generic defers every lot until it is sold or used
                lot.AllocatedRecognizedCost = lot.RecognizedCost;  // one count, so no drift
                list.Add(lot);
            }
            return list;
        }

        public async Task<GenericDeferredResponse> GetAsync(string farmId, string? scope, int? itemId, int? supplierId,
            string? category, DateTime? fromDate, DateTime? toDate, string? search)
        {
            // The summary covers every lot the other filters allow; the scope picks the rows shown.
            var all = await LotsAsync(farmId, "ALL", itemId, supplierId, category, fromDate, toDate, search);
            var sc = (scope ?? "DEFERRED").ToUpperInvariant();
            var rows = sc switch
            {
                "ALL" => all,
                "RECOGNIZED" => all.Where(l => l.RemainingQuantity <= 0).ToList(),
                "EXCEPTION" => new List<GenericDeferredLot>(),
                _ => all.Where(l => l.RemainingQuantity > 0).ToList(),
            };
            var basis = all.Sum(l => l.DeferredTotalCost);
            var rec = all.Sum(l => l.RecognizedCost);
            var blocked = all.Where(l => (l.QueuePosition ?? 0) > 1).ToList();
            return new GenericDeferredResponse
            {
                Purchases = rows,
                Summary = new GenericDeferredSummary
                {
                    RemainingDeferredCost = all.Sum(l => l.DeferredRemainingCost),
                    RecognizedCost = rec,
                    DeferredBasis = basis,
                    OperationalCost = all.Sum(l => l.OperationalCost),
                    PurchaseCount = all.Count,
                    DeferredPurchases = all.Count(l => l.RemainingQuantity > 0),
                    FullyRecognized = all.Count(l => l.RemainingQuantity <= 0),
                    NotRecognized = all.Count(l => l.ConsumedQuantity <= 0),
                    Exceptions = 0,
                    ExceptionDrift = 0,
                    RecognitionPercent = basis > 0 ? Math.Round(100m * rec / basis, 1) : 0,
                    BlockedPurchases = blocked.Count,
                    BlockedCost = blocked.Sum(l => l.DeferredRemainingCost),
                },
            };
        }

        public async Task<List<GenericDeferredDraw>> GetHistoryAsync(string farmId, int lotId)
        {
            var list = new List<GenericDeferredDraw>();
            using var c = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM spgenericdeferredcost_history(p_farmid => @F::text, p_lotid => @L::int)", c);
            cmd.Parameters.AddWithValue("@F", farmId);
            cmd.Parameters.AddWithValue("@L", lotId);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Add(new GenericDeferredDraw
                {
                    GenericStockMovementId = r.GetInt32(r.GetOrdinal("movementid")),
                    UsedDate = r.GetDateTime(r.GetOrdinal("useddate")),
                    SourceType = Str(r, "sourcetype"),
                    SourceLabel = Str(r, "sourcelabel"),
                    ReferenceId = IntN(r, "referenceid"),
                    ItemName = Str(r, "itemname"),
                    QuantityDrawn = Dec(r, "quantitydrawn"),
                    UnitCostAtDraw = Dec(r, "unitcostatdraw"),
                    OperationalCost = Dec(r, "operationalcost"),
                    RecognizedCost = Dec(r, "recognizedcost"),
                    RecognitionOutcome = Str(r, "recognitionoutcome"),
                });
            return list;
        }
    }
}
