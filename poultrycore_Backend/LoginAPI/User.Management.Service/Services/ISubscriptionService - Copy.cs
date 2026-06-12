//using System.Collections.Generic;
//using System.Threading.Tasks;
//using User.Management.Data.Models;
//using User.Management.Service.Models;

//namespace User.Management.Service.Services
//{
//    public interface ISubscriptionService111
//    {
//        // New repository-based methods

//        Task<Subscriber> CreateSubscriptionAsync(Subscriber subscription);
//        Task DeleteSubscriptionAsync(string id);
//        Task<IEnumerable<Subscriber>> GetAllSubscriptionsAsync();
//        Task<Subscriber> GetSubscriptionByCustomerIdAsync(string customerId);
//        Task<Subscriber> GetSubscriptionByIdAsync(string id);
//        Task<Subscriber> UpdateSubscriptionAsync(Subscriber subscription);
//        Task<ApplicationUser> FindUserByEmailAsync(string email);
//        Task<ApplicationUser> UpdateUserAsync(ApplicationUser user);

//        // Existing methods from the original service
//        PlansDisplay GetPlans(string userId);
//        Subscriber GetSubscriberByCustomerId(string customerId);
//        Session RequestMemberSession(string priceId);
//        Session RequestCustomerPortalSession(string customerId, string accessToken);
//    }
//}
