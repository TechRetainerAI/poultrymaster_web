using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using User.Management.Data.Models;
using User.Management.Service.Services;

namespace User.Management.API.Controllers
{
    [Authorize]
    [Route("api/[controller]")]
    [ApiController]
    public class CompaniesController : ControllerBase
    {
        private readonly ICompanyService _companies;
        private readonly ILogger<CompaniesController> _logger;

        public CompaniesController(ICompanyService companies, ILogger<CompaniesController> logger)
        {
            _companies = companies;
            _logger = logger;
        }

        // GET /api/Companies/mine
        // Returns every farm/company the current user belongs to.
        [HttpGet("mine")]
        public async Task<IActionResult> GetMine()
        {
            var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);
            if (string.IsNullOrEmpty(userId)) return Unauthorized();

            var result = await _companies.GetMineAsync(userId);
            return result.IsSuccess ? Ok(result.Response) : StatusCode(result.StatusCode, result.Message);
        }

        // POST /api/Companies
        // Creates a new company owned by the current user.
        [HttpPost]
        public async Task<IActionResult> Create([FromBody] CreateCompanyRequest req)
        {
            var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);
            if (string.IsNullOrEmpty(userId)) return Unauthorized();

            try
            {
                var result = await _companies.CreateAsync(userId, req);
                return result.IsSuccess
                    ? StatusCode(result.StatusCode, result.Response)
                    : StatusCode(result.StatusCode, new { message = result.Message });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "[Companies] Create failed");
                return StatusCode(500, new { message = ex.Message });
            }
        }

        // PUT /api/Companies/{farmId}
        // Edits a company the current user belongs to (Doc 3 §8).
        [HttpPut("{farmId}")]
        public async Task<IActionResult> Update(string farmId, [FromBody] CreateCompanyRequest req)
        {
            var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);
            if (string.IsNullOrEmpty(userId)) return Unauthorized();

            try
            {
                var result = await _companies.UpdateAsync(userId, farmId, req);
                return result.IsSuccess
                    ? Ok(result.Response)
                    : StatusCode(result.StatusCode, new { message = result.Message });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "[Companies] Update failed");
                return StatusCode(500, new { message = ex.Message });
            }
        }

        // POST /api/Companies/switch
        // Switches the user's active company. Returns a new JWT scoped to that
        // company. Frontend should replace the stored token with the response.
        [HttpPost("switch")]
        public async Task<IActionResult> Switch([FromBody] SwitchFarmRequest req)
        {
            var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);
            if (string.IsNullOrEmpty(userId)) return Unauthorized();

            try
            {
                var result = await _companies.SwitchAsync(userId, req?.FarmId ?? string.Empty);
                return result.IsSuccess
                    ? Ok(result.Response)
                    : StatusCode(result.StatusCode, new { message = result.Message });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "[Companies] Switch failed");
                return StatusCode(500, new { message = ex.Message });
            }
        }
    }
}
