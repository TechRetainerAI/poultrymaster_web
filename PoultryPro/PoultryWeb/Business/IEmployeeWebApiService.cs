using PoultryWeb.Models;

namespace PoultryWeb.Business
{
    public interface IEmployeeWebApiService
    {
        Task<List<EmployeeModel>> GetAllEmployeesAsync();
        Task<EmployeeModel?> GetEmployeeByIdAsync(string employeeId);
        Task<EmployeeModel?> CreateEmployeeAsync(EmployeeModel employee);
        Task UpdateEmployeeAsync(string employeeId, EmployeeModel employee);
        Task DeleteEmployeeAsync(string employeeId);
        Task<int> GetEmployeeCountAsync();
    }
}

