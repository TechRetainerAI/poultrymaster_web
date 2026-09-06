using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Npgsql;
using PoultryFarmAPIWeb.Helpers;
using System.Security.Cryptography;

namespace PoultryFarmAPIWeb.Controllers
{
    public class CreateStaffRequest { public string FarmId { get; set; } = ""; public string FirstName { get; set; } = ""; public string LastName { get; set; } = ""; public string? Email { get; set; } public string? Phone { get; set; } public string Role { get; set; } = "Other"; public string Department { get; set; } = "Other"; public decimal SalaryAmount { get; set; } public string? HireDate { get; set; } public bool IsActive { get; set; } = true; }
    public class UpdateStaffRequest { public string FarmId { get; set; } = ""; public string FirstName { get; set; } = ""; public string LastName { get; set; } = ""; public string? Email { get; set; } public string? Phone { get; set; } public string Role { get; set; } = ""; public string Department { get; set; } = ""; public decimal SalaryAmount { get; set; } public bool IsActive { get; set; } = true; }
    public class CreateInventoryRequest { public string FarmId { get; set; } = ""; public string Name { get; set; } = ""; public string Category { get; set; } = ""; public string Unit { get; set; } = "pcs"; public int StockOnHand { get; set; } public int ReorderLevel { get; set; } public decimal UnitCost { get; set; } }
    public class CreateMaintenanceReq { public string FarmId { get; set; } = ""; public int? HotelRoomId { get; set; } public string AssetDescription { get; set; } = "General"; public string IssueDescription { get; set; } = ""; public string Priority { get; set; } = "Normal"; public decimal EstimatedCost { get; set; } }
    public class CreateClosingRequest { public string FarmId { get; set; } = ""; public string? ClosingDate { get; set; } public string? Notes { get; set; } }

    [ApiController][Authorize][Route("api/Hotel")]
    public class HotelOperationsController : ControllerBase
    {
        private readonly string _cs;
        private readonly Business.IEmailService _email;
        private readonly ILogger<HotelOperationsController> _logger;
        public HotelOperationsController(IConfiguration config, Business.IEmailService email, ILogger<HotelOperationsController> logger)
        {
            _cs = config.GetConnectionString("PoultryConn") ?? "";
            _email = email;
            _logger = logger;
        }

        // ======================= STAFF =======================
        [HttpGet("staff")]
        public async Task<IActionResult> ListStaff([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM hotelstaff WHERE farmid=@f ORDER BY department, lastname", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            return Ok(await ReadAll(cmd));
        }

        [HttpPost("staff")]
        public async Task<IActionResult> CreateStaff([FromBody] CreateStaffRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            string hire = string.IsNullOrEmpty(req.HireDate) ? DateTime.UtcNow.ToString("yyyy-MM-dd") : req.HireDate;

            // --- 1. Generate username & password ---
            string baseUsername = $"{req.FirstName.Trim().ToLower()}.{req.LastName.Trim().ToLower()}".Replace(" ", "");
            string username = baseUsername;
            string password = GeneratePassword();
            string? userId = null;

            // --- 2. Create user account if email is provided ---
            if (!string.IsNullOrWhiteSpace(req.Email))
            {
                using var connU = new NpgsqlConnection(_cs); await connU.OpenAsync();

                // Ensure unique username
                int suffix = 1;
                while (true)
                {
                    using var chk = new NpgsqlCommand("SELECT COUNT(*) FROM aspnetusers WHERE normalizedusername=@u", connU);
                    chk.Parameters.AddWithValue("@u", username.ToUpper());
                    var cnt = Convert.ToInt32(await chk.ExecuteScalarAsync());
                    if (cnt == 0) break;
                    username = $"{baseUsername}{suffix++}";
                }

                // Hash password using Identity's hasher
                var hasher = new PasswordHasher<object>();
                string passwordHash = hasher.HashPassword(new object(), password);
                userId = Guid.NewGuid().ToString();

                // Build department-based feature permissions
                string featurePerms = BuildDepartmentPermissions(req.Department);

                // Get farm name
                string farmName = "";
                using (var fn = new NpgsqlCommand("SELECT hotelname FROM hotelprofiles WHERE farmid=@f LIMIT 1", connU))
                {
                    fn.Parameters.AddWithValue("@f", req.FarmId);
                    var fnResult = await fn.ExecuteScalarAsync();
                    farmName = fnResult?.ToString() ?? "";
                }

                // Insert user into aspnetusers
                using (var ins = new NpgsqlCommand(@"
                    INSERT INTO aspnetusers (id, username, normalizedusername, email, normalizedemail, emailconfirmed,
                        passwordhash, securitystamp, concurrencystamp, phonenumber, phonenumberconfirmed,
                        twofactorenabled, lockoutenabled, accessfailedcount,
                        firstname, lastname, farmid, farmname, isstaff, isadmin, issubscriber, featurepermissions)
                    VALUES (@id, @u, @nu, @e, @ne, true, @ph, @ss, @cs, @p, false, false, true, 0,
                        @fn, @ln, @fid, @fname, true, false, false, @fp)", connU))
                {
                    ins.Parameters.AddWithValue("@id", userId);
                    ins.Parameters.AddWithValue("@u", username);
                    ins.Parameters.AddWithValue("@nu", username.ToUpper());
                    ins.Parameters.AddWithValue("@e", req.Email);
                    ins.Parameters.AddWithValue("@ne", req.Email.ToUpper());
                    ins.Parameters.AddWithValue("@ph", passwordHash);
                    ins.Parameters.AddWithValue("@ss", Guid.NewGuid().ToString());
                    ins.Parameters.AddWithValue("@cs", Guid.NewGuid().ToString());
                    ins.Parameters.AddWithValue("@p", (object?)req.Phone ?? DBNull.Value);
                    ins.Parameters.AddWithValue("@fn", req.FirstName);
                    ins.Parameters.AddWithValue("@ln", req.LastName);
                    ins.Parameters.AddWithValue("@fid", req.FarmId);
                    ins.Parameters.AddWithValue("@fname", farmName);
                    ins.Parameters.AddWithValue("@fp", featurePerms);
                    await ins.ExecuteNonQueryAsync();
                }

                // Assign Staff role
                using (var role = new NpgsqlCommand(
                    "INSERT INTO aspnetuserroles (userid, roleid) VALUES (@uid, @rid) ON CONFLICT DO NOTHING", connU))
                {
                    role.Parameters.AddWithValue("@uid", userId);
                    role.Parameters.AddWithValue("@rid", "a9ce449e-e523-4fa3-a33a-6cf03be781b8"); // Staff role ID
                    await role.ExecuteNonQueryAsync();
                }

                // Link user to farm
                using (var uf = new NpgsqlCommand(
                    "INSERT INTO userfarms (userid, farmid, role, createdat) VALUES (@uid, @fid, 'Staff', NOW()) ON CONFLICT DO NOTHING", connU))
                {
                    uf.Parameters.AddWithValue("@uid", userId);
                    uf.Parameters.AddWithValue("@fid", req.FarmId);
                    await uf.ExecuteNonQueryAsync();
                }
            }

            // --- 3. Create hotel staff record ---
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand(
                "INSERT INTO hotelstaff(farmid,firstname,lastname,email,phone,role,department,salaryamount,hiredate,isactive,userid) " +
                "VALUES(@f,@fn,@ln,@e,@p,@r,@d,@s,@h::date,@a,@uid) RETURNING *", conn);
            cmd.Parameters.AddWithValue("@f", req.FarmId); cmd.Parameters.AddWithValue("@fn", req.FirstName);
            cmd.Parameters.AddWithValue("@ln", req.LastName); cmd.Parameters.AddWithValue("@e", (object?)req.Email ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@p", (object?)req.Phone ?? DBNull.Value); cmd.Parameters.AddWithValue("@r", req.Role);
            cmd.Parameters.AddWithValue("@d", req.Department); cmd.Parameters.AddWithValue("@s", req.SalaryAmount);
            cmd.Parameters.AddWithValue("@h", hire); cmd.Parameters.AddWithValue("@a", req.IsActive);
            cmd.Parameters.AddWithValue("@uid", (object?)userId ?? DBNull.Value);
            using var r = await cmd.ExecuteReaderAsync();
            if (!await r.ReadAsync()) return StatusCode(500);
            var row = ReadRow(r);
            r.Close();

            // --- 4. Send welcome email with credentials ---
            if (!string.IsNullOrWhiteSpace(req.Email) && userId != null)
            {
                var emailUsername = username;
                var emailPassword = password;
                _ = Task.Run(async () =>
                {
                    try
                    {
                        string hotelName = "Hotel";
                        using var conn2 = new NpgsqlConnection(_cs); await conn2.OpenAsync();
                        using var hcmd = new NpgsqlCommand("SELECT hotelname FROM hotelprofiles WHERE farmid=@f LIMIT 1", conn2);
                        hcmd.Parameters.AddWithValue("@f", req.FarmId);
                        var hResult = await hcmd.ExecuteScalarAsync();
                        if (hResult != null && hResult != DBNull.Value) hotelName = hResult.ToString()!;

                        var subject = $"Welcome to {hotelName} — Your Login Credentials";
                        var body = $@"
<!DOCTYPE html><html><head><meta charset='utf-8'></head>
<body style='margin:0;padding:0;background:#f1f5f9;font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif'>
<div style='max-width:600px;margin:0 auto;padding:24px'>
    <div style='background:#7c3aed;color:white;padding:20px 24px;border-radius:12px 12px 0 0;text-align:center'>
        <h1 style='margin:0;font-size:22px'>{hotelName}</h1>
    </div>
    <div style='background:white;padding:24px;border-radius:0 0 12px 12px;box-shadow:0 1px 3px rgba(0,0,0,.1)'>
        <h2 style='color:#7c3aed;margin:0 0 16px'>Welcome to the Team!</h2>
        <p>Dear {req.FirstName} {req.LastName},</p>
        <p>You have been added as a staff member at <strong>{hotelName}</strong>. Here are your details:</p>
        <table style='width:100%;border-collapse:collapse;margin:16px 0'>
            <tr><td style='padding:8px;border-bottom:1px solid #e2e8f0;color:#64748b'>Role</td><td style='padding:8px;border-bottom:1px solid #e2e8f0;font-weight:600'>{req.Role}</td></tr>
            <tr><td style='padding:8px;border-bottom:1px solid #e2e8f0;color:#64748b'>Department</td><td style='padding:8px;border-bottom:1px solid #e2e8f0;font-weight:600'>{req.Department}</td></tr>
            <tr><td style='padding:8px;border-bottom:1px solid #e2e8f0;color:#64748b'>Start Date</td><td style='padding:8px;border-bottom:1px solid #e2e8f0;font-weight:600'>{hire}</td></tr>
        </table>
        <div style='background:#f8fafc;border:2px solid #7c3aed;border-radius:12px;padding:20px;margin:20px 0;text-align:center'>
            <p style='color:#64748b;font-size:12px;margin:0 0 12px;text-transform:uppercase;letter-spacing:1px'>Your Login Credentials</p>
            <table style='margin:0 auto;border-collapse:collapse'>
                <tr><td style='padding:6px 16px;color:#64748b;text-align:right'>Username:</td><td style='padding:6px 16px;font-weight:700;font-size:18px;color:#7c3aed;font-family:monospace'>{emailUsername}</td></tr>
                <tr><td style='padding:6px 16px;color:#64748b;text-align:right'>Password:</td><td style='padding:6px 16px;font-weight:700;font-size:18px;color:#7c3aed;font-family:monospace'>{emailPassword}</td></tr>
            </table>
            <p style='color:#dc2626;font-size:11px;margin:12px 0 0;font-weight:600'>Please change your password after your first login.</p>
        </div>
        <p style='color:#64748b;font-size:13px'>You can access the system based on your department ({req.Department}). If you need additional access, contact your administrator.</p>
        <p>We're excited to have you on board!</p>
    </div>
    <p style='text-align:center;color:#94a3b8;font-size:12px;margin-top:16px'>
        This is an automated email from {hotelName}. Please do not reply.
    </p>
</div></body></html>";

                        await _email.SendAsync(new[] { req.Email }, subject, body);
                        _logger.LogInformation("Welcome email with credentials sent to {Name} ({Username})", $"{req.FirstName} {req.LastName}", emailUsername);
                    }
                    catch (Exception ex) { _logger.LogWarning(ex, "Failed to send welcome email to staff {Email}", req.Email); }
                });
            }

            return Ok(row);
        }

        private static string GeneratePassword()
        {
            const string upper = "ABCDEFGHJKLMNPQRSTUVWXYZ";
            const string lower = "abcdefghjkmnpqrstuvwxyz";
            const string digits = "23456789";
            const string special = "!@#$%&*";
            var rng = RandomNumberGenerator.Create();
            var bytes = new byte[12];
            rng.GetBytes(bytes);
            var chars = new char[12];
            chars[0] = upper[bytes[0] % upper.Length];
            chars[1] = lower[bytes[1] % lower.Length];
            chars[2] = digits[bytes[2] % digits.Length];
            chars[3] = special[bytes[3] % special.Length];
            var all = upper + lower + digits + special;
            for (int i = 4; i < 12; i++) chars[i] = all[bytes[i] % all.Length];
            // Shuffle
            for (int i = chars.Length - 1; i > 0; i--)
            {
                var b = new byte[1]; rng.GetBytes(b);
                int j = b[0] % (i + 1);
                (chars[i], chars[j]) = (chars[j], chars[i]);
            }
            return new string(chars);
        }

        private static string BuildDepartmentPermissions(string department)
        {
            var dept = (department ?? "").ToLower();
            // Base: everything off
            bool canSales = false, canExpenses = false, canCash = false, canEmployees = false;
            bool canReports = false, canFinancial = false, canCustomers = false, canActivity = false, canSettings = false;

            // Department-based access
            if (dept.Contains("front desk") || dept.Contains("reception"))
            {
                canCustomers = true; canSales = true; canReports = true;
            }
            else if (dept.Contains("housekeeping"))
            {
                // Minimal access — just their tasks
            }
            else if (dept.Contains("restaurant") || dept.Contains("kitchen") || dept.Contains("bar"))
            {
                canSales = true;
            }
            else if (dept.Contains("finance") || dept.Contains("accounting"))
            {
                canSales = true; canExpenses = true; canCash = true; canFinancial = true; canReports = true;
            }
            else if (dept.Contains("management") || dept.Contains("admin"))
            {
                canSales = true; canExpenses = true; canCash = true; canEmployees = true;
                canReports = true; canFinancial = true; canCustomers = true; canActivity = true; canSettings = true;
            }
            else if (dept.Contains("maintenance") || dept.Contains("security"))
            {
                // Minimal access
            }

            return $"{{\"canEnterSales\":{B(canSales)},\"canEnterExpenses\":{B(canExpenses)},\"canViewCashLedger\":{B(canCash)},\"canSeeEmployees\":{B(canEmployees)},\"canViewReports\":{B(canReports)},\"canViewFinancial\":{B(canFinancial)},\"canViewCustomers\":{B(canCustomers)},\"canViewActivityLog\":{B(canActivity)},\"canViewSettings\":{B(canSettings)}}}";
        }

        private static string B(bool v) => v ? "true" : "false";

        [HttpPut("staff/{id}")]
        public async Task<IActionResult> UpdateStaff(int id, [FromBody] UpdateStaffRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("UPDATE hotelstaff SET firstname=@fn,lastname=@ln,email=@e,phone=@p,role=@r,department=@d,salaryamount=@s,isactive=@a,updatedat=NOW() WHERE hotelstaffid=@id AND farmid=@f", conn);
            cmd.Parameters.AddWithValue("@id", id); cmd.Parameters.AddWithValue("@f", req.FarmId);
            cmd.Parameters.AddWithValue("@fn", req.FirstName); cmd.Parameters.AddWithValue("@ln", req.LastName);
            cmd.Parameters.AddWithValue("@e", (object?)req.Email ?? DBNull.Value); cmd.Parameters.AddWithValue("@p", (object?)req.Phone ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@r", req.Role); cmd.Parameters.AddWithValue("@d", req.Department);
            cmd.Parameters.AddWithValue("@s", req.SalaryAmount); cmd.Parameters.AddWithValue("@a", req.IsActive);
            await cmd.ExecuteNonQueryAsync();
            return NoContent();
        }

        [HttpDelete("staff/{id}")]
        public async Task<IActionResult> DeleteStaff(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("DELETE FROM hotelstaff WHERE hotelstaffid=@id AND farmid=@f", conn);
            cmd.Parameters.AddWithValue("@id", id); cmd.Parameters.AddWithValue("@f", farmId);
            await cmd.ExecuteNonQueryAsync();
            return NoContent();
        }

        // ======================= INVENTORY =======================
        [HttpGet("inventory")]
        public async Task<IActionResult> ListInventory([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM hotelinventoryitems WHERE farmid=@f ORDER BY category, name", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            return Ok(await ReadAll(cmd));
        }

        [HttpPost("inventory")]
        public async Task<IActionResult> CreateInventory([FromBody] CreateInventoryRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("INSERT INTO hotelinventoryitems(farmid,name,category,unit,stockonhand,reorderlevel,unitcost) VALUES(@f,@n,@c,@u,@s,@r,@co) RETURNING *", conn);
            cmd.Parameters.AddWithValue("@f", req.FarmId); cmd.Parameters.AddWithValue("@n", req.Name);
            cmd.Parameters.AddWithValue("@c", req.Category); cmd.Parameters.AddWithValue("@u", req.Unit);
            cmd.Parameters.AddWithValue("@s", req.StockOnHand); cmd.Parameters.AddWithValue("@r", req.ReorderLevel);
            cmd.Parameters.AddWithValue("@co", req.UnitCost);
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Ok(ReadRow(r)) : StatusCode(500);
        }

        // ======================= MAINTENANCE =======================
        [HttpGet("maintenance")]
        public async Task<IActionResult> ListMaintenance([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT m.*, r.roomnumber FROM hotelmaintenancerequests m LEFT JOIN hotelrooms r ON m.hotelroomid=r.hotelroomid WHERE m.farmid=@f ORDER BY m.createdat DESC", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            return Ok(await ReadAll(cmd));
        }

        [HttpPost("maintenance")]
        public async Task<IActionResult> CreateMaintenance([FromBody] CreateMaintenanceReq req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("INSERT INTO hotelmaintenancerequests(farmid,hotelroomid,assetdescription,issuedescription,priority,estimatedcost) VALUES(@f,@r,@a,@i,@p,@c) RETURNING *", conn);
            cmd.Parameters.AddWithValue("@f", req.FarmId);
            cmd.Parameters.AddWithValue("@r", req.HotelRoomId.HasValue ? (object)req.HotelRoomId.Value : DBNull.Value);
            cmd.Parameters.AddWithValue("@a", req.AssetDescription); cmd.Parameters.AddWithValue("@i", req.IssueDescription);
            cmd.Parameters.AddWithValue("@p", req.Priority); cmd.Parameters.AddWithValue("@c", req.EstimatedCost);
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Ok(ReadRow(r)) : StatusCode(500);
        }

        [HttpPatch("maintenance/{id}/status")]
        public async Task<IActionResult> UpdateMaintenanceStatus(int id, [FromQuery] string farmId, [FromBody] UpdateStatusRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("UPDATE hotelmaintenancerequests SET status=@s,updatedat=NOW(),completedat=CASE WHEN @s='Completed' THEN NOW() ELSE completedat END WHERE hotelmaintenancerequestid=@id AND farmid=@f", conn);
            cmd.Parameters.AddWithValue("@s", req.Status); cmd.Parameters.AddWithValue("@id", id); cmd.Parameters.AddWithValue("@f", farmId);
            await cmd.ExecuteNonQueryAsync();
            return NoContent();
        }

        // ======================= REPORTS / DAILY CLOSING =======================
        [HttpGet("reports/daily-closings")]
        public async Task<IActionResult> ListClosings([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM hoteldailyclosings WHERE farmid=@f ORDER BY closingdate DESC", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            return Ok(await ReadAll(cmd));
        }

        [HttpPost("reports/daily-closings")]
        public async Task<IActionResult> CreateClosing([FromBody] CreateClosingRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            string date = string.IsNullOrEmpty(req.ClosingDate) ? DateTime.UtcNow.ToString("yyyy-MM-dd") : req.ClosingDate;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            int totalRooms = 0, occupied = 0; decimal revenue = 0, expenses = 0;
            using (var c = new NpgsqlCommand("SELECT COUNT(*) FROM hotelrooms WHERE farmid=@f AND isactive=TRUE", conn)) { c.Parameters.AddWithValue("@f", req.FarmId); totalRooms = Convert.ToInt32(await c.ExecuteScalarAsync()); }
            using (var c = new NpgsqlCommand("SELECT COUNT(*) FROM hotelrooms WHERE farmid=@f AND isactive=TRUE AND status='Occupied'", conn)) { c.Parameters.AddWithValue("@f", req.FarmId); occupied = Convert.ToInt32(await c.ExecuteScalarAsync()); }
            using (var c = new NpgsqlCommand("SELECT COALESCE(SUM(amount),0) FROM hotelpayments WHERE farmid=@f AND paymentdate::date=@d::date", conn)) { c.Parameters.AddWithValue("@f", req.FarmId); c.Parameters.AddWithValue("@d", date); revenue = Convert.ToDecimal(await c.ExecuteScalarAsync()); }
            using (var c = new NpgsqlCommand("SELECT COALESCE(SUM(amount),0) FROM hotelexpenses WHERE farmid=@f AND expensedate=@d::date", conn)) { c.Parameters.AddWithValue("@f", req.FarmId); c.Parameters.AddWithValue("@d", date); expenses = Convert.ToDecimal(await c.ExecuteScalarAsync()); }
            decimal occRate = totalRooms > 0 ? Math.Round((decimal)occupied / totalRooms * 100, 2) : 0;
            decimal adr = occupied > 0 ? Math.Round(revenue / occupied, 2) : 0;
            decimal revpar = totalRooms > 0 ? Math.Round(revenue / totalRooms, 2) : 0;
            using var cmd = new NpgsqlCommand("INSERT INTO hoteldailyclosings(farmid,closingdate,totalrevenue,totalexpenses,occupancyrate,roomsoccupied,totalrooms,adr,revpar,notes) VALUES(@f,@d::date,@r,@e,@o,@oc,@tr,@adr,@rp,@n) ON CONFLICT(farmid,closingdate) DO UPDATE SET totalrevenue=EXCLUDED.totalrevenue,totalexpenses=EXCLUDED.totalexpenses,occupancyrate=EXCLUDED.occupancyrate,roomsoccupied=EXCLUDED.roomsoccupied,adr=EXCLUDED.adr,revpar=EXCLUDED.revpar RETURNING *", conn);
            cmd.Parameters.AddWithValue("@f", req.FarmId); cmd.Parameters.AddWithValue("@d", date); cmd.Parameters.AddWithValue("@r", revenue); cmd.Parameters.AddWithValue("@e", expenses);
            cmd.Parameters.AddWithValue("@o", occRate); cmd.Parameters.AddWithValue("@oc", occupied); cmd.Parameters.AddWithValue("@tr", totalRooms);
            cmd.Parameters.AddWithValue("@adr", adr); cmd.Parameters.AddWithValue("@rp", revpar); cmd.Parameters.AddWithValue("@n", (object?)req.Notes ?? DBNull.Value);
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Ok(ReadRow(r)) : StatusCode(500);
        }

        // ======================= DASHBOARD =======================
        [HttpGet("dashboard/summary")]
        public async Task<IActionResult> Summary([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            int total = 0, avail = 0, occ = 0, res = 0, clean = 0, maint = 0, arr = 0, dep = 0;
            async Task<int> Count(string sql) { using var c = new NpgsqlCommand(sql, conn); c.Parameters.AddWithValue("@f", farmId); return Convert.ToInt32(await c.ExecuteScalarAsync()); }
            total = await Count("SELECT COUNT(*) FROM hotelrooms WHERE farmid=@f AND isactive=TRUE");
            avail = await Count("SELECT COUNT(*) FROM hotelrooms WHERE farmid=@f AND isactive=TRUE AND status='Available'");
            occ = await Count("SELECT COUNT(*) FROM hotelrooms WHERE farmid=@f AND isactive=TRUE AND status='Occupied'");
            res = await Count("SELECT COUNT(*) FROM hotelrooms WHERE farmid=@f AND isactive=TRUE AND status='Reserved'");
            clean = await Count("SELECT COUNT(*) FROM hotelrooms WHERE farmid=@f AND isactive=TRUE AND status='Cleaning'");
            maint = await Count("SELECT COUNT(*) FROM hotelrooms WHERE farmid=@f AND isactive=TRUE AND status='Maintenance'");
            arr = await Count("SELECT COUNT(*) FROM hotelbookings WHERE farmid=@f AND checkindate=CURRENT_DATE AND status='Confirmed'");
            dep = await Count("SELECT COUNT(*) FROM hotelbookings WHERE farmid=@f AND checkoutdate=CURRENT_DATE AND status='CheckedIn'");
            decimal occRate = total > 0 ? Math.Round((decimal)occ / total * 100, 2) : 0;
            return Ok(new { totalRooms = total, availableRooms = avail, occupiedRooms = occ, reservedRooms = res, cleaningRooms = clean, maintenanceRooms = maint, occupancyRate = occRate, todayArrivals = arr, todayDepartures = dep, todayRevenue = 0, monthlyRevenue = 0, adr = 0, revPar = 0 });
        }

        // ======================= NIGHT AUDIT =======================
        [HttpPost("night-audit")]
        public async Task<IActionResult> RunNightAudit([FromBody] CreateClosingRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            string date = string.IsNullOrEmpty(req.ClosingDate) ? DateTime.UtcNow.ToString("yyyy-MM-dd") : req.ClosingDate;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();

            async Task<int> Count(string sql) { using var c = new NpgsqlCommand(sql, conn); c.Parameters.AddWithValue("@f", req.FarmId); c.Parameters.AddWithValue("@d", date); return Convert.ToInt32(await c.ExecuteScalarAsync()); }
            async Task<decimal> Sum(string sql) { using var c = new NpgsqlCommand(sql, conn); c.Parameters.AddWithValue("@f", req.FarmId); c.Parameters.AddWithValue("@d", date); return Convert.ToDecimal(await c.ExecuteScalarAsync() ?? 0); }

            int totalRooms = await Count("SELECT COUNT(*) FROM hotelrooms WHERE farmid=@f AND isactive=TRUE");
            int occupied = await Count("SELECT COUNT(*) FROM hotelrooms WHERE farmid=@f AND isactive=TRUE AND status='Occupied'");
            int available = await Count("SELECT COUNT(*) FROM hotelrooms WHERE farmid=@f AND isactive=TRUE AND status='Available'");
            decimal revenue = await Sum("SELECT COALESCE(SUM(amount),0) FROM hotelpayments WHERE farmid=@f AND paymentdate::date=@d::date");
            decimal expenses = await Sum("SELECT COALESCE(SUM(amount),0) FROM hotelexpenses WHERE farmid=@f AND expensedate=@d::date");
            decimal outstanding = await Sum("SELECT COALESCE(SUM(b.totalamount - COALESCE((SELECT SUM(p.amount) FROM hotelpayments p WHERE p.hotelbookingid=b.hotelbookingid AND p.farmid=@f),0)),0) FROM hotelbookings b WHERE b.farmid=@f AND b.status='CheckedIn'");
            int checkins = await Count("SELECT COUNT(*) FROM hotelcheckins WHERE farmid=@f AND checkintime::date=@d::date");
            int checkouts = await Count("SELECT COUNT(*) FROM hotelcheckouts WHERE farmid=@f AND checkouttime::date=@d::date");
            int noshows = await Count("SELECT COUNT(*) FROM hotelbookings WHERE farmid=@f AND checkindate=@d::date AND status='NoShow'");
            int pendingHouse = await Count("SELECT COUNT(*) FROM hotelhousekeepingtasks WHERE farmid=@f AND status='Pending'");
            int openMaint = await Count("SELECT COUNT(*) FROM hotelmaintenancerequests WHERE farmid=@f AND status IN ('Open','InProgress')");

            decimal occRate = totalRooms > 0 ? Math.Round((decimal)occupied / totalRooms * 100, 2) : 0;

            // Auto-post nightly room charges for all checked-in bookings (idempotent)
            int roomChargesPosted = 0;
            using var txn = await conn.BeginTransactionAsync();
            try
            {
                using (var bCmd = new NpgsqlCommand("SELECT hotelbookingid, nightlyrate FROM hotelbookings WHERE farmid=@f AND status='CheckedIn'", conn, txn))
                {
                    bCmd.Parameters.AddWithValue("@f", req.FarmId);
                    var checkedInBookings = new List<(int bookingId, decimal rate)>();
                    using (var br = await bCmd.ExecuteReaderAsync()) { while (await br.ReadAsync()) checkedInBookings.Add((br.GetInt32(0), br.GetDecimal(1))); }

                    foreach (var (bookingId, rate) in checkedInBookings)
                    {
                        if (rate <= 0) continue;
                        using var chg = new NpgsqlCommand(@"INSERT INTO hotelstaycharges(farmid, hotelbookingid, chargetype, description, quantity, unitprice, totalamount, postedby, chargedate)
                            SELECT @f, @b, 'Room', 'Nightly room charge - ' || @d, 1, @rate, @rate, 'Night Audit', @d::date
                            WHERE NOT EXISTS (SELECT 1 FROM hotelstaycharges WHERE farmid=@f AND hotelbookingid=@b AND chargetype='Room' AND chargedate::date=@d::date)", conn, txn);
                        chg.Parameters.AddWithValue("@f", req.FarmId); chg.Parameters.AddWithValue("@b", bookingId);
                        chg.Parameters.AddWithValue("@rate", rate); chg.Parameters.AddWithValue("@d", date);
                        roomChargesPosted += await chg.ExecuteNonQueryAsync();
                    }
                }

                // Build issues list
                var issues = new List<string>();
                if (outstanding > 0) issues.Add($"Outstanding balances: GH₵{outstanding:F2}");
                if (pendingHouse > 0) issues.Add($"{pendingHouse} pending housekeeping tasks");
                if (openMaint > 0) issues.Add($"{openMaint} open maintenance requests");
                if (noshows > 0) issues.Add($"{noshows} no-shows today");

                using var cmd = new NpgsqlCommand("INSERT INTO hotelnightaudits(farmid,auditdate,totalrooms,occupiedrooms,availablerooms,occupancyrate,totalrevenue,totalexpenses,outstandingbalances,checkincount,checkoutcount,noshowcount,pendinghousetasks,openmaintenance,issues,status,roomchargesposted) VALUES(@f,@d::date,@tr,@or,@ar,@occ,@rev,@exp,@out,@ci,@co,@ns,@ph,@om,@iss,'Completed',@rcp) ON CONFLICT(farmid,auditdate) DO UPDATE SET totalrooms=EXCLUDED.totalrooms,occupiedrooms=EXCLUDED.occupiedrooms,availablerooms=EXCLUDED.availablerooms,occupancyrate=EXCLUDED.occupancyrate,totalrevenue=EXCLUDED.totalrevenue,totalexpenses=EXCLUDED.totalexpenses,outstandingbalances=EXCLUDED.outstandingbalances,checkincount=EXCLUDED.checkincount,checkoutcount=EXCLUDED.checkoutcount,noshowcount=EXCLUDED.noshowcount,pendinghousetasks=EXCLUDED.pendinghousetasks,openmaintenance=EXCLUDED.openmaintenance,issues=EXCLUDED.issues,roomchargesposted=EXCLUDED.roomchargesposted RETURNING *", conn, txn);
                cmd.Parameters.AddWithValue("@f", req.FarmId); cmd.Parameters.AddWithValue("@d", date);
                cmd.Parameters.AddWithValue("@tr", totalRooms); cmd.Parameters.AddWithValue("@or", occupied); cmd.Parameters.AddWithValue("@ar", available);
                cmd.Parameters.AddWithValue("@occ", occRate); cmd.Parameters.AddWithValue("@rev", revenue); cmd.Parameters.AddWithValue("@exp", expenses);
                cmd.Parameters.AddWithValue("@out", outstanding); cmd.Parameters.AddWithValue("@ci", checkins); cmd.Parameters.AddWithValue("@co", checkouts);
                cmd.Parameters.AddWithValue("@ns", noshows); cmd.Parameters.AddWithValue("@ph", pendingHouse); cmd.Parameters.AddWithValue("@om", openMaint);
                cmd.Parameters.AddWithValue("@iss", issues.Count > 0 ? string.Join("; ", issues) : (object)DBNull.Value);
                cmd.Parameters.AddWithValue("@rcp", roomChargesPosted);
                using var r = await cmd.ExecuteReaderAsync();
                if (!await r.ReadAsync()) { await txn.RollbackAsync(); return StatusCode(500); }
                var result = ReadRow(r);
                await r.CloseAsync();
                await txn.CommitAsync();
                return Ok(result);
            }
            catch
            {
                await txn.RollbackAsync();
                throw;
            }
        }

        [HttpGet("night-audit")]
        public async Task<IActionResult> ListNightAudits([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM hotelnightaudits WHERE farmid=@f ORDER BY auditdate DESC", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            return Ok(await ReadAll(cmd));
        }

        // ======================= ROOM RATES =======================
        public class CreateRoomRateRequest { public string FarmId { get; set; } = ""; public int HotelRoomTypeId { get; set; } public string RateName { get; set; } = ""; public decimal Rate { get; set; } public string StartDate { get; set; } = ""; public string EndDate { get; set; } = ""; public bool IsWeekend { get; set; } }

        [HttpGet("room-rates")]
        public async Task<IActionResult> ListRoomRates([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT rr.*, rt.name as roomtypename FROM hotelroomrates rr JOIN hotelroomtypes rt ON rr.hotelroomtypeid=rt.hotelroomtypeid WHERE rr.farmid=@f ORDER BY rr.startdate", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            return Ok(await ReadAll(cmd));
        }

        [HttpPost("room-rates")]
        public async Task<IActionResult> CreateRoomRate([FromBody] CreateRoomRateRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("INSERT INTO hotelroomrates(farmid,hotelroomtypeid,ratename,rate,startdate,enddate,isweekend) VALUES(@f,@rt,@n,@r,@s::date,@e::date,@w) RETURNING *", conn);
            cmd.Parameters.AddWithValue("@f", req.FarmId); cmd.Parameters.AddWithValue("@rt", req.HotelRoomTypeId);
            cmd.Parameters.AddWithValue("@n", req.RateName); cmd.Parameters.AddWithValue("@r", req.Rate);
            cmd.Parameters.AddWithValue("@s", req.StartDate); cmd.Parameters.AddWithValue("@e", req.EndDate);
            cmd.Parameters.AddWithValue("@w", req.IsWeekend);
            using var rd = await cmd.ExecuteReaderAsync();
            return await rd.ReadAsync() ? Ok(ReadRow(rd)) : StatusCode(500);
        }

        [HttpDelete("room-rates/{id}")]
        public async Task<IActionResult> DeleteRoomRate(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("DELETE FROM hotelroomrates WHERE hotelroomrateid=@id AND farmid=@f", conn);
            cmd.Parameters.AddWithValue("@id", id); cmd.Parameters.AddWithValue("@f", farmId);
            await cmd.ExecuteNonQueryAsync();
            return NoContent();
        }

        // ======================= LOYALTY =======================
        public class EnrollLoyaltyRequest { public string FarmId { get; set; } = ""; public int HotelGuestId { get; set; } public string? Notes { get; set; } }
        public class LoyaltyPointsRequest { public string FarmId { get; set; } = ""; public int HotelLoyaltyMemberId { get; set; } public int? HotelBookingId { get; set; } public string TransactionType { get; set; } = "Earn"; public int Points { get; set; } public string? Description { get; set; } }

        [HttpGet("loyalty")]
        public async Task<IActionResult> ListLoyaltyMembers([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT lm.*, g.firstname, g.lastname, g.email, g.phone, g.isvip FROM hotelloyaltymembers lm JOIN hotelguests g ON lm.hotelguestid=g.hotelguestid WHERE lm.farmid=@f ORDER BY lm.totalpoints DESC", conn);
            cmd.Parameters.AddWithValue("@f", farmId);
            return Ok(await ReadAll(cmd));
        }

        [HttpGet("loyalty/{id}")]
        public async Task<IActionResult> GetLoyaltyMember(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT lm.*, g.firstname, g.lastname, g.email, g.phone, g.isvip FROM hotelloyaltymembers lm JOIN hotelguests g ON lm.hotelguestid=g.hotelguestid WHERE lm.hotelloyaltymemberid=@id AND lm.farmid=@f", conn);
            cmd.Parameters.AddWithValue("@id", id); cmd.Parameters.AddWithValue("@f", farmId);
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Ok(ReadRow(r)) : NotFound();
        }

        [HttpGet("loyalty/guest/{guestId}")]
        public async Task<IActionResult> GetLoyaltyByGuest(int guestId, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT lm.*, g.firstname, g.lastname FROM hotelloyaltymembers lm JOIN hotelguests g ON lm.hotelguestid=g.hotelguestid WHERE lm.hotelguestid=@gid AND lm.farmid=@f", conn);
            cmd.Parameters.AddWithValue("@gid", guestId); cmd.Parameters.AddWithValue("@f", farmId);
            using var r = await cmd.ExecuteReaderAsync();
            return await r.ReadAsync() ? Ok(ReadRow(r)) : Ok(new { enrolled = false });
        }

        [HttpPost("loyalty/enroll")]
        public async Task<IActionResult> EnrollLoyalty([FromBody] EnrollLoyaltyRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            // Generate membership number
            string memberNum = $"LYL-{DateTime.UtcNow:yyyyMMdd}-{req.HotelGuestId:D4}";
            using var cmd = new NpgsqlCommand("INSERT INTO hotelloyaltymembers(farmid,hotelguestid,membershipnumber,notes) VALUES(@f,@g,@m,@n) ON CONFLICT(farmid,hotelguestid) DO NOTHING RETURNING *", conn);
            cmd.Parameters.AddWithValue("@f", req.FarmId); cmd.Parameters.AddWithValue("@g", req.HotelGuestId);
            cmd.Parameters.AddWithValue("@m", memberNum); cmd.Parameters.AddWithValue("@n", (object?)req.Notes ?? DBNull.Value);
            using var r = await cmd.ExecuteReaderAsync();
            if (await r.ReadAsync()) return Ok(ReadRow(r));
            return Conflict("Guest is already enrolled in loyalty program.");
        }

        [HttpPost("loyalty/points")]
        public async Task<IActionResult> AddLoyaltyPoints([FromBody] LoyaltyPointsRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var txn = await conn.BeginTransactionAsync();

            // Insert transaction
            using (var cmd = new NpgsqlCommand("INSERT INTO hotelloyaltytransactions(farmid,hotelloyaltymemberid,hotelbookingid,transactiontype,points,description) VALUES(@f,@m,@b,@t,@p,@d)", conn, txn))
            {
                cmd.Parameters.AddWithValue("@f", req.FarmId); cmd.Parameters.AddWithValue("@m", req.HotelLoyaltyMemberId);
                cmd.Parameters.AddWithValue("@b", req.HotelBookingId.HasValue ? (object)req.HotelBookingId.Value : DBNull.Value);
                cmd.Parameters.AddWithValue("@t", req.TransactionType); cmd.Parameters.AddWithValue("@p", req.Points);
                cmd.Parameters.AddWithValue("@d", (object?)req.Description ?? DBNull.Value);
                await cmd.ExecuteNonQueryAsync();
            }

            // Update member points
            int pointsDelta = req.TransactionType == "Redeem" ? -Math.Abs(req.Points) : req.Points;
            using (var cmd = new NpgsqlCommand("UPDATE hotelloyaltymembers SET totalpoints=GREATEST(0,totalpoints+@p),lifetimepoints=CASE WHEN @p>0 THEN lifetimepoints+@p ELSE lifetimepoints END,updatedat=NOW() WHERE hotelloyaltymemberid=@m AND farmid=@f", conn, txn))
            {
                cmd.Parameters.AddWithValue("@p", pointsDelta); cmd.Parameters.AddWithValue("@m", req.HotelLoyaltyMemberId);
                cmd.Parameters.AddWithValue("@f", req.FarmId);
                await cmd.ExecuteNonQueryAsync();
            }

            // Auto-update tier based on lifetime points
            string newTier = "Bronze";
            using (var cmd = new NpgsqlCommand("SELECT lifetimepoints FROM hotelloyaltymembers WHERE hotelloyaltymemberid=@m AND farmid=@f", conn, txn))
            {
                cmd.Parameters.AddWithValue("@m", req.HotelLoyaltyMemberId); cmd.Parameters.AddWithValue("@f", req.FarmId);
                var lp = Convert.ToInt32(await cmd.ExecuteScalarAsync() ?? 0);
                if (lp >= 10000) newTier = "Platinum";
                else if (lp >= 5000) newTier = "Gold";
                else if (lp >= 2000) newTier = "Silver";
            }
            using (var cmd = new NpgsqlCommand("UPDATE hotelloyaltymembers SET tier=@t,lasttierupdate=CASE WHEN tier!=@t THEN NOW() ELSE lasttierupdate END WHERE hotelloyaltymemberid=@m AND farmid=@f", conn, txn))
            {
                cmd.Parameters.AddWithValue("@t", newTier); cmd.Parameters.AddWithValue("@m", req.HotelLoyaltyMemberId);
                cmd.Parameters.AddWithValue("@f", req.FarmId);
                await cmd.ExecuteNonQueryAsync();
            }

            await txn.CommitAsync();
            return Ok(new { success = true, tier = newTier });
        }

        [HttpGet("loyalty/{id}/transactions")]
        public async Task<IActionResult> ListLoyaltyTransactions(int id, [FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            using var conn = new NpgsqlConnection(_cs); await conn.OpenAsync();
            using var cmd = new NpgsqlCommand("SELECT * FROM hotelloyaltytransactions WHERE hotelloyaltymemberid=@id AND farmid=@f ORDER BY createdat DESC LIMIT 50", conn);
            cmd.Parameters.AddWithValue("@id", id); cmd.Parameters.AddWithValue("@f", farmId);
            return Ok(await ReadAll(cmd));
        }

        private static async Task<List<Dictionary<string, object?>>> ReadAll(NpgsqlCommand cmd) { using var r = await cmd.ExecuteReaderAsync(); var list = new List<Dictionary<string, object?>>(); while (await r.ReadAsync()) list.Add(ReadRow(r)); return list; }
        private static Dictionary<string, object?> ReadRow(NpgsqlDataReader r) { var d = new Dictionary<string, object?>(); for (int i = 0; i < r.FieldCount; i++) { var n = r.GetName(i); d[char.ToLower(n[0]) + n[1..]] = r.IsDBNull(i) ? null : r.GetValue(i); } return d; }
    }
}
