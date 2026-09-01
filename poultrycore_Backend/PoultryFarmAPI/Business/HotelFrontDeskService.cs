using System.Data;
using Npgsql;
using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public class HotelFrontDeskService : IHotelFrontDeskService
    {
        private readonly string _cs;
        public HotelFrontDeskService(string cs) => _cs = cs;

        public async Task<object> CheckInAsync(string farmId, int bookingId, int roomId, string? keyCardNumber, decimal depositAmount, string? depositMethod, string? notes)
        {
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            using var txn = await conn.BeginTransactionAsync();
            try
            {
                // Get guest ID from booking
                int guestId;
                using (var cmd = new NpgsqlCommand("SELECT hotelguestid FROM hotelbookings WHERE hotelbookingid = @bid AND farmid = @fid", conn, txn))
                {
                    cmd.Parameters.AddWithValue("@bid", bookingId);
                    cmd.Parameters.AddWithValue("@fid", farmId);
                    var result = await cmd.ExecuteScalarAsync();
                    if (result == null) { await txn.RollbackAsync(); throw new Exception("Booking not found"); }
                    guestId = Convert.ToInt32(result);
                }

                // Insert check-in record
                int checkInId;
                using (var cmd = new NpgsqlCommand(
                    "INSERT INTO hotelcheckins(farmid, hotelbookingid, hotelroomid, hotelguestid, keycardnumber, depositamount, depositmethod, notes) " +
                    "VALUES(@fid, @bid, @rid, @gid, @key, @dep, @method, @notes) RETURNING hotelcheckinid", conn, txn))
                {
                    cmd.Parameters.AddWithValue("@fid", farmId);
                    cmd.Parameters.AddWithValue("@bid", bookingId);
                    cmd.Parameters.AddWithValue("@rid", roomId);
                    cmd.Parameters.AddWithValue("@gid", guestId);
                    cmd.Parameters.AddWithValue("@key", (object?)keyCardNumber ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@dep", depositAmount);
                    cmd.Parameters.AddWithValue("@method", (object?)depositMethod ?? DBNull.Value);
                    cmd.Parameters.AddWithValue("@notes", (object?)notes ?? DBNull.Value);
                    checkInId = Convert.ToInt32(await cmd.ExecuteScalarAsync());
                }

                // Update booking status to CheckedIn and assign room
                using (var cmd = new NpgsqlCommand("UPDATE hotelbookings SET status='CheckedIn', hotelroomid=@rid, updatedat=NOW() WHERE hotelbookingid=@bid AND farmid=@fid", conn, txn))
                {
                    cmd.Parameters.AddWithValue("@bid", bookingId);
                    cmd.Parameters.AddWithValue("@rid", roomId);
                    cmd.Parameters.AddWithValue("@fid", farmId);
                    await cmd.ExecuteNonQueryAsync();
                }

                // Update room status to Occupied
                using (var cmd = new NpgsqlCommand("UPDATE hotelrooms SET status='Occupied', updatedat=NOW() WHERE hotelroomid=@rid AND farmid=@fid", conn, txn))
                {
                    cmd.Parameters.AddWithValue("@rid", roomId);
                    cmd.Parameters.AddWithValue("@fid", farmId);
                    await cmd.ExecuteNonQueryAsync();
                }

                // Update guest stay count
                using (var cmd = new NpgsqlCommand("UPDATE hotelguests SET totalstays=totalstays+1, laststaydate=CURRENT_DATE, updatedat=NOW() WHERE hotelguestid=@gid AND farmid=@fid", conn, txn))
                {
                    cmd.Parameters.AddWithValue("@gid", guestId);
                    cmd.Parameters.AddWithValue("@fid", farmId);
                    await cmd.ExecuteNonQueryAsync();
                }

                await txn.CommitAsync();
                return new { hotelCheckInId = checkInId, message = "Checked in successfully" };
            }
            catch
            {
                await txn.RollbackAsync();
                throw;
            }
        }

        public async Task<object> CheckOutAsync(string farmId, int bookingId, int roomId, decimal lateFee, decimal damageCharges, bool keyReturned, string? notes)
        {
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            using var txn = await conn.BeginTransactionAsync();
            try
            {
                // Get total amount from booking
                decimal totalAmount = 0;
                using (var cmd = new NpgsqlCommand("SELECT totalamount FROM hotelbookings WHERE hotelbookingid=@bid AND farmid=@fid", conn, txn))
                {
                    cmd.Parameters.AddWithValue("@bid", bookingId);
                    cmd.Parameters.AddWithValue("@fid", farmId);
                    var result = await cmd.ExecuteScalarAsync();
                    if (result != null) totalAmount = Convert.ToDecimal(result);
                }

                // Insert check-out record
                int checkOutId;
                using (var cmd = new NpgsqlCommand(
                    "INSERT INTO hotelcheckouts(farmid, hotelbookingid, hotelroomid, finalbillamount, latefee, damagecharges, keyreturned, notes) " +
                    "VALUES(@fid, @bid, @rid, @bill, @late, @damage, @key, @notes) RETURNING hotelcheckoutid", conn, txn))
                {
                    cmd.Parameters.AddWithValue("@fid", farmId);
                    cmd.Parameters.AddWithValue("@bid", bookingId);
                    cmd.Parameters.AddWithValue("@rid", roomId);
                    cmd.Parameters.AddWithValue("@bill", totalAmount + lateFee + damageCharges);
                    cmd.Parameters.AddWithValue("@late", lateFee);
                    cmd.Parameters.AddWithValue("@damage", damageCharges);
                    cmd.Parameters.AddWithValue("@key", keyReturned);
                    cmd.Parameters.AddWithValue("@notes", (object?)notes ?? DBNull.Value);
                    checkOutId = Convert.ToInt32(await cmd.ExecuteScalarAsync());
                }

                // Update booking to CheckedOut
                using (var cmd = new NpgsqlCommand("UPDATE hotelbookings SET status='CheckedOut', updatedat=NOW() WHERE hotelbookingid=@bid AND farmid=@fid", conn, txn))
                {
                    cmd.Parameters.AddWithValue("@bid", bookingId);
                    cmd.Parameters.AddWithValue("@fid", farmId);
                    await cmd.ExecuteNonQueryAsync();
                }

                // Set room to Cleaning
                using (var cmd = new NpgsqlCommand("UPDATE hotelrooms SET status='Cleaning', updatedat=NOW() WHERE hotelroomid=@rid AND farmid=@fid", conn, txn))
                {
                    cmd.Parameters.AddWithValue("@rid", roomId);
                    cmd.Parameters.AddWithValue("@fid", farmId);
                    await cmd.ExecuteNonQueryAsync();
                }

                // Auto-create housekeeping task
                using (var cmd = new NpgsqlCommand("INSERT INTO hotelhousekeepingtasks(farmid, hotelroomid, tasktype, priority) VALUES(@fid, @rid, 'Cleaning', 'High')", conn, txn))
                {
                    cmd.Parameters.AddWithValue("@fid", farmId);
                    cmd.Parameters.AddWithValue("@rid", roomId);
                    await cmd.ExecuteNonQueryAsync();
                }

                await txn.CommitAsync();
                return new { hotelCheckOutId = checkOutId, message = "Checked out successfully" };
            }
            catch
            {
                await txn.RollbackAsync();
                throw;
            }
        }
    }

    public class HotelHousekeepingService : IHotelHousekeepingService
    {
        private readonly string _cs;
        public HotelHousekeepingService(string cs) => _cs = cs;

        public async Task<List<HotelHousekeepingTaskModel>> ListAsync(string farmId)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand("SELECT * FROM sphotel_housekeeping_list(p_farmid => @FarmId::text)", conn);
            cmd.Parameters.AddWithValue("@FarmId", farmId);
            await conn.OpenAsync();
            using var r = await cmd.ExecuteReaderAsync();
            var list = new List<HotelHousekeepingTaskModel>();
            while (await r.ReadAsync())
                list.Add(new HotelHousekeepingTaskModel
                {
                    HotelHousekeepingTaskId = r.GetInt32(r.GetOrdinal("HotelHousekeepingTaskId")),
                    FarmId = r.GetString(r.GetOrdinal("FarmId")),
                    HotelRoomId = r.GetInt32(r.GetOrdinal("HotelRoomId")),
                    TaskType = r.GetString(r.GetOrdinal("TaskType")),
                    Priority = r.GetString(r.GetOrdinal("Priority")),
                    Status = r.GetString(r.GetOrdinal("Status")),
                    AssignedTo = r.IsDBNull(r.GetOrdinal("AssignedTo")) ? null : r.GetString(r.GetOrdinal("AssignedTo")),
                    ScheduledDate = r.GetDateTime(r.GetOrdinal("ScheduledDate")),
                    StartedAt = r.IsDBNull(r.GetOrdinal("StartedAt")) ? null : r.GetDateTime(r.GetOrdinal("StartedAt")),
                    CompletedAt = r.IsDBNull(r.GetOrdinal("CompletedAt")) ? null : r.GetDateTime(r.GetOrdinal("CompletedAt")),
                    Notes = r.IsDBNull(r.GetOrdinal("Notes")) ? null : r.GetString(r.GetOrdinal("Notes")),
                    CreatedAt = r.GetDateTime(r.GetOrdinal("CreatedAt")),
                    UpdatedAt = r.IsDBNull(r.GetOrdinal("UpdatedAt")) ? null : r.GetDateTime(r.GetOrdinal("UpdatedAt")),
                    RoomNumber = r.IsDBNull(r.GetOrdinal("RoomNumber")) ? null : r.GetString(r.GetOrdinal("RoomNumber")),
                });
            return list;
        }

        public async Task<int> InsertAsync(string farmId, int roomId, string taskType, string priority, string? assignedTo, string? scheduledDate, string? notes)
        {
            using var conn = new NpgsqlConnection(_cs);
            using var cmd = new NpgsqlCommand(
                "INSERT INTO hotelhousekeepingtasks(farmid, hotelroomid, tasktype, priority, assignedto, scheduleddate, notes) " +
                "VALUES(@fid, @rid, @type, @pri, @assign, COALESCE(@date::date, CURRENT_DATE), @notes) RETURNING hotelhousekeepingtaskid", conn);
            cmd.Parameters.AddWithValue("@fid", farmId);
            cmd.Parameters.AddWithValue("@rid", roomId);
            cmd.Parameters.AddWithValue("@type", taskType);
            cmd.Parameters.AddWithValue("@pri", priority);
            cmd.Parameters.AddWithValue("@assign", (object?)assignedTo ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@date", (object?)scheduledDate ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@notes", (object?)notes ?? DBNull.Value);
            await conn.OpenAsync();
            return Convert.ToInt32(await cmd.ExecuteScalarAsync());
        }

        public async Task UpdateStatusAsync(int id, string farmId, string status)
        {
            using var conn = new NpgsqlConnection(_cs);
            await conn.OpenAsync();
            using var txn = await conn.BeginTransactionAsync();
            try
            {
                using var cmd = new NpgsqlCommand(
                    "UPDATE hotelhousekeepingtasks SET status=@status, updatedat=NOW(), " +
                    "startedat = CASE WHEN @status = 'InProgress' AND startedat IS NULL THEN NOW() ELSE startedat END, " +
                    "completedat = CASE WHEN @status IN ('Completed','Inspected') THEN NOW() ELSE completedat END " +
                    "WHERE hotelhousekeepingtaskid=@id AND farmid=@fid", conn, txn);
                cmd.Parameters.AddWithValue("@status", status);
                cmd.Parameters.AddWithValue("@id", id);
                cmd.Parameters.AddWithValue("@fid", farmId);
                await cmd.ExecuteNonQueryAsync();

                // If completed/inspected, set room back to Available
                if (status == "Completed" || status == "Inspected")
                {
                    using var cmd2 = new NpgsqlCommand(
                        "UPDATE hotelrooms SET status='Available', updatedat=NOW() " +
                        "WHERE hotelroomid = (SELECT hotelroomid FROM hotelhousekeepingtasks WHERE hotelhousekeepingtaskid=@id) " +
                        "AND status='Cleaning' AND farmid=@fid", conn, txn);
                    cmd2.Parameters.AddWithValue("@id", id);
                    cmd2.Parameters.AddWithValue("@fid", farmId);
                    await cmd2.ExecuteNonQueryAsync();
                }

                await txn.CommitAsync();
            }
            catch
            {
                await txn.RollbackAsync();
                throw;
            }
        }
    }
}
