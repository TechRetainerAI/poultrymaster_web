using Npgsql;
using NpgsqlTypes;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class RestaurantInventoryService : IRestaurantInventoryService
    {
        private readonly string _cs;
        public RestaurantInventoryService(string cs) => _cs = cs;

        private static void AddTextParam(NpgsqlCommand cmd, string name, string value) { cmd.Parameters.AddWithValue(name, NpgsqlTypes.NpgsqlDbType.Text, value); }
        private static void AddTextParamNullable(NpgsqlCommand cmd, string name, string? value) { cmd.Parameters.AddWithValue(name, NpgsqlTypes.NpgsqlDbType.Text, (object?)value ?? DBNull.Value); }

        // =====================================================================
        // INGREDIENTS
        // =====================================================================

        public async Task<List<RestaurantIngredientModel>> ListIngredientsAsync(string farmId, string? category = null)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_ingredient_list(p_farmid=>@F::text,p_category=>@C::text)", conn);
            AddTextParam(cmd, "@F", farmId);
            AddTextParamNullable(cmd, "@C", category);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<RestaurantIngredientModel>();
            while (await r.ReadAsync()) list.Add(new()
            {
                IngredientId = r.GetInt32(r.GetOrdinal("ingredientid")),
                FarmId = r.GetString(r.GetOrdinal("farmid")),
                Name = r.GetString(r.GetOrdinal("name")),
                Category = r.IsDBNull(r.GetOrdinal("category")) ? null : r.GetString(r.GetOrdinal("category")),
                Unit = r.GetString(r.GetOrdinal("unit")),
                CostPerUnit = r.GetDecimal(r.GetOrdinal("costperunit")),
                CurrentStock = r.GetDecimal(r.GetOrdinal("currentstock")),
                ParLevel = r.GetDecimal(r.GetOrdinal("parlevel")),
                ReorderPoint = r.GetDecimal(r.GetOrdinal("reorderpoint")),
                SupplierName = r.IsDBNull(r.GetOrdinal("suppliername")) ? null : r.GetString(r.GetOrdinal("suppliername")),
                ExpiryDays = r.IsDBNull(r.GetOrdinal("expirydays")) ? null : r.GetInt32(r.GetOrdinal("expirydays")),
                StorageArea = r.IsDBNull(r.GetOrdinal("storagearea")) ? null : r.GetString(r.GetOrdinal("storagearea")),
                IsActive = r.GetBoolean(r.GetOrdinal("isactive")),
                Notes = r.IsDBNull(r.GetOrdinal("notes")) ? null : r.GetString(r.GetOrdinal("notes")),
                CreatedAt = r.GetDateTime(r.GetOrdinal("createdat")),
                UpdatedAt = r.IsDBNull(r.GetOrdinal("updatedat")) ? null : r.GetDateTime(r.GetOrdinal("updatedat")),
                IsLow = r.GetBoolean(r.GetOrdinal("islow")),
            });
            return list;
        }

        public async Task<int> InsertIngredientAsync(RestaurantIngredientModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "INSERT INTO restaurantingredients (farmid, name, category, unit, costperunit, currentstock, parlevel, reorderpoint, suppliername, expirydays, storagearea, notes) " +
                "VALUES (@FarmId, @Name, @Cat, @Unit, @CostPU, @Stock, @Par, @Reorder, @Supplier, @Expiry, @Storage, @Notes) RETURNING ingredientid", conn);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Name", m.Name); cmd.Parameters.AddWithValue("@Cat", (object?)m.Category ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Unit", m.Unit); cmd.Parameters.AddWithValue("@CostPU", m.CostPerUnit);
            cmd.Parameters.AddWithValue("@Stock", m.CurrentStock); cmd.Parameters.AddWithValue("@Par", m.ParLevel);
            cmd.Parameters.AddWithValue("@Reorder", m.ReorderPoint); cmd.Parameters.AddWithValue("@Supplier", (object?)m.SupplierName ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Expiry", (object?)m.ExpiryDays ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Storage", (object?)m.StorageArea ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            await conn.OpenAsync();
            var id = Convert.ToInt32(await cmd.ExecuteScalarAsync());
            // Record opening stock movement if stock > 0
            if (m.CurrentStock > 0)
            {
                using var cmd2 = new NpgsqlCommand("INSERT INTO restaurantstockmovements (farmid, ingredientid, movementtype, quantity, unitcost, reference) VALUES (@FarmId2, @IngId, 'OpeningStock', @Qty, @Cost, 'Initial stock')", conn);
                cmd2.Parameters.AddWithValue("@FarmId2", m.FarmId); cmd2.Parameters.AddWithValue("@IngId", id);
                cmd2.Parameters.AddWithValue("@Qty", m.CurrentStock); cmd2.Parameters.AddWithValue("@Cost", m.CostPerUnit);
                await cmd2.ExecuteNonQueryAsync();
            }
            return id;
        }

        public async Task UpdateIngredientAsync(RestaurantIngredientModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_ingredient_update(p_id=>@I::int,p_farmid=>@F::text,p_name=>@a::text,p_category=>@b::text," +
                "p_unit=>@c::text,p_costperunit=>@d::numeric,p_parlevel=>@f::numeric,p_reorderpoint=>@g::numeric," +
                "p_suppliername=>@h::text,p_expirydays=>@i::int,p_storagearea=>@j::text,p_isactive=>@l::boolean,p_notes=>@k::text)", conn);
            cmd.Parameters.AddWithValue("@I", m.IngredientId); AddTextParam(cmd, "@F", m.FarmId);
            cmd.Parameters.AddWithValue("@a", m.Name); cmd.Parameters.AddWithValue("@b", (object?)m.Category ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@c", m.Unit); cmd.Parameters.AddWithValue("@d", m.CostPerUnit);
            cmd.Parameters.AddWithValue("@f", m.ParLevel); cmd.Parameters.AddWithValue("@g", m.ReorderPoint);
            cmd.Parameters.AddWithValue("@h", (object?)m.SupplierName ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@i", (object?)m.ExpiryDays ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@j", (object?)m.StorageArea ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@l", m.IsActive);
            cmd.Parameters.AddWithValue("@k", (object?)m.Notes ?? DBNull.Value);
            await conn.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteIngredientAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sprestaurant_ingredient_delete(p_id=>@I::int,p_farmid=>@F::text)", conn);
            cmd.Parameters.AddWithValue("@I", id); AddTextParam(cmd, "@F", farmId);
            await conn.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }

        public async Task AdjustStockAsync(int id, string farmId, decimal quantity, string movementType, string reason, string createdBy)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_ingredient_adjust_stock(p_id=>@I::int,p_farmid=>@F::text,p_quantity=>@Q::numeric," +
                "p_movementtype=>@M::text,p_reason=>@R::text,p_createdby=>@C::text)", conn);
            cmd.Parameters.AddWithValue("@I", id); AddTextParam(cmd, "@F", farmId);
            cmd.Parameters.AddWithValue("@Q", quantity); cmd.Parameters.AddWithValue("@M", movementType);
            cmd.Parameters.AddWithValue("@R", reason); cmd.Parameters.AddWithValue("@C", createdBy);
            await conn.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }

        public async Task<List<RestaurantIngredientModel>> GetLowStockAsync(string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_ingredient_lowstock(p_farmid=>@F::text)", conn);
            AddTextParam(cmd, "@F", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<RestaurantIngredientModel>();
            while (await r.ReadAsync()) list.Add(new()
            {
                IngredientId = r.GetInt32(0), Name = r.GetString(1), Category = r.IsDBNull(2) ? null : r.GetString(2),
                Unit = r.GetString(3), CurrentStock = r.GetDecimal(4), ReorderPoint = r.GetDecimal(5),
                ParLevel = r.GetDecimal(6), CostPerUnit = r.GetDecimal(7),
                SupplierName = r.IsDBNull(8) ? null : r.GetString(8),
            });
            return list;
        }

        // =====================================================================
        // RECIPES
        // =====================================================================

        public async Task<List<RestaurantRecipeModel>> ListRecipeAsync(int menuItemId, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_recipe_list(p_menuitemid=>@M::int,p_farmid=>@F::text)", conn);
            cmd.Parameters.AddWithValue("@M", menuItemId); AddTextParam(cmd, "@F", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<RestaurantRecipeModel>();
            while (await r.ReadAsync()) list.Add(new()
            {
                RecipeId = r.GetInt32(r.GetOrdinal("recipeid")), FarmId = r.GetString(r.GetOrdinal("farmid")),
                MenuItemId = r.GetInt32(r.GetOrdinal("menuitemid")), IngredientId = r.GetInt32(r.GetOrdinal("ingredientid")),
                IngredientName = r.IsDBNull(r.GetOrdinal("ingredientname")) ? null : r.GetString(r.GetOrdinal("ingredientname")),
                Quantity = r.GetDecimal(r.GetOrdinal("quantity")), Unit = r.GetString(r.GetOrdinal("unit")),
                WastePercent = r.GetDecimal(r.GetOrdinal("wastepercent")),
                Notes = r.IsDBNull(r.GetOrdinal("notes")) ? null : r.GetString(r.GetOrdinal("notes")),
                CostPerUnit = r.GetDecimal(r.GetOrdinal("costperunit")), LineCost = r.GetDecimal(r.GetOrdinal("linecost")),
            });
            return list;
        }

        public async Task<int> UpsertRecipeAsync(string farmId, int menuItemId, int ingredientId, decimal quantity, string unit, decimal wastePercent, string? notes)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_recipe_upsert(p_farmid=>@F::text,p_menuitemid=>@M::int,p_ingredientid=>@I::int," +
                "p_quantity=>@Q::numeric,p_unit=>@U::text,p_wastepercent=>@W::numeric,p_notes=>@N::text)", conn);
            AddTextParam(cmd, "@F", farmId); cmd.Parameters.AddWithValue("@M", menuItemId);
            cmd.Parameters.AddWithValue("@I", ingredientId); cmd.Parameters.AddWithValue("@Q", quantity);
            cmd.Parameters.AddWithValue("@U", unit); cmd.Parameters.AddWithValue("@W", wastePercent);
            cmd.Parameters.AddWithValue("@N", (object?)notes ?? DBNull.Value);
            await conn.OpenAsync(); return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task DeleteRecipeAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sprestaurant_recipe_delete(p_id=>@I::int,p_farmid=>@F::text)", conn);
            cmd.Parameters.AddWithValue("@I", id); AddTextParam(cmd, "@F", farmId);
            await conn.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }

        public async Task<FoodCostModel> GetFoodCostAsync(int menuItemId, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_recipe_foodcost(p_menuitemid=>@M::int,p_farmid=>@F::text)", conn);
            cmd.Parameters.AddWithValue("@M", menuItemId); AddTextParam(cmd, "@F", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            if (await r.ReadAsync()) return new() { TotalCost = r.GetDecimal(0), SellingPrice = r.GetDecimal(1), FoodCostPercent = r.GetDecimal(2) };
            return new();
        }

        public async Task<int> DeductOrderStockAsync(int orderId, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sprestaurant_recipe_deduct_order(p_orderid=>@O::int,p_farmid=>@F::text)", conn);
            cmd.Parameters.AddWithValue("@O", orderId); AddTextParam(cmd, "@F", farmId);
            await conn.OpenAsync(); return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        // =====================================================================
        // WASTE
        // =====================================================================

        public async Task<List<RestaurantWasteLogModel>> ListWasteAsync(string farmId, DateTime? fromDate = null, DateTime? toDate = null)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_wastelog_list(p_farmid=>@F::text,p_fromdate=>@A::timestamp,p_todate=>@B::timestamp)", conn);
            AddTextParam(cmd, "@F", farmId);
            cmd.Parameters.AddWithValue("@A", (object?)fromDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@B", (object?)toDate ?? DBNull.Value);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<RestaurantWasteLogModel>();
            while (await r.ReadAsync()) list.Add(new()
            {
                WasteLogId = r.GetInt32(r.GetOrdinal("wastelogid")), FarmId = r.GetString(r.GetOrdinal("farmid")),
                IngredientId = r.IsDBNull(r.GetOrdinal("ingredientid")) ? null : r.GetInt32(r.GetOrdinal("ingredientid")),
                MenuItemId = r.IsDBNull(r.GetOrdinal("menuitemid")) ? null : r.GetInt32(r.GetOrdinal("menuitemid")),
                IngredientName = r.GetString(r.GetOrdinal("ingredientname")),
                Quantity = r.GetDecimal(r.GetOrdinal("quantity")), Unit = r.GetString(r.GetOrdinal("unit")),
                CostAmount = r.GetDecimal(r.GetOrdinal("costamount")),
                Reason = r.GetString(r.GetOrdinal("reason")),
                Notes = r.IsDBNull(r.GetOrdinal("notes")) ? null : r.GetString(r.GetOrdinal("notes")),
                LoggedBy = r.IsDBNull(r.GetOrdinal("loggedby")) ? null : r.GetString(r.GetOrdinal("loggedby")),
                CreatedAt = r.GetDateTime(r.GetOrdinal("createdat")),
            });
            return list;
        }

        public async Task<int> LogWasteAsync(RestaurantWasteLogModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "INSERT INTO RestaurantWasteLog (FarmId, IngredientId, MenuItemId, IngredientName, Quantity, Unit, CostAmount, Reason, Notes, LoggedBy) " +
                "VALUES (@FarmId, @IngredientId, @MenuItemId, @IngredientName, @Quantity, @Unit, @CostAmount, @Reason, @Notes, @LoggedBy) " +
                "RETURNING WasteLogId", conn);
            AddTextParam(cmd, "@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@IngredientId", (object?)m.IngredientId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@MenuItemId", (object?)m.MenuItemId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IngredientName", m.IngredientName);
            cmd.Parameters.AddWithValue("@Quantity", m.Quantity);
            AddTextParam(cmd, "@Unit", m.Unit);
            cmd.Parameters.AddWithValue("@CostAmount", m.CostAmount);
            AddTextParam(cmd, "@Reason", m.Reason);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@LoggedBy", (object?)m.LoggedBy ?? DBNull.Value);
            await conn.OpenAsync(); return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task<List<WasteSummaryModel>> GetWasteSummaryAsync(string farmId, DateTime? fromDate = null, DateTime? toDate = null)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_wastelog_summary(p_farmid=>@F::text,p_fromdate=>@A::timestamp,p_todate=>@B::timestamp)", conn);
            AddTextParam(cmd, "@F", farmId);
            cmd.Parameters.AddWithValue("@A", (object?)fromDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@B", (object?)toDate ?? DBNull.Value);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<WasteSummaryModel>();
            while (await r.ReadAsync()) list.Add(new() { Reason = r.GetString(0), TotalQuantity = r.GetDecimal(1), TotalCost = r.GetDecimal(2), Count = r.GetInt64(3) });
            return list;
        }

        // =====================================================================
        // STOCK TAKES
        // =====================================================================

        public async Task<List<RestaurantStockTakeModel>> ListStockTakesAsync(string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_stocktake_list(p_farmid=>@F::text)", conn);
            AddTextParam(cmd, "@F", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<RestaurantStockTakeModel>();
            while (await r.ReadAsync()) list.Add(new()
            {
                StockTakeId = r.GetInt32(r.GetOrdinal("stocktakeid")), FarmId = r.GetString(r.GetOrdinal("farmid")),
                TakeDate = r.GetDateTime(r.GetOrdinal("takedate")), Status = r.GetString(r.GetOrdinal("status")),
                Notes = r.IsDBNull(r.GetOrdinal("notes")) ? null : r.GetString(r.GetOrdinal("notes")),
                CompletedBy = r.IsDBNull(r.GetOrdinal("completedby")) ? null : r.GetString(r.GetOrdinal("completedby")),
                CreatedAt = r.GetDateTime(r.GetOrdinal("createdat")),
                CompletedAt = r.IsDBNull(r.GetOrdinal("completedat")) ? null : r.GetDateTime(r.GetOrdinal("completedat")),
                ItemCount = r.GetInt64(r.GetOrdinal("itemcount")),
            });
            return list;
        }

        public async Task<int> CreateStockTakeAsync(string farmId, string? notes)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sprestaurant_stocktake_create(p_farmid=>@F::text,p_notes=>@N::text)", conn);
            AddTextParam(cmd, "@F", farmId); cmd.Parameters.AddWithValue("@N", (object?)notes ?? DBNull.Value);
            await conn.OpenAsync(); return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task<List<RestaurantStockTakeItemModel>> GetStockTakeItemsAsync(int stockTakeId, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_stocktake_items(p_stocktakeid=>@S::int,p_farmid=>@F::text)", conn);
            cmd.Parameters.AddWithValue("@S", stockTakeId); AddTextParam(cmd, "@F", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<RestaurantStockTakeItemModel>();
            while (await r.ReadAsync()) list.Add(new()
            {
                StockTakeItemId = r.GetInt32(0), IngredientId = r.GetInt32(1),
                IngredientName = r.IsDBNull(2) ? null : r.GetString(2), Category = r.IsDBNull(3) ? null : r.GetString(3),
                SystemQty = r.GetDecimal(4), ActualQty = r.GetDecimal(5), Variance = r.GetDecimal(6),
                Unit = r.IsDBNull(7) ? null : r.GetString(7), Notes = r.IsDBNull(8) ? null : r.GetString(8),
            });
            return list;
        }

        public async Task UpdateStockTakeItemAsync(int id, string farmId, decimal actualQty, string? notes)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sprestaurant_stocktake_update_item(p_id=>@I::int,p_farmid=>@F::text,p_actualqty=>@Q::numeric,p_notes=>@N::text)", conn);
            cmd.Parameters.AddWithValue("@I", id); AddTextParam(cmd, "@F", farmId);
            cmd.Parameters.AddWithValue("@Q", actualQty); cmd.Parameters.AddWithValue("@N", (object?)notes ?? DBNull.Value);
            await conn.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }

        public async Task CompleteStockTakeAsync(int id, string farmId, string completedBy)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sprestaurant_stocktake_complete(p_id=>@I::int,p_farmid=>@F::text,p_completedby=>@C::text)", conn);
            cmd.Parameters.AddWithValue("@I", id); AddTextParam(cmd, "@F", farmId);
            cmd.Parameters.AddWithValue("@C", completedBy);
            await conn.OpenAsync(); await cmd.ExecuteNonQueryAsync();
        }

        // =====================================================================
        // REPORTS
        // =====================================================================

        public async Task<List<InventoryValueModel>> GetInventoryValueAsync(string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_inventory_value(p_farmid=>@F::text)", conn);
            AddTextParam(cmd, "@F", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<InventoryValueModel>();
            while (await r.ReadAsync()) list.Add(new()
            {
                IngredientId = r.GetInt32(0), Name = r.GetString(1), Category = r.IsDBNull(2) ? null : r.GetString(2),
                Unit = r.IsDBNull(3) ? null : r.GetString(3), CurrentStock = r.GetDecimal(4),
                CostPerUnit = r.GetDecimal(5), TotalValue = r.GetDecimal(6), IsLow = r.GetBoolean(7),
            });
            return list;
        }
    }
}
