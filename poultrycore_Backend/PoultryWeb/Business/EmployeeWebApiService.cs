using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using PoultryWeb.Models;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Collections.Generic;
using System.Threading.Tasks;
using System;
using Microsoft.Extensions.Logging;

namespace PoultryWeb.Business
{
    public class EmployeeWebApiService : IEmployeeWebApiService
    {
        private readonly HttpClient _httpClient;
        private readonly string _loginApiUrl;
        private readonly string _userId;
        private readonly string _farmId;
        private readonly ILogger<EmployeeWebApiService> _logger;
        private readonly IHttpContextAccessor _httpContextAccessor;

        public EmployeeWebApiService(
            HttpClient httpClient, 
            IConfiguration configuration, 
            IHttpContextAccessor httpContextAccessor,
            ILogger<EmployeeWebApiService> logger)
        {
            _httpClient = httpClient;
            _httpContextAccessor = httpContextAccessor;
            _logger = logger;
            _loginApiUrl = configuration["LoginApiUrl"] ?? "https://localhost:7080/";

            var user = httpContextAccessor.HttpContext?.User;
            _userId = user?.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            _farmId = user?.FindFirst("FarmId")?.Value;

            if (string.IsNullOrEmpty(_userId))
                throw new Exception("UserId is missing from the current user's claims.");

            if (string.IsNullOrEmpty(_farmId))
                throw new Exception("FarmId is missing from the current user's claims.");

            // Add authentication token
            AddAuthenticationHeader();

            _logger.LogInformation("EmployeeWebApiService initialized - UserId: {UserId}, FarmId: {FarmId}, LoginApiUrl: {LoginApiUrl}", 
                _userId, _farmId, _loginApiUrl);
        }

        private void AddAuthenticationHeader()
        {
            var httpContext = _httpContextAccessor.HttpContext;
            if (httpContext != null)
            {
                // Try to get token from cookie
                var tokenCookie = httpContext.Request.Cookies["auth_token"];
                if (!string.IsNullOrEmpty(tokenCookie))
                {
                    _httpClient.DefaultRequestHeaders.Authorization = 
                        new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", tokenCookie);
                }
            }
        }

        public async Task<List<EmployeeModel>> GetAllEmployeesAsync()
        {
            try
            {
                _logger.LogInformation("Fetching all employees for farm: {FarmId}", _farmId);

                var response = await _httpClient.GetAsync($"{_loginApiUrl}api/Admin/employees");

                if (response.IsSuccessStatusCode)
                {
                    var employees = await response.Content.ReadFromJsonAsync<List<EmployeeModel>>();
                    _logger.LogInformation("Retrieved {Count} employees", employees?.Count ?? 0);
                    return employees ?? new List<EmployeeModel>();
                }
                else
                {
                    var errorContent = await response.Content.ReadAsStringAsync();
                    _logger.LogError("API returned {StatusCode} for GET All Employees. Error: {ErrorContent}",
                        response.StatusCode, errorContent);
                    throw new HttpRequestException($"API returned {response.StatusCode}: {errorContent}");
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error fetching employees");
                throw;
            }
        }

        public async Task<EmployeeModel?> GetEmployeeByIdAsync(string employeeId)
        {
            try
            {
                var response = await _httpClient.GetAsync($"{_loginApiUrl}api/Admin/employees/{employeeId}");

                if (response.IsSuccessStatusCode)
                {
                    return await response.Content.ReadFromJsonAsync<EmployeeModel>();
                }
                else
                {
                    var errorContent = await response.Content.ReadAsStringAsync();
                    _logger.LogError("API returned {StatusCode} for GET Employee {EmployeeId}. Error: {ErrorContent}",
                        response.StatusCode, employeeId, errorContent);
                    return null;
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error fetching employee {EmployeeId}", employeeId);
                throw;
            }
        }

        public async Task<EmployeeModel?> CreateEmployeeAsync(EmployeeModel employee)
        {
            try
            {
                _logger.LogInformation("Creating employee: {UserName}", employee.UserName);

                var createRequest = new CreateEmployeeRequest
                {
                    Email = employee.Email,
                    FirstName = employee.FirstName,
                    LastName = employee.LastName,
                    PhoneNumber = employee.PhoneNumber,
                    UserName = employee.UserName,
                    Password = employee.Password,
                    FarmId = _farmId,
                    FarmName = employee.FarmName
                };

                var response = await _httpClient.PostAsJsonAsync($"{_loginApiUrl}api/Admin/employees", createRequest);

                if (response.IsSuccessStatusCode)
                {
                    _logger.LogInformation("Employee created successfully");
                    return await response.Content.ReadFromJsonAsync<EmployeeModel>();
                }
                else
                {
                    var errorContent = await response.Content.ReadAsStringAsync();
                    _logger.LogError("API returned {StatusCode} for CREATE Employee. Error: {ErrorContent}",
                        response.StatusCode, errorContent);
                    throw new HttpRequestException($"API returned {response.StatusCode}: {errorContent}");
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error creating employee");
                throw;
            }
        }

        public async Task UpdateEmployeeAsync(string employeeId, EmployeeModel employee)
        {
            try
            {
                var updateRequest = new UpdateEmployeeRequest
                {
                    Id = employeeId,
                    FirstName = employee.FirstName,
                    LastName = employee.LastName,
                    PhoneNumber = employee.PhoneNumber,
                    Email = employee.Email
                };

                var response = await _httpClient.PutAsJsonAsync($"{_loginApiUrl}api/Admin/employees/{employeeId}", updateRequest);

                if (!response.IsSuccessStatusCode)
                {
                    var errorContent = await response.Content.ReadAsStringAsync();
                    _logger.LogError("API returned {StatusCode} for UPDATE Employee {EmployeeId}. Error: {ErrorContent}",
                        response.StatusCode, employeeId, errorContent);
                    throw new HttpRequestException($"API returned {response.StatusCode}: {errorContent}");
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error updating employee {EmployeeId}", employeeId);
                throw;
            }
        }

        public async Task DeleteEmployeeAsync(string employeeId)
        {
            try
            {
                var response = await _httpClient.DeleteAsync($"{_loginApiUrl}api/Admin/employees/{employeeId}");

                if (!response.IsSuccessStatusCode)
                {
                    var errorContent = await response.Content.ReadAsStringAsync();
                    _logger.LogError("API returned {StatusCode} for DELETE Employee {EmployeeId}. Error: {ErrorContent}",
                        response.StatusCode, employeeId, errorContent);
                    throw new HttpRequestException($"API returned {response.StatusCode}: {errorContent}");
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error deleting employee {EmployeeId}", employeeId);
                throw;
            }
        }

        public async Task<int> GetEmployeeCountAsync()
        {
            try
            {
                var response = await _httpClient.GetAsync($"{_loginApiUrl}api/Admin/employees/count");

                if (response.IsSuccessStatusCode)
                {
                    var result = await response.Content.ReadFromJsonAsync<Dictionary<string, int>>();
                    return result?.GetValueOrDefault("count", 0) ?? 0;
                }
                else
                {
                    var errorContent = await response.Content.ReadAsStringAsync();
                    _logger.LogError("API returned {StatusCode} for GET Employee Count. Error: {ErrorContent}",
                        response.StatusCode, errorContent);
                    return 0;
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting employee count");
                return 0;
            }
        }
    }
}

