using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Npgsql;

namespace PoultryFarmAPI.Controllers
{
    /// <summary>
    /// Platform-level farm management for the developer admin portal.
    /// Same JWT gate as the platform audit feed: SystemAdmin / PlatformOwner only.
    /// </summary>
    [ApiController]
    [Route("api/PlatformFarms")]
    [Authorize(Roles = "SystemAdmin,PlatformOwner")]
    public class PlatformFarmsController : ControllerBase
    {
        private readonly string _cs;
        private readonly ILogger<PlatformFarmsController> _logger;

        public PlatformFarmsController(IConfiguration cfg, ILogger<PlatformFarmsController> logger)
        {
            _cs = cfg.GetConnectionString("PoultryConn")
                  ?? cfg["ConnectionStrings:PoultryConn"] ?? "";
            _logger = logger;
        }

        /// <summary>
        /// Permanently delete a farm and every row it owns (all-or-nothing transaction).
        /// The caller must echo the exact farm name in <paramref name="confirmName"/> —
        /// a tripwire against deleting the wrong row from a list.
        /// </summary>
        [HttpDelete("{farmId:guid}")]
        public async Task<IActionResult> DeleteFarm(Guid farmId, [FromQuery] string confirmName)
        {
            var actor = User.FindFirstValue(ClaimTypes.Name)
                        ?? User.FindFirstValue(ClaimTypes.NameIdentifier) ?? "platform-admin";
            try
            {
                await using var conn = new NpgsqlConnection(_cs);
                await conn.OpenAsync();

                string? farmName;
                await using (var check = new NpgsqlCommand("SELECT farmname FROM farms WHERE farmid = @id", conn))
                {
                    check.Parameters.AddWithValue("id", farmId);
                    farmName = (string?)await check.ExecuteScalarAsync();
                }
                if (farmName is null)
                    return NotFound(new { ok = false, message = "Farm not found." });
                if (!string.Equals(farmName.Trim(), (confirmName ?? "").Trim(), StringComparison.OrdinalIgnoreCase))
                    return BadRequest(new { ok = false, message = $"Confirmation name does not match the farm name. Type the exact farm name to delete it." });

                await using var tx = await conn.BeginTransactionAsync();
                string summary;
                await using (var cmd = new NpgsqlCommand("SELECT platform_delete_farm(@id)", conn, tx))
                {
                    cmd.CommandTimeout = 300;
                    cmd.Parameters.AddWithValue("id", farmId);
                    summary = (string?)await cmd.ExecuteScalarAsync() ?? "Deleted.";
                }

                // The purge removed the farm's own audit rows; record the deletion farm-less.
                await using (var log = new NpgsqlCommand(
                    @"INSERT INTO auditlogs (userid, username, action, resource, resourceid, details, timestamp, status)
                      VALUES (@uid, @uname, 'FARM_DELETED', 'Farm', @rid, @details, now() AT TIME ZONE 'utc', 'Success')", conn, tx))
                {
                    log.Parameters.AddWithValue("uid", User.FindFirstValue(ClaimTypes.NameIdentifier) ?? "");
                    log.Parameters.AddWithValue("uname", actor);
                    log.Parameters.AddWithValue("rid", farmId.ToString());
                    log.Parameters.AddWithValue("details", summary);
                    await log.ExecuteNonQueryAsync();
                }

                await tx.CommitAsync();
                _logger.LogWarning("Farm {FarmId} ({FarmName}) deleted by {Actor}: {Summary}", farmId, farmName, actor, summary);
                return Ok(new { ok = true, message = summary });
            }
            catch (PostgresException ex)
            {
                _logger.LogError(ex, "Farm delete failed for {FarmId} (SQL {SqlState})", farmId, ex.SqlState);
                return StatusCode(500, new { ok = false, message = $"Delete failed: {ex.MessageText}" });
            }
        }
    }
}
