using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using System.Security.Claims;
using System.Text.Json;
using User.Management.API.Models;
using User.Management.Data.Models;
using User.Management.Service.Services;

namespace User.Management.API.Controllers
{
    [Authorize]
    [Route("api/[controller]")]
    [ApiController]
    public class AdminController : ControllerBase
    {
        private static readonly JsonSerializerOptions JsonOptions = new()
        {
            PropertyNameCaseInsensitive = true
        };

        private static Dictionary<string, bool>? DeserializePermissions(string? value)
        {
            if (string.IsNullOrWhiteSpace(value))
            {
                return null;
            }

            try
            {
                return JsonSerializer.Deserialize<Dictionary<string, bool>>(value, JsonOptions);
            }
            catch
            {
                return null;
            }
        }

        private static string? SerializePermissions(Dictionary<string, bool>? permissions)
        {
            if (permissions == null || permissions.Count == 0)
            {
                return null;
            }

            return JsonSerializer.Serialize(permissions, JsonOptions);
        }

        private readonly IAdminService _adminService;
        private readonly ILogger<AdminController> _logger;

        public AdminController(IAdminService adminService, ILogger<AdminController> logger)
        {
            _adminService = adminService;
            _logger = logger;
        }

        /// <summary>
        /// Get all employees for the current farm
        /// </summary>
        [HttpGet("employees")]
        public async Task<ActionResult<List<EmployeeModel>>> GetEmployees()
        {
            try
            {
                var farmId = User.FindFirst("FarmId")?.Value;
                
                if (string.IsNullOrEmpty(farmId))
                {
                    return BadRequest("FarmId not found in user claims");
                }

                _logger.LogInformation("Fetching employees for farm: {FarmId}", farmId);

                var employees = await _adminService.GetEmployeesByFarmIdAsync(farmId);

                var employeeModels = employees.Select(e => new EmployeeModel
                {
                    Id = e.Id,
                    Email = e.Email,
                    FirstName = e.FirstName,
                    LastName = e.LastName,
                    PhoneNumber = e.PhoneNumber,
                    UserName = e.UserName,
                    FarmId = e.FarmId,
                    FarmName = e.FarmName,
                    IsStaff = e.IsStaff,
                    IsAdmin = e.IsAdmin,
                    AdminTitle = e.AdminTitle,
                    Permissions = DeserializePermissions(e.Permissions),
                    FeaturePermissions = DeserializePermissions(e.FeaturePermissions),
                    EmailConfirmed = e.EmailConfirmed,
                    CreatedDate = DateTime.UtcNow, // Temporary: Should add CreatedDate column to database
                    LastLoginTime = null // Commented out until database column is added
                }).ToList();

                _logger.LogInformation("Found {Count} employees for farm {FarmId}", employeeModels.Count, farmId);

                return Ok(employeeModels);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error fetching employees");
                return StatusCode(500, $"Internal server error: {ex.Message}");
            }
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
                _logger.LogError(ex, "Error fetching farms");
                return StatusCode(500, $"Internal server error: {ex.Message}");
            }
        }

        /// <summary>
        /// Get total count of distinct farms
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
                _logger.LogError(ex, "Error fetching farm count");
                return StatusCode(500, $"Internal server error: {ex.Message}");
            }
        }

        /// <summary>
        /// Get a specific employee by ID
        /// </summary>
        [HttpGet("employees/{id}")]
        public async Task<ActionResult<EmployeeModel>> GetEmployeeById(string id)
        {
            try
            {
                var farmId = User.FindFirst("FarmId")?.Value;
                
                if (string.IsNullOrEmpty(farmId))
                {
                    return BadRequest("FarmId not found in user claims");
                }

                var employee = await _adminService.GetEmployeeByIdAsync(id, farmId);

                if (employee == null)
                {
                    return NotFound($"Employee with ID {id} not found");
                }

                var employeeModel = new EmployeeModel
                {
                    Id = employee.Id,
                    Email = employee.Email,
                    FirstName = employee.FirstName,
                    LastName = employee.LastName,
                    PhoneNumber = employee.PhoneNumber,
                    UserName = employee.UserName,
                    FarmId = employee.FarmId,
                    FarmName = employee.FarmName,
                    IsStaff = employee.IsStaff,
                    IsAdmin = employee.IsAdmin,
                    AdminTitle = employee.AdminTitle,
                    Permissions = DeserializePermissions(employee.Permissions),
                    FeaturePermissions = DeserializePermissions(employee.FeaturePermissions),
                    EmailConfirmed = employee.EmailConfirmed,
                    CreatedDate = DateTime.UtcNow, // Temporary: Should add CreatedDate column to database
                    LastLoginTime = null // Commented out until database column is added
                };

                return Ok(employeeModel);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error fetching employee {EmployeeId}", id);
                return StatusCode(500, $"Internal server error: {ex.Message}");
            }
        }

        /// <summary>
        /// Create a new employee
        /// </summary>
        [HttpPost("employees")]
        public async Task<ActionResult<EmployeeModel>> CreateEmployee([FromBody] CreateEmployeeRequest request)
        {
            try
            {
                // Log incoming request for debugging
                _logger.LogInformation("CreateEmployee called with request: Email={Email}, UserName={UserName}, FirstName={FirstName}, LastName={LastName}", 
                    request?.Email, request?.UserName, request?.FirstName, request?.LastName);

                if (request == null)
                {
                    _logger.LogError("CreateEmployee: Request body is null");
                    return BadRequest("Request body is required");
                }

                var farmId = User.FindFirst("FarmId")?.Value;
                var farmName = User.FindFirst("FarmName")?.Value;
                
                if (string.IsNullOrEmpty(farmId))
                {
                    _logger.LogError("CreateEmployee: FarmId not found in user claims");
                    return BadRequest("FarmId not found in user claims. Please ensure you are logged in as an admin.");
                }

                _logger.LogInformation("Creating employee for farm: {FarmId}, FarmName: {FarmName}", farmId, farmName);

                var employee = new ApplicationUser
                {
                    Email = request.Email,
                    FirstName = request.FirstName,
                    LastName = request.LastName,
                    PhoneNumber = request.PhoneNumber,
                    UserName = request.UserName,
                    FarmId = farmId,
                    FarmName = farmName,
                    IsStaff = true,
                    IsAdmin = request.IsAdmin,
                    AdminTitle = string.IsNullOrWhiteSpace(request.AdminTitle) ? null : request.AdminTitle.Trim(),
                    Permissions = SerializePermissions(request.Permissions),
                    FeaturePermissions = SerializePermissions(request.FeaturePermissions)
                };

                _logger.LogInformation("Calling AdminService.CreateEmployeeAsync for user: {UserName}", employee.UserName);
                var createdEmployee = await _adminService.CreateEmployeeAsync(employee, request.Password);
                _logger.LogInformation("AdminService.CreateEmployeeAsync completed. Employee ID: {EmployeeId}", createdEmployee?.Id);

                // Verify employee was actually saved to database
                if (createdEmployee == null || string.IsNullOrEmpty(createdEmployee.Id))
                {
                    _logger.LogError("Employee creation returned null or empty ID");
                    return BadRequest(new { message = "Failed to create employee - employee object is null or invalid" });
                }

                // Double-check employee exists in database
                var verifyEmployee = await _adminService.GetEmployeeByIdAsync(createdEmployee.Id, farmId);
                if (verifyEmployee == null)
                {
                    _logger.LogError("Employee {EmployeeId} not found in database after creation", createdEmployee.Id);
                    return StatusCode(500, new { message = "Employee was created but could not be verified in database" });
                }

                _logger.LogInformation("Employee verified in database: {EmployeeId}, UserName: {UserName}", verifyEmployee.Id, verifyEmployee.UserName);

                var employeeModel = new EmployeeModel
                {
                    Id = createdEmployee.Id,
                    Email = createdEmployee.Email,
                    FirstName = createdEmployee.FirstName,
                    LastName = createdEmployee.LastName,
                    PhoneNumber = createdEmployee.PhoneNumber,
                    UserName = createdEmployee.UserName,
                    FarmId = createdEmployee.FarmId,
                    FarmName = createdEmployee.FarmName,
                    IsStaff = createdEmployee.IsStaff,
                    IsAdmin = createdEmployee.IsAdmin,
                    AdminTitle = createdEmployee.AdminTitle,
                    Permissions = DeserializePermissions(createdEmployee.Permissions),
                    FeaturePermissions = DeserializePermissions(createdEmployee.FeaturePermissions),
                    EmailConfirmed = createdEmployee.EmailConfirmed,
                    CreatedDate = DateTime.UtcNow,
                    LastLoginTime = null // Commented out until database column is added
                };

                _logger.LogInformation("Employee created and verified successfully: {EmployeeId}, UserName: {UserName}", createdEmployee.Id, createdEmployee.UserName);

                return CreatedAtAction(nameof(GetEmployeeById), new { id = createdEmployee.Id }, employeeModel);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error creating employee");
                return BadRequest(new { message = ex.Message });
            }
        }

        /// <summary>
        /// Update an employee
        /// </summary>
        [HttpPut("employees/{id}")]
        public async Task<ActionResult> UpdateEmployee(string id, [FromBody] UpdateEmployeeRequest request)
        {
            try
            {
                var farmId = User.FindFirst("FarmId")?.Value;
                
                if (string.IsNullOrEmpty(farmId))
                {
                    return BadRequest("FarmId not found in user claims");
                }

                if (id != request.Id)
                {
                    return BadRequest("ID mismatch");
                }

                _logger.LogInformation("Updating employee {EmployeeId} for farm: {FarmId}", id, farmId);

                var employee = new ApplicationUser
                {
                    Id = request.Id,
                    FirstName = request.FirstName,
                    LastName = request.LastName,
                    PhoneNumber = request.PhoneNumber,
                    Email = request.Email,
                    IsAdmin = request.IsAdmin,
                    AdminTitle = string.IsNullOrWhiteSpace(request.AdminTitle) ? null : request.AdminTitle.Trim(),
                    Permissions = SerializePermissions(request.Permissions),
                    FeaturePermissions = SerializePermissions(request.FeaturePermissions)
                };

                var result = await _adminService.UpdateEmployeeAsync(employee);

                if (!result)
                {
                    return BadRequest("Failed to update employee");
                }

                _logger.LogInformation("Employee {EmployeeId} updated successfully", id);

                return NoContent();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error updating employee {EmployeeId}", id);
                return BadRequest(new { message = ex.Message });
            }
        }

        /// <summary>
        /// Delete an employee
        /// </summary>
        [HttpDelete("employees/{id}")]
        public async Task<ActionResult> DeleteEmployee(string id)
        {
            try
            {
                var farmId = User.FindFirst("FarmId")?.Value;
                
                if (string.IsNullOrEmpty(farmId))
                {
                    return BadRequest("FarmId not found in user claims");
                }

                _logger.LogInformation("Deleting employee {EmployeeId} from farm: {FarmId}", id, farmId);

                var result = await _adminService.DeleteEmployeeAsync(id, farmId);

                if (!result)
                {
                    return BadRequest("Failed to delete employee");
                }

                _logger.LogInformation("Employee {EmployeeId} deleted successfully", id);

                return NoContent();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error deleting employee {EmployeeId}", id);
                return BadRequest(new { message = ex.Message });
            }
        }

        /// <summary>
        /// Get employee count for the current farm
        /// </summary>
        [HttpGet("employees/count")]
        public async Task<ActionResult<int>> GetEmployeeCount()
        {
            try
            {
                var farmId = User.FindFirst("FarmId")?.Value;
                
                if (string.IsNullOrEmpty(farmId))
                {
                    return BadRequest("FarmId not found in user claims");
                }

                var count = await _adminService.GetEmployeeCountAsync(farmId);

                return Ok(new { count });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting employee count");
                return StatusCode(500, $"Internal server error: {ex.Message}");
            }
        }

        /// <summary>
        /// Get employees who logged in today
        /// </summary>
        [HttpGet("employees/today-logins")]
        public async Task<ActionResult<List<EmployeeModel>>> GetTodayLogins()
        {
            try
            {
                var farmId = User.FindFirst("FarmId")?.Value;
                
                if (string.IsNullOrEmpty(farmId))
                {
                    return BadRequest("FarmId not found in user claims");
                }

                _logger.LogInformation("Fetching today's logins for farm: {FarmId}", farmId);

                var today = DateTime.UtcNow.Date;
                var employees = await _adminService.GetEmployeesByFarmIdAsync(farmId);

                // Commenting out today's logins until LastLoginTime column is added to database
                var todayLogins = new List<EmployeeModel>(); // Empty list for now
                // var todayLogins = employees
                //     .Where(e => e.LastLoginTime.HasValue && e.LastLoginTime.Value.Date == today)
                //     .Select(e => new EmployeeModel
                //     {
                //         Id = e.Id,
                //         Email = e.Email,
                //         FirstName = e.FirstName,
                //         LastName = e.LastName,
                //         PhoneNumber = e.PhoneNumber,
                //         UserName = e.UserName,
                //         FarmId = e.FarmId,
                //         FarmName = e.FarmName,
                //         IsStaff = e.IsStaff,
                //         EmailConfirmed = e.EmailConfirmed,
                //         CreatedDate = DateTime.UtcNow,
                //         LastLoginTime = e.LastLoginTime
                //     })
                //     .ToList();

                _logger.LogInformation("Found {Count} employees who logged in today", todayLogins.Count);

                return Ok(todayLogins);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error fetching today's logins");
                return StatusCode(500, $"Internal server error: {ex.Message}");
            }
        }
    }
}
