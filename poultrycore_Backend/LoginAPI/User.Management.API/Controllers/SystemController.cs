using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using User.Management.Data.Models;
using User.Management.Service.Services;

namespace User.Management.API.Controllers
{
    // Platform CEO / owner: full directory across all farms (not farm staff).
    [Authorize(Roles = "SystemAdmin,PlatformOwner")]
    [Route("api/[controller]")]
    [ApiController]
    public class SystemController : ControllerBase
    {
        private readonly IAdminService _adminService;
        private readonly ILogger<SystemController> _logger;

        public SystemController(IAdminService adminService, ILogger<SystemController> logger)
        {
            _adminService = adminService;
            _logger = logger;
        }

        /// <summary>
        /// List all farms registered in the system with user/staff counts
        /// </summary>
        [HttpGet("farms")]
        public async Task<ActionResult<List<FarmSummary>>> GetFarms()
        {
            try
            {
                var farms = await _adminService.GetFarmsAsync();
                return Ok(farms);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "[System] Error fetching farms");
                return StatusCode(500, $"Internal server error: {ex.Message}");
            }
        }

        /// <summary>
        /// Get total count of distinct farms registered in the system
        /// </summary>
        [HttpGet("farms/count")]
        public async Task<ActionResult<object>> GetFarmCount()
        {
            try
            {
                var count = await _adminService.GetFarmCountAsync();
                return Ok(new { count });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "[System] Error fetching farm count");
                return StatusCode(500, $"Internal server error: {ex.Message}");
            }
        }

        /// <summary>
        /// Full audit detail for one farm: farm fields, owner account and employees
        /// (each with their 2FA state). Backs the portal "Audit" action.
        /// </summary>
        [HttpGet("farms/{farmId}/detail")]
        public async Task<ActionResult<FarmDetail>> GetFarmDetail(string farmId)
        {
            try
            {
                var detail = await _adminService.GetFarmDetailAsync(farmId);
                return Ok(detail);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "[System] Error loading farm detail for {FarmId}", farmId);
                return StatusCode(500, $"Internal server error: {ex.Message}");
            }
        }

        /// <summary>
        /// Platform-admin override to turn two-factor on/off for any account —
        /// used to switch 2FA back off for a customer who enabled it and got stuck.
        /// </summary>
        [HttpPost("users/{userId}/two-factor")]
        public async Task<ActionResult<object>> SetUserTwoFactor(string userId, [FromBody] TwoFactorToggleRequest request)
        {
            try
            {
                var enabled = await _adminService.SetUserTwoFactorAsync(userId, request?.Enabled ?? false);
                return Ok(new { ok = true, userId, twoFactorEnabled = enabled });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "[System] Error setting 2FA for user {UserId}", userId);
                return StatusCode(500, new { ok = false, message = ex.Message });
            }
        }
    }

    public class TwoFactorToggleRequest
    {
        public bool Enabled { get; set; }
    }
}


