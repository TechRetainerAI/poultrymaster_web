using PoultryWeb.Models;

namespace PoultryWeb.Business
{
    public interface ICustomerWebApiService
    {
        Task<List<CustomerModel>> GetAllAsync();
        Task<CustomerModel?> GetByIdAsync(int customerId);
        Task<CustomerModel?> CreateAsync(CustomerModel model);
        Task UpdateAsync(int customerId, CustomerModel model);
        Task DeleteAsync(int customerId);
    }
}
