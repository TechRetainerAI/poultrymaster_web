using User.Management.Data.Models;

namespace User.Management.Service.Services
{
    public interface IAdminService
    {
        /// <summary>
        /// Get all employees (staff members) for a specific farm
        /// </summary>
        Task<List<ApplicationUser>> GetEmployeesByFarmIdAsync(string farmId);

        /// <summary>
        /// Get a specific employee by ID
        /// </summary>
        Task<ApplicationUser> GetEmployeeByIdAsync(string employeeId, string farmId);

        /// <summary>
        /// Create a new employee for a farm
        /// </summary>
        Task<ApplicationUser> CreateEmployeeAsync(ApplicationUser employee, string password);

        /// <summary>
        /// Update employee information
        /// </summary>
        Task<bool> UpdateEmployeeAsync(ApplicationUser employee);

        /// <summary>
        /// Delete/deactivate an employee
        /// </summary>
        Task<bool> DeleteEmployeeAsync(string employeeId, string farmId);

        /// <summary>
        /// Get employee count for a farm
        /// </summary>
        Task<int> GetEmployeeCountAsync(string farmId);

        /// <summary>
        /// List all farms registered in the system with counts
        /// </summary>
        Task<List<FarmSummary>> GetFarmsAsync();

        /// <summary>
        /// Get total number of farms registered in the system
        /// </summary>
        Task<int> GetFarmCountAsync();
    }
}

