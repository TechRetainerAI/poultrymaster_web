using System.Data;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class HotelGuestService : IHotelGuestService
    {
        private readonly string _cs;
        public HotelGuestService(string cs) => _cs = cs;

        public async Task<List<HotelGuestModel>> ListAsync(string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sphotel_guest_list(p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<HotelGuestModel>();
            while (await r.ReadAsync()) list.Add(ReadGuest(r));
            return list;
        }

        public async Task<HotelGuestModel?> GetByIdAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sphotel_guest_get(p_hotelguestid => @Id::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? ReadGuest(r) : null;
        }

        public async Task<List<HotelGuestModel>> SearchAsync(string farmId, string query)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sphotel_guest_search(p_farmid => @FarmId::text, p_query => @Query::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Query", query);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<HotelGuestModel>();
            while (await r.ReadAsync()) list.Add(ReadGuest(r));
            return list;
        }

        public async Task<int> InsertAsync(HotelGuestModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sphotel_guest_insert(p_farmid => @FarmId::text, p_firstname => @FirstName::text, " +
                "p_lastname => @LastName::text, p_email => @Email::text, p_phone => @Phone::text, " +
                "p_idtype => @IdType::text, p_idnumber => @IdNumber::text, p_nationality => @Nationality::text, " +
                "p_address => @Address::text, p_dateofbirth => @DateOfBirth::date, p_notes => @Notes::text, p_isvip => @IsVIP::boolean)", conn);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@FirstName", m.FirstName);
            cmd.Parameters.AddWithValue("@LastName", m.LastName);
            cmd.Parameters.AddWithValue("@Email", (object?)m.Email ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Phone", (object?)m.Phone ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IdType", (object?)m.IdType ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IdNumber", (object?)m.IdNumber ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Nationality", (object?)m.Nationality ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Address", (object?)m.Address ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DateOfBirth", (object?)m.DateOfBirth ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsVIP", m.IsVIP);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateAsync(HotelGuestModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sphotel_guest_update(p_hotelguestid => @Id::int, p_farmid => @FarmId::text, " +
                "p_firstname => @FirstName::text, p_lastname => @LastName::text, p_email => @Email::text, " +
                "p_phone => @Phone::text, p_idtype => @IdType::text, p_idnumber => @IdNumber::text, " +
                "p_nationality => @Nationality::text, p_address => @Address::text, p_dateofbirth => @DateOfBirth::date, " +
                "p_notes => @Notes::text, p_isvip => @IsVIP::boolean)", conn);
            cmd.Parameters.AddWithValue("@Id", m.HotelGuestId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@FirstName", m.FirstName);
            cmd.Parameters.AddWithValue("@LastName", m.LastName);
            cmd.Parameters.AddWithValue("@Email", (object?)m.Email ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Phone", (object?)m.Phone ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IdType", (object?)m.IdType ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IdNumber", (object?)m.IdNumber ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Nationality", (object?)m.Nationality ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Address", (object?)m.Address ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@DateOfBirth", (object?)m.DateOfBirth ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@IsVIP", m.IsVIP);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sphotel_guest_delete(p_hotelguestid => @Id::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static HotelGuestModel ReadGuest(NpgsqlDataReader r) => new()
        {
            HotelGuestId = r.GetInt32(r.GetOrdinal("HotelGuestId")),
            FarmId       = r.GetString(r.GetOrdinal("FarmId")),
            FirstName    = r.GetString(r.GetOrdinal("FirstName")),
            LastName     = r.GetString(r.GetOrdinal("LastName")),
            Email        = r.IsDBNull(r.GetOrdinal("Email")) ? null : r.GetString(r.GetOrdinal("Email")),
            Phone        = r.IsDBNull(r.GetOrdinal("Phone")) ? null : r.GetString(r.GetOrdinal("Phone")),
            IdType       = r.IsDBNull(r.GetOrdinal("IdType")) ? null : r.GetString(r.GetOrdinal("IdType")),
            IdNumber     = r.IsDBNull(r.GetOrdinal("IdNumber")) ? null : r.GetString(r.GetOrdinal("IdNumber")),
            Nationality  = r.IsDBNull(r.GetOrdinal("Nationality")) ? null : r.GetString(r.GetOrdinal("Nationality")),
            Address      = r.IsDBNull(r.GetOrdinal("Address")) ? null : r.GetString(r.GetOrdinal("Address")),
            DateOfBirth  = r.IsDBNull(r.GetOrdinal("DateOfBirth")) ? null : r.GetDateTime(r.GetOrdinal("DateOfBirth")),
            Notes        = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
            IsVIP        = r.GetBoolean(r.GetOrdinal("IsVIP")),
            TotalStays   = r.GetInt32(r.GetOrdinal("TotalStays")),
            LastStayDate = r.IsDBNull(r.GetOrdinal("LastStayDate")) ? null : r.GetDateTime(r.GetOrdinal("LastStayDate")),
            CreatedAt    = r.GetDateTime(r.GetOrdinal("CreatedAt")),
            UpdatedAt    = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
        };
    }

    public class HotelBookingService : IHotelBookingService
    {
        private readonly string _cs;
        public HotelBookingService(string cs) => _cs = cs;

        public async Task<List<HotelBookingModel>> ListAsync(string farmId) => await QueryBookings("sphotel_booking_list", farmId);
        public async Task<List<HotelBookingModel>> TodayArrivalsAsync(string farmId) => await QueryBookings("sphotel_booking_todayarrivals", farmId);
        public async Task<List<HotelBookingModel>> TodayDeparturesAsync(string farmId) => await QueryBookings("sphotel_booking_todaydepartures", farmId);

        private async Task<List<HotelBookingModel>> QueryBookings(string func, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand($"SELECT * FROM {func}(p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<HotelBookingModel>();
            while (await r.ReadAsync()) list.Add(ReadBooking(r));
            return list;
        }

        public async Task<HotelBookingModel?> GetByIdAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sphotel_booking_get(p_hotelbookingid => @Id::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? ReadBooking(r) : null;
        }

        public async Task<int> InsertAsync(HotelBookingModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sphotel_booking_insert(p_farmid => @FarmId::text, p_bookingref => @BookingRef::text, " +
                "p_hotelguestid => @GuestId::int, p_hotelroomid => @RoomId::int, p_hotelroomtypeid => @RoomTypeId::int, " +
                "p_checkindate => @CheckIn::date, p_checkoutdate => @CheckOut::date, p_numberofguests => @NumGuests::int, " +
                "p_adults => @Adults::int, p_children => @Children::int, p_nightlyrate => @Rate::numeric, " +
                "p_totalamount => @Total::numeric, p_status => @Status::text, p_source => @Source::text, " +
                "p_specialrequests => @Requests::text, p_createdby => @CreatedBy::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@BookingRef", m.BookingRef);
            cmd.Parameters.AddWithValue("@GuestId", m.HotelGuestId);
            cmd.Parameters.AddWithValue("@RoomId", (object?)m.HotelRoomId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@RoomTypeId", m.HotelRoomTypeId);
            cmd.Parameters.AddWithValue("@CheckIn", m.CheckInDate);
            cmd.Parameters.AddWithValue("@CheckOut", m.CheckOutDate);
            cmd.Parameters.AddWithValue("@NumGuests", m.NumberOfGuests);
            cmd.Parameters.AddWithValue("@Adults", m.Adults);
            cmd.Parameters.AddWithValue("@Children", m.Children);
            cmd.Parameters.AddWithValue("@Rate", m.NightlyRate);
            cmd.Parameters.AddWithValue("@Total", m.TotalAmount);
            cmd.Parameters.AddWithValue("@Status", m.Status);
            cmd.Parameters.AddWithValue("@Source", m.Source);
            cmd.Parameters.AddWithValue("@Requests", (object?)m.SpecialRequests ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)m.CreatedBy ?? DBNull.Value);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateAsync(HotelBookingModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sphotel_booking_update(p_hotelbookingid => @Id::int, p_farmid => @FarmId::text, " +
                "p_hotelroomid => @RoomId::int, p_hotelroomtypeid => @RoomTypeId::int, " +
                "p_checkindate => @CheckIn::date, p_checkoutdate => @CheckOut::date, p_numberofguests => @NumGuests::int, " +
                "p_adults => @Adults::int, p_children => @Children::int, p_nightlyrate => @Rate::numeric, " +
                "p_totalamount => @Total::numeric, p_source => @Source::text, p_specialrequests => @Requests::text)", conn);
            cmd.Parameters.AddWithValue("@Id", m.HotelBookingId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@RoomId", (object?)m.HotelRoomId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@RoomTypeId", m.HotelRoomTypeId);
            cmd.Parameters.AddWithValue("@CheckIn", m.CheckInDate);
            cmd.Parameters.AddWithValue("@CheckOut", m.CheckOutDate);
            cmd.Parameters.AddWithValue("@NumGuests", m.NumberOfGuests);
            cmd.Parameters.AddWithValue("@Adults", m.Adults);
            cmd.Parameters.AddWithValue("@Children", m.Children);
            cmd.Parameters.AddWithValue("@Rate", m.NightlyRate);
            cmd.Parameters.AddWithValue("@Total", m.TotalAmount);
            cmd.Parameters.AddWithValue("@Source", m.Source);
            cmd.Parameters.AddWithValue("@Requests", (object?)m.SpecialRequests ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task UpdateStatusAsync(int id, string farmId, string status)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sphotel_booking_updatestatus(p_hotelbookingid => @Id::int, p_farmid => @FarmId::text, p_status => @Status::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status", status);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task CancelAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sphotel_booking_cancel(p_hotelbookingid => @Id::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        private static HotelBookingModel ReadBooking(NpgsqlDataReader r)
        {
            var m = new HotelBookingModel
            {
                HotelBookingId = r.GetInt32(r.GetOrdinal("HotelBookingId")),
                FarmId         = r.GetString(r.GetOrdinal("FarmId")),
                BookingRef     = r.GetString(r.GetOrdinal("BookingRef")),
                HotelGuestId   = r.GetInt32(r.GetOrdinal("HotelGuestId")),
                HotelRoomId    = r.IsDBNull(r.GetOrdinal("HotelRoomId")) ? null : r.GetInt32(r.GetOrdinal("HotelRoomId")),
                HotelRoomTypeId = r.GetInt32(r.GetOrdinal("HotelRoomTypeId")),
                CheckInDate    = r.GetDateTime(r.GetOrdinal("CheckInDate")),
                CheckOutDate   = r.GetDateTime(r.GetOrdinal("CheckOutDate")),
                NumberOfGuests = r.GetInt32(r.GetOrdinal("NumberOfGuests")),
                Adults         = r.GetInt32(r.GetOrdinal("Adults")),
                Children       = r.GetInt32(r.GetOrdinal("Children")),
                NightlyRate    = r.GetDecimal(r.GetOrdinal("NightlyRate")),
                TotalAmount    = r.GetDecimal(r.GetOrdinal("TotalAmount")),
                Status         = r.GetString(r.GetOrdinal("Status")),
                Source         = r.GetString(r.GetOrdinal("Source")),
                SpecialRequests = r.IsDBNull(r.GetOrdinal("SpecialRequests")) ? null : r.GetString(r.GetOrdinal("SpecialRequests")),
                CreatedBy      = r.IsDBNull(r.GetOrdinal("CreatedBy")) ? null : r.GetString(r.GetOrdinal("CreatedBy")),
                CreatedAt      = r.GetDateTime(r.GetOrdinal("CreatedAt")),
                UpdatedAt      = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
                GuestFirstName = r.IsDBNull(r.GetOrdinal("GuestFirstName")) ? null : r.GetString(r.GetOrdinal("GuestFirstName")),
                GuestLastName  = r.IsDBNull(r.GetOrdinal("GuestLastName")) ? null : r.GetString(r.GetOrdinal("GuestLastName")),
                GuestPhone     = r.IsDBNull(r.GetOrdinal("GuestPhone")) ? null : r.GetString(r.GetOrdinal("GuestPhone")),
                RoomNumber     = r.IsDBNull(r.GetOrdinal("RoomNumber")) ? null : r.GetString(r.GetOrdinal("RoomNumber")),
                RoomTypeName   = r.IsDBNull(r.GetOrdinal("RoomTypeName")) ? null : r.GetString(r.GetOrdinal("RoomTypeName")),
            };
            try { m.GuestEmail = r.IsDBNull(r.GetOrdinal("GuestEmail")) ? null : r.GetString(r.GetOrdinal("GuestEmail")); } catch { }
            return m;
        }
    }
}
