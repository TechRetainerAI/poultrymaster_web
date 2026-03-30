using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using User.Management.Data.Models;
using User.Management.Service.Services;

namespace User.Management.API.Controllers
{
    // Endpoints intended for the system developer/project manager only
    [Authorize(Roles = "SystemAdmin")]
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
    }
}


