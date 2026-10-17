using System.Data;
using System.Text.Json;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    // Poultry products/stock/recipes/batches/losses/daily-closing services (slices 2-6).
    // Additive; mirrors the Water production services. Raw ADO.NET + spPoultry*.

    internal static class PoultryRdr
    {
        public static bool Has(this NpgsqlDataReader r, string n)
        {
            for (int i = 0; i < r.FieldCount; i++) if (string.Equals(r.GetName(i), n, StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }
        public static string Str(this NpgsqlDataReader r, string n) => r.GetString(r.GetOrdinal(n));
        public static string? StrN(this NpgsqlDataReader r, string n) { int i = r.GetOrdinal(n); return r.IsDBNull(i) ? null : r.GetString(i); }
        public static int Int(this NpgsqlDataReader r, string n) => r.GetInt32(r.GetOrdinal(n));
        public static int? IntN(this NpgsqlDataReader r, string n) { int i = r.GetOrdinal(n); return r.IsDBNull(i) ? (int?)null : r.GetInt32(i); }
        public static decimal Dec(this NpgsqlDataReader r, string n) => r.GetDecimal(r.GetOrdinal(n));
        public static decimal? DecN(this NpgsqlDataReader r, string n) { int i = r.GetOrdinal(n); return r.IsDBNull(i) ? (decimal?)null : r.GetDecimal(i); }
        public static bool Bool(this NpgsqlDataReader r, string n) => r.GetBoolean(r.GetOrdinal(n));
        public static DateTime Date(this NpgsqlDataReader r, string n) => r.GetDateTime(r.GetOrdinal(n));
        public static DateTime? DateN(this NpgsqlDataReader r, string n) { int i = r.GetOrdinal(n); return r.IsDBNull(i) ? (DateTime?)null : r.GetDateTime(i); }
    }

    // ============================ Products ============================
    public interface IPoultryProductService
    {
        Task<List<PoultryProductModel>> GetAllAsync(string farmId);
        Task<PoultryProductModel?> GetByIdAsync(int id, string farmId);
        Task<int> InsertAsync(PoultryProductModel m);
        Task UpdateAsync(PoultryProductModel m);
        Task DeleteAsync(int id, string farmId);
        Task<int> EnsureDefaultEggAsync(string farmId);
        Task<int> EnsureDefaultBirdsAsync(string farmId);
        Task<List<ProductReconcileRow>> ReconcileStockAsync(string farmId, int? productId);
        Task<decimal> SetStockAsync(int productId, ProductSetStockRequest req);
    }

    public class PoultryProductService : IPoultryProductService
    {
        private readonly string _cs; public PoultryProductService(string cs) => _cs = cs;
        private static PoultryProductModel Map(NpgsqlDataReader r) => new()
        {
            PoultryProductId = r.Int("PoultryProductId"), FarmId = r.Str("FarmId"), Name = r.Str("Name"),
            Sku = r.StrN("Sku"), Unit = r.StrN("Unit"), UnitPrice = r.Dec("UnitPrice"), ProductType = r.Str("ProductType"),
            IsActive = r.Bool("IsActive"), Notes = r.StrN("Notes"),
            IsRawEggProduct = r.Has("IsRawEggProduct") && r.Bool("IsRawEggProduct"),
            RequiresRecipeSetup = !r.Has("RequiresRecipeSetup") || r.Bool("RequiresRecipeSetup"),
            IsBirdProduct = r.Has("IsBirdProduct") && r.Bool("IsBirdProduct"),
            Size = r.Has("Size") ? r.StrN("Size") : null,
            StockOnHand = r.Has("StockOnHand") ? r.Dec("StockOnHand") : 0,
            CreatedDate = r.Date("CreatedDate"), UpdatedDate = r.DateN("UpdatedDate"),
        };
        public async Task<List<PoultryProductModel>> GetAllAsync(string farmId)
        {
            var list = new List<PoultryProductModel>();
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryproduct_getall(p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId); await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync(); while (await r.ReadAsync()) list.Add(Map(r));
            return list;
        }
        public async Task<PoultryProductModel?> GetByIdAsync(int id, string farmId)
            => (await GetAllAsync(farmId)).FirstOrDefault(x => x.PoultryProductId == id);
        public async Task<List<ProductReconcileRow>> ReconcileStockAsync(string farmId, int? productId)
        {
            var list = new List<ProductReconcileRow>();
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryproduct_reconcilestock(p_farmid => @FarmId::text, p_poultryproductid => @PoultryProductId::int)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@PoultryProductId", (object?)productId ?? DBNull.Value);
            await c.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync())
                list.Add(new ProductReconcileRow { ProductId = r.Int("PoultryProductId"), Name = r.Str("Name"), StockIn = r.Dec("StockIn"), StockOut = r.Dec("StockOut"), CurrentStock = r.Dec("CurrentStock") });
            return list;
        }
        public async Task<decimal> SetStockAsync(int productId, ProductSetStockRequest req)
        {
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryproduct_setstock(p_farmid => @FarmId::text, p_poultryproductid => @PoultryProductId::int, p_targetquantity => @TargetQuantity::numeric, p_note => @Note::text, p_createdby => @CreatedBy::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", req.FarmId);
            cmd.Parameters.AddWithValue("@PoultryProductId", productId);
            cmd.Parameters.AddWithValue("@TargetQuantity", req.TargetQuantity);
            cmd.Parameters.AddWithValue("@Note", (object?)req.Note ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)req.CreatedBy ?? DBNull.Value);
            await c.OpenAsync();
            var v = await cmd.ExecuteScalarAsync();
            return v is null || v == DBNull.Value ? 0 : Convert.ToDecimal(v);
        }
        public async Task<int> InsertAsync(PoultryProductModel m)
        {
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryproduct_insert(p_farmid => @FarmId::text, p_name => @Name::text, p_sku => @Sku::text, p_unit => @Unit::text, p_unitprice => @UnitPrice::numeric, p_producttype => @ProductType::text, p_notes => @Notes::text, p_israweggproduct => @IsRawEggProduct::boolean, p_requiresrecipesetup => @RequiresRecipeSetup::boolean, p_size => @Size::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId); cmd.Parameters.AddWithValue("@Name", m.Name);
            cmd.Parameters.AddWithValue("@Sku", (object?)m.Sku ?? DBNull.Value); cmd.Parameters.AddWithValue("@Unit", (object?)m.Unit ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@UnitPrice", m.UnitPrice); cmd.Parameters.AddWithValue("@ProductType", m.ProductType ?? "FinishedGood");
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsRawEggProduct", m.IsRawEggProduct);
            cmd.Parameters.AddWithValue("@RequiresRecipeSetup", m.RequiresRecipeSetup);
            cmd.Parameters.AddWithValue("@Size", (object?)m.Size ?? DBNull.Value);
            await c.OpenAsync(); return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }
        public async Task UpdateAsync(PoultryProductModel m)
        {
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryproduct_update(p_poultryproductid => @PoultryProductId::int, p_farmid => @FarmId::text, p_name => @Name::text, p_sku => @Sku::text, p_unit => @Unit::text, p_unitprice => @UnitPrice::numeric, p_producttype => @ProductType::text, p_isactive => @IsActive::boolean, p_notes => @Notes::text, p_israweggproduct => @IsRawEggProduct::boolean, p_requiresrecipesetup => @RequiresRecipeSetup::boolean, p_size => @Size::text)", c);
            cmd.Parameters.AddWithValue("@PoultryProductId", m.PoultryProductId); cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Name", m.Name); cmd.Parameters.AddWithValue("@Sku", (object?)m.Sku ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Unit", (object?)m.Unit ?? DBNull.Value); cmd.Parameters.AddWithValue("@UnitPrice", m.UnitPrice);
            cmd.Parameters.AddWithValue("@ProductType", m.ProductType ?? "FinishedGood"); cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsRawEggProduct", m.IsRawEggProduct);
            cmd.Parameters.AddWithValue("@RequiresRecipeSetup", m.RequiresRecipeSetup);
            cmd.Parameters.AddWithValue("@Size", (object?)m.Size ?? DBNull.Value);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }
        public async Task DeleteAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryproduct_delete(p_poultryproductid => @PoultryProductId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@PoultryProductId", id); cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }
        public async Task<int> EnsureDefaultEggAsync(string farmId)
        {
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryproduct_ensuredefaultegg(p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); var r = await cmd.ExecuteScalarAsync();
            return r is null || r == DBNull.Value ? 0 : Convert.ToInt32(r);
        }
        public async Task<int> EnsureDefaultBirdsAsync(string farmId)
        {
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryproduct_ensuredefaultbirds(p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); var r = await cmd.ExecuteScalarAsync();
            return r is null || r == DBNull.Value ? 0 : Convert.ToInt32(r);
        }
    }

    // ============================ Stock ============================
    public interface IPoultryStockService
    {
        Task<List<PoultryStockTransactionModel>> GetTransactionsAsync(string farmId, int? productId);
        Task<int> AddTransactionAsync(PoultryStockTransactionModel m);
        // 359: birds are adjusted per flock / batch, never as a bare ledger row.
        Task<List<PoultryBirdAdjustmentOption>> GetBirdAdjustmentOptionsAsync(string farmId);
        Task<List<PoultryBirdAdjustmentModel>> GetBirdAdjustmentsAsync(string farmId);
        Task<int> PostBirdAdjustmentAsync(PoultryBirdAdjustmentRequest m);
        // 373: manual stock movements (batch / flock / date / reason, reversible).
        Task<string> PreviewManualMovementAsync(string farmId, int? productId, int? rawItemId, int? batchId, int? flockId);
        Task<string> PostManualMovementAsync(PoultryManualMovementRequest m);
        Task<string> ReverseManualMovementAsync(int movementId, PoultryManualMovementReverseRequest m);
        Task<List<PoultryManualMovementModel>> GetManualMovementsAsync(string farmId);
        // 374: Broken Eggs / Dead Birds in Add Sale.
        Task<PoultryByproductSettings> GetByproductSettingsAsync(string farmId);
        Task SetByproductSettingsAsync(PoultryByproductSettings s);
        // Broken Eggs / Dead Birds trackers.
        Task<PoultryByproductTrackerResponse> GetByproductTrackerAsync(string farmId, string role, DateTime from, DateTime to, int? flockId);
    }
    public class PoultryStockService : IPoultryStockService
    {
        private readonly string _cs; public PoultryStockService(string cs) => _cs = cs;
        public async Task<List<PoultryStockTransactionModel>> GetTransactionsAsync(string farmId, int? productId)
        {
            var list = new List<PoultryStockTransactionModel>();
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrystock_gettransactions(p_farmid => @FarmId::text, p_poultryproductid => @PoultryProductId::int)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId); cmd.Parameters.AddWithValue("@PoultryProductId", (object?)productId ?? DBNull.Value);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(new PoultryStockTransactionModel
            {
                PoultryStockTransactionId = r.Int("PoultryStockTransactionId"), FarmId = r.Str("FarmId"),
                PoultryProductId = r.Int("PoultryProductId"), ProductName = r.StrN("ProductName"), TxnType = r.Str("TxnType"),
                Quantity = r.Dec("Quantity"), UnitCost = r.DecN("UnitCost"), RelatedId = r.IntN("RelatedId"),
                Note = r.StrN("Note"), CreatedDate = r.Date("CreatedDate"), CreatedBy = r.StrN("CreatedBy"),
                BatchId = r.IntN("BatchId"), BatchCode = r.StrN("BatchCode"), FlockId = r.IntN("FlockId"), FlockName = r.StrN("FlockName"),
                EffectiveDate = r.DateN("EffectiveDate"), Reason = r.StrN("Reason"),
                ManualMovementId = r.IntN("ManualMovementId"), ManualReversal = r.Bool("ManualReversal"),
            });
            return list;
        }
        public async Task<int> AddTransactionAsync(PoultryStockTransactionModel m)
        {
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrystock_addtransaction(p_farmid => @FarmId::text, p_poultryproductid => @PoultryProductId::int, p_txntype => @TxnType::text, p_quantity => @Quantity::numeric, p_unitcost => @UnitCost::numeric, p_relatedid => @RelatedId::int, p_note => @Note::text, p_createdby => @CreatedBy::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId); cmd.Parameters.AddWithValue("@PoultryProductId", m.PoultryProductId);
            cmd.Parameters.AddWithValue("@TxnType", m.TxnType); cmd.Parameters.AddWithValue("@Quantity", m.Quantity);
            cmd.Parameters.AddWithValue("@UnitCost", (object?)m.UnitCost ?? DBNull.Value); cmd.Parameters.AddWithValue("@RelatedId", (object?)m.RelatedId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Note", (object?)m.Note ?? DBNull.Value); cmd.Parameters.AddWithValue("@CreatedBy", (object?)m.CreatedBy ?? DBNull.Value);
            await c.OpenAsync(); return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task<List<PoultryBirdAdjustmentOption>> GetBirdAdjustmentOptionsAsync(string farmId)
        {
            var list = new List<PoultryBirdAdjustmentOption>();
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrybirdadjustment_options(p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(new PoultryBirdAdjustmentOption
            {
                BatchId = r.Int("BatchId"), BatchCode = r.StrN("BatchCode") ?? "", BatchName = r.StrN("BatchName") ?? "",
                BatchBirds = r.Int("BatchBirds"), UnplacedBirds = r.Int("UnplacedBirds"),
                FlockId = r.IntN("FlockId"), FlockName = r.StrN("FlockName"), LiveBirds = r.IntN("LiveBirds"),
                LastCountDate = r.DateN("LastCountDate"), HasProductionRecord = r.Bool("HasProductionRecord"), IsClosed = r.Bool("IsClosed"),
            });
            return list;
        }

        public async Task<List<PoultryBirdAdjustmentModel>> GetBirdAdjustmentsAsync(string farmId)
        {
            var list = new List<PoultryBirdAdjustmentModel>();
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrybirdadjustment_getall(p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(new PoultryBirdAdjustmentModel
            {
                BirdAdjustmentId = r.Int("BirdAdjustmentId"), AdjustmentDate = r.Date("AdjustmentDate"),
                BatchId = r.Int("BatchId"), BatchCode = r.StrN("BatchCode"), FlockId = r.IntN("FlockId"), FlockName = r.StrN("FlockName"),
                MovementType = r.Str("MovementType"), Quantity = r.Int("Quantity"), BirdsBefore = r.Int("BirdsBefore"), BirdsAfter = r.Int("BirdsAfter"),
                ProductionRecordId = r.IntN("ProductionRecordId"), Note = r.StrN("Note"), CreatedBy = r.StrN("CreatedBy"), CreatedAt = r.Date("CreatedAt"),
            });
            return list;
        }

        public async Task<int> PostBirdAdjustmentAsync(PoultryBirdAdjustmentRequest m)
        {
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT sppoultrybirdadjustment_post(p_farmid => @FarmId::text, p_batchid => @BatchId::int, p_flockid => @FlockId::int, p_movementtype => @MovementType::text, p_quantity => @Quantity::int, p_note => @Note::text, p_by => @By::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId); cmd.Parameters.AddWithValue("@BatchId", m.BatchId);
            cmd.Parameters.AddWithValue("@FlockId", (object?)m.FlockId ?? DBNull.Value); cmd.Parameters.AddWithValue("@MovementType", m.MovementType ?? "Adjustment");
            cmd.Parameters.AddWithValue("@Quantity", m.Quantity); cmd.Parameters.AddWithValue("@Note", (object?)m.Note ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@By", (object?)m.CreatedBy ?? DBNull.Value);
            await c.OpenAsync(); return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task<string> PreviewManualMovementAsync(string farmId, int? productId, int? rawItemId, int? batchId, int? flockId)
        {
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand(
                "SELECT sppoultrymanualmovement_preview(p_farmid => @FarmId::text, p_poultryproductid => @P::int, " +
                "p_rawmaterialitemid => @R::int, p_batchid => @B::int, p_flockid => @F::int)::text", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@P", (object?)productId ?? DBNull.Value); cmd.Parameters.AddWithValue("@R", (object?)rawItemId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@B", (object?)batchId ?? DBNull.Value); cmd.Parameters.AddWithValue("@F", (object?)flockId ?? DBNull.Value);
            await c.OpenAsync(); return (string?)await cmd.ExecuteScalarAsync() ?? "{}";
        }

        public async Task<string> PostManualMovementAsync(PoultryManualMovementRequest m)
        {
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand(
                "SELECT sppoultrymanualmovement_post(p_farmid => @FarmId::text, p_poultryproductid => @P::int, p_rawmaterialitemid => @R::int, " +
                "p_movementtype => @Type::text, p_quantity => @Qty::numeric, p_unitcost => @Cost::numeric, p_batchid => @B::int, p_flockid => @F::int, " +
                "p_effectivedate => @Date::date, p_reason => @Reason::text, p_disposition => @Disp::text, p_note => @Note::text, " +
                "p_requestkey => @Key::text, p_by => @By::text)::text", c);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@P", (object?)m.PoultryProductId ?? DBNull.Value); cmd.Parameters.AddWithValue("@R", (object?)m.RawMaterialItemId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Type", m.MovementType ?? string.Empty); cmd.Parameters.AddWithValue("@Qty", m.Quantity);
            cmd.Parameters.AddWithValue("@Cost", (object?)m.UnitCost ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@B", (object?)m.BatchId ?? DBNull.Value); cmd.Parameters.AddWithValue("@F", (object?)m.FlockId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Date", m.EffectiveDate.HasValue ? m.EffectiveDate.Value.Date : DBNull.Value);
            cmd.Parameters.AddWithValue("@Reason", m.Reason ?? string.Empty); cmd.Parameters.AddWithValue("@Disp", (object?)m.Disposition ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Note", (object?)m.Note ?? DBNull.Value); cmd.Parameters.AddWithValue("@Key", (object?)m.RequestKey ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@By", (object?)m.CreatedBy ?? DBNull.Value);
            await c.OpenAsync(); return (string?)await cmd.ExecuteScalarAsync() ?? "{}";
        }

        public async Task<string> ReverseManualMovementAsync(int movementId, PoultryManualMovementReverseRequest m)
        {
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand(
                "SELECT sppoultrymanualmovement_reverse(p_farmid => @FarmId::text, p_movementid => @Id::int, p_reason => @Reason::text, p_by => @By::text)::text", c);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId); cmd.Parameters.AddWithValue("@Id", movementId);
            cmd.Parameters.AddWithValue("@Reason", m.Reason ?? string.Empty); cmd.Parameters.AddWithValue("@By", (object?)m.ReversedBy ?? DBNull.Value);
            await c.OpenAsync(); return (string?)await cmd.ExecuteScalarAsync() ?? "{}";
        }

        public async Task<PoultryByproductSettings> GetByproductSettingsAsync(string farmId)
        {
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrybyproductsettings_get(p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            var s = new PoultryByproductSettings { FarmId = farmId, BrokenEggsInSales = true, DeadBirdsInSales = false };
            if (await r.ReadAsync())
            {
                s.BrokenEggsInSales = r.Bool("BrokenEggsInSales"); s.DeadBirdsInSales = r.Bool("DeadBirdsInSales"); s.CutoverAt = r.DateN("CutoverAt");
            }
            return s;
        }

        public async Task<PoultryByproductTrackerResponse> GetByproductTrackerAsync(string farmId, string role, DateTime from, DateTime to, int? flockId)
        {
            var res = new PoultryByproductTrackerResponse { Role = role };
            using var c = new NpgsqlConnection(_cs);
            await c.OpenAsync();

            using (var cmd = new NpgsqlCommand("SELECT fnpoultry_byproductonhand(@FarmId::text, @Role::text)", c))
            {
                cmd.Parameters.AddWithValue("@FarmId", farmId); cmd.Parameters.AddWithValue("@Role", role);
                res.OnHand = Convert.ToDecimal(await cmd.ExecuteScalarAsync() ?? 0m);
            }

            using (var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryreport_byproducts(p_farmid => @FarmId::text, p_startdate => @S::date, p_enddate => @E::date, " +
                "p_flockid => @Flock::int, p_role => @Role::text, p_byflock => TRUE)", c))
            {
                cmd.Parameters.AddWithValue("@FarmId", farmId); cmd.Parameters.AddWithValue("@S", from.Date); cmd.Parameters.AddWithValue("@E", to.Date);
                cmd.Parameters.AddWithValue("@Flock", (object?)flockId ?? DBNull.Value); cmd.Parameters.AddWithValue("@Role", role);
                using var r = await cmd.ExecuteReaderAsync();
                while (await r.ReadAsync()) res.Flocks.Add(new PoultryByproductTrackerFlockRow
                {
                    FlockId = r.IntN("flockid"), FlockName = r.StrN("flockname"), BatchCode = r.StrN("batchcode"),
                    Opening = r.Dec("opening"), Generated = r.Dec("generated"), Sold = r.Dec("sold"), Disposed = r.Dec("disposed"),
                    InternalUse = r.Dec("internaluse"), ManualIn = r.Dec("manualin"), ManualOut = r.Dec("manualout"),
                    Reversals = r.Dec("reversals"), Closing = r.Dec("closing"), Revenue = r.Dec("revenue"),
                });
            }

            using (var cmd = new NpgsqlCommand(
                "SELECT * FROM sppoultryreport_byproductmovements(p_farmid => @FarmId::text, p_startdate => @S::date, p_enddate => @E::date, " +
                "p_flockid => @Flock::int, p_role => @Role::text) ORDER BY bdate, txnid", c))
            {
                cmd.Parameters.AddWithValue("@FarmId", farmId); cmd.Parameters.AddWithValue("@S", from.Date); cmd.Parameters.AddWithValue("@E", to.Date);
                cmd.Parameters.AddWithValue("@Flock", (object?)flockId ?? DBNull.Value); cmd.Parameters.AddWithValue("@Role", role);
                using var r = await cmd.ExecuteReaderAsync();
                while (await r.ReadAsync()) res.Movements.Add(new PoultryByproductTrackerMovement
                {
                    TxnId = r.Int("txnid"), Date = r.Date("bdate"), Category = r.StrN("category") ?? "", TxnType = r.StrN("txntype") ?? "",
                    Quantity = r.Dec("quantity"), FlockId = r.IntN("flockid"), FlockName = r.StrN("flockname"), BatchCode = r.StrN("batchcode"),
                    SaleId = r.IntN("saleid"), Revenue = r.DecN("revenue") ?? 0m, ManualMovementId = r.IntN("manualmovementid"),
                    MovementNo = r.StrN("movementno"), Note = r.StrN("note"),
                });
            }
            return res;
        }

        public async Task SetByproductSettingsAsync(PoultryByproductSettings s)
        {
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand(
                "SELECT sppoultrybyproductsettings_set(p_farmid => @FarmId::text, p_brokeneggsinsales => @B::boolean, p_deadbirdsinsales => @D::boolean, p_by => @By::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", s.FarmId);
            cmd.Parameters.AddWithValue("@B", (object?)s.BrokenEggsInSales ?? DBNull.Value); cmd.Parameters.AddWithValue("@D", (object?)s.DeadBirdsInSales ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@By", (object?)s.UpdatedBy ?? DBNull.Value);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }

        public async Task<List<PoultryManualMovementModel>> GetManualMovementsAsync(string farmId)
        {
            var list = new List<PoultryManualMovementModel>();
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrymanualmovement_list(p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(new PoultryManualMovementModel
            {
                MovementId = r.Int("MovementId"), MovementNo = r.Str("MovementNo"), ItemKind = r.Str("ItemKind"),
                PoultryProductId = r.IntN("PoultryProductId"), RawMaterialItemId = r.IntN("RawMaterialItemId"),
                ItemName = r.Str("ItemName"), MovementType = r.Str("MovementType"), Quantity = r.Dec("Quantity"), UnitCost = r.DecN("UnitCost"),
                BatchId = r.IntN("BatchId"), BatchCode = r.StrN("BatchCode"), FlockId = r.IntN("FlockId"), FlockName = r.StrN("FlockName"),
                EffectiveDate = r.Date("EffectiveDate"), Reason = r.Str("Reason"), Disposition = r.StrN("Disposition"),
                ConvertedToBroken = r.Bool("ConvertedToBroken"), Note = r.StrN("Note"),
                ItemBefore = r.DecN("ItemBefore"), ItemAfter = r.DecN("ItemAfter"),
                BirdAdjustmentId = r.IntN("BirdAdjustmentId"), RawAdjustmentId = r.IntN("RawAdjustmentId"),
                Status = r.Str("Status"), CreatedBy = r.StrN("CreatedBy"), CreatedAt = r.Date("CreatedAt"),
                ReversedAt = r.DateN("ReversedAt"), ReversedBy = r.StrN("ReversedBy"), ReversalReason = r.StrN("ReversalReason"),
            });
            return list;
        }
    }

    // ============================ Recipes ============================
    public interface IPoultryProductionRecipeService
    {
        Task<PoultryProductionRecipeModel?> GetByProductAsync(string farmId, int productId);
        Task<int> UpsertAsync(string farmId, int productId, PoultryProductionRecipeUpsertRequest req);
        Task DeleteAsync(string farmId, int recipeId);
    }
    public class PoultryProductionRecipeService : IPoultryProductionRecipeService
    {
        private readonly string _cs; public PoultryProductionRecipeService(string cs) => _cs = cs;
        public async Task<PoultryProductionRecipeModel?> GetByProductAsync(string farmId, int productId)
        {
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryproductionrecipe_getbyproduct_rs1(p_farmid => @FarmId::text, p_poultryproductid => @PoultryProductId::int); SELECT * FROM sppoultryproductionrecipe_getbyproduct_rs2(p_farmid => @FarmId::text, p_poultryproductid => @PoultryProductId::int)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId); cmd.Parameters.AddWithValue("@PoultryProductId", productId);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            PoultryProductionRecipeModel? recipe = null;
            if (await r.ReadAsync()) recipe = new PoultryProductionRecipeModel
            {
                PoultryProductionRecipeId = r.Int("PoultryProductionRecipeId"), FarmId = r.Str("FarmId"),
                PoultryProductId = r.Int("PoultryProductId"), RecipeName = r.StrN("RecipeName"), IsActive = r.Bool("IsActive"), Notes = r.StrN("Notes"),
            };
            if (recipe == null) return null;
            if (await r.NextResultAsync())
                while (await r.ReadAsync()) recipe.Items.Add(new PoultryProductionRecipeItemModel
                {
                    PoultryProductionRecipeItemId = r.Int("PoultryProductionRecipeItemId"), PoultryProductionRecipeId = r.Int("PoultryProductionRecipeId"),
                    PoultryRawMaterialItemId = r.Int("PoultryRawMaterialItemId"), ItemName = r.StrN("ItemName"), UnitOfMeasure = r.StrN("UnitOfMeasure"),
                    AvailableStock = r.Has("AvailableStock") ? r.Dec("AvailableStock") : 0, LatestUnitCost = r.Has("LatestUnitCost") ? r.Dec("LatestUnitCost") : 0,
                    QuantityPerOutputUnit = r.Dec("QuantityPerOutputUnit"), WasteAllowancePercent = r.Dec("WasteAllowancePercent"),
                    IsOptional = r.Bool("IsOptional"), DisplayOrder = r.Int("DisplayOrder"), Notes = r.StrN("Notes"),
                });
            return recipe;
        }
        public async Task<int> UpsertAsync(string farmId, int productId, PoultryProductionRecipeUpsertRequest req)
        {
            var itemsJson = JsonSerializer.Serialize(req.Items, new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase });
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryproductionrecipe_upsert(p_farmid => @FarmId::text, p_poultryproductid => @PoultryProductId::int, p_recipename => @RecipeName::text, p_notes => @Notes::text, p_itemsjson => @ItemsJson::text, p_updatedby => @UpdatedBy::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId); cmd.Parameters.AddWithValue("@PoultryProductId", productId);
            cmd.Parameters.AddWithValue("@RecipeName", (object?)req.RecipeName ?? DBNull.Value); cmd.Parameters.AddWithValue("@Notes", (object?)req.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ItemsJson", (object?)itemsJson ?? DBNull.Value); cmd.Parameters.AddWithValue("@UpdatedBy", (object?)req.UpdatedBy ?? DBNull.Value);
            await c.OpenAsync(); return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }
        public async Task DeleteAsync(string farmId, int recipeId)
        {
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryproductionrecipe_delete(p_farmid => @FarmId::text, p_poultryproductionrecipeid => @PoultryProductionRecipeId::int)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId); cmd.Parameters.AddWithValue("@PoultryProductionRecipeId", recipeId);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }
    }

    // ============================ Batches + Production loss ============================
    public interface IPoultryProductionBatchService
    {
        Task<List<PoultryProductionBatchModel>> GetAllAsync(string farmId, string? status, DateTime? fromDate, DateTime? toDate);
        Task<List<PoultryProductionMaterialUsageInput>> GetMaterialsAsync(string farmId, int batchId);
        Task<int> InsertAsync(PoultryProductionBatchModel m);
        Task UpdateAsync(PoultryProductionBatchModel m);
        Task ApproveAsync(int id, string farmId, string? approvedBy);
        Task CancelAsync(int id, string farmId);
        Task<List<PoultryProductionLossModel>> GetProductionLossesAsync(string farmId, DateTime? fromDate, DateTime? toDate);
    }
    public class PoultryProductionBatchService : IPoultryProductionBatchService
    {
        private readonly string _cs; public PoultryProductionBatchService(string cs) => _cs = cs;
        private static string MaterialsJson(List<PoultryProductionMaterialUsageInput> m)
            => JsonSerializer.Serialize(m ?? new(), new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase });
        private static PoultryProductionBatchModel Map(NpgsqlDataReader r) => new()
        {
            PoultryProductionBatchId = r.Int("PoultryProductionBatchId"), FarmId = r.Str("FarmId"), BatchNumber = r.Str("BatchNumber"),
            ProductionDate = r.Date("ProductionDate"), PoultryProductId = r.Int("PoultryProductId"), ProductName = r.StrN("ProductName"),
            QuantityProduced = r.Dec("QuantityProduced"), Unit = r.StrN("Unit"), DamagedQuantity = r.Dec("DamagedQuantity"),
            LaborCost = r.Dec("LaborCost"), OtherCost = r.Dec("OtherCost"), MaterialsCost = r.Dec("MaterialsCost"),
            TotalCost = r.Dec("TotalCost"), CostPerUnit = r.Dec("CostPerUnit"), Status = r.Str("Status"), Notes = r.StrN("Notes"),
            CreatedBy = r.StrN("CreatedBy"), ApprovedBy = r.StrN("ApprovedBy"), ApprovedAt = r.DateN("ApprovedAt"),
            CreatedAt = r.Date("CreatedAt"), UpdatedAt = r.DateN("UpdatedAt"),
        };
        public async Task<List<PoultryProductionBatchModel>> GetAllAsync(string farmId, string? status, DateTime? fromDate, DateTime? toDate)
        {
            var list = new List<PoultryProductionBatchModel>();
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryproductionbatch_getall(p_farmid => @FarmId::text, p_status => @Status::text, p_fromdate => @FromDate::date, p_todate => @ToDate::date)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId); cmd.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value); cmd.Parameters.AddWithValue("@ToDate", (object?)toDate ?? DBNull.Value);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync(); while (await r.ReadAsync()) list.Add(Map(r));
            return list;
        }
        public async Task<List<PoultryProductionMaterialUsageInput>> GetMaterialsAsync(string farmId, int batchId)
        {
            var list = new List<PoultryProductionMaterialUsageInput>();
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryproductionbatch_getmaterials(p_farmid => @FarmId::text, p_poultryproductionbatchid => @PoultryProductionBatchId::int)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId); cmd.Parameters.AddWithValue("@PoultryProductionBatchId", batchId);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(new PoultryProductionMaterialUsageInput
            {
                PoultryRawMaterialItemId = r.Int("PoultryRawMaterialItemId"), QuantityUsed = r.Dec("QuantityUsed"),
                ExpectedQuantityUsed = r.DecN("ExpectedQuantityUsed"), UnitCost = r.DecN("UnitCost"),
            });
            return list;
        }
        public async Task<int> InsertAsync(PoultryProductionBatchModel m)
        {
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryproductionbatch_insert(p_farmid => @FarmId::text, p_batchnumber => @BatchNumber::text, p_productiondate => @ProductionDate::timestamp, p_poultryproductid => @PoultryProductId::int, p_quantityproduced => @QuantityProduced::numeric, p_unit => @Unit::text, p_damagedquantity => @DamagedQuantity::numeric, p_laborcost => @LaborCost::numeric, p_othercost => @OtherCost::numeric, p_notes => @Notes::text, p_createdby => @CreatedBy::text, p_materialsusedjson => @MaterialsUsedJson::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId); cmd.Parameters.AddWithValue("@BatchNumber", m.BatchNumber);
            cmd.Parameters.AddWithValue("@ProductionDate", (object?)m.ProductionDate ?? DBNull.Value); cmd.Parameters.AddWithValue("@PoultryProductId", m.PoultryProductId);
            cmd.Parameters.AddWithValue("@QuantityProduced", m.QuantityProduced); cmd.Parameters.AddWithValue("@Unit", (object?)m.Unit ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DamagedQuantity", m.DamagedQuantity); cmd.Parameters.AddWithValue("@LaborCost", m.LaborCost);
            cmd.Parameters.AddWithValue("@OtherCost", m.OtherCost); cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)m.CreatedBy ?? DBNull.Value); cmd.Parameters.AddWithValue("@MaterialsUsedJson", MaterialsJson(m.MaterialsUsed));
            await c.OpenAsync(); return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }
        public async Task UpdateAsync(PoultryProductionBatchModel m)
        {
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryproductionbatch_update(p_poultryproductionbatchid => @PoultryProductionBatchId::int, p_farmid => @FarmId::text, p_batchnumber => @BatchNumber::text, p_productiondate => @ProductionDate::timestamp, p_poultryproductid => @PoultryProductId::int, p_quantityproduced => @QuantityProduced::numeric, p_unit => @Unit::text, p_damagedquantity => @DamagedQuantity::numeric, p_laborcost => @LaborCost::numeric, p_othercost => @OtherCost::numeric, p_notes => @Notes::text, p_materialsusedjson => @MaterialsUsedJson::text)", c);
            cmd.Parameters.AddWithValue("@PoultryProductionBatchId", m.PoultryProductionBatchId); cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@BatchNumber", m.BatchNumber); cmd.Parameters.AddWithValue("@ProductionDate", (object?)m.ProductionDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PoultryProductId", m.PoultryProductId); cmd.Parameters.AddWithValue("@QuantityProduced", m.QuantityProduced);
            cmd.Parameters.AddWithValue("@Unit", (object?)m.Unit ?? DBNull.Value); cmd.Parameters.AddWithValue("@DamagedQuantity", m.DamagedQuantity);
            cmd.Parameters.AddWithValue("@LaborCost", m.LaborCost); cmd.Parameters.AddWithValue("@OtherCost", m.OtherCost);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value); cmd.Parameters.AddWithValue("@MaterialsUsedJson", MaterialsJson(m.MaterialsUsed));
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }
        public async Task ApproveAsync(int id, string farmId, string? approvedBy)
        {
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryproductionbatch_approve(p_poultryproductionbatchid => @PoultryProductionBatchId::int, p_farmid => @FarmId::text, p_approvedby => @ApprovedBy::text)", c);
            cmd.Parameters.AddWithValue("@PoultryProductionBatchId", id); cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }
        public async Task CancelAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryproductionbatch_cancel(p_poultryproductionbatchid => @PoultryProductionBatchId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@PoultryProductionBatchId", id); cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }
        public async Task<List<PoultryProductionLossModel>> GetProductionLossesAsync(string farmId, DateTime? fromDate, DateTime? toDate)
        {
            var list = new List<PoultryProductionLossModel>();
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sppoultryproductionloss_getall(p_farmid => @FarmId::text, p_fromdate => @FromDate::date, p_todate => @ToDate::date)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId); cmd.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value); cmd.Parameters.AddWithValue("@ToDate", (object?)toDate ?? DBNull.Value);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(new PoultryProductionLossModel
            {
                PoultryProductionLossId = r.Int("PoultryProductionLossId"), FarmId = r.Str("FarmId"), SourceType = r.Str("SourceType"),
                SourceId = r.IntN("SourceId"), LossDate = r.Date("LossDate"), PoultryProductId = r.IntN("PoultryProductId"),
                ProductName = r.StrN("ProductName"), QuantityLost = r.Dec("QuantityLost"), EstimatedValue = r.DecN("EstimatedValue"),
                Reason = r.StrN("Reason"), CreatedAt = r.Date("CreatedAt"),
            });
            return list;
        }
    }

    // ============================ Manual loss records ============================
    public interface IPoultryLossRecordService
    {
        Task<List<PoultryLossRecordModel>> GetAllAsync(string farmId, string? lossType, DateTime? fromDate, DateTime? toDate);
        Task<int> InsertAsync(PoultryLossRecordModel m);
        Task UpdateAsync(PoultryLossRecordModel m);
        Task ApproveAsync(int id, string farmId, string? approvedBy);
        Task UnapproveAsync(int id, string farmId);
        Task DeleteAsync(int id, string farmId);
    }
    public class PoultryLossRecordService : IPoultryLossRecordService
    {
        private readonly string _cs; public PoultryLossRecordService(string cs) => _cs = cs;
        public async Task<List<PoultryLossRecordModel>> GetAllAsync(string farmId, string? lossType, DateTime? fromDate, DateTime? toDate)
        {
            var list = new List<PoultryLossRecordModel>();
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrylossrecord_getall(p_farmid => @FarmId::text, p_losstype => @LossType::text, p_fromdate => @FromDate::date, p_todate => @ToDate::date)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId); cmd.Parameters.AddWithValue("@LossType", (object?)lossType ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value); cmd.Parameters.AddWithValue("@ToDate", (object?)toDate ?? DBNull.Value);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(new PoultryLossRecordModel
            {
                PoultryLossRecordId = r.Int("PoultryLossRecordId"), FarmId = r.Str("FarmId"), LossDate = r.Date("LossDate"), LossType = r.Str("LossType"),
                PoultryProductId = r.IntN("PoultryProductId"), ProductName = r.StrN("ProductName"), Quantity = r.DecN("Quantity"),
                EstimatedValue = r.DecN("EstimatedValue"), ResponsibleStaffId = r.IntN("ResponsibleStaffId"), Reason = r.StrN("Reason"),
                Status = r.Str("Status"), ApprovedBy = r.StrN("ApprovedBy"), ApprovedAt = r.DateN("ApprovedAt"), Notes = r.StrN("Notes"),
                CreatedBy = r.StrN("CreatedBy"), CreatedAt = r.Date("CreatedAt"), UpdatedAt = r.DateN("UpdatedAt"),
            });
            return list;
        }
        public async Task<int> InsertAsync(PoultryLossRecordModel m)
        {
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrylossrecord_insert(p_farmid => @FarmId::text, p_lossdate => @LossDate::timestamp, p_losstype => @LossType::text, p_poultryproductid => @PoultryProductId::int, p_quantity => @Quantity::numeric, p_estimatedvalue => @EstimatedValue::numeric, p_responsiblestaffid => @ResponsibleStaffId::int, p_reason => @Reason::text, p_notes => @Notes::text, p_createdby => @CreatedBy::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId); cmd.Parameters.AddWithValue("@LossDate", (object?)m.LossDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@LossType", m.LossType); cmd.Parameters.AddWithValue("@PoultryProductId", (object?)m.PoultryProductId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Quantity", (object?)m.Quantity ?? DBNull.Value); cmd.Parameters.AddWithValue("@EstimatedValue", (object?)m.EstimatedValue ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ResponsibleStaffId", (object?)m.ResponsibleStaffId ?? DBNull.Value); cmd.Parameters.AddWithValue("@Reason", (object?)m.Reason ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value); cmd.Parameters.AddWithValue("@CreatedBy", (object?)m.CreatedBy ?? DBNull.Value);
            await c.OpenAsync(); return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }
        public async Task UpdateAsync(PoultryLossRecordModel m)
        {
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrylossrecord_update(p_poultrylossrecordid => @PoultryLossRecordId::int, p_farmid => @FarmId::text, p_lossdate => @LossDate::timestamp, p_losstype => @LossType::text, p_poultryproductid => @PoultryProductId::int, p_quantity => @Quantity::numeric, p_estimatedvalue => @EstimatedValue::numeric, p_responsiblestaffid => @ResponsibleStaffId::int, p_reason => @Reason::text, p_notes => @Notes::text)", c);
            cmd.Parameters.AddWithValue("@PoultryLossRecordId", m.PoultryLossRecordId); cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@LossDate", (object?)m.LossDate ?? DBNull.Value); cmd.Parameters.AddWithValue("@LossType", m.LossType);
            cmd.Parameters.AddWithValue("@PoultryProductId", (object?)m.PoultryProductId ?? DBNull.Value); cmd.Parameters.AddWithValue("@Quantity", (object?)m.Quantity ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@EstimatedValue", (object?)m.EstimatedValue ?? DBNull.Value); cmd.Parameters.AddWithValue("@ResponsibleStaffId", (object?)m.ResponsibleStaffId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Reason", (object?)m.Reason ?? DBNull.Value); cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }
        public async Task ApproveAsync(int id, string farmId, string? approvedBy)
        {
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrylossrecord_approve(p_poultrylossrecordid => @PoultryLossRecordId::int, p_farmid => @FarmId::text, p_approvedby => @ApprovedBy::text)", c);
            cmd.Parameters.AddWithValue("@PoultryLossRecordId", id); cmd.Parameters.AddWithValue("@FarmId", farmId); cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }
        public async Task UnapproveAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrylossrecord_unapprove(p_poultrylossrecordid => @PoultryLossRecordId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@PoultryLossRecordId", id); cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }
        public async Task DeleteAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrylossrecord_delete(p_poultrylossrecordid => @PoultryLossRecordId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@PoultryLossRecordId", id); cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }
    }

    // ============================ Daily closing ============================
    public interface IPoultryDailyClosingService
    {
        Task<List<PoultryDailyClosingModel>> GetAllAsync(string farmId, string? status, DateTime? fromDate, DateTime? toDate);
        Task<PoultryDailyClosingModel?> GetByIdAsync(int id, string farmId);
        Task<int> InsertAsync(string farmId, DateTime closingDate, string? managerNotes, string? createdBy);
        Task SubmitAsync(int id, PoultryDailyClosingSubmitRequest req);
        Task ApproveAsync(int id, string farmId, string? approvedBy);
        Task RejectAsync(int id, string farmId, string? reason);
        Task DeleteAsync(int id, string farmId);
        /// <summary>Migration 333: a reason is required and the reopen is kept in history.</summary>
        Task ReopenAsync(int id, string farmId, string reason, string? reopenedBy);
        Task RecreateAsync(int id, string farmId);
        Task UpdateNotesAsync(int id, string farmId, decimal? actualCashCounted, string? managerNotes);
    }
    public class PoultryDailyClosingService : IPoultryDailyClosingService
    {
        private readonly string _cs; public PoultryDailyClosingService(string cs) => _cs = cs;
        private static PoultryDailyClosingModel Map(NpgsqlDataReader r) => new()
        {
            PoultryDailyClosingId = r.Int("PoultryDailyClosingId"), FarmId = r.Str("FarmId"), ClosingDate = r.Date("ClosingDate"),
            QuantityProduced = r.Dec("QuantityProduced"), QuantityDamaged = r.Dec("QuantityDamaged"), TotalProductionCost = r.Dec("TotalProductionCost"),
            ClosingStock = r.Dec("ClosingStock"), CashAtHand = r.Dec("CashAtHand"), ActualCashCounted = r.Dec("ActualCashCounted"),
            CashDifference = r.Dec("CashDifference"), ManagerNotes = r.StrN("ManagerNotes"), Status = r.Str("Status"), RejectionReason = r.StrN("RejectionReason"),
            CreatedBy = r.StrN("CreatedBy"), SubmittedBy = r.StrN("SubmittedBy"), SubmittedAt = r.DateN("SubmittedAt"),
            ApprovedBy = r.StrN("ApprovedBy"), ApprovedAt = r.DateN("ApprovedAt"), CreatedAt = r.Date("CreatedAt"), UpdatedAt = r.DateN("UpdatedAt"),
            EggsSold = r.Dec("EggsSold"), EggsReturned = r.Dec("EggsReturned"), Mortality = r.Dec("Mortality"), FeedUsedQty = r.Dec("FeedUsedQty"), MedUsedQty = r.Dec("MedUsedQty"),
            TotalIncome = r.Dec("TotalIncome"), TotalExpenses = r.Dec("TotalExpenses"), CreditSales = r.Dec("CreditSales"), CustomerCollections = r.Dec("CustomerCollections"),
            CashCollected = r.Dec("CashCollected"), MoMoCollected = r.Dec("MoMoCollected"), BankCollected = r.Dec("BankCollected"),
            CashBalance = r.Dec("CashBalance"), MoMoBalance = r.Dec("MoMoBalance"), BankBalance = r.Dec("BankBalance"),
        };
        public async Task<List<PoultryDailyClosingModel>> GetAllAsync(string farmId, string? status, DateTime? fromDate, DateTime? toDate)
        {
            var list = new List<PoultryDailyClosingModel>();
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrydailyclosing_getall(p_farmid => @FarmId::text, p_status => @Status::text, p_fromdate => @FromDate::date, p_todate => @ToDate::date)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId); cmd.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@FromDate", (object?)fromDate ?? DBNull.Value); cmd.Parameters.AddWithValue("@ToDate", (object?)toDate ?? DBNull.Value);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync(); while (await r.ReadAsync()) list.Add(Map(r));
            return list;
        }
        public async Task<PoultryDailyClosingModel?> GetByIdAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrydailyclosing_getbyid(p_poultrydailyclosingid => @PoultryDailyClosingId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@PoultryDailyClosingId", id); cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); using var r = await cmd.ExecuteReaderAsync(); return await r.ReadAsync() ? Map(r) : null;
        }
        public async Task<int> InsertAsync(string farmId, DateTime closingDate, string? managerNotes, string? createdBy)
        {
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrydailyclosing_insert(p_farmid => @FarmId::text, p_closingdate => @ClosingDate::date, p_managernotes => @ManagerNotes::text, p_createdby => @CreatedBy::text)", c);
            cmd.Parameters.AddWithValue("@FarmId", farmId); cmd.Parameters.AddWithValue("@ClosingDate", closingDate.Date);
            cmd.Parameters.AddWithValue("@ManagerNotes", (object?)managerNotes ?? DBNull.Value); cmd.Parameters.AddWithValue("@CreatedBy", (object?)createdBy ?? DBNull.Value);
            await c.OpenAsync(); return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }
        public async Task SubmitAsync(int id, PoultryDailyClosingSubmitRequest req)
        {
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrydailyclosing_submit(p_poultrydailyclosingid => @PoultryDailyClosingId::int, p_farmid => @FarmId::text, p_actualcashcounted => @ActualCashCounted::numeric, p_managernotes => @ManagerNotes::text, p_submittedby => @SubmittedBy::text)", c);
            cmd.Parameters.AddWithValue("@PoultryDailyClosingId", id); cmd.Parameters.AddWithValue("@FarmId", req.FarmId);
            cmd.Parameters.AddWithValue("@ActualCashCounted", req.ActualCashCounted); cmd.Parameters.AddWithValue("@ManagerNotes", (object?)req.ManagerNotes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@SubmittedBy", (object?)req.SubmittedBy ?? DBNull.Value);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }
        public async Task ApproveAsync(int id, string farmId, string? approvedBy)
        {
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrydailyclosing_approve(p_poultrydailyclosingid => @PoultryDailyClosingId::int, p_farmid => @FarmId::text, p_approvedby => @ApprovedBy::text)", c);
            cmd.Parameters.AddWithValue("@PoultryDailyClosingId", id); cmd.Parameters.AddWithValue("@FarmId", farmId); cmd.Parameters.AddWithValue("@ApprovedBy", (object?)approvedBy ?? DBNull.Value);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }
        public async Task RejectAsync(int id, string farmId, string? reason)
        {
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrydailyclosing_reject(p_poultrydailyclosingid => @PoultryDailyClosingId::int, p_farmid => @FarmId::text, p_rejectionreason => @RejectionReason::text)", c);
            cmd.Parameters.AddWithValue("@PoultryDailyClosingId", id); cmd.Parameters.AddWithValue("@FarmId", farmId); cmd.Parameters.AddWithValue("@RejectionReason", (object?)reason ?? DBNull.Value);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }
        public async Task DeleteAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrydailyclosing_delete(p_poultrydailyclosingid => @PoultryDailyClosingId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@PoultryDailyClosingId", id); cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }
        public async Task ReopenAsync(int id, string farmId, string reason, string? reopenedBy)
        {
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrydailyclosing_reopen(p_poultrydailyclosingid => @PoultryDailyClosingId::int, p_farmid => @FarmId::text, p_reason => @Reason::text, p_reopenedby => @ReopenedBy::text)", c);
            cmd.Parameters.AddWithValue("@PoultryDailyClosingId", id); cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Reason", reason); cmd.Parameters.AddWithValue("@ReopenedBy", (object?)reopenedBy ?? DBNull.Value);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }
        public async Task RecreateAsync(int id, string farmId)
        {
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrydailyclosing_recreate(p_poultrydailyclosingid => @PoultryDailyClosingId::int, p_farmid => @FarmId::text)", c);
            cmd.Parameters.AddWithValue("@PoultryDailyClosingId", id); cmd.Parameters.AddWithValue("@FarmId", farmId);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }
        public async Task UpdateNotesAsync(int id, string farmId, decimal? actualCashCounted, string? managerNotes)
        {
            using var c = new NpgsqlConnection(_cs); using var cmd = new NpgsqlCommand("SELECT * FROM sppoultrydailyclosing_updatenotes(p_poultrydailyclosingid => @PoultryDailyClosingId::int, p_farmid => @FarmId::text, p_actualcashcounted => @ActualCashCounted::numeric, p_managernotes => @ManagerNotes::text)", c);
            cmd.Parameters.AddWithValue("@PoultryDailyClosingId", id); cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@ActualCashCounted", (object?)actualCashCounted ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ManagerNotes", (object?)managerNotes ?? DBNull.Value);
            await c.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }
    }
}
