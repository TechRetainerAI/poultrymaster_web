using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Npgsql;
using PoultryFarmAPIWeb.Helpers;

namespace PoultryFarmAPIWeb.Controllers
{
    // Request models
    public class CreateDepositRequest { public string FarmId { get; set; } = ""; public int HotelBookingId { get; set; } public int HotelGuestId { get; set; } public string DepositType { get; set; } = "Collected"; public decimal Amount { get; set; } public string? Method { get; set; } public string? Reference { get; set; } public string? Notes { get; set; } }
    public class CreateCommunicationRequest { public string FarmId { get; set; } = ""; public int HotelGuestId { get; set; } public int? HotelBookingId { get; set; } public string CommType { get; set; } = "Note"; public string? Subject { get; set; } public string Message { get; set; } = ""; public string Priority { get; set; } = "Normal"; public string? AssignedTo { get; set; } }
    public class UpdateCommunicationStatusRequest { public string FarmId { get; set; } = ""; public string Status { get; set; } = ""; }
    public class CreateGuestRequestReq { public string FarmId { get; set; } = ""; public int? HotelBookingId { get; set; } public int? HotelRoomId { get; set; } public string RequestType { get; set; } = "Other"; public string? Description { get; set; } public string? ScheduledTime { get; set; } public string? AssignedTo { get; set; } public string? Notes { get; set; } }
    public class UpdateGuestRequestStatusReq { public string FarmId { get; set; } = ""; public string Status { get; set; } = ""; }
    public class CreateLostFoundRequest { public string FarmId { get; set; } = ""; public int? HotelRoomId { get; set; } public int? HotelBookingId { get; set; } public int? HotelGuestId { get; set; } public string ItemDescription { get; set; } = ""; public string? FoundDate { get; set; } public string? FoundBy { get; set; } public string? FoundLocation { get; set; } public string Category { get; set; } = "Other"; public string? StorageLocation { get; set; } public string? Notes { get; set; } }
    public class UpdateLostFoundStatusReq { public string FarmId { get; set; } = ""; public string Status { get; set; } = ""; public string? ClaimedBy { get; set; } }
    public class UpdateRoomFlagsRequest { public string FarmId { get; set; } = ""; public bool? Dnd { get; set; } public string? LateCheckout { get; set; } public bool? VipTreatment { get; set; } public string? SpecialInstructions { get; set; } }
    public class CreateHKScheduleRequest { public string FarmId { get; set; } = ""; public string ScheduleDate { get; set; } = ""; public int HotelRoomId { get; set; } public string? AssignedTo { get; set; } public string TaskType { get; set; } = "Daily"; public string Priority { get; set; } = "Normal"; public string? Notes { get; set; } }
    public class BulkHKScheduleRequest { public string FarmId { get; set; } = ""; public string ScheduleDate { get; set; } = ""; public string TaskType { get; set; } = "Daily"; public string? AssignedTo { get; set; } }
    public class UpdateHKScheduleStatusReq { public string FarmId { get; set; } = ""; public string Status { get; set; } = ""; }
    public class CreateShiftHandoverRequest { public string FarmId { get; set; } = ""; public string? ShiftDate { get; set; } public string ShiftType { get; set; } = "Night"; public string HandoverBy { get; set; } = ""; public string? KeyMessages { get; set; } public string? PendingItems { get; set; } public string? VipGuests { get; set; } public string? Incidents { get; set; } public decimal? CashBalance { get; set; } }
    public class AcknowledgeHandoverRequest { public string FarmId { get; set; } = ""; public string ReceivedBy { get; set; } = ""; }

    [ApiController][Authorize][Route("api/Hotel")]
    public class HotelGuestServicesController : ControllerBase
    {
        private readonly string _cs;
        public HotelGuestServicesController(IConfiguration config) => _cs = config.GetConnectionString("PoultryConn") ?? "";

        // ======================= ROOM AVAILABILITY =======================
        [HttpGet("availability")]
        public async Task<IActionResult> CheckAvailability([FromQuery] string farmId, [FromQuery] string checkIn, [FromQuery] string checkOut, [FromQuery] int? roomTypeId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();

            // Get all rooms, then subtract those with overlapping bookings
            string roomFilter = roomTypeId.HasValue ? "AND r.hotelroomtypeid=@rt" : "";
            using var cmd = new NpgsqlCommand($@"
                SELECT r.hotelroomid, r.roomnumber, r.status, rt.name AS roomtypename, rt.baserate, f.name AS floorname, r.hotelroomtypeid, r.hotelfloorid
                FROM hotelrooms r
                JOIN hotelroomtypes rt ON r.hotelroomtypeid=rt.hotelroomtypeid
                LEFT JOIN hotelfloors f ON r.hotelfloorid=f.hotelfloorid
                WHERE r.farmid=@f AND r.isactive=TRUE {roomFilter}
                AND r.hotelroomid NOT IN (
                    SELECT DISTINCT b.hotelroomid FROM hotelbookings b
                    WHERE b.farmid=@f AND b.hotelroomid IS NOT NULL
                    AND b.status IN ('Confirmed','CheckedIn')
                    AND b.checkindate < @co::date AND b.checkoutdate > @ci::date
                )
                ORDER BY f.name, r.roomnumber", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            cmd.Parameters.AddWithValue("@ci", checkIn);
            cmd.Parameters.AddWithValue("@co", checkOut);
            if (roomTypeId.HasValue) cmd.Parameters.AddWithValue("@rt", roomTypeId.Value);
            return Ok(await ReadAll(cmd));
        }

        // ======================= GUEST STAY HISTORY =======================
        [HttpGet("stay-history/{guestId}")]
        public async Task<IActionResult> GetStayHistory(int guestId, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand(@"
                SELECT b.hotelbookingid, b.bookingref, b.checkindate, b.checkoutdate, b.status, b.nightlyrate, b.totalamount,
                       r.roomnumber, rt.name AS roomtypename,
                       ci.checkintime, co.checkouttime,
                       COALESCE((SELECT SUM(p.amount) FROM hotelpayments p WHERE p.hotelbookingid=b.hotelbookingid AND p.farmid=@f),0) AS totalpaid,
                       COALESCE((SELECT SUM(sc.totalamount) FROM hotelstaycharges sc WHERE sc.hotelbookingid=b.hotelbookingid AND sc.farmid=@f),0) AS totalcharges
                FROM hotelbookings b
                LEFT JOIN hotelrooms r ON b.hotelroomid=r.hotelroomid
                LEFT JOIN hotelroomtypes rt ON b.hotelroomtypeid=rt.hotelroomtypeid
                LEFT JOIN hotelcheckins ci ON ci.hotelbookingid=b.hotelbookingid AND ci.farmid=@f
                LEFT JOIN hotelcheckouts co ON co.hotelbookingid=b.hotelbookingid AND co.farmid=@f
                WHERE b.hotelguestid=@g AND b.farmid=@f
                ORDER BY b.checkindate DESC", conn);
            cmd.Parameters.AddWithValue("@f", farmId); cmd.Parameters.AddWithValue("@g", guestId);
            return Ok(await ReadAll(cmd));
        }

        // ======================= CHECK-IN/OUT HISTORY =======================
        [HttpGet("checkin-history")]
        public async Task<IActionResult> CheckInHistory([FromQuery] string farmId, [FromQuery] int? page, [FromQuery] int? pageSize)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            string sql = @"SELECT ci.*, g.firstname, g.lastname, r.roomnumber, b.bookingref
                FROM hotelcheckins ci
                JOIN hotelbookings b ON ci.hotelbookingid=b.hotelbookingid
                JOIN hotelguests g ON ci.hotelguestid=g.hotelguestid
                LEFT JOIN hotelrooms r ON ci.hotelroomid=r.hotelroomid
                WHERE ci.farmid=@f ORDER BY ci.checkintime DESC";
            if (page.HasValue && page > 0) { int ps = Math.Clamp(pageSize ?? 20, 1, 100); sql += $" LIMIT {ps} OFFSET {(page.Value - 1) * ps}"; }
            else sql += " LIMIT 200";
            using var cmd = new NpgsqlCommand(sql, conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            return Ok(await ReadAll(cmd));
        }

        [HttpGet("checkout-history")]
        public async Task<IActionResult> CheckOutHistory([FromQuery] string farmId, [FromQuery] int? page, [FromQuery] int? pageSize)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            string sql = @"SELECT co.*, b.bookingref, b.hotelguestid, g.firstname, g.lastname, r.roomnumber
                FROM hotelcheckouts co
                JOIN hotelbookings b ON co.hotelbookingid=b.hotelbookingid
                JOIN hotelguests g ON b.hotelguestid=g.hotelguestid
                LEFT JOIN hotelrooms r ON co.hotelroomid=r.hotelroomid
                WHERE co.farmid=@f ORDER BY co.checkouttime DESC";
            if (page.HasValue && page > 0) { int ps = Math.Clamp(pageSize ?? 20, 1, 100); sql += $" LIMIT {ps} OFFSET {(page.Value - 1) * ps}"; }
            else sql += " LIMIT 200";
            using var cmd = new NpgsqlCommand(sql, conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            return Ok(await ReadAll(cmd));
        }

        // ======================= GUEST FOLIO =======================
        [HttpGet("folio/{bookingId}")]
        public async Task<IActionResult> GetGuestFolio(int bookingId, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();

            // Booking + guest info
            Dictionary<string, object?>? booking = null;
            using (var cmd = new NpgsqlCommand(@"SELECT b.*, g.firstname, g.lastname, g.email, g.phone, g.nationality,
                r.roomnumber, rt.name AS roomtypename
                FROM hotelbookings b JOIN hotelguests g ON b.hotelguestid=g.hotelguestid
                LEFT JOIN hotelrooms r ON b.hotelroomid=r.hotelroomid
                LEFT JOIN hotelroomtypes rt ON b.hotelroomtypeid=rt.hotelroomtypeid
                WHERE b.hotelbookingid=@b AND b.farmid=@f", conn))
            { cmd.Parameters.AddWithValue("@b", bookingId); cmd.Parameters.AddWithValue("@f", farmId); using var rd = await cmd.ExecuteReaderAsync(); if (await rd.ReadAsync()) booking = ReadRow(rd); }
            if (booking == null) return NotFound(new { message = "Booking not found" });

            // Charges
            List<Dictionary<string, object?>> charges;
            using (var cmd = new NpgsqlCommand("SELECT * FROM hotelstaycharges WHERE hotelbookingid=@b AND farmid=@f ORDER BY chargedate", conn))
            { cmd.Parameters.AddWithValue("@b", bookingId); cmd.Parameters.AddWithValue("@f", farmId); charges = await ReadAll(cmd); }

            // Payments
            List<Dictionary<string, object?>> payments;
            using (var cmd = new NpgsqlCommand("SELECT * FROM hotelpayments WHERE hotelbookingid=@b AND farmid=@f ORDER BY paymentdate", conn))
            { cmd.Parameters.AddWithValue("@b", bookingId); cmd.Parameters.AddWithValue("@f", farmId); payments = await ReadAll(cmd); }

            // Deposits
            List<Dictionary<string, object?>> deposits;
            using (var cmd = new NpgsqlCommand("SELECT * FROM hoteldeposits WHERE hotelbookingid=@b AND farmid=@f ORDER BY createdat", conn))
            { cmd.Parameters.AddWithValue("@b", bookingId); cmd.Parameters.AddWithValue("@f", farmId); deposits = await ReadAll(cmd); }

            // Hotel profile
            string hotelName = "Hotel"; string hotelAddress = ""; string hotelPhone = ""; string hotelEmail = "";
            using (var cmd = new NpgsqlCommand("SELECT hotelname, address, phone, email FROM hotelprofiles WHERE farmid=@f LIMIT 1", conn))
            {
                cmd.Parameters.AddWithValue("@f", farmId);
                using var rd = await cmd.ExecuteReaderAsync();
                if (await rd.ReadAsync()) { hotelName = rd.IsDBNull(0) ? "Hotel" : rd.GetString(0); hotelAddress = rd.IsDBNull(1) ? "" : rd.GetString(1); hotelPhone = rd.IsDBNull(2) ? "" : rd.GetString(2); hotelEmail = rd.IsDBNull(3) ? "" : rd.GetString(3); }
            }

            decimal roomTotal = Convert.ToDecimal(booking.GetValueOrDefault("totalamount", 0m));
            decimal chargesTotal = charges.Sum(c => Convert.ToDecimal(c.GetValueOrDefault("totalamount", 0m)));
            decimal paymentsTotal = payments.Sum(p => Convert.ToDecimal(p.GetValueOrDefault("amount", 0m)));
            decimal depositsCollected = deposits.Where(d => (d.GetValueOrDefault("deposittype", "")?.ToString() ?? "") == "Collected").Sum(d => Convert.ToDecimal(d.GetValueOrDefault("amount", 0m)));
            decimal depositsRefunded = deposits.Where(d => (d.GetValueOrDefault("deposittype", "")?.ToString() ?? "") == "Refunded").Sum(d => Convert.ToDecimal(d.GetValueOrDefault("amount", 0m)));

            return Ok(new
            {
                hotel = new { name = hotelName, address = hotelAddress, phone = hotelPhone, email = hotelEmail },
                booking, charges, payments, deposits,
                summary = new { roomTotal, chargesTotal, grandTotal = roomTotal + chargesTotal, paymentsTotal, depositsCollected, depositsRefunded, balance = roomTotal + chargesTotal - paymentsTotal }
            });
        }

        // ======================= DEPOSITS =======================
        [HttpGet("deposits")]
        public async Task<IActionResult> ListDeposits([FromQuery] string farmId, [FromQuery] int? bookingId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            string where = bookingId.HasValue ? "d.farmid=@f AND d.hotelbookingid=@b" : "d.farmid=@f";
            using var cmd = new NpgsqlCommand($"SELECT d.*, g.firstname, g.lastname, b.bookingref FROM hoteldeposits d JOIN hotelbookings b ON d.hotelbookingid=b.hotelbookingid JOIN hotelguests g ON d.hotelguestid=g.hotelguestid WHERE {where} ORDER BY d.createdat DESC", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            if (bookingId.HasValue) cmd.Parameters.AddWithValue("@b", bookingId.Value);
            return Ok(await ReadAll(cmd));
        }

        [HttpPost("deposits")]
        public async Task<IActionResult> CreateDeposit([FromBody] CreateDepositRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("INSERT INTO hoteldeposits(farmid,hotelbookingid,hotelguestid,deposittype,amount,method,reference,notes,processedby) VALUES(@f,@b,@g,@t,@a,@m,@r,@n,@p) RETURNING *", conn);
            cmd.Parameters.AddWithValue("@f", req.FarmId); cmd.Parameters.AddWithValue("@b", req.HotelBookingId);
            cmd.Parameters.AddWithValue("@g", req.HotelGuestId); cmd.Parameters.AddWithValue("@t", req.DepositType);
            cmd.Parameters.AddWithValue("@a", req.Amount); cmd.Parameters.AddWithValue("@m", (object?)req.Method ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@r", (object?)req.Reference ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@n", (object?)req.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@p", HotelAuthHelper.GetUserName(User));
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Ok(ReadRow(r)) : StatusCode(500);
        }

        // ======================= GUEST COMMUNICATIONS =======================
        [HttpGet("communications")]
        public async Task<IActionResult> ListCommunications([FromQuery] string farmId, [FromQuery] int? guestId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            string where = guestId.HasValue ? "c.farmid=@f AND c.hotelguestid=@g" : "c.farmid=@f";
            using var cmd = new NpgsqlCommand($"SELECT c.*, g.firstname, g.lastname, b.bookingref, b.hotelroomid, r.roomnumber FROM hotelguestcommunications c JOIN hotelguests g ON c.hotelguestid=g.hotelguestid LEFT JOIN hotelbookings b ON c.hotelbookingid=b.hotelbookingid LEFT JOIN hotelrooms r ON b.hotelroomid=r.hotelroomid WHERE {where} ORDER BY c.createdat DESC LIMIT 200", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            if (guestId.HasValue) cmd.Parameters.AddWithValue("@g", guestId.Value);
            return Ok(await ReadAll(cmd));
        }

        [HttpPost("communications")]
        public async Task<IActionResult> CreateCommunication([FromBody] CreateCommunicationRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("INSERT INTO hotelguestcommunications(farmid,hotelguestid,hotelbookingid,commtype,subject,message,priority,assignedto,createdby) VALUES(@f,@g,@b,@t,@s,@m,@p,@a,@cb) RETURNING *", conn);
            cmd.Parameters.AddWithValue("@f", req.FarmId); cmd.Parameters.AddWithValue("@g", req.HotelGuestId);
            cmd.Parameters.AddWithValue("@b", (object?)req.HotelBookingId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@t", req.CommType); cmd.Parameters.AddWithValue("@s", (object?)req.Subject ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@m", req.Message); cmd.Parameters.AddWithValue("@p", req.Priority);
            cmd.Parameters.AddWithValue("@a", (object?)req.AssignedTo ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@cb", HotelAuthHelper.GetUserName(User));
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Ok(ReadRow(r)) : StatusCode(500);
        }

        [HttpPatch("communications/{id}/status")]
        public async Task<IActionResult> UpdateCommunicationStatus(int id, [FromBody] UpdateCommunicationStatusRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            string extra = req.Status == "Resolved" ? ", resolvedby=@rb, resolvedat=NOW()" : "";
            using var cmd = new NpgsqlCommand($"UPDATE hotelguestcommunications SET status=@s, updatedat=NOW(){extra} WHERE hotelguestcommid=@id AND farmid=@f RETURNING *", conn);
            cmd.Parameters.AddWithValue("@id", id); cmd.Parameters.AddWithValue("@f", req.FarmId); cmd.Parameters.AddWithValue("@s", req.Status);
            if (req.Status == "Resolved") cmd.Parameters.AddWithValue("@rb", HotelAuthHelper.GetUserName(User));
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Ok(ReadRow(r)) : NotFound();
        }

        // ======================= GUEST REQUESTS =======================
        [HttpGet("guest-requests")]
        public async Task<IActionResult> ListGuestRequests([FromQuery] string farmId, [FromQuery] string? status)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            string where = !string.IsNullOrEmpty(status) ? "r.farmid=@f AND r.status=@s" : "r.farmid=@f";
            using var cmd = new NpgsqlCommand($"SELECT r.*, rm.roomnumber, b.bookingref, g.firstname, g.lastname FROM hotelguestrequests r LEFT JOIN hotelrooms rm ON r.hotelroomid=rm.hotelroomid LEFT JOIN hotelbookings b ON r.hotelbookingid=b.hotelbookingid LEFT JOIN hotelguests g ON b.hotelguestid=g.hotelguestid WHERE {where} ORDER BY r.createdat DESC LIMIT 200", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            if (!string.IsNullOrEmpty(status)) cmd.Parameters.AddWithValue("@s", status);
            return Ok(await ReadAll(cmd));
        }

        [HttpPost("guest-requests")]
        public async Task<IActionResult> CreateGuestRequest([FromBody] CreateGuestRequestReq req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("INSERT INTO hotelguestrequests(farmid,hotelbookingid,hotelroomid,requesttype,description,scheduledtime,assignedto,notes,createdby) VALUES(@f,@b,@r,@t,@d,@st,@a,@n,@cb) RETURNING *", conn);
            cmd.Parameters.AddWithValue("@f", req.FarmId);
            cmd.Parameters.AddWithValue("@b", (object?)req.HotelBookingId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@r", (object?)req.HotelRoomId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@t", req.RequestType); cmd.Parameters.AddWithValue("@d", (object?)req.Description ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@st", string.IsNullOrEmpty(req.ScheduledTime) ? DBNull.Value : DateTime.Parse(req.ScheduledTime));
            cmd.Parameters.AddWithValue("@a", (object?)req.AssignedTo ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@n", (object?)req.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@cb", HotelAuthHelper.GetUserName(User));
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Ok(ReadRow(r)) : StatusCode(500);
        }

        [HttpPatch("guest-requests/{id}/status")]
        public async Task<IActionResult> UpdateGuestRequestStatus(int id, [FromBody] UpdateGuestRequestStatusReq req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            string extra = req.Status == "Completed" ? ", completedby=@cb, completedat=NOW()" : "";
            using var cmd = new NpgsqlCommand($"UPDATE hotelguestrequests SET status=@s{extra} WHERE hotelguestrequestid=@id AND farmid=@f RETURNING *", conn);
            cmd.Parameters.AddWithValue("@id", id); cmd.Parameters.AddWithValue("@f", req.FarmId); cmd.Parameters.AddWithValue("@s", req.Status);
            if (req.Status == "Completed") cmd.Parameters.AddWithValue("@cb", HotelAuthHelper.GetUserName(User));
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Ok(ReadRow(r)) : NotFound();
        }

        // ======================= LOST & FOUND =======================
        [HttpGet("lost-and-found")]
        public async Task<IActionResult> ListLostFound([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT lf.*, r.roomnumber, g.firstname, g.lastname FROM hotellostandfound lf LEFT JOIN hotelrooms r ON lf.hotelroomid=r.hotelroomid LEFT JOIN hotelguests g ON lf.hotelguestid=g.hotelguestid WHERE lf.farmid=@f ORDER BY lf.createdat DESC", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            return Ok(await ReadAll(cmd));
        }

        [HttpPost("lost-and-found")]
        public async Task<IActionResult> CreateLostFound([FromBody] CreateLostFoundRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            string date = string.IsNullOrEmpty(req.FoundDate) ? DateTime.UtcNow.ToString("yyyy-MM-dd") : req.FoundDate;
            using var cmd = new NpgsqlCommand("INSERT INTO hotellostandfound(farmid,hotelroomid,hotelbookingid,hotelguestid,itemdescription,founddate,foundby,foundlocation,category,storagelocation,notes,createdby) VALUES(@f,@r,@b,@g,@desc,@d::date,@fb,@fl,@cat,@sl,@n,@cb) RETURNING *", conn);
            cmd.Parameters.AddWithValue("@f", req.FarmId);
            cmd.Parameters.AddWithValue("@r", (object?)req.HotelRoomId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@b", (object?)req.HotelBookingId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@g", (object?)req.HotelGuestId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@desc", req.ItemDescription); cmd.Parameters.AddWithValue("@d", date);
            cmd.Parameters.AddWithValue("@fb", (object?)req.FoundBy ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@fl", (object?)req.FoundLocation ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@cat", req.Category);
            cmd.Parameters.AddWithValue("@sl", (object?)req.StorageLocation ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@n", (object?)req.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@cb", HotelAuthHelper.GetUserName(User));
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Ok(ReadRow(r)) : StatusCode(500);
        }

        [HttpPatch("lost-and-found/{id}/status")]
        public async Task<IActionResult> UpdateLostFoundStatus(int id, [FromBody] UpdateLostFoundStatusReq req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            string extra = req.Status == "Claimed" ? ", claimedby=@clb, claimedat=NOW()" : "";
            using var cmd = new NpgsqlCommand($"UPDATE hotellostandfound SET status=@s{extra} WHERE hotellostandfoundid=@id AND farmid=@f RETURNING *", conn);
            cmd.Parameters.AddWithValue("@id", id); cmd.Parameters.AddWithValue("@f", req.FarmId); cmd.Parameters.AddWithValue("@s", req.Status);
            if (req.Status == "Claimed") cmd.Parameters.AddWithValue("@clb", (object?)req.ClaimedBy ?? HotelAuthHelper.GetUserName(User));
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Ok(ReadRow(r)) : NotFound();
        }

        // ======================= ROOM FLAGS (DND, SPECIAL) =======================
        [HttpPatch("rooms/{id}/flags")]
        public async Task<IActionResult> UpdateRoomFlags(int id, [FromBody] UpdateRoomFlagsRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            // Build JSON flags
            var flags = new Dictionary<string, object?>();
            if (req.Dnd.HasValue) flags["dnd"] = req.Dnd.Value;
            if (req.LateCheckout != null) flags["lateCheckout"] = req.LateCheckout;
            if (req.VipTreatment.HasValue) flags["vipTreatment"] = req.VipTreatment.Value;
            if (req.SpecialInstructions != null) flags["specialInstructions"] = req.SpecialInstructions;
            string json = System.Text.Json.JsonSerializer.Serialize(flags);
            using var cmd = new NpgsqlCommand("UPDATE hotelrooms SET flags=flags || @j::jsonb, updatedat=NOW() WHERE hotelroomid=@id AND farmid=@f RETURNING hotelroomid, roomnumber, flags", conn);
            cmd.Parameters.AddWithValue("@id", id); cmd.Parameters.AddWithValue("@f", req.FarmId);
            cmd.Parameters.AddWithValue("@j", json);
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Ok(ReadRow(r)) : NotFound();
        }

        // ======================= HOUSEKEEPING SCHEDULE =======================
        [HttpGet("housekeeping-schedule")]
        public async Task<IActionResult> ListHKSchedule([FromQuery] string farmId, [FromQuery] string? date)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            string where = !string.IsNullOrEmpty(date) ? "s.farmid=@f AND s.scheduledate=@d::date" : "s.farmid=@f AND s.scheduledate=CURRENT_DATE";
            using var cmd = new NpgsqlCommand($"SELECT s.*, r.roomnumber, rt.name AS roomtypename, f.name AS floorname FROM hotelhousekeepingschedule s JOIN hotelrooms r ON s.hotelroomid=r.hotelroomid LEFT JOIN hotelroomtypes rt ON r.hotelroomtypeid=rt.hotelroomtypeid LEFT JOIN hotelfloors f ON r.hotelfloorid=f.hotelfloorid WHERE {where} ORDER BY f.name, r.roomnumber", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            if (!string.IsNullOrEmpty(date)) cmd.Parameters.AddWithValue("@d", date);
            return Ok(await ReadAll(cmd));
        }

        [HttpPost("housekeeping-schedule")]
        public async Task<IActionResult> CreateHKSchedule([FromBody] CreateHKScheduleRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("INSERT INTO hotelhousekeepingschedule(farmid,scheduledate,hotelroomid,assignedto,tasktype,priority,notes,createdby) VALUES(@f,@d::date,@r,@a,@t,@p,@n,@cb) ON CONFLICT(farmid,hotelroomid,scheduledate,tasktype) DO UPDATE SET assignedto=EXCLUDED.assignedto,priority=EXCLUDED.priority,notes=EXCLUDED.notes RETURNING *", conn);
            cmd.Parameters.AddWithValue("@f", req.FarmId); cmd.Parameters.AddWithValue("@d", req.ScheduleDate);
            cmd.Parameters.AddWithValue("@r", req.HotelRoomId); cmd.Parameters.AddWithValue("@a", (object?)req.AssignedTo ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@t", req.TaskType); cmd.Parameters.AddWithValue("@p", req.Priority);
            cmd.Parameters.AddWithValue("@n", (object?)req.Notes ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@cb", HotelAuthHelper.GetUserName(User));
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Ok(ReadRow(r)) : StatusCode(500);
        }

        [HttpPost("housekeeping-schedule/bulk")]
        public async Task<IActionResult> BulkCreateHKSchedule([FromBody] BulkHKScheduleRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            // Get all occupied rooms
            using var roomCmd = new NpgsqlCommand("SELECT hotelroomid FROM hotelrooms WHERE farmid=@f AND isactive=TRUE AND status='Occupied'", conn);
            roomCmd.Parameters.AddWithValue("@f", req.FarmId);
            var rooms = new List<int>();
            using (var rd = await roomCmd.ExecuteReaderAsync()) { while (await rd.ReadAsync()) rooms.Add(rd.GetInt32(0)); }

            int created = 0;
            foreach (var roomId in rooms)
            {
                using var cmd = new NpgsqlCommand("INSERT INTO hotelhousekeepingschedule(farmid,scheduledate,hotelroomid,assignedto,tasktype,createdby) VALUES(@f,@d::date,@r,@a,@t,@cb) ON CONFLICT(farmid,hotelroomid,scheduledate,tasktype) DO NOTHING", conn);
                cmd.Parameters.AddWithValue("@f", req.FarmId); cmd.Parameters.AddWithValue("@d", req.ScheduleDate);
                cmd.Parameters.AddWithValue("@r", roomId); cmd.Parameters.AddWithValue("@a", (object?)req.AssignedTo ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@t", req.TaskType);
                cmd.Parameters.AddWithValue("@cb", HotelAuthHelper.GetUserName(User));
                created += await cmd.ExecuteNonQueryAsync();
            }
            return Ok(new { created, totalRooms = rooms.Count });
        }

        [HttpPatch("housekeeping-schedule/{id}/status")]
        public async Task<IActionResult> UpdateHKScheduleStatus(int id, [FromBody] UpdateHKScheduleStatusReq req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            string extra = req.Status == "InProgress" ? ", starttime=NOW()" : req.Status == "Completed" ? ", endtime=NOW()" : "";
            using var cmd = new NpgsqlCommand($"UPDATE hotelhousekeepingschedule SET status=@s{extra} WHERE hotelschedid=@id AND farmid=@f RETURNING *", conn);
            cmd.Parameters.AddWithValue("@id", id); cmd.Parameters.AddWithValue("@f", req.FarmId); cmd.Parameters.AddWithValue("@s", req.Status);
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Ok(ReadRow(r)) : NotFound();
        }

        // ======================= SHIFT HANDOVER =======================
        [HttpGet("shift-handovers")]
        public async Task<IActionResult> ListShiftHandovers([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM hotelshifthandovers WHERE farmid=@f ORDER BY shiftdate DESC, createdat DESC LIMIT 100", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            return Ok(await ReadAll(cmd));
        }

        [HttpPost("shift-handovers")]
        public async Task<IActionResult> CreateShiftHandover([FromBody] CreateShiftHandoverRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            string date = string.IsNullOrEmpty(req.ShiftDate) ? DateTime.UtcNow.ToString("yyyy-MM-dd") : req.ShiftDate;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("INSERT INTO hotelshifthandovers(farmid,shiftdate,shifttype,handoverby,keymessages,pendingitems,vipguests,incidents,cashbalance,status) VALUES(@f,@d::date,@st,@hb,@km,@pi,@vg,@inc,@cb,'Submitted') RETURNING *", conn);
            cmd.Parameters.AddWithValue("@f", req.FarmId); cmd.Parameters.AddWithValue("@d", date);
            cmd.Parameters.AddWithValue("@st", req.ShiftType); cmd.Parameters.AddWithValue("@hb", req.HandoverBy);
            cmd.Parameters.AddWithValue("@km", (object?)req.KeyMessages ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@pi", (object?)req.PendingItems ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@vg", (object?)req.VipGuests ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@inc", (object?)req.Incidents ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@cb", (object?)req.CashBalance ?? DBNull.Value);
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Ok(ReadRow(r)) : StatusCode(500);
        }

        [HttpPost("shift-handovers/{id}/acknowledge")]
        public async Task<IActionResult> AcknowledgeHandover(int id, [FromBody] AcknowledgeHandoverRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("UPDATE hotelshifthandovers SET status='Acknowledged', receivedby=@rb, acknowledgedat=NOW() WHERE hotelshifthandoverid=@id AND farmid=@f RETURNING *", conn);
            cmd.Parameters.AddWithValue("@id", id); cmd.Parameters.AddWithValue("@f", req.FarmId);
            cmd.Parameters.AddWithValue("@rb", req.ReceivedBy);
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Ok(ReadRow(r)) : NotFound();
        }

        // ======================= HELPERS =======================
        private static async Task<List<Dictionary<string, object?>>> ReadAll(NpgsqlCommand cmd) { using var r = await cmd.ExecuteReaderAsync(); var list = new List<Dictionary<string, object?>>(); while (await r.ReadAsync()) list.Add(ReadRow(r)); return list; }
        private static Dictionary<string, object?> ReadRow(NpgsqlDataReader r) { var d = new Dictionary<string, object?>(); for (int i = 0; i < r.FieldCount; i++) { var n = r.GetName(i); d[char.ToLower(n[0]) + n[1..]] = r.IsDBNull(i) ? null : r.GetValue(i); } return d; }
    }
}
