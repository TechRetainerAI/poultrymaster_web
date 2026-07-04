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
        private readonly IAuditLogger _auditLogger;
        private readonly ILogger<AdminController> _logger;

        public AdminController(IAdminService adminService, IAuditLogger auditLogger, ILogger<AdminController> logger)
        {
            _adminService = adminService;
            _auditLogger = auditLogger;
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

                var claimFarmId = User.FindFirst("FarmId")?.Value;
                var claimFarmName = User.FindFirst("FarmName")?.Value;
                var callerUserId = User.FindFirstValue(ClaimTypes.NameIdentifier);

                // Doc 3 §6-7: an admin can create an employee for a SPECIFIC company
                // chosen in the Business Office (request.FarmId), not just the JWT's
                // active company — the Business Office is company-neutral, so the
                // claim may be empty. If a company is supplied and differs from the
                // claim, verify the caller actually has access to it.
                var farmId = !string.IsNullOrWhiteSpace(request.FarmId) ? request.FarmId.Trim() : claimFarmId;
                var farmName = !string.IsNullOrWhiteSpace(request.FarmName) ? request.FarmName : claimFarmName;

                if (string.IsNullOrEmpty(farmId))
                {
                    _logger.LogError("CreateEmployee: no company supplied and none in claims");
                    return BadRequest("Please select a company for this employee.");
                }

                if (!string.IsNullOrWhiteSpace(request.FarmId)
                    && !string.Equals(request.FarmId.Trim(), claimFarmId, StringComparison.OrdinalIgnoreCase)
                    && !string.IsNullOrEmpty(callerUserId))
                {
                    var hasAccess = await _adminService.UserHasCompanyAccessAsync(callerUserId, farmId);
                    if (!hasAccess)
                    {
                        _logger.LogWarning("CreateEmployee: caller {UserId} has no access to company {FarmId}", callerUserId, farmId);
                        return BadRequest("You do not have access to the selected company.");
                    }
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

                // Audit trail. Fire-and-forget — failure to insert the audit row
                // must not break the response. Details mirror the Farm API filter's
                // "<METHOD> <Resource> (ID: x) - Created" format so the existing
                // /audit-logs UI renders this row consistently.
                await _auditLogger.LogAsync(
                    HttpContext,
                    action:     "POST",
                    resource:   "Employee",
                    resourceId: createdEmployee.Id,
                    farmId:     farmId,
                    details:    $"POST Employee (ID: {createdEmployee.Id}) - Created");

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

                await _auditLogger.LogAsync(
                    HttpContext,
                    action:     "PUT",
                    resource:   "Employee",
                    resourceId: id,
                    farmId:     farmId,
                    details:    $"PUT Employee (ID: {id}) - Updated");

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

                await _auditLogger.LogAsync(
                    HttpContext,
                    action:     "DELETE",
                    resource:   "Employee",
                    resourceId: id,
                    farmId:     farmId,
                    details:    $"DELETE Employee (ID: {id}) - Deleted");

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

        // ---- Doc 3 §6-7: organization employees + company access (UserFarms) ----

        /// <summary>
        /// All employees across every company in the current admin's organization,
        /// each with the list of companies they can access.
        /// </summary>
        [HttpGet("organization/employees")]
        public async Task<ActionResult<List<OrganizationEmployeeModel>>> GetOrganizationEmployees()
        {
            try
            {
                var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);
                if (string.IsNullOrEmpty(userId))
                {
                    return BadRequest("User id not found in claims");
                }

                var employees = await _adminService.GetOrganizationEmployeesAsync(userId);
                var result = new List<OrganizationEmployeeModel>(employees.Count);

                foreach (var e in employees)
                {
                    var companies = await _adminService.GetEmployeeCompaniesAsync(e.Id);
                    result.Add(new OrganizationEmployeeModel
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
                        CreatedDate = DateTime.UtcNow,
                        LastLoginTime = null,
                        Companies = companies.Select(c => new CompanyAccessModel
                        {
                            FarmId = c.FarmId,
                            Name = c.Name,
                            Type = c.Type,
                            Role = c.Role,
                        }).ToList(),
                    });
                }

                return Ok(result);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error fetching organization employees");
                return StatusCode(500, $"Internal server error: {ex.Message}");
            }
        }

        /// <summary>
        /// Companies a given employee can access.
        /// </summary>
        [HttpGet("employees/{id}/companies")]
        public async Task<ActionResult<List<CompanyAccessModel>>> GetEmployeeCompanies(string id)
        {
            try
            {
                var companies = await _adminService.GetEmployeeCompaniesAsync(id);
                return Ok(companies.Select(c => new CompanyAccessModel
                {
                    FarmId = c.FarmId,
                    Name = c.Name,
                    Type = c.Type,
                    Role = c.Role,
                }).ToList());
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error fetching companies for employee {EmployeeId}", id);
                return StatusCode(500, $"Internal server error: {ex.Message}");
            }
        }

        /// <summary>
        /// Grant an employee access to a company.
        /// </summary>
        [HttpPost("employees/{id}/company-access")]
        public async Task<ActionResult> AssignCompanyAccess(string id, [FromBody] CompanyAccessRequest request)
        {
            try
            {
                if (request == null || string.IsNullOrWhiteSpace(request.FarmId))
                {
                    return BadRequest("FarmId is required");
                }

                await _adminService.AssignCompanyAccessAsync(id, request.FarmId, request.Role ?? "Staff");

                await _auditLogger.LogAsync(
                    HttpContext,
                    action:     "POST",
                    resource:   "EmployeeCompanyAccess",
                    resourceId: id,
                    farmId:     request.FarmId,
                    details:    $"POST EmployeeCompanyAccess (Employee: {id}, Company: {request.FarmId}) - Granted");

                return NoContent();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error assigning company access for employee {EmployeeId}", id);
                return BadRequest(new { message = ex.Message });
            }
        }

        /// <summary>
        /// Revoke an employee's access to a company.
        /// </summary>
        [HttpDelete("employees/{id}/company-access/{farmId}")]
        public async Task<ActionResult> RemoveCompanyAccess(string id, string farmId)
        {
            try
            {
                if (string.IsNullOrWhiteSpace(farmId))
                {
                    return BadRequest("FarmId is required");
                }

                await _adminService.RemoveCompanyAccessAsync(id, farmId);

                await _auditLogger.LogAsync(
                    HttpContext,
                    action:     "DELETE",
                    resource:   "EmployeeCompanyAccess",
                    resourceId: id,
                    farmId:     farmId,
                    details:    $"DELETE EmployeeCompanyAccess (Employee: {id}, Company: {farmId}) - Revoked");

                return NoContent();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error removing company access for employee {EmployeeId}", id);
                return BadRequest(new { message = ex.Message });
            }
        }

        /// <summary>
        /// Employees who have access to a specific company (access-based list).
        /// </summary>
        [HttpGet("company-employees")]
        public async Task<ActionResult<List<EmployeeModel>>> GetCompanyEmployees([FromQuery] string farmId)
        {
            try
            {
                if (string.IsNullOrWhiteSpace(farmId))
                {
                    farmId = User.FindFirst("FarmId")?.Value ?? string.Empty;
                }
                if (string.IsNullOrWhiteSpace(farmId))
                {
                    return BadRequest("FarmId is required");
                }

                var employees = await _adminService.GetEmployeesWithAccessAsync(farmId);
                var result = employees.Select(e => new EmployeeModel
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
                    CreatedDate = DateTime.UtcNow,
                    LastLoginTime = null,
                }).ToList();

                return Ok(result);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error fetching employees with access to farm {FarmId}", farmId);
                return StatusCode(500, $"Internal server error: {ex.Message}");
            }
        }

        /// <summary>
        /// Set (or create) the current owner's organization code. Lets an owner
        /// whose code is missing enter one so staff can join with it.
        /// </summary>
        [HttpPost("organization/code")]
        public async Task<ActionResult> SetOrganizationCode([FromBody] SetOrgCodeRequest request)
        {
            try
            {
                var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);
                if (string.IsNullOrEmpty(userId)) return BadRequest("User id not found in claims");
                if (request == null || string.IsNullOrWhiteSpace(request.Code)) return BadRequest("Organization code is required.");

                var saved = await _adminService.SetOrganizationCodeAsync(userId, request.Code);
                return Ok(new { organizationCode = saved });
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Error setting organization code");
                return BadRequest(new { message = ex.Message });
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
