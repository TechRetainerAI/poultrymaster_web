using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class RestaurantKdsService : IRestaurantKdsService
    {
        private readonly string _cs;
        public RestaurantKdsService(string cs) => _cs = cs;

        // =====================================================================
        // STATIONS
        // =====================================================================

        public async Task<List<RestaurantKdsStationModel>> ListStationsAsync(string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_kdsstation_list(p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<RestaurantKdsStationModel>();
            while (await r.ReadAsync()) list.Add(new()
            {
                KdsStationId = r.GetInt32(r.GetOrdinal("kdsstationid")),
                FarmId       = r.GetString(r.GetOrdinal("farmid")),
                Name         = r.GetString(r.GetOrdinal("name")),
                DisplayColor = r.IsDBNull(r.GetOrdinal("displaycolor")) ? "#3B82F6" : r.GetString(r.GetOrdinal("displaycolor")),
                SortOrder    = r.GetInt32(r.GetOrdinal("sortorder")),
                IsExpo       = r.GetBoolean(r.GetOrdinal("isexpo")),
                IsActive     = r.GetBoolean(r.GetOrdinal("isactive")),
                CreatedAt    = r.GetDateTime(r.GetOrdinal("createdat")),
                UpdatedAt    = r.IsDBNull(r.GetOrdinal("updatedat")) ? null : r.GetDateTime(r.GetOrdinal("updatedat")),
                ItemCount    = r.GetInt64(r.GetOrdinal("itemcount")),
            });
            return list;
        }

        public async Task<int> InsertStationAsync(RestaurantKdsStationModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_kdsstation_insert(p_farmid => @FarmId::text, p_name => @Name::text, " +
                "p_displaycolor => @DisplayColor::text, p_sortorder => @SortOrder::int, " +
                "p_isexpo => @IsExpo::boolean, p_isactive => @IsActive::boolean)", conn);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Name", m.Name);
            cmd.Parameters.AddWithValue("@DisplayColor", m.DisplayColor);
            cmd.Parameters.AddWithValue("@SortOrder", m.SortOrder);
            cmd.Parameters.AddWithValue("@IsExpo", m.IsExpo);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateStationAsync(RestaurantKdsStationModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_kdsstation_update(p_id => @Id::int, p_farmid => @FarmId::text, " +
                "p_name => @Name::text, p_displaycolor => @DisplayColor::text, p_sortorder => @SortOrder::int, " +
                "p_isexpo => @IsExpo::boolean, p_isactive => @IsActive::boolean)", conn);
            cmd.Parameters.AddWithValue("@Id", m.KdsStationId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Name", m.Name);
            cmd.Parameters.AddWithValue("@DisplayColor", m.DisplayColor);
            cmd.Parameters.AddWithValue("@SortOrder", m.SortOrder);
            cmd.Parameters.AddWithValue("@IsExpo", m.IsExpo);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteStationAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sprestaurant_kdsstation_delete(p_id => @Id::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // =====================================================================
        // STATION-ITEM MAPPINGS
        // =====================================================================

        public async Task<List<RestaurantKdsStationItemModel>> ListStationItemsAsync(int stationId, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_kdsstationitem_list(p_kdsstationid => @StationId::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@StationId", stationId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<RestaurantKdsStationItemModel>();
            while (await r.ReadAsync()) list.Add(new()
            {
                KdsStationItemId = r.GetInt32(r.GetOrdinal("kdsstationitemid")),
                FarmId           = r.GetString(r.GetOrdinal("farmid")),
                KdsStationId     = r.GetInt32(r.GetOrdinal("kdsstationid")),
                MenuItemId       = r.GetInt32(r.GetOrdinal("menuitemid")),
                MenuItemName     = r.IsDBNull(r.GetOrdinal("menuitemname")) ? null : r.GetString(r.GetOrdinal("menuitemname")),
                CategoryName     = r.IsDBNull(r.GetOrdinal("categoryname")) ? null : r.GetString(r.GetOrdinal("categoryname")),
            });
            return list;
        }

        public async Task<int> AssignItemToStationAsync(string farmId, int stationId, int menuItemId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sprestaurant_kdsstationitem_assign(p_farmid => @FarmId::text, p_kdsstationid => @StationId::int, p_menuitemid => @MenuItemId::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@StationId", stationId);
            cmd.Parameters.AddWithValue("@MenuItemId", menuItemId);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UnassignItemFromStationAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sprestaurant_kdsstationitem_unassign(p_id => @Id::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task SetItemStationAsync(string farmId, int menuItemId, int stationId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sprestaurant_kdsstationitem_set_station(p_farmid => @FarmId::text, p_menuitemid => @MenuItemId::int, p_kdsstationid => @StationId::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@MenuItemId", menuItemId);
            cmd.Parameters.AddWithValue("@StationId", stationId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // =====================================================================
        // KDS QUEUE
        // =====================================================================

        public async Task<List<KdsQueueItemModel>> GetQueueAsync(string farmId, int? stationId = null, bool isExpo = false)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sprestaurant_kds_queue(p_farmid => @FarmId::text, p_kdsstationid => @StationId::int, p_isexpo => @IsExpo::boolean)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@StationId", (object?)stationId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsExpo", isExpo);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<KdsQueueItemModel>();
            while (await r.ReadAsync()) list.Add(new()
            {
                OrderItemId    = r.GetInt32(r.GetOrdinal("orderitemid")),
                OrderId        = r.GetInt32(r.GetOrdinal("orderid")),
                OrderNumber    = r.GetString(r.GetOrdinal("ordernumber")),
                OrderType      = r.GetString(r.GetOrdinal("ordertype")),
                TableNumber    = r.IsDBNull(r.GetOrdinal("tablenumber")) ? null : r.GetString(r.GetOrdinal("tablenumber")),
                ItemName       = r.GetString(r.GetOrdinal("itemname")),
                Quantity       = r.GetInt32(r.GetOrdinal("quantity")),
                Notes          = r.IsDBNull(r.GetOrdinal("notes")) ? null : r.GetString(r.GetOrdinal("notes")),
                Status         = r.GetString(r.GetOrdinal("status")),
                SeatNumber     = r.IsDBNull(r.GetOrdinal("seatnumber")) ? null : r.GetInt32(r.GetOrdinal("seatnumber")),
                KdsStation     = r.IsDBNull(r.GetOrdinal("kdsstation")) ? null : r.GetString(r.GetOrdinal("kdsstation")),
                SentToKitchenAt = r.IsDBNull(r.GetOrdinal("senttoktchenat")) ? null : r.GetDateTime(r.GetOrdinal("senttoktchenat")),
                PrepStartedAt  = r.IsDBNull(r.GetOrdinal("prepstartedat")) ? null : r.GetDateTime(r.GetOrdinal("prepstartedat")),
                ReadyAt        = r.IsDBNull(r.GetOrdinal("readyat")) ? null : r.GetDateTime(r.GetOrdinal("readyat")),
                CreatedAt      = r.GetDateTime(r.GetOrdinal("createdat")),
                Modifiers      = r.IsDBNull(r.GetOrdinal("modifiers")) ? null : r.GetString(r.GetOrdinal("modifiers")),
                ElapsedMinutes = r.GetDouble(r.GetOrdinal("elapsedminutes")),
            });
            return list;
        }

        public async Task<string> BumpItemAsync(int orderItemId, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sprestaurant_kds_bump(p_orderitemid => @Id::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@Id", orderItemId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            return (await cmd.ExecuteScalarAsync())?.ToString() ?? "";
        }

        public async Task<string> RecallItemAsync(int orderItemId, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sprestaurant_kds_recall(p_orderitemid => @Id::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@Id", orderItemId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            return (await cmd.ExecuteScalarAsync())?.ToString() ?? "";
        }

        public async Task BumpOrderAsync(int orderId, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sprestaurant_kds_bump_order(p_orderid => @OrderId::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@OrderId", orderId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // =====================================================================
        // STATS
        // =====================================================================

        public async Task<KdsStatsModel> GetStatsAsync(string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_kds_stats(p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            if (await r.ReadAsync()) return new()
            {
                PendingCount       = r.GetInt64(r.GetOrdinal("pending_count")),
                PreparingCount     = r.GetInt64(r.GetOrdinal("preparing_count")),
                ReadyCount         = r.GetInt64(r.GetOrdinal("ready_count")),
                AvgPrepMinutes     = r.IsDBNull(r.GetOrdinal("avg_prep_minutes")) ? null : r.GetDouble(r.GetOrdinal("avg_prep_minutes")),
                LongestWaitMinutes = r.IsDBNull(r.GetOrdinal("longest_wait_minutes")) ? null : r.GetDouble(r.GetOrdinal("longest_wait_minutes")),
            };
            return new();
        }
    }
}
