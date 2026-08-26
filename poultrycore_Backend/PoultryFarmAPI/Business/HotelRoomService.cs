using System.Data;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class HotelRoomService : IHotelRoomService
    {
        private readonly string _cs;
        public HotelRoomService(string cs) => _cs = cs;

        public async Task<List<HotelRoomModel>> ListAsync(string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sphotel_room_list(p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<HotelRoomModel>();
            while (await r.ReadAsync()) list.Add(ReadRoom(r));
            return list;
        }

        public async Task<HotelRoomModel?> GetByIdAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sphotel_room_get(p_hotelroomid => @Id::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? ReadRoom(r) : null;
        }

        public async Task<int> InsertAsync(HotelRoomModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sphotel_room_insert(p_farmid => @FarmId::text, p_roomnumber => @RoomNumber::text, " +
                "p_hotelroomtypeid => @RoomTypeId::int, p_hotelfloorid => @FloorId::int, p_status => @Status::text, " +
                "p_description => @Description::text, p_isactive => @IsActive::boolean)", conn);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@RoomNumber", m.RoomNumber);
            cmd.Parameters.AddWithValue("@RoomTypeId", m.HotelRoomTypeId);
            cmd.Parameters.AddWithValue("@FloorId", (object?)m.HotelFloorId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Status", m.Status);
            cmd.Parameters.AddWithValue("@Description", (object?)m.Description ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateAsync(HotelRoomModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sphotel_room_update(p_hotelroomid => @Id::int, p_farmid => @FarmId::text, " +
                "p_roomnumber => @RoomNumber::text, p_hotelroomtypeid => @RoomTypeId::int, " +
                "p_hotelfloorid => @FloorId::int, p_description => @Description::text, p_isactive => @IsActive::boolean)", conn);
            cmd.Parameters.AddWithValue("@Id", m.HotelRoomId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@RoomNumber", m.RoomNumber);
            cmd.Parameters.AddWithValue("@RoomTypeId", m.HotelRoomTypeId);
            cmd.Parameters.AddWithValue("@FloorId", (object?)m.HotelFloorId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Description", (object?)m.Description ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task UpdateStatusAsync(int id, string farmId, string status)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sphotel_room_updatestatus(p_hotelroomid => @Id::int, p_farmid => @FarmId::text, p_status => @Status::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status", status);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sphotel_room_delete(p_hotelroomid => @Id::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<List<HotelRoomStatusSummary>> GetStatusSummaryAsync(string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sphotel_room_statussummary(p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<HotelRoomStatusSummary>();
            while (await r.ReadAsync())
                list.Add(new HotelRoomStatusSummary
                {
                    Status = r.GetString(r.GetOrdinal("Status")),
                    RoomCount = r.GetInt32(r.GetOrdinal("RoomCount")),
                });
            return list;
        }

        public async Task<List<HotelRoomAmenityModel>> ListRoomAmenitiesAsync(int roomId, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sphotel_roomamenity_listbyroom(p_hotelroomid => @RoomId::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@RoomId", roomId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<HotelRoomAmenityModel>();
            while (await r.ReadAsync())
                list.Add(new HotelRoomAmenityModel
                {
                    HotelRoomId    = r.GetInt32(r.GetOrdinal("HotelRoomId")),
                    HotelAmenityId = r.GetInt32(r.GetOrdinal("HotelAmenityId")),
                    FarmId         = r.GetString(r.GetOrdinal("FarmId")),
                    Name           = r.IsDBNull(r.GetOrdinal("Name")) ? null : r.GetString(r.GetOrdinal("Name")),
                    Category       = r.IsDBNull(r.GetOrdinal("Category")) ? null : r.GetString(r.GetOrdinal("Category")),
                    Icon           = r.IsDBNull(r.GetOrdinal("Icon")) ? null : r.GetString(r.GetOrdinal("Icon")),
                });
            return list;
        }

        public async Task SetRoomAmenityAsync(int roomId, int amenityId, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sphotel_roomamenity_set(p_hotelroomid => @RoomId::int, p_hotelamenityid => @AmenityId::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@RoomId", roomId);
            cmd.Parameters.AddWithValue("@AmenityId", amenityId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task RemoveRoomAmenityAsync(int roomId, int amenityId, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sphotel_roomamenity_remove(p_hotelroomid => @RoomId::int, p_hotelamenityid => @AmenityId::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@RoomId", roomId);
            cmd.Parameters.AddWithValue("@AmenityId", amenityId);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static HotelRoomModel ReadRoom(NpgsqlDataReader r) => new()
        {
            HotelRoomId     = r.GetInt32(r.GetOrdinal("HotelRoomId")),
            FarmId          = r.GetString(r.GetOrdinal("FarmId")),
            RoomNumber      = r.GetString(r.GetOrdinal("RoomNumber")),
            HotelRoomTypeId = r.GetInt32(r.GetOrdinal("HotelRoomTypeId")),
            HotelFloorId    = r.IsDBNull(r.GetOrdinal("HotelFloorId")) ? null : r.GetInt32(r.GetOrdinal("HotelFloorId")),
            Status          = r.GetString(r.GetOrdinal("Status")),
            Description     = r.IsDBNull(r.GetOrdinal("Description")) ? null : r.GetString(r.GetOrdinal("Description")),
            IsActive        = r.GetBoolean(r.GetOrdinal("IsActive")),
            CreatedAt       = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt       = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
            RoomTypeName    = r.IsDBNull(r.GetOrdinal("RoomTypeName")) ? null : r.GetString(r.GetOrdinal("RoomTypeName")),
            BaseRate        = r.IsDBNull(r.GetOrdinal("BaseRate")) ? null : r.GetDecimal(r.GetOrdinal("BaseRate")),
            MaxOccupancy    = r.IsDBNull(r.GetOrdinal("MaxOccupancy")) ? null : r.GetInt32(r.GetOrdinal("MaxOccupancy")),
            BedType         = r.IsDBNull(r.GetOrdinal("BedType")) ? null : r.GetString(r.GetOrdinal("BedType")),
            FloorNumber     = r.IsDBNull(r.GetOrdinal("FloorNumber")) ? null : r.GetInt32(r.GetOrdinal("FloorNumber")),
            FloorName       = r.IsDBNull(r.GetOrdinal("FloorName")) ? null : r.GetString(r.GetOrdinal("FloorName")),
        };
    }
}
