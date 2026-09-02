using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class RestaurantFloorService : IRestaurantFloorService
    {
        private readonly string _cs;
        public RestaurantFloorService(string cs) => _cs = cs;

        // =====================================================================
        // FLOORS
        // =====================================================================

        public async Task<List<RestaurantFloorModel>> ListFloorsAsync(string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_floor_list(p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<RestaurantFloorModel>();
            while (await r.ReadAsync()) list.Add(new()
            {
                FloorId     = r.GetInt32(r.GetOrdinal("floorid")),
                FarmId      = r.GetString(r.GetOrdinal("farmid")),
                Name        = r.GetString(r.GetOrdinal("name")),
                FloorNumber = r.GetInt32(r.GetOrdinal("floornumber")),
                Description = r.IsDBNull(r.GetOrdinal("description")) ? null : r.GetString(r.GetOrdinal("description")),
                IsActive    = r.GetBoolean(r.GetOrdinal("isactive")),
                SortOrder   = r.GetInt32(r.GetOrdinal("sortorder")),
                CreatedAt   = r.GetDateTime(r.GetOrdinal("createdat")),
                UpdatedAt   = r.IsDBNull(r.GetOrdinal("updatedat")) ? null : r.GetDateTime(r.GetOrdinal("updatedat")),
                TableCount  = r.GetInt64(r.GetOrdinal("tablecount")),
            });
            return list;
        }

        public async Task<int> InsertFloorAsync(RestaurantFloorModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_floor_insert(p_farmid => @FarmId::text, p_name => @Name::text, " +
                "p_floornumber => @FloorNumber::int, p_description => @Description::text, " +
                "p_isactive => @IsActive::boolean, p_sortorder => @SortOrder::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Name", m.Name);
            cmd.Parameters.AddWithValue("@FloorNumber", m.FloorNumber);
            cmd.Parameters.AddWithValue("@Description", (object?)m.Description ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            cmd.Parameters.AddWithValue("@SortOrder", m.SortOrder);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateFloorAsync(RestaurantFloorModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_floor_update(p_id => @Id::int, p_farmid => @FarmId::text, " +
                "p_name => @Name::text, p_floornumber => @FloorNumber::int, p_description => @Description::text, " +
                "p_isactive => @IsActive::boolean, p_sortorder => @SortOrder::int)", conn);
            cmd.Parameters.AddWithValue("@Id", m.FloorId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Name", m.Name);
            cmd.Parameters.AddWithValue("@FloorNumber", m.FloorNumber);
            cmd.Parameters.AddWithValue("@Description", (object?)m.Description ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            cmd.Parameters.AddWithValue("@SortOrder", m.SortOrder);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteFloorAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sprestaurant_floor_delete(p_id => @Id::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // =====================================================================
        // TABLES
        // =====================================================================

        public async Task<List<RestaurantTableModel>> ListTablesAsync(string farmId, int? floorId = null, string? status = null)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sprestaurant_table_list(p_farmid => @FarmId::text, p_floorid => @FloorId::int, p_status => @Status::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@FloorId", (object?)floorId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<RestaurantTableModel>();
            while (await r.ReadAsync()) list.Add(ReadTable(r));
            return list;
        }

        public async Task<RestaurantTableModel?> GetTableAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_table_get(p_id => @Id::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? ReadTable(r) : null;
        }

        public async Task<int> InsertTableAsync(RestaurantTableModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_table_insert(p_farmid => @FarmId::text, p_floorid => @FloorId::int, " +
                "p_tablenumber => @TableNumber::text, p_tablename => @TableName::text, " +
                "p_capacity => @Capacity::int, p_shape => @Shape::text, " +
                "p_positionx => @PositionX::int, p_positiony => @PositionY::int, " +
                "p_width => @Width::int, p_height => @Height::int, p_isactive => @IsActive::boolean)", conn);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@FloorId", (object?)m.FloorId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@TableNumber", m.TableNumber);
            cmd.Parameters.AddWithValue("@TableName", (object?)m.TableName ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Capacity", m.Capacity);
            cmd.Parameters.AddWithValue("@Shape", m.Shape);
            cmd.Parameters.AddWithValue("@PositionX", m.PositionX);
            cmd.Parameters.AddWithValue("@PositionY", m.PositionY);
            cmd.Parameters.AddWithValue("@Width", m.Width);
            cmd.Parameters.AddWithValue("@Height", m.Height);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateTableAsync(RestaurantTableModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_table_update(p_id => @Id::int, p_farmid => @FarmId::text, " +
                "p_floorid => @FloorId::int, p_tablenumber => @TableNumber::text, p_tablename => @TableName::text, " +
                "p_capacity => @Capacity::int, p_shape => @Shape::text, " +
                "p_positionx => @PositionX::int, p_positiony => @PositionY::int, " +
                "p_width => @Width::int, p_height => @Height::int, p_isactive => @IsActive::boolean)", conn);
            cmd.Parameters.AddWithValue("@Id", m.TableId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@FloorId", (object?)m.FloorId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@TableNumber", m.TableNumber);
            cmd.Parameters.AddWithValue("@TableName", (object?)m.TableName ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Capacity", m.Capacity);
            cmd.Parameters.AddWithValue("@Shape", m.Shape);
            cmd.Parameters.AddWithValue("@PositionX", m.PositionX);
            cmd.Parameters.AddWithValue("@PositionY", m.PositionY);
            cmd.Parameters.AddWithValue("@Width", m.Width);
            cmd.Parameters.AddWithValue("@Height", m.Height);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteTableAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sprestaurant_table_delete(p_id => @Id::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task UpdateTableStatusAsync(int id, string farmId, string status, int? currentOrderId = null)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_table_update_status(p_id => @Id::int, p_farmid => @FarmId::text, " +
                "p_status => @Status::text, p_currentorderid => @CurrentOrderId::int)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status", status);
            cmd.Parameters.AddWithValue("@CurrentOrderId", (object?)currentOrderId ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task UpdateTablePositionAsync(int id, string farmId, int positionX, int positionY)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_table_update_position(p_id => @Id::int, p_farmid => @FarmId::text, " +
                "p_positionx => @PositionX::int, p_positiony => @PositionY::int)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@PositionX", positionX);
            cmd.Parameters.AddWithValue("@PositionY", positionY);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static RestaurantTableModel ReadTable(NpgsqlDataReader r) => new()
        {
            TableId        = r.GetInt32(r.GetOrdinal("tableid")),
            FarmId         = r.GetString(r.GetOrdinal("farmid")),
            FloorId        = r.IsDBNull(r.GetOrdinal("floorid")) ? null : r.GetInt32(r.GetOrdinal("floorid")),
            FloorName      = r.IsDBNull(r.GetOrdinal("floorname")) ? null : r.GetString(r.GetOrdinal("floorname")),
            TableNumber    = r.GetString(r.GetOrdinal("tablenumber")),
            TableName      = r.IsDBNull(r.GetOrdinal("tablename")) ? null : r.GetString(r.GetOrdinal("tablename")),
            Capacity       = r.GetInt32(r.GetOrdinal("capacity")),
            Shape          = r.GetString(r.GetOrdinal("shape")),
            Status         = r.GetString(r.GetOrdinal("status")),
            PositionX      = r.GetInt32(r.GetOrdinal("positionx")),
            PositionY      = r.GetInt32(r.GetOrdinal("positiony")),
            Width          = r.GetInt32(r.GetOrdinal("width")),
            Height         = r.GetInt32(r.GetOrdinal("height")),
            IsActive       = r.GetBoolean(r.GetOrdinal("isactive")),
            CurrentOrderId = r.IsDBNull(r.GetOrdinal("currentorderid")) ? null : r.GetInt32(r.GetOrdinal("currentorderid")),
            CreatedAt      = r.GetDateTime(r.GetOrdinal("createdat")),
            UpdatedAt      = r.IsDBNull(r.GetOrdinal("updatedat")) ? null : r.GetDateTime(r.GetOrdinal("updatedat")),
        };
    }
}
