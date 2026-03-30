using System.Collections.Generic;
using System.Threading.Tasks;
using User.Management.Data.Models;
using User.Management.Service.Models;

namespace User.Management.Service.Services
{
    public interface ISubscriptionService
    {
        // Existing methods from the original service
        PlansDisplay GetPlans(string userId);
        Subscriber GetSubscriberByCustomerId(string customerId);
        Session RequestMemberSession(string priceId);
        Session RequestCustomerPortalSession(string customerId, string accessToken);

        Task<bool> CreateFarmAsync(Farm farm);
    }
}
