using System.Data;
using User.Management.Data.Models;

namespace User.Management.Data
{
    public interface ISubscriptionDAL
    {
        //TaxSetting GetTaxSettings(string userId);
        List<Plan> GetPlans();
        Subscriber GetSubscriberByCustomerId(string customerId);
        Task<bool> CreateFarmAsync(Farm farm);
        Task<List<Farm>> GetFarmsAsync();
        Task<int> GetFarmCountAsync();
        
    }
}
