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

        // ---- Doc 3 §6-7: organization employees + company access (UserFarms) ----

        /// <summary>
        /// All staff across every company the owner belongs to (deduped by user id) —
        /// includes both employees whose primary FarmId is an org company and those
        /// granted access to an org company via UserFarms.
        /// </summary>
        Task<List<ApplicationUser>> GetOrganizationEmployeesAsync(string ownerUserId);

        /// <summary>Companies a given employee can access (their UserFarms rows).</summary>
        Task<List<CompanyResponse>> GetEmployeeCompaniesAsync(string employeeId);

        /// <summary>Grant an employee access to a company (idempotent UserFarms insert).</summary>
        Task AssignCompanyAccessAsync(string employeeId, string farmId, string role);

        /// <summary>Revoke an employee's access to a company (UserFarms delete).</summary>
        Task RemoveCompanyAccessAsync(string employeeId, string farmId);

        /// <summary>Staff who have access to a company via UserFarms (access-based list).</summary>
        Task<List<ApplicationUser>> GetEmployeesWithAccessAsync(string farmId);

        /// <summary>True if the user belongs to (owns/has access to) the given company.</summary>
        Task<bool> UserHasCompanyAccessAsync(string userId, string farmId);

        /// <summary>
        /// Set the organization code for a user (normalized, uniqueness-checked).
        /// Lets an owner whose code is missing create one so staff can join.
        /// Returns the saved (normalized) code. Throws if the code is taken.
        /// </summary>
        Task<string> SetOrganizationCodeAsync(string userId, string code);

        /// <summary>
        /// Read the current owner's organization/owner profile (name, contact and
        /// organization-level details stored on their account). JWT-keyed — no
        /// client-supplied id — so it always resolves the authenticated user.
        /// </summary>
        Task<OrganizationProfile> GetOrganizationProfileAsync(string userId);

        /// <summary>
        /// Update the current owner's organization/owner profile. Persists via
        /// UserManager (EF) so every AspNetUsers column — including the
        /// BusinessOffice* fields — is saved without wiping the password/identity
        /// columns. Only the provided fields are changed.
        /// </summary>
        Task<OrganizationProfile> UpdateOrganizationProfileAsync(string userId, OrganizationProfile profile);
    }

    /// <summary>Organization/owner profile carried between the API and the client.</summary>
    public class OrganizationProfile
    {
        public string? FirstName { get; set; }
        public string? LastName { get; set; }
        public string? Email { get; set; }
        public string? PhoneNumber { get; set; }
        public string? BusinessOfficeName { get; set; }
        public string? BusinessOfficeCurrency { get; set; }
        public string? BusinessOfficeCountry { get; set; }
        public string? OrganizationCode { get; set; }
    }
}

