using System.Data;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class HotelSetupService : IHotelSetupService
    {
        private readonly string _cs;
        public HotelSetupService(string cs) => _cs = cs;

        // =====================================================================
        // PROFILE
        // =====================================================================

        public async Task<HotelProfileModel?> GetProfileAsync(string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sphotel_profile_get(p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? ReadProfile(r) : null;
        }

        public async Task<HotelProfileModel> UpsertProfileAsync(HotelProfileModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sphotel_profile_upsert(p_farmid => @FarmId::text, p_hotelname => @HotelName::text, " +
                "p_address => @Address::text, p_city => @City::text, p_country => @Country::text, " +
                "p_phone => @Phone::text, p_email => @Email::text, p_starrating => @StarRating::int, " +
                "p_checkintime => @CheckInTime::text, p_checkouttime => @CheckOutTime::text, " +
                "p_defaultcurrency => @DefaultCurrency::text, p_taxrate => @TaxRate::numeric, " +
                "p_servicechargerate => @ServiceChargeRate::numeric, p_timezone => @TimeZone::text, " +
                "p_logourl => @LogoUrl::text, p_description => @Description::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@HotelName", m.HotelName);
            cmd.Parameters.AddWithValue("@Address", (object?)m.Address ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@City", (object?)m.City ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Country", (object?)m.Country ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Phone", (object?)m.Phone ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Email", (object?)m.Email ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@StarRating", (object?)m.StarRating ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CheckInTime", m.CheckInTime);
            cmd.Parameters.AddWithValue("@CheckOutTime", m.CheckOutTime);
            cmd.Parameters.AddWithValue("@DefaultCurrency", m.DefaultCurrency);
            cmd.Parameters.AddWithValue("@TaxRate", m.TaxRate);
            cmd.Parameters.AddWithValue("@ServiceChargeRate", m.ServiceChargeRate);
            cmd.Parameters.AddWithValue("@TimeZone", (object?)m.TimeZone ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@LogoUrl", (object?)m.LogoUrl ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Description", (object?)m.Description ?? DBNull.Value);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            await r.ReadAsync();
            return ReadProfile(r);
        }

        private static HotelProfileModel ReadProfile(NpgsqlDataReader r) => new()
        {
            HotelProfileId   = r.GetInt32(r.GetOrdinal("HotelProfileId")),
            FarmId           = r.GetString(r.GetOrdinal("FarmId")),
            HotelName        = r.GetString(r.GetOrdinal("HotelName")),
            Address          = r.IsDBNull(r.GetOrdinal("Address")) ? null : r.GetString(r.GetOrdinal("Address")),
            City             = r.IsDBNull(r.GetOrdinal("City")) ? null : r.GetString(r.GetOrdinal("City")),
            Country          = r.IsDBNull(r.GetOrdinal("Country")) ? null : r.GetString(r.GetOrdinal("Country")),
            Phone            = r.IsDBNull(r.GetOrdinal("Phone")) ? null : r.GetString(r.GetOrdinal("Phone")),
            Email            = r.IsDBNull(r.GetOrdinal("Email")) ? null : r.GetString(r.GetOrdinal("Email")),
            StarRating       = r.IsDBNull(r.GetOrdinal("StarRating")) ? null : r.GetInt32(r.GetOrdinal("StarRating")),
            CheckInTime      = r.GetString(r.GetOrdinal("CheckInTime")),
            CheckOutTime     = r.GetString(r.GetOrdinal("CheckOutTime")),
            DefaultCurrency  = r.GetString(r.GetOrdinal("DefaultCurrency")),
            TaxRate          = r.GetDecimal(r.GetOrdinal("TaxRate")),
            ServiceChargeRate = r.GetDecimal(r.GetOrdinal("ServiceChargeRate")),
            TimeZone         = r.IsDBNull(r.GetOrdinal("TimeZone")) ? null : r.GetString(r.GetOrdinal("TimeZone")),
            LogoUrl          = r.IsDBNull(r.GetOrdinal("LogoUrl")) ? null : r.GetString(r.GetOrdinal("LogoUrl")),
            Description      = r.IsDBNull(r.GetOrdinal("Description")) ? null : r.GetString(r.GetOrdinal("Description")),
            CreatedAt        = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt        = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };

        // =====================================================================
        // ROOM TYPES
        // =====================================================================

        public async Task<List<HotelRoomTypeModel>> ListRoomTypesAsync(string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sphotel_roomtype_list(p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<HotelRoomTypeModel>();
            while (await r.ReadAsync()) list.Add(ReadRoomType(r));
            return list;
        }

        public async Task<HotelRoomTypeModel?> GetRoomTypeAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sphotel_roomtype_get(p_hotelroomtypeid => @Id::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? ReadRoomType(r) : null;
        }

        public async Task<int> InsertRoomTypeAsync(HotelRoomTypeModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sphotel_roomtype_insert(p_farmid => @FarmId::text, p_name => @Name::text, " +
                "p_description => @Description::text, p_baserate => @BaseRate::numeric, p_maxoccupancy => @MaxOccupancy::int, " +
                "p_bedtype => @BedType::text, p_imageurl => @ImageUrl::text, p_isactive => @IsActive::boolean, p_sortorder => @SortOrder::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Name", m.Name);
            cmd.Parameters.AddWithValue("@Description", (object?)m.Description ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@BaseRate", m.BaseRate);
            cmd.Parameters.AddWithValue("@MaxOccupancy", m.MaxOccupancy);
            cmd.Parameters.AddWithValue("@BedType", (object?)m.BedType ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ImageUrl", (object?)m.ImageUrl ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            cmd.Parameters.AddWithValue("@SortOrder", m.SortOrder);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateRoomTypeAsync(HotelRoomTypeModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sphotel_roomtype_update(p_hotelroomtypeid => @Id::int, p_farmid => @FarmId::text, p_name => @Name::text, " +
                "p_description => @Description::text, p_baserate => @BaseRate::numeric, p_maxoccupancy => @MaxOccupancy::int, " +
                "p_bedtype => @BedType::text, p_imageurl => @ImageUrl::text, p_isactive => @IsActive::boolean, p_sortorder => @SortOrder::int)", conn);
            cmd.Parameters.AddWithValue("@Id", m.HotelRoomTypeId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Name", m.Name);
            cmd.Parameters.AddWithValue("@Description", (object?)m.Description ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@BaseRate", m.BaseRate);
            cmd.Parameters.AddWithValue("@MaxOccupancy", m.MaxOccupancy);
            cmd.Parameters.AddWithValue("@BedType", (object?)m.BedType ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ImageUrl", (object?)m.ImageUrl ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            cmd.Parameters.AddWithValue("@SortOrder", m.SortOrder);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteRoomTypeAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sphotel_roomtype_delete(p_hotelroomtypeid => @Id::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static HotelRoomTypeModel ReadRoomType(NpgsqlDataReader r) => new()
        {
            HotelRoomTypeId = r.GetInt32(r.GetOrdinal("HotelRoomTypeId")),
            FarmId          = r.GetString(r.GetOrdinal("FarmId")),
            Name            = r.GetString(r.GetOrdinal("Name")),
            Description     = r.IsDBNull(r.GetOrdinal("Description")) ? null : r.GetString(r.GetOrdinal("Description")),
            BaseRate        = r.GetDecimal(r.GetOrdinal("BaseRate")),
            MaxOccupancy    = r.GetInt32(r.GetOrdinal("MaxOccupancy")),
            BedType         = r.IsDBNull(r.GetOrdinal("BedType")) ? null : r.GetString(r.GetOrdinal("BedType")),
            ImageUrl        = r.IsDBNull(r.GetOrdinal("ImageUrl")) ? null : r.GetString(r.GetOrdinal("ImageUrl")),
            IsActive        = r.GetBoolean(r.GetOrdinal("IsActive")),
            SortOrder       = r.GetInt32(r.GetOrdinal("SortOrder")),
            CreatedAt       = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt       = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };

        // =====================================================================
        // FLOORS
        // =====================================================================

        public async Task<List<HotelFloorModel>> ListFloorsAsync(string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sphotel_floor_list(p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<HotelFloorModel>();
            while (await r.ReadAsync()) list.Add(ReadFloor(r));
            return list;
        }

        public async Task<int> InsertFloorAsync(HotelFloorModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sphotel_floor_insert(p_farmid => @FarmId::text, p_floornumber => @FloorNumber::int, " +
                "p_name => @Name::text, p_isactive => @IsActive::boolean, p_sortorder => @SortOrder::int)", conn);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@FloorNumber", m.FloorNumber);
            cmd.Parameters.AddWithValue("@Name", m.Name);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            cmd.Parameters.AddWithValue("@SortOrder", m.SortOrder);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateFloorAsync(HotelFloorModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sphotel_floor_update(p_hotelfloorid => @Id::int, p_farmid => @FarmId::text, " +
                "p_floornumber => @FloorNumber::int, p_name => @Name::text, p_isactive => @IsActive::boolean, p_sortorder => @SortOrder::int)", conn);
            cmd.Parameters.AddWithValue("@Id", m.HotelFloorId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@FloorNumber", m.FloorNumber);
            cmd.Parameters.AddWithValue("@Name", m.Name);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            cmd.Parameters.AddWithValue("@SortOrder", m.SortOrder);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteFloorAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sphotel_floor_delete(p_hotelfloorid => @Id::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static HotelFloorModel ReadFloor(NpgsqlDataReader r) => new()
        {
            HotelFloorId = r.GetInt32(r.GetOrdinal("HotelFloorId")),
            FarmId       = r.GetString(r.GetOrdinal("FarmId")),
            FloorNumber  = r.GetInt32(r.GetOrdinal("FloorNumber")),
            Name         = r.GetString(r.GetOrdinal("Name")),
            IsActive     = r.GetBoolean(r.GetOrdinal("IsActive")),
            SortOrder    = r.GetInt32(r.GetOrdinal("SortOrder")),
            CreatedAt    = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt    = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };

        // =====================================================================
        // AMENITIES
        // =====================================================================

        public async Task<List<HotelAmenityModel>> ListAmenitiesAsync(string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sphotel_amenity_list(p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<HotelAmenityModel>();
            while (await r.ReadAsync()) list.Add(ReadAmenity(r));
            return list;
        }

        public async Task<int> InsertAmenityAsync(HotelAmenityModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sphotel_amenity_insert(p_farmid => @FarmId::text, p_name => @Name::text, " +
                "p_category => @Category::text, p_icon => @Icon::text, p_isactive => @IsActive::boolean)", conn);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Name", m.Name);
            cmd.Parameters.AddWithValue("@Category", (object?)m.Category ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Icon", (object?)m.Icon ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateAmenityAsync(HotelAmenityModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sphotel_amenity_update(p_hotelamenityid => @Id::int, p_farmid => @FarmId::text, " +
                "p_name => @Name::text, p_category => @Category::text, p_icon => @Icon::text, p_isactive => @IsActive::boolean)", conn);
            cmd.Parameters.AddWithValue("@Id", m.HotelAmenityId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Name", m.Name);
            cmd.Parameters.AddWithValue("@Category", (object?)m.Category ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Icon", (object?)m.Icon ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsActive", m.IsActive);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteAmenityAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sphotel_amenity_delete(p_hotelamenityid => @Id::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static HotelAmenityModel ReadAmenity(NpgsqlDataReader r) => new()
        {
            HotelAmenityId = r.GetInt32(r.GetOrdinal("HotelAmenityId")),
            FarmId         = r.GetString(r.GetOrdinal("FarmId")),
            Name           = r.GetString(r.GetOrdinal("Name")),
            Category       = r.IsDBNull(r.GetOrdinal("Category")) ? null : r.GetString(r.GetOrdinal("Category")),
            Icon           = r.IsDBNull(r.GetOrdinal("Icon")) ? null : r.GetString(r.GetOrdinal("Icon")),
            IsActive       = r.GetBoolean(r.GetOrdinal("IsActive")),
            CreatedAt      = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt      = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };
    }
}
