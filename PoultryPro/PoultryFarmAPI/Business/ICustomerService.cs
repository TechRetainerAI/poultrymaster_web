using PoultryFarmAPIWeb.Models;

namespace PoultryFarmAPIWeb.Business
{
    public interface ICustomerService
    {
        Task<int> Insert(CustomerModel model);
        Task Update(CustomerModel model);
        Task<CustomerModel?> GetById(int customerId, string userId, string farmId);
        Task<List<CustomerModel>> GetAll(string userId, string farmId);
        Task Delete(int customerId, string userId, string farmId);
    }

}