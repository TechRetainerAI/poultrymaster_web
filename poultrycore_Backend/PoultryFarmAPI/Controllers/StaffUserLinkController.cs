// Staff <-> Employee link (migration 362).
//
// An Employee is a login (aspnetusers, Login API); a Staff member is a payroll
// record in the company type's staff table. staff.userid links the two so one
// person shows on both pages. This controller only reads and sets that link:
// creating the staff row or the login still goes through each side's own
// endpoint, and the page links them straight after.
//
// Route is api/StaffUserLink: module-neutral because it serves all five company
// types (the SP picks the table from farms.type), and its first segment must
// not be one the Next.js proxy sends to the Login API. The company must be the
// caller's token company -- the same check the Employees list scopes by.

using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Npgsql;
using NpgsqlTypes;
using PoultryFarmAPIWeb.Helpers;

namespace PoultryFarmAPIWeb.Controllers
{
    public class StaffUserLinkModel { public int StaffId { get; set; } public string UserId { get; set; } = ""; }
    public class SetStaffUserLinkRequest { public string FarmId { get; set; } = ""; public int StaffId { get; set; } public string? UserId { get; set; } }

    [Authorize]
    [ApiController]
    [Route("api/StaffUserLink")]
    public class StaffUserLinkController : ControllerBase
    {
        private readonly string _cs;
        public StaffUserLinkController(IConfiguration config) { _cs = config.GetConnectionString("PoultryConn") ?? ""; }

        /// <summary>Every live staff row of the company that is linked to an existing login.</summary>
        [HttpGet]
        public async Task<IActionResult> GetAll([FromQuery] string farmId)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, farmId); if (auth != null) return auth;
            await using var conn = new NpgsqlConnection(_cs);
            await using var cmd = new NpgsqlCommand("SELECT staffid, userid FROM fnstaff_userlinks(p_farmid => @F::text)", conn);
            cmd.Parameters.Add(new NpgsqlParameter("@F", NpgsqlDbType.Text) { Value = farmId });
            await conn.OpenAsync();
            var list = new List<StaffUserLinkModel>();
            await using var r = await cmd.ExecuteReaderAsync();
            while (await r.ReadAsync()) list.Add(new StaffUserLinkModel { StaffId = r.GetInt32(0), UserId = r.GetString(1) });
            return Ok(list);
        }

        /// <summary>Link a staff row to a login, or unlink it (UserId null).</summary>
        [HttpPut]
        public async Task<IActionResult> Set([FromBody] SetStaffUserLinkRequest req)
        {
            var auth = HotelAuthHelper.VerifyFarmOwnership(User, req.FarmId); if (auth != null) return auth;
            if (req.StaffId <= 0) return BadRequest("Staff member is required.");
            await using var conn = new NpgsqlConnection(_cs);
            await using var cmd = new NpgsqlCommand(
                "SELECT spstaff_linkuser(p_farmid => @F::text, p_staffid => @S::int, p_userid => @U::text)", conn);
            cmd.Parameters.Add(new NpgsqlParameter("@F", NpgsqlDbType.Text) { Value = req.FarmId });
            cmd.Parameters.Add(new NpgsqlParameter("@S", NpgsqlDbType.Integer) { Value = req.StaffId });
            cmd.Parameters.Add(new NpgsqlParameter("@U", NpgsqlDbType.Text)
                { Value = string.IsNullOrWhiteSpace(req.UserId) ? DBNull.Value : req.UserId });
            await conn.OpenAsync();
            try { await cmd.ExecuteNonQueryAsync(); }
            // The SP's refusals are sentences meant for the user.
            catch (PostgresException ex) when (ex.SqlState == "P0001") { return Conflict(new { message = ex.MessageText }); }
            catch (PostgresException ex) when (ex.SqlState == "P0002") { return NotFound(new { message = ex.MessageText }); }
            return NoContent();
        }
    }
}
