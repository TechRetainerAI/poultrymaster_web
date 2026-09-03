using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class RestaurantReservationService : IRestaurantReservationService
    {
        private readonly string _cs;
        public RestaurantReservationService(string cs) => _cs = cs;

        // =====================================================================
        // SETTINGS
        // =====================================================================

        public async Task<RestaurantReservationSettingsModel?> GetSettingsAsync(string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_reservationsettings_get(p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            if (!await r.ReadAsync()) return null;
            return new()
            {
                ReservationSettingId = r.GetInt32(r.GetOrdinal("reservationsettingid")),
                FarmId = r.GetString(r.GetOrdinal("farmid")),
                DefaultDurationMins = r.GetInt32(r.GetOrdinal("defaultdurationmins")),
                MaxPartySizeOnline = r.GetInt32(r.GetOrdinal("maxpartysizeonline")),
                MinAdvanceHours = r.GetInt32(r.GetOrdinal("minadvancehours")),
                MaxAdvanceDays = r.GetInt32(r.GetOrdinal("maxadvancedays")),
                SlotIntervalMins = r.GetInt32(r.GetOrdinal("slotintervalmins")),
                OverbookingBuffer = r.GetInt32(r.GetOrdinal("overbookingbuffer")),
                AutoConfirm = r.GetBoolean(r.GetOrdinal("autoconfirm")),
                NoShowThresholdMins = r.GetInt32(r.GetOrdinal("noshow_threshold_mins")),
                CancellationPolicy = r.IsDBNull(r.GetOrdinal("cancellation_policy")) ? null : r.GetString(r.GetOrdinal("cancellation_policy")),
                ConfirmationMessage = r.IsDBNull(r.GetOrdinal("confirmation_message")) ? null : r.GetString(r.GetOrdinal("confirmation_message")),
                CreatedAt = r.GetDateTime(r.GetOrdinal("createdat")),
                UpdatedAt = r.IsDBNull(r.GetOrdinal("updatedat")) ? null : r.GetDateTime(r.GetOrdinal("updatedat")),
            };
        }

        public async Task UpsertSettingsAsync(RestaurantReservationSettingsModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_reservationsettings_upsert(p_farmid => @FarmId::text, " +
                "p_defaultdurationmins => @Dur::int, p_maxpartysizeonline => @MaxParty::int, " +
                "p_minadvancehours => @MinAdv::int, p_maxadvancedays => @MaxAdv::int, " +
                "p_slotintervalmins => @Slot::int, p_overbookingbuffer => @Overbook::int, " +
                "p_autoconfirm => @Auto::boolean, p_noshow_threshold_mins => @NoShow::int, " +
                "p_cancellation_policy => @CancelPolicy::text, p_confirmation_message => @ConfirmMsg::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Dur", m.DefaultDurationMins);
            cmd.Parameters.AddWithValue("@MaxParty", m.MaxPartySizeOnline);
            cmd.Parameters.AddWithValue("@MinAdv", m.MinAdvanceHours);
            cmd.Parameters.AddWithValue("@MaxAdv", m.MaxAdvanceDays);
            cmd.Parameters.AddWithValue("@Slot", m.SlotIntervalMins);
            cmd.Parameters.AddWithValue("@Overbook", m.OverbookingBuffer);
            cmd.Parameters.AddWithValue("@Auto", m.AutoConfirm);
            cmd.Parameters.AddWithValue("@NoShow", m.NoShowThresholdMins);
            cmd.Parameters.AddWithValue("@CancelPolicy", (object?)m.CancellationPolicy ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ConfirmMsg", (object?)m.ConfirmationMessage ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        // =====================================================================
        // RESERVATIONS
        // =====================================================================

        public async Task<(int id, string number)> CreateReservationAsync(RestaurantReservationModel m, bool autoConfirm)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sprestaurant_reservation_insert(p_farmid => @FarmId::text, " +
                "p_reservationdate => @Date::date, p_reservationtime => @Time::text, p_endtime => @EndTime::text, " +
                "p_partysize => @Party::int, p_guestname => @Name::text, p_guestphone => @Phone::text, " +
                "p_guestemail => @Email::text, p_tableid => @TableId::int, p_tablenumber => @TableNum::text, " +
                "p_specialrequests => @Requests::text, p_occasion => @Occasion::text, p_source => @Source::text, " +
                "p_isvip => @IsVip::boolean, p_notes => @Notes::text, p_createdby => @CreatedBy::text, " +
                "p_autoconfirm => @AutoConfirm::boolean)", conn);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Date", m.ReservationDate);
            cmd.Parameters.AddWithValue("@Time", m.ReservationTime);
            cmd.Parameters.AddWithValue("@EndTime", (object?)m.EndTime ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Party", m.PartySize);
            cmd.Parameters.AddWithValue("@Name", m.GuestName);
            cmd.Parameters.AddWithValue("@Phone", (object?)m.GuestPhone ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Email", (object?)m.GuestEmail ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@TableId", (object?)m.TableId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@TableNum", (object?)m.TableNumber ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Requests", (object?)m.SpecialRequests ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Occasion", (object?)m.Occasion ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Source", m.Source);
            cmd.Parameters.AddWithValue("@IsVip", m.IsVip);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CreatedBy", (object?)m.CreatedBy ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@AutoConfirm", autoConfirm);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            await r.ReadAsync();
            return (r.GetInt32(r.GetOrdinal("reservationid")), r.GetString(r.GetOrdinal("reservationnumber")));
        }

        public async Task<List<RestaurantReservationModel>> ListReservationsAsync(string farmId, DateTime? date = null, string? status = null, DateTime? fromDate = null, DateTime? toDate = null)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sprestaurant_reservation_list(p_farmid => @FarmId::text, p_date => @Date::date, " +
                "p_status => @Status::text, p_fromdate => @From::date, p_todate => @To::date)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Date", (object?)date ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@From", (object?)fromDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@To", (object?)toDate ?? DBNull.Value);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<RestaurantReservationModel>();
            while (await r.ReadAsync()) list.Add(ReadReservation(r));
            return list;
        }

        public async Task<RestaurantReservationModel?> GetReservationAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_reservation_get(p_id => @Id::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? ReadReservation(r) : null;
        }

        public async Task UpdateReservationAsync(RestaurantReservationModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_reservation_update(p_id => @Id::int, p_farmid => @FarmId::text, " +
                "p_reservationdate => @Date::date, p_reservationtime => @Time::text, p_endtime => @EndTime::text, " +
                "p_partysize => @Party::int, p_guestname => @Name::text, p_guestphone => @Phone::text, " +
                "p_guestemail => @Email::text, p_tableid => @TableId::int, p_tablenumber => @TableNum::text, " +
                "p_specialrequests => @Requests::text, p_occasion => @Occasion::text, p_source => @Source::text, " +
                "p_isvip => @IsVip::boolean, p_notes => @Notes::text)", conn);
            cmd.Parameters.AddWithValue("@Id", m.ReservationId);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Date", m.ReservationDate);
            cmd.Parameters.AddWithValue("@Time", m.ReservationTime);
            cmd.Parameters.AddWithValue("@EndTime", (object?)m.EndTime ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Party", m.PartySize);
            cmd.Parameters.AddWithValue("@Name", m.GuestName);
            cmd.Parameters.AddWithValue("@Phone", (object?)m.GuestPhone ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Email", (object?)m.GuestEmail ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@TableId", (object?)m.TableId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@TableNum", (object?)m.TableNumber ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Requests", (object?)m.SpecialRequests ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Occasion", (object?)m.Occasion ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Source", m.Source);
            cmd.Parameters.AddWithValue("@IsVip", m.IsVip);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task UpdateReservationStatusAsync(int id, string farmId, string status, string? reason = null)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_reservation_update_status(p_id => @Id::int, p_farmid => @FarmId::text, p_status => @Status::text, p_reason => @Reason::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status", status);
            cmd.Parameters.AddWithValue("@Reason", (object?)reason ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteReservationAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sprestaurant_reservation_delete(p_id => @Id::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<List<AutoAssignTableResult>> AutoAssignTableAsync(string farmId, int partySize, DateTime date, string time)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT * FROM sprestaurant_reservation_auto_assign_table(p_farmid => @FarmId::text, p_partysize => @Party::int, p_date => @Date::date, p_time => @Time::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Party", partySize);
            cmd.Parameters.AddWithValue("@Date", date);
            cmd.Parameters.AddWithValue("@Time", time);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<AutoAssignTableResult>();
            while (await r.ReadAsync()) list.Add(new() { TableId = r.GetInt32(0), TableNumber = r.GetString(1), Capacity = r.GetInt32(2) });
            return list;
        }

        public async Task<ReservationStatsModel> GetReservationStatsAsync(string farmId, DateTime date)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_reservation_stats(p_farmid => @FarmId::text, p_date => @Date::date)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Date", date);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            if (await r.ReadAsync()) return new()
            {
                TotalCount = r.GetInt64(0), ConfirmedCount = r.GetInt64(1), SeatedCount = r.GetInt64(2),
                CompletedCount = r.GetInt64(3), CancelledCount = r.GetInt64(4), NoShowCount = r.GetInt64(5),
                TotalCovers = r.GetInt64(6), NoShowRate = r.GetDouble(7),
            };
            return new();
        }

        private static RestaurantReservationModel ReadReservation(NpgsqlDataReader r) => new()
        {
            ReservationId = r.GetInt32(r.GetOrdinal("reservationid")),
            FarmId = r.GetString(r.GetOrdinal("farmid")),
            ReservationNumber = r.GetString(r.GetOrdinal("reservationnumber")),
            Status = r.GetString(r.GetOrdinal("status")),
            ReservationDate = r.GetDateTime(r.GetOrdinal("reservationdate")),
            ReservationTime = r.GetString(r.GetOrdinal("reservationtime")),
            EndTime = r.IsDBNull(r.GetOrdinal("endtime")) ? null : r.GetString(r.GetOrdinal("endtime")),
            PartySize = r.GetInt32(r.GetOrdinal("partysize")),
            GuestName = r.GetString(r.GetOrdinal("guestname")),
            GuestPhone = r.IsDBNull(r.GetOrdinal("guestphone")) ? null : r.GetString(r.GetOrdinal("guestphone")),
            GuestEmail = r.IsDBNull(r.GetOrdinal("guestemail")) ? null : r.GetString(r.GetOrdinal("guestemail")),
            TableId = r.IsDBNull(r.GetOrdinal("tableid")) ? null : r.GetInt32(r.GetOrdinal("tableid")),
            TableNumber = r.IsDBNull(r.GetOrdinal("tablenumber")) ? null : r.GetString(r.GetOrdinal("tablenumber")),
            SpecialRequests = r.IsDBNull(r.GetOrdinal("specialrequests")) ? null : r.GetString(r.GetOrdinal("specialrequests")),
            Occasion = r.IsDBNull(r.GetOrdinal("occasion")) ? null : r.GetString(r.GetOrdinal("occasion")),
            Source = r.GetString(r.GetOrdinal("source")),
            IsVip = r.GetBoolean(r.GetOrdinal("isvip")),
            Notes = r.IsDBNull(r.GetOrdinal("notes")) ? null : r.GetString(r.GetOrdinal("notes")),
            CancelReason = r.IsDBNull(r.GetOrdinal("cancelreason")) ? null : r.GetString(r.GetOrdinal("cancelreason")),
            SeatedAt = r.IsDBNull(r.GetOrdinal("seatedat")) ? null : r.GetDateTime(r.GetOrdinal("seatedat")),
            CompletedAt = r.IsDBNull(r.GetOrdinal("completedat")) ? null : r.GetDateTime(r.GetOrdinal("completedat")),
            NoShowMarkedAt = r.IsDBNull(r.GetOrdinal("noshowmarkedat")) ? null : r.GetDateTime(r.GetOrdinal("noshowmarkedat")),
            ReminderSent = r.GetBoolean(r.GetOrdinal("remindersent")),
            CreatedBy = r.IsDBNull(r.GetOrdinal("createdby")) ? null : r.GetString(r.GetOrdinal("createdby")),
            CreatedAt = r.GetDateTime(r.GetOrdinal("createdat")),
            UpdatedAt = r.IsDBNull(r.GetOrdinal("updatedat")) ? null : r.GetDateTime(r.GetOrdinal("updatedat")),
        };

        // =====================================================================
        // WAITLIST
        // =====================================================================

        public async Task<List<RestaurantWaitlistModel>> ListWaitlistAsync(string farmId, string? status = null)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_waitlist_list(p_farmid => @FarmId::text, p_status => @Status::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status", (object?)status ?? DBNull.Value);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<RestaurantWaitlistModel>();
            while (await r.ReadAsync()) list.Add(new()
            {
                WaitlistId = r.GetInt32(r.GetOrdinal("waitlistid")),
                FarmId = r.GetString(r.GetOrdinal("farmid")),
                GuestName = r.GetString(r.GetOrdinal("guestname")),
                GuestPhone = r.IsDBNull(r.GetOrdinal("guestphone")) ? null : r.GetString(r.GetOrdinal("guestphone")),
                PartySize = r.GetInt32(r.GetOrdinal("partysize")),
                EstimatedWaitMins = r.GetInt32(r.GetOrdinal("estimatedwaitmins")),
                Status = r.GetString(r.GetOrdinal("status")),
                Notes = r.IsDBNull(r.GetOrdinal("notes")) ? null : r.GetString(r.GetOrdinal("notes")),
                QuotedWaitMins = r.IsDBNull(r.GetOrdinal("quotedwaitmins")) ? null : r.GetInt32(r.GetOrdinal("quotedwaitmins")),
                NotifiedAt = r.IsDBNull(r.GetOrdinal("notifiedat")) ? null : r.GetDateTime(r.GetOrdinal("notifiedat")),
                SeatedAt = r.IsDBNull(r.GetOrdinal("seatedat")) ? null : r.GetDateTime(r.GetOrdinal("seatedat")),
                TableId = r.IsDBNull(r.GetOrdinal("tableid")) ? null : r.GetInt32(r.GetOrdinal("tableid")),
                TableNumber = r.IsDBNull(r.GetOrdinal("tablenumber")) ? null : r.GetString(r.GetOrdinal("tablenumber")),
                CreatedAt = r.GetDateTime(r.GetOrdinal("createdat")),
                UpdatedAt = r.IsDBNull(r.GetOrdinal("updatedat")) ? null : r.GetDateTime(r.GetOrdinal("updatedat")),
                ActualWaitMins = r.IsDBNull(r.GetOrdinal("actualwaitmins")) ? null : r.GetDouble(r.GetOrdinal("actualwaitmins")),
            });
            return list;
        }

        public async Task<int> AddToWaitlistAsync(RestaurantWaitlistModel m)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_waitlist_insert(p_farmid => @FarmId::text, p_guestname => @Name::text, " +
                "p_guestphone => @Phone::text, p_partysize => @Party::int, p_estimatedwaitmins => @Est::int, " +
                "p_quotedwaitmins => @Quoted::int, p_notes => @Notes::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", m.FarmId);
            cmd.Parameters.AddWithValue("@Name", m.GuestName);
            cmd.Parameters.AddWithValue("@Phone", (object?)m.GuestPhone ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Party", m.PartySize);
            cmd.Parameters.AddWithValue("@Est", m.EstimatedWaitMins);
            cmd.Parameters.AddWithValue("@Quoted", (object?)m.QuotedWaitMins ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@Notes", (object?)m.Notes ?? DBNull.Value);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateWaitlistStatusAsync(int id, string farmId, string status, int? tableId = null, string? tableNumber = null)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "SELECT sprestaurant_waitlist_update_status(p_id => @Id::int, p_farmid => @FarmId::text, " +
                "p_status => @Status::text, p_tableid => @TableId::int, p_tablenumber => @TableNum::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            cmd.Parameters.AddWithValue("@Status", status);
            cmd.Parameters.AddWithValue("@TableId", (object?)tableId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@TableNum", (object?)tableNumber ?? DBNull.Value);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task DeleteFromWaitlistAsync(int id, string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT sprestaurant_waitlist_delete(p_id => @Id::int, p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            await cmd.ExecuteNonQueryAsync();
        }

        public async Task<WaitlistStatsModel> GetWaitlistStatsAsync(string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sprestaurant_waitlist_stats(p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            if (await r.ReadAsync()) return new()
            {
                WaitingCount = r.GetInt64(0), NotifiedCount = r.GetInt64(1),
                AvgWaitMins = r.IsDBNull(2) ? null : r.GetDouble(2),
                LongestWaitMins = r.IsDBNull(3) ? null : r.GetDouble(3),
                TotalCovers = r.GetInt64(4),
            };
            return new();
        }
    }
}
